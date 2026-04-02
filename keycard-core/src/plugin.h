#pragma once

#include "KeycardBridge.h"
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QDateTime>
#include <QSet>
#include <module_lib/interface.h>

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

    // Authorization request API
    Q_INVOKABLE QString requestAuth(const QString& domain, const QString& caller);
    Q_INVOKABLE QString checkAuthStatus(const QString& authId);
    Q_INVOKABLE QString getPendingAuths();
    Q_INVOKABLE QString authorizeRequest(const QString& authId, const QString& pin);
    Q_INVOKABLE QString rejectRequest(const QString& authId);

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);
    void activityLogged(const QString& timestamp, const QString& message, const QString& level);

private:
    struct AuthRequest {
        QString id;
        QString domain;
        QString caller;
        QString status;  // "pending", "complete", "failed"
        QString key;     // Result key (if complete)
        QString error;   // Error message (if failed)
        qint64 timestamp;
    };

    QString mapBridgeStateToSpec(KeycardBridge::State state);
    void logActivity(const QString& message, const QString& level = "info");
    void addActivityToResponse(QJsonObject& response);

    enum class SessionState {
        NoSession,
        Active
    };

private:
    KeycardBridge* m_bridge = nullptr;
    SessionState m_sessionState = SessionState::NoSession;
    QList<AuthRequest> m_authRequests;

    // Activity log queue (for QML)
    struct ActivityEntry {
        QString timestamp;
        QString message;
        QString level;
    };
    QList<ActivityEntry> m_recentActivity;
    QSet<QString> m_loggedRequestIds;
};
