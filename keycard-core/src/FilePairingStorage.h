#pragma once

#include <keycard-qt/pairing_storage.h>
#include <QMutex>
#include <QString>
#include <QJsonObject>

/**
 * Persistent pairing storage using JSON file
 * Thread-safe with mutex protection
 * Location: ~/.local/share/Logos/LogosBasecamp/keycard-pairings.json
 * Permissions: 0600 (owner read/write only)
 */
class FilePairingStorage : public Keycard::IPairingStorage
{
public:
    explicit FilePairingStorage(const QString& filePath);
    ~FilePairingStorage() override = default;

    // IPairingStorage implementation
    bool save(const QString& instanceUID, const Keycard::PairingInfo& pairing) override;
    Keycard::PairingInfo load(const QString& instanceUID) override;
    bool remove(const QString& instanceUID) override;

    // Additional methods
    QStringList listPaired();  // List all paired card UIDs

private:
    QString m_filePath;
    QMutex m_mutex;

    // File I/O helpers
    QJsonObject readFile();
    bool writeFile(const QJsonObject& data);
    bool ensureFileExists();

    // Serialization
    static QJsonObject pairingToJson(const Keycard::PairingInfo& pairing);
    static Keycard::PairingInfo jsonToPairing(const QJsonObject& obj);
};
