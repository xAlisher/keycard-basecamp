#include "FilePairingStorage.h"
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutexLocker>
#include <QDebug>
#include <sys/stat.h>
#include <sodium.h>

FilePairingStorage::FilePairingStorage(const QString& filePath)
    : m_filePath(filePath)
{
    qDebug() << "FilePairingStorage: Using file:" << m_filePath;
    if (sodium_init() < 0) {
        qWarning() << "FilePairingStorage: Failed to initialize libsodium!";
    }
    ensureFileExists();
}

// IPairingStorage::load — returns cached pairing if available, otherwise invalid
Keycard::PairingInfo FilePairingStorage::load(const QString& instanceUID)
{
    QMutexLocker locker(&m_mutex);

    if (instanceUID.isEmpty()) {
        return Keycard::PairingInfo();
    }

    // Return cached pairing if available (decrypted previously via loadEncrypted)
    if (m_cache.contains(instanceUID)) {
        auto pairing = m_cache[instanceUID];
        qDebug() << "FilePairingStorage::load: Returning cached pairing for" << instanceUID << "slot" << pairing.index;
        return pairing;
    }

    qDebug() << "FilePairingStorage::load: No cached pairing for" << instanceUID << "(PIN needed to decrypt)";
    return Keycard::PairingInfo();  // Invalid — caller must use loadEncrypted with PIN
}

// IPairingStorage::save — saves encrypted (requires PIN in cache context)
// This is called by KeycardBridge::pairCard, which now must provide PIN via saveEncrypted instead
bool FilePairingStorage::save(const QString& instanceUID, const Keycard::PairingInfo& pairing)
{
    // Legacy path — should not be called in encrypted mode
    // Kept for IPairingStorage interface compliance
    qWarning() << "FilePairingStorage::save: Called without PIN — pairing will NOT be persisted!";
    qWarning() << "FilePairingStorage::save: Use saveEncrypted() instead.";

    // Cache in memory only (not persisted to disk without encryption)
    QMutexLocker locker(&m_mutex);
    m_cache[instanceUID] = pairing;
    return true;
}

bool FilePairingStorage::remove(const QString& instanceUID)
{
    QMutexLocker locker(&m_mutex);

    if (instanceUID.isEmpty()) {
        return false;
    }

    // Clear cache
    m_cache.remove(instanceUID);

    bool hadParseError = false;
    QJsonObject data = readFile(&hadParseError);
    if (hadParseError) {
        qWarning() << "FilePairingStorage::remove: Refusing to modify corrupted pairing file";
        return false;
    }
    if (!data.contains(instanceUID)) {
        qDebug() << "FilePairingStorage::remove: No pairing to remove for" << instanceUID;
        return true;
    }

    data.remove(instanceUID);

    if (!writeFile(data)) {
        qWarning() << "FilePairingStorage::remove: Failed to write file";
        return false;
    }

    qDebug() << "FilePairingStorage::remove: Removed pairing for" << instanceUID;
    return true;
}

// Probe file without decrypting — returns status only
PairingLoadResult FilePairingStorage::probeFile(const QString& instanceUID)
{
    QMutexLocker locker(&m_mutex);

    if (!QFile::exists(m_filePath)) {
        return PairingLoadResult::FileNotFound;
    }

    bool hadParseError = false;
    QJsonObject data = readFile(&hadParseError);
    if (hadParseError) {
        return PairingLoadResult::Corrupted;
    }
    if (data.isEmpty()) {
        return PairingLoadResult::FileNotFound;
    }

    if (!data.contains(instanceUID)) {
        return PairingLoadResult::FileNotFound;
    }

    QJsonObject entry = data[instanceUID].toObject();

    // Check if encrypted (v2) or plaintext (legacy)
    if (entry.contains("version") && entry["version"].toInt() == 2) {
        if (!entry.contains("salt") || !entry.contains("nonce") || !entry.contains("encrypted")) {
            return PairingLoadResult::Corrupted;
        }
        return PairingLoadResult::PairingLocked;
    }

    // Legacy plaintext format (has "index" and "key" but no "version")
    if (entry.contains("index") && entry.contains("key")) {
        return PairingLoadResult::PlaintextLegacy;
    }

    return PairingLoadResult::Corrupted;
}

