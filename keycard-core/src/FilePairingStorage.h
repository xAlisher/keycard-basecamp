#pragma once

#include <keycard-qt/pairing_storage.h>
#include <QMutex>
#include <QString>
#include <QJsonObject>

/**
 * Encrypted persistent pairing storage using libsodium.
 *
 * File format v2 (encrypted):
 *   { "version": 2, "salt": "hex", "nonce": "hex", "encrypted": "hex" }
 *
 * Encryption: crypto_pwhash (Argon2id) + crypto_secretbox (XSalsa20-Poly1305)
 * Key derivation: PIN → Argon2id → 32-byte key
 *
 * Thread-safe with mutex protection.
 * Permissions: 0600 (owner read/write only)
 */

enum class PairingLoadResult {
    Success,           // Decrypted successfully
    FileNotFound,      // No pairing file → not paired
    PairingLocked,     // Encrypted file exists, PIN needed
    WrongPin,          // Decryption failed (MAC mismatch)
    Corrupted,         // Malformed envelope
    PlaintextLegacy    // Old format, needs migration
};

class FilePairingStorage : public Keycard::IPairingStorage
{
public:
    explicit FilePairingStorage(const QString& filePath);
    ~FilePairingStorage() override = default;

    // IPairingStorage implementation (uses cached pairing if available)
    bool save(const QString& instanceUID, const Keycard::PairingInfo& pairing) override;
    Keycard::PairingInfo load(const QString& instanceUID) override;
    bool remove(const QString& instanceUID) override;

    // Encrypted operations
    PairingLoadResult loadEncrypted(const QString& instanceUID, const QString& pin, Keycard::PairingInfo& out);
    bool saveEncrypted(const QString& instanceUID, const Keycard::PairingInfo& pairing, const QString& pin);

    // Cache management (session-memory only)
    bool hasCachedPairing(const QString& instanceUID) const;
    void clearCache();

    // Status check (no PIN needed)
    PairingLoadResult probeFile(const QString& instanceUID);

    // Additional methods
    QStringList listPaired();

private:
    QString m_filePath;
    mutable QMutex m_mutex;

    // Session-memory cache (cleared on wrong PIN, card loss, stop, unpair)
    QMap<QString, Keycard::PairingInfo> m_cache;

    // File I/O helpers
    QJsonObject readFile(bool* parseError = nullptr);
    bool writeFile(const QJsonObject& data);
    bool ensureFileExists();

    // Encryption helpers
    QByteArray deriveKey(const QString& pin, const QByteArray& salt);

    // Serialization
    static QJsonObject pairingToJson(const Keycard::PairingInfo& pairing);
    static Keycard::PairingInfo jsonToPairing(const QJsonObject& obj);
};
