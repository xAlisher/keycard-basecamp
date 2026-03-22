#include "plugin.h"
#include <QJsonDocument>
#include <QJsonObject>

KeycardPlugin::KeycardPlugin(QObject* parent)
    : QObject(parent)
{
}

void KeycardPlugin::initLogos(LogosAPI* api)
{
    logosAPI = api;
}

QString KeycardPlugin::initialize()
{
    QJsonObject result;
    result["initialized"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverReader()
{
    QJsonObject result;
    result["error"] = "Not implemented - Phase 1 stub";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverCard()
{
    QJsonObject result;
    result["error"] = "Not implemented - Phase 1 stub";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::authorize(const QString& pin)
{
    QJsonObject result;
    result["error"] = "Not implemented - Phase 1 stub";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::deriveKey(const QString& domain)
{
    QJsonObject result;
    result["error"] = "Not implemented - Phase 1 stub";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getState()
{
    QJsonObject result;
    result["state"] = "READER_NOT_FOUND";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::closeSession()
{
    QJsonObject result;
    result["error"] = "Not implemented - Phase 1 stub";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getLastError()
{
    QJsonObject result;
    result["error"] = "No errors - Phase 1 stub";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
