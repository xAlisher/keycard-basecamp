#include "FilePairingStorage.h"
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutexLocker>
#include <QDebug>
#include <sys/stat.h>

FilePairingStorage::FilePairingStorage(const QString& filePath)
    : m_filePath(filePath)
{
    qDebug() << "FilePairingStorage: Using file:" << m_filePath;
    ensureFileExists();
}

bool FilePairingStorage::save(const QString& instanceUID, const Keycard::PairingInfo& pairing)
{
    QMutexLocker locker(&m_mutex);

    if (instanceUID.isEmpty() || !pairing.isValid()) {
        qWarning() << "FilePairingStorage::save: Invalid pairing data";
        return false;
    }

    QJsonObject data = readFile();
    data[instanceUID] = pairingToJson(pairing);

    if (!writeFile(data)) {
        qWarning() << "FilePairingStorage::save: Failed to write file";
        return false;
    }

    qDebug() << "FilePairingStorage::save: Saved pairing for" << instanceUID << "slot" << pairing.index;
    return true;
}

Keycard::PairingInfo FilePairingStorage::load(const QString& instanceUID)
{
    QMutexLocker locker(&m_mutex);

    if (instanceUID.isEmpty()) {
        return Keycard::PairingInfo();  // Invalid pairing
    }

    QJsonObject data = readFile();
    if (!data.contains(instanceUID)) {
        qDebug() << "FilePairingStorage::load: No pairing found for" << instanceUID;
        return Keycard::PairingInfo();  // Invalid pairing
    }

    auto pairing = jsonToPairing(data[instanceUID].toObject());
    qDebug() << "FilePairingStorage::load: Loaded pairing for" << instanceUID << "slot" << pairing.index;
    return pairing;
}

bool FilePairingStorage::remove(const QString& instanceUID)
{
    QMutexLocker locker(&m_mutex);

    if (instanceUID.isEmpty()) {
        return false;
    }

    QJsonObject data = readFile();
    if (!data.contains(instanceUID)) {
        qDebug() << "FilePairingStorage::remove: No pairing to remove for" << instanceUID;
        return true;  // Already removed
    }

    data.remove(instanceUID);

    if (!writeFile(data)) {
        qWarning() << "FilePairingStorage::remove: Failed to write file";
        return false;
    }

    qDebug() << "FilePairingStorage::remove: Removed pairing for" << instanceUID;
    return true;
}

QStringList FilePairingStorage::listPaired()
{
    QMutexLocker locker(&m_mutex);

    QJsonObject data = readFile();
    return data.keys();
}

// Private helpers

QJsonObject FilePairingStorage::readFile()
{
    QFile file(m_filePath);
    if (!file.exists()) {
        return QJsonObject();
    }

    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "FilePairingStorage::readFile: Failed to open" << m_filePath;
        return QJsonObject();
    }

    QByteArray content = file.readAll();
    file.close();

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(content, &error);

    if (error.error != QJsonParseError::NoError) {
        qWarning() << "FilePairingStorage::readFile: JSON parse error:" << error.errorString();
        // Corrupted file - return empty, will be overwritten
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

    // Remove old file if exists (QFile::rename doesn't overwrite on all platforms)
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
    // Ensure parent directory exists
    QFileInfo fileInfo(m_filePath);
    QDir dir = fileInfo.dir();
    if (!dir.exists()) {
        if (!dir.mkpath(".")) {
            qWarning() << "FilePairingStorage::ensureFileExists: Failed to create directory" << dir.path();
            return false;
        }
    }

    // If file doesn't exist, create empty JSON object
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
