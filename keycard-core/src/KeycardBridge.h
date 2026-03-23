#pragma once

#include <QObject>
#include <QString>
#include <QJsonObject>
#include <memory>

// Forward declarations (keycard-qt)
namespace Keycard {
    class CommunicationManager;
    class CommandSet;
    class KeycardChannel;
    struct PairingInfo;
    class IPairingStorage;
}

// Thin C++ wrapper around keycard-qt (native C++/Qt Keycard library).
// Manages PC/SC reader monitoring and card state.
// API compatible with previous libkeycard.so implementation.
class KeycardBridge : public QObject
{
    Q_OBJECT

public:
    // Card detection states (compatible with previous implementation)
    enum class State {
        Unknown,            // Before start() called
        NoPCSC,             // PC/SC library not available
        WaitingForReader,   // No USB reader connected
        WaitingForCard,     // Reader connected, no card inserted
        ConnectingCard,     // Establishing connection to card
        ConnectionError,    // Communication error
        NotKeycard,         // Card present but not a Keycard
        EmptyKeycard,       // Uninitialized Keycard (no mnemonic loaded)
        BlockedPIN,         // PIN blocked (0 attempts left)
        BlockedPUK,         // PUK blocked (card bricked)
        Ready,              // Card connected, ready for PIN
        Authorized,         // PIN verified, card unlocked
    };
    Q_ENUM(State)

    explicit KeycardBridge(QObject *parent = nullptr);
    ~KeycardBridge() override;

    // Start PC/SC monitoring. Returns true on success.
    bool start();

    // Stop monitoring and release resources.
    void stop();

    // Current card state.
    State state() const { return m_state; }

    // Human-readable status text for the current state.
    QString statusText() const;

    // Whether the bridge is actively monitoring.
    bool isRunning() const { return m_running; }

    // Actively query current state (updates cached state).
    void pollStatus();

    // Authorize with PIN. Returns JSON: {"authorized":true} or {"authorized":false,"remainingAttempts":N}
    QJsonObject authorize(const QString &pin);

    // Export key at derivation path. Returns raw private key bytes.
    // Default path: m/43'/60'/1581'/1'/0 (EIP-1581 encryption key)
    // With path parameter: Derives key at custom EIP-1581 path (Issue #11)
    QByteArray exportKey(const QString &path = "m/43'/60'/1581'/1'/0");

    // Flow API: Login (auth + export in one atomic operation).
    // Returns the encryption private key bytes, or empty on failure.
    QByteArray loginFlow(const QString &pin);

    // Last error from an operation (for debugging)
    QString lastError() const { return m_lastError; }

    // Card info from last status query
    int remainingPINAttempts() const { return m_remainingPIN; }
    int remainingPUKAttempts() const { return m_remainingPUK; }
    bool keyInitialized() const { return m_keyInitialized; }
    QString keyUID() const { return m_keyUID; }

    // Access to command set (for advanced operations)
    std::shared_ptr<Keycard::CommandSet> commandSet() const { return m_commandSet; }

signals:
    void stateChanged(KeycardBridge::State newState);

private slots:
    void onCardReady(const QString& uid);
    void onCardLost();

private:
    void setState(State newState);
    void updateStatusFromCommandSet();
    QByteArray parsePrivateKeyFromTLV(const QByteArray& tlv);

    std::shared_ptr<Keycard::KeycardChannel> m_channel;
    std::shared_ptr<Keycard::CommandSet> m_commandSet;
    std::shared_ptr<Keycard::IPairingStorage> m_pairingStorage;

    State m_state = State::Unknown;
    bool m_running = false;
    bool m_cardReady = false;

    QString m_lastError;

    // Card status
    int m_remainingPIN = -1;
    int m_remainingPUK = -1;
    bool m_keyInitialized = false;
    QString m_keyUID;
};
