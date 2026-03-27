#pragma once

#include "KeycardBridge.h"
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QTimer>
#include <QDateTime>
#include <QMap>
#include <QSet>
#include <core/interface.h>

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

    // Authorization request API (Option C: Module-Managed Auth State)
    // Allows consuming modules to request auth, user completes in keycard-ui
    Q_INVOKABLE QString requestAuth(const QString& domain, const QString& caller);
    Q_INVOKABLE QString checkAuthStatus(const QString& authId);
    Q_INVOKABLE QString getPendingAuths();

    // SECURITY: Only keycard-ui should call this - verifies PIN and derives key internally
    Q_INVOKABLE QString authorizeRequest(const QString& authId, const QString& pin);
    Q_INVOKABLE QString completeAuthRequest(const QString& authId, const QString& key);  // Complete request when session active
    Q_INVOKABLE QString rejectRequest(const QString& authId);

    // Session Management (Issue #44)
    Q_INVOKABLE QString lockSession();
    Q_INVOKABLE QString getSessionInfo();
    Q_INVOKABLE QString getAuthorizedModules();
    Q_INVOKABLE QString revokeModule(const QString& moduleName);

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);
    void sessionLocked(const QString& reason);  // "timeout" or "manual"
    void activityLogged(const QString& timestamp, const QString& message, const QString& level);

private:
    enum class SessionState {
        NoSession,        // No active session
        Active,          // SESSION_ACTIVE - key derived and active
        Locked           // SESSION_LOCKED - timeout or manual lock, requires re-PIN
    };

    struct AuthRequest {
        QString id;
        QString domain;
        QString caller;
        QString status;  // "pending", "complete", "failed"
        QString key;     // Result key (if complete)
        QString error;   // Error message (if failed)
        qint64 timestamp;
    };

    struct AuthorizationRecord {
        QString moduleName;
        QString domain;
        QDateTime lastAccess;
        int accessCount = 0;
    };

    QString mapBridgeStateToSpec(KeycardBridge::State state);
    void startSessionTimer();
    void clearSessionData();
    void logActivity(const QString& message, const QString& level = "info");
    void addActivityToResponse(QJsonObject& response);

private slots:
    void handleSessionTimeout();

private:
    KeycardBridge* m_bridge = nullptr;
    SessionState m_sessionState = SessionState::NoSession;
    QList<AuthRequest> m_authRequests;  // Pending authorization requests

    // Session management (Issue #44)
    QTimer* m_sessionTimer = nullptr;
    int m_sessionTimeoutMs = 300000;  // 5 minutes default
    QDateTime m_sessionStartTime;
    QMap<QString, AuthorizationRecord> m_authorizedModules;  // key: moduleName

    // Activity log queue (for QML)
    struct ActivityEntry {
        QString timestamp;
        QString message;
        QString level;
    };
    QList<ActivityEntry> m_recentActivity;
    QSet<QString> m_loggedRequestIds;  // Track which requests have been logged to avoid duplicates
};