// Load and decrypt pairing with PIN
PairingLoadResult FilePairingStorage::loadEncrypted(const QString& instanceUID, const QString& pin, Keycard::PairingInfo& out)
{
    QMutexLocker locker(&m_mutex);

    // Check cache first
    if (m_cache.contains(instanceUID)) {
        out = m_cache[instanceUID];
        return PairingLoadResult::Success;
    }

    if (!QFile::exists(m_filePath)) {
        return PairingLoadResult::FileNotFound;
    }

    bool hadParseError = false;
    QJsonObject data = readFile(&hadParseError);
    if (hadParseError) {
        return PairingLoadResult::Corrupted;
    }
    if (!data.contains(instanceUID)) {
        return PairingLoadResult::FileNotFound;
    }

    QJsonObject entry = data[instanceUID].toObject();

    // Check if plaintext legacy format
    if (!entry.contains("version")) {
        if (entry.contains("index") && entry.contains("key")) {
            // Legacy plaintext — load directly, will be migrated on next save
            out = jsonToPairing(entry);
            m_cache[instanceUID] = out;
            qDebug() << "FilePairingStorage::loadEncrypted: Loaded legacy plaintext pairing for" << instanceUID;
            return PairingLoadResult::PlaintextLegacy;
        }
        return PairingLoadResult::Corrupted;
    }

    int version = entry["version"].toInt();
    if (version != 2) {
        return PairingLoadResult::Corrupted;
    }

    // Extract encrypted envelope
    QByteArray salt = QByteArray::fromHex(entry["salt"].toString().toUtf8());
    QByteArray nonce = QByteArray::fromHex(entry["nonce"].toString().toUtf8());
    QByteArray ciphertext = QByteArray::fromHex(entry["encrypted"].toString().toUtf8());

    if (salt.size() != crypto_pwhash_SALTBYTES ||
        nonce.size() != crypto_secretbox_NONCEBYTES ||
        ciphertext.isEmpty()) {
        return PairingLoadResult::Corrupted;
    }

    // Derive key from PIN
    QByteArray key = deriveKey(pin, salt);
    if (key.isEmpty()) {
        return PairingLoadResult::Corrupted;  // Key derivation failed (out of memory)
    }

    // Decrypt
    QByteArray plaintext(ciphertext.size() - crypto_secretbox_MACBYTES, 0);
    if (crypto_secretbox_open_easy(
            reinterpret_cast<unsigned char*>(plaintext.data()),
            reinterpret_cast<const unsigned char*>(ciphertext.constData()),
            ciphertext.size(),
            reinterpret_cast<const unsigned char*>(nonce.constData()),
            reinterpret_cast<const unsigned char*>(key.constData())) != 0) {
        // MAC verification failed — wrong PIN or tampered data
        sodium_memzero(key.data(), key.size());
        return PairingLoadResult::WrongPin;
    }

    // Wipe key immediately
    sodium_memzero(key.data(), key.size());

    // Parse decrypted pairing JSON
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(plaintext, &parseError);
    sodium_memzero(plaintext.data(), plaintext.size());

    if (parseError.error != QJsonParseError::NoError) {
        return PairingLoadResult::Corrupted;
    }

    out = jsonToPairing(doc.object());
    m_cache[instanceUID] = out;

    qDebug() << "FilePairingStorage::loadEncrypted: Decrypted pairing for" << instanceUID << "slot" << out.index;
    return PairingLoadResult::Success;
}

// Save pairing encrypted with PIN-derived key
bool FilePairingStorage::saveEncrypted(const QString& instanceUID, const Keycard::PairingInfo& pairing, const QString& pin)
{
    QMutexLocker locker(&m_mutex);

    if (instanceUID.isEmpty() || !pairing.isValid() || pin.isEmpty()) {
        qWarning() << "FilePairingStorage::saveEncrypted: Invalid parameters";
        return false;
    }

    // Serialize pairing to JSON
    QJsonObject pairingObj = pairingToJson(pairing);
    QByteArray plaintext = QJsonDocument(pairingObj).toJson(QJsonDocument::Compact);

    // Generate random salt and nonce
    QByteArray salt(crypto_pwhash_SALTBYTES, 0);
    randombytes_buf(salt.data(), salt.size());

    QByteArray nonce(crypto_secretbox_NONCEBYTES, 0);
    randombytes_buf(nonce.data(), nonce.size());

    // Derive key from PIN
    QByteArray key = deriveKey(pin, salt);
    if (key.isEmpty()) {
        qWarning() << "FilePairingStorage::saveEncrypted: Key derivation failed";
        return false;
    }

    // Encrypt
    QByteArray ciphertext(plaintext.size() + crypto_secretbox_MACBYTES, 0);
    crypto_secretbox_easy(
        reinterpret_cast<unsigned char*>(ciphertext.data()),
        reinterpret_cast<const unsigned char*>(plaintext.constData()),
        plaintext.size(),
        reinterpret_cast<const unsigned char*>(nonce.constData()),
        reinterpret_cast<const unsigned char*>(key.constData()));

    // Wipe sensitive data
    sodium_memzero(key.data(), key.size());
    sodium_memzero(plaintext.data(), plaintext.size());

    // Build encrypted envelope
    QJsonObject envelope;
    envelope["version"] = 2;
    envelope["salt"] = QString::fromUtf8(salt.toHex());
    envelope["nonce"] = QString::fromUtf8(nonce.toHex());
    envelope["encrypted"] = QString::fromUtf8(ciphertext.toHex());

    // Write to file (preserving other card entries, fail-closed on corruption)
    bool hadParseError = false;
    QJsonObject data = readFile(&hadParseError);
    if (hadParseError) {
        qWarning() << "FilePairingStorage::saveEncrypted: Refusing to overwrite corrupted pairing file";
        return false;
    }
    data[instanceUID] = envelope;

    if (!writeFile(data)) {
        qWarning() << "FilePairingStorage::saveEncrypted: Failed to write file";
        return false;
    }

    // Update cache
    m_cache[instanceUID] = pairing;

    qDebug() << "FilePairingStorage::saveEncrypted: Saved encrypted pairing for" << instanceUID;
    return true;
}

