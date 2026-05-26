#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include "interface.h"

class KeycardShowcasePlugin : public QObject, public PluginInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.KeycardShowcaseModuleInterface" FILE "plugin_metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    explicit KeycardShowcasePlugin(QObject* parent = nullptr);

    QString name()    const override { return QStringLiteral("keycard_showcase"); }
    QString version() const override { return QStringLiteral("1.0.0"); }

    Q_INVOKABLE void    initLogos(LogosAPI* api);
    Q_INVOKABLE QString initialize();
    Q_INVOKABLE QString hashMessage(const QString& message);

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);
};
