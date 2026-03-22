#pragma once

#include "keycard_manager.h"
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

    QString name()    const override { return QStringLiteral("keycard"); }
    QString version() const override { return QStringLiteral("1.0.0"); }

    // No override keyword (Lesson #19 - called reflectively)
    Q_INVOKABLE void    initLogos(LogosAPI* api);
    Q_INVOKABLE QString initialize();

    // Core keycard operations
    Q_INVOKABLE QString discoverReader();
    Q_INVOKABLE QString discoverCard();
    Q_INVOKABLE QString authorize(const QString& pin);
    Q_INVOKABLE QString deriveKey(const QString& domain);
    Q_INVOKABLE QString getState();
    Q_INVOKABLE QString closeSession();
    Q_INVOKABLE QString getLastError();

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);

private:
    Keycard::KeycardManager* m_manager = nullptr;
};
