#include "plugin.h"
#include <QJsonDocument>
#include <QJsonObject>

AuthShowcasePlugin::AuthShowcasePlugin(QObject* parent)
    : QObject(parent)
{
}

void AuthShowcasePlugin::initLogos(LogosAPI* api)
{
    logosAPI = api;
}

QString AuthShowcasePlugin::initialize()
{
    QJsonObject result;
    result["initialized"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
