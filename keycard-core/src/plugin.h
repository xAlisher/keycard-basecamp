#pragma once

#include "KeycardBridge.h"
#include <QObject>
#include <QString>
#include <QVariantList>
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
    Q_INVOKABLE QString authorize(const QString& pin);
    Q_INVOKABLE QString deriveKey(const QString& domain, int version = 1);
    Q_INVOKABLE QString getState();
    Q_INVOKABLE QString closeSession();
    Q_INVOKABLE QString getLastError();
    Q_INVOKABLE QString testPCSC();  // Debug: test PC/SC directly

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);

private:
    enum class SessionState {
        NoSession,        // No active session
        Active,          // SESSION_ACTIVE - key derived
        Closed           // SESSION_CLOSED - explicitly closed
    };

    QString mapBridgeStateToSpec(KeycardBridge::State state);
    QString domainToEIP1581Path(const QString& domain);

    KeycardBridge* m_bridge = nullptr;
    SessionState m_sessionState = SessionState::NoSession;
};
