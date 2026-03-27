#pragma once

#include <QObject>
#include <QString>
#include <core/interface.h>

class AuthShowcasePlugin : public QObject, public PluginInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.AuthShowcaseModuleInterface" FILE "plugin_metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    explicit AuthShowcasePlugin(QObject* parent = nullptr);

    QString name()    const override { return QStringLiteral("auth_showcase"); }
    QString version() const override { return QStringLiteral("1.0.0"); }

    Q_INVOKABLE void    initLogos(LogosAPI* api);
    Q_INVOKABLE QString initialize();

private:
    LogosAPI* logosAPI = nullptr;
};