bool FilePairingStorage::hasCachedPairing(const QString& instanceUID) const
{
    QMutexLocker locker(&m_mutex);
    return m_cache.contains(instanceUID);
}

void FilePairingStorage::clearCache()
{
    QMutexLocker locker(&m_mutex);
    // Wipe cached pairing keys from memory
    for (auto& pairing : m_cache) {
        sodium_memzero(pairing.key.data(), pairing.key.size());
    }
    m_cache.clear();
    qDebug() << "FilePairingStorage::clearCache: Pairing cache cleared";
}

QStringList FilePairingStorage::listPaired()
{
    QMutexLocker locker(&m_mutex);
    QJsonObject data = readFile();
    return data.keys();
}

// Private helpers

QByteArray FilePairingStorage::deriveKey(const QString& pin, const QByteArray& salt)
{
    QByteArray key(crypto_secretbox_KEYBYTES, 0);
    QByteArray pinBytes = pin.toUtf8();

    if (crypto_pwhash(
            reinterpret_cast<unsigned char*>(key.data()),
            key.size(),
            pinBytes.constData(),
            pinBytes.size(),
            reinterpret_cast<const unsigned char*>(salt.constData()),
            crypto_pwhash_OPSLIMIT_INTERACTIVE,
            crypto_pwhash_MEMLIMIT_INTERACTIVE,
            crypto_pwhash_ALG_DEFAULT) != 0) {
        qWarning() << "FilePairingStorage::deriveKey: crypto_pwhash failed (out of memory?)";
        sodium_memzero(pinBytes.data(), pinBytes.size());
        return QByteArray();
    }

    sodium_memzero(pinBytes.data(), pinBytes.size());
    return key;
}

QJsonObject FilePairingStorage::readFile(bool* parseError)
{
    if (parseError) *parseError = false;

    QFile file(m_filePath);
    if (!file.exists()) {
        return QJsonObject();
    }

    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "FilePairingStorage::readFile: Failed to open" << m_filePath;
        if (parseError) *parseError = true;
        return QJsonObject();
    }

    QByteArray content = file.readAll();
    file.close();

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(content, &error);

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "FilePairingStorage::readFile: JSON parse error:" << error.errorString();
        if (parseError) *parseError = true;
        return QJsonObject();
    }

    return doc.object();
}

bool FilePairingStorage::writeFile(const QJsonObject& data)
{
    // Write to temp file first, then atomic rename
    QString tempPath = m_filePath + ".tmp";
    QFile file(tempPath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "FilePairingStorage::writeFile: Failed to open temp file" << tempPath;
        return false;
    }

    QJsonDocument doc(data);
    file.write(doc.toJson(QJsonDocument::Indented));
    file.close();

    // Set permissions to 0600 (owner read/write only)
    if (chmod(tempPath.toUtf8().constData(), S_IRUSR | S_IWUSR) != 0) {
        qWarning() << "FilePairingStorage::writeFile: Failed to set permissions on" << tempPath;
    }

    // Remove old file if exists
    if (QFile::exists(m_filePath)) {
        if (!QFile::remove(m_filePath)) {
            qWarning() << "FilePairingStorage::writeFile: Failed to remove old file" << m_filePath;
            QFile::remove(tempPath);
            return false;
        }
    }

    // Atomic rename
    if (!QFile::rename(tempPath, m_filePath)) {
        qWarning() << "FilePairingStorage::writeFile: Failed to rename" << tempPath << "to" << m_filePath;
        QFile::remove(tempPath);
        return false;
    }

    return true;
}

bool FilePairingStorage::ensureFileExists()
{
    QFileInfo fileInfo(m_filePath);
    QDir dir = fileInfo.dir();
    if (!dir.exists()) {
        if (!dir.mkpath(".")) {
            qWarning() << "FilePairingStorage::ensureFileExists: Failed to create directory" << dir.path();
            return false;
        }
    }

    if (!QFile::exists(m_filePath)) {
        qDebug() << "FilePairingStorage::ensureFileExists: Creating new file" << m_filePath;
        return writeFile(QJsonObject());
    }

    return true;
}

QJsonObject FilePairingStorage::pairingToJson(const Keycard::PairingInfo& pairing)
{
    QJsonObject obj;
    obj["index"] = pairing.index;
    obj["key"] = QString::fromUtf8(pairing.key.toBase64());
    return obj;
}

Keycard::PairingInfo FilePairingStorage::jsonToPairing(const QJsonObject& obj)
{
    Keycard::PairingInfo pairing;
    pairing.index = obj["index"].toInt(-1);
    pairing.key = QByteArray::fromBase64(obj["key"].toString().toUtf8());
    return pairing;
}
