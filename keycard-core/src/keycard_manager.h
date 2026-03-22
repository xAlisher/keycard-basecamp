#pragma once

#include "keycard_types.h"
#include "secure_buffer.h"
#include <QObject>
#include <QByteArray>
#include <QTimer>
#include <PCSC/winscard.h>

namespace Keycard {

/**
 * KeycardManager - State machine and PC/SC interface for Keycard smartcard.
 *
 * Security properties enforced:
 * - PIN never leaves card
 * - Key only exported after PIN verification
 * - BIP32 derivation on-card
 * - Card UID verified on reinsertion
 * - No persistent key storage
 * - Memory wiped via SecureBuffer RAII
 */
class KeycardManager : public QObject
{
    Q_OBJECT

public:
    explicit KeycardManager(QObject* parent = nullptr);
    ~KeycardManager();

    // State queries
    State currentState() const { return m_state; }
    Error lastError() const { return m_lastError; }

    // Core operations (match Q_INVOKABLE methods in plugin.cpp)
    bool discoverReader();
    bool discoverCard();
    bool authorize(const QString& pin, int& remainingAttempts);
    bool deriveKey(const QString& domain, SecureBuffer& outKey);
    void closeSession();

    // Card info
    QByteArray cardUID() const { return m_cardUID; }
    bool isSessionActive() const { return m_state == State::SESSION_ACTIVE; }

signals:
    void stateChanged(State newState);
    void cardRemoved();
    void cardInserted();

private:
    // State machine
    void transitionTo(State newState);
    void setError(Error error);

    // PC/SC low-level
    bool establishContext();
    void releaseContext();
    bool connectToCard();
    void disconnectCard();
    bool transmitAPDU(const QByteArray& command, QByteArray& response);

    // Card operations
    bool selectKeycardApplet();
    bool verifyPIN(const QString& pin, int& remainingAttempts);
    bool exportMasterKey(SecureBuffer& outKey);
    QByteArray readCardUID();

    // Key derivation
    SecureBuffer deriveKeycardMasterKey(const SecureBuffer& cardKey);
    SecureBuffer deriveDomainKey(const SecureBuffer& masterKey, const QString& domain);

    // Card presence polling
    void startPolling();
    void stopPolling();

private slots:
    void pollCardPresence();

private:
    // State
    State m_state = State::READER_NOT_FOUND;
    Error m_lastError = Error::NONE;

    // PC/SC handles
    SCARDCONTEXT m_context = 0;
    SCARDHANDLE m_cardHandle = 0;
    DWORD m_activeProtocol = 0;
    QString m_readerName;

    // Card identity
    QByteArray m_cardUID;          // UID from card insertion
    QByteArray m_sessionCardUID;   // UID verified during session

    // Session state
    SecureBuffer m_derivedKey;     // Current derived key (SESSION_ACTIVE only)
    QString m_currentDomain;       // Domain of current key

    // Card presence polling
    QTimer* m_pollTimer = nullptr;
    static constexpr int POLL_INTERVAL_MS = 1000;
};

} // namespace Keycard
