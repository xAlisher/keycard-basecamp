#include "plugin.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QCryptographicHash>

KeycardShowcasePlugin::KeycardShowcasePlugin(QObject* parent)
    : QObject(parent)
{
}

void KeycardShowcasePlugin::initLogos(LogosAPI* api)
{
    logosAPI = api;
}

QString KeycardShowcasePlugin::initialize()
{
    QJsonObject result;
    result["initialized"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardShowcasePlugin::hashMessage(const QString& message)
{
    QByteArray hash = QCryptographicHash::hash(message.toUtf8(), QCryptographicHash::Sha256);
    QJsonObject result;
    result["hash"] = QString::fromLatin1(hash.toHex());
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
