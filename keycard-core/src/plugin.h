#pragma once

#include "KeycardBridge.h"
#include "secure_buffer.h"
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QDateTime>
#include <QSet>
#include <vector>
#include "interface.h"

class KeycardPlugin : public QObject, public PluginInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.KeycardModuleInterface" FILE "plugin_metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    explicit KeycardPlugin(QObject* parent = nullptr);
    ~KeycardPlugin() override;

    QString name()    const override { return QStringLiteral("keycard"); }
    QString version() const override { return QStringLiteral("1.0.0"); }

    // No override keyword (Lesson #19 - called reflectively)
    Q_INVOKABLE void    initLogos(LogosAPI* api);
    Q_INVOKABLE QString initialize();

    // Core keycard operations
    Q_INVOKABLE QString discoverReader();
    Q_INVOKABLE QString discoverCard();
    Q_INVOKABLE QString checkPairing();
    Q_INVOKABLE QString pairCard(const QString& pairingPassword);
    Q_INVOKABLE QString unpairCard();
    Q_INVOKABLE QString authorize(const QString& pin);
    Q_INVOKABLE QString deriveKey(const QString& domain);
    Q_INVOKABLE QString getState();
    Q_INVOKABLE QString closeSession();
    Q_INVOKABLE QString getLastError();
    Q_INVOKABLE QString testPCSC();  // Debug: test PC/SC directly
    Q_INVOKABLE QString checkReaderPresent();  // Fresh PC/SC check
    Q_INVOKABLE QString checkCardPresent();   // Fresh PC/SC check
    Q_INVOKABLE QString unblockPIN(const QString& puk, const QString& newPIN);
    Q_INVOKABLE QString getCardStatus();  // Get PIN/PUK attempts remaining
    Q_INVOKABLE QString detectMode();     // Returns {"mode":"BIP39"|"LEE"|"none"}
    Q_INVOKABLE QString loadKey(const QString& jsonArgs); // Debug: load key, expects {"seedHex":"...","keyType":0|1}
    Q_INVOKABLE QString removeKey();      // Debug: remove loaded key

    // Authorization request API
    Q_INVOKABLE QString requestAuth(const QString& domain, const QString& caller);
    Q_INVOKABLE QString checkAuthStatus(const QString& authId);
    Q_INVOKABLE QString getPendingAuths();
    Q_INVOKABLE QString authorizeRequest(const QString& authId, const QString& pin);
    Q_INVOKABLE QString rejectRequest(const QString& authId);

    // Utility
    Q_INVOKABLE QString hashMessage(const QString& message);  // SHA-256 hex of UTF-8 message

    // Signing request API (#98, #149, #150)
    Q_INVOKABLE QString requestSign(const QString& jsonArgs); // {"domain","payloadHash","caller","scheme","bip32_path"?}
    Q_INVOKABLE QString checkSignStatus(const QString& signId);
    Q_INVOKABLE QString getPendingSigns();
    Q_INVOKABLE QString approveSign(const QString& jsonArgs); // {"signId":"...","pin":"..."}
    Q_INVOKABLE QString rejectSign(const QString& signId);

    // XPUB export API (#142)
    Q_INVOKABLE QString requestXPUB(const QString& jsonArgs);  // {"domain","caller"}
    Q_INVOKABLE QString approveXPUB(const QString& jsonArgs);  // {"xpubId","pin"}
    Q_INVOKABLE QString rejectXPUB(const QString& xpubId);
    Q_INVOKABLE QString checkXPUBStatus(const QString& xpubId);
    Q_INVOKABLE QString getPendingXPUBs();
    Q_INVOKABLE QString testXPUBExport(const QString& jsonArgs); // Debug: {"domain","pin"} — direct export, bypasses request queue
    Q_INVOKABLE QString testMasterExport(const QString& pin);   // Debug: authorize + export master (no derive) — chain code probe
    Q_INVOKABLE QString testEip1581Export(const QString& pin);  // Debug: authorize + export at m/43'/60'/1581' — EIP-1581 root probe

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);
    void activityLogged(const QString& timestamp, const QString& message, const QString& level);

private:
    struct AuthRequest {
        QString id;
        QString domain;
        QString caller;
        QString status;  // "pending", "complete", "consumed", "failed"
        SecureBuffer key; // Result key (if complete) — wiped after first read
        QString error;   // Error message (if failed)
        qint64 timestamp;

        // Move-only (SecureBuffer is non-copyable)
        AuthRequest() = default;
        AuthRequest(AuthRequest&&) = default;
        AuthRequest& operator=(AuthRequest&&) = default;
        AuthRequest(const AuthRequest&) = delete;
        AuthRequest& operator=(const AuthRequest&) = delete;
    };

    void purgeCompletedRequests();

    QString mapBridgeStateToSpec(KeycardBridge::State state);
    QString domainToPath(const QString& domain);      // m/43'/60'/1581' — auth/key-export subtree
    QString domainToSignPath(const QString& domain);  // m/43'/60'/1582' — signing subtree (#150)
    void logActivity(const QString& message, const QString& level = "info");
    void addActivityToResponse(QJsonObject& response);

    enum class SessionState {
        NoSession,
        Active
    };

private:
    struct SignRequest {
        QString id;
        QString domain;
        QString payloadHash;  // hex-encoded 32-byte digest
        QString caller;
        QString scheme;       // "ecdsa" or "schnorr"
        QString bip32_path;   // explicit BIP32 path (#149); if set, overrides domain derivation
        QString status;       // "pending", "complete", "rejected", "failed"
        SecureBuffer signature; // Result — wiped after first read
        QString error;
        qint64 timestamp;

        SignRequest() = default;
        SignRequest(SignRequest&&) = default;
        SignRequest& operator=(SignRequest&&) = default;
        SignRequest(const SignRequest&) = delete;
        SignRequest& operator=(const SignRequest&) = delete;
    };

    struct XPUBRequest {
        QString id;
        QString bip32_path;
        QString caller;
        QString status;   // "pending", "complete", "rejected", "failed"
        SecureBuffer xpub; // pubkey_hex + chaincode_hex — wiped after first read
        QString error;
        qint64 timestamp;

        XPUBRequest() = default;
        XPUBRequest(XPUBRequest&&) = default;
        XPUBRequest& operator=(XPUBRequest&&) = default;
        XPUBRequest(const XPUBRequest&) = delete;
        XPUBRequest& operator=(const XPUBRequest&) = delete;
    };

private:
    KeycardBridge* m_bridge = nullptr;
    SessionState m_sessionState = SessionState::NoSession;
    std::vector<AuthRequest> m_authRequests;
    std::vector<SignRequest> m_signRequests;
    std::vector<XPUBRequest> m_xpubRequests;

    // Activity log queue (for QML)
    struct ActivityEntry {
        QString timestamp;
        QString message;
        QString level;
    };
    QList<ActivityEntry> m_recentActivity;
    QSet<QString> m_loggedRequestIds;
};
