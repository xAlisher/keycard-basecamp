#include "plugin.h"
#include "keycard_types.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

KeycardPlugin::KeycardPlugin(QObject* parent)
    : QObject(parent)
    , m_manager(new Keycard::KeycardManager(this))
{
    qDebug() << "KeycardPlugin constructed";
}

void KeycardPlugin::initLogos(LogosAPI* api)
{
    logosAPI = api;
    qDebug() << "KeycardPlugin: Logos API initialized";
}

QString KeycardPlugin::initialize()
{
    qDebug() << "KeycardPlugin::initialize() called";
    QJsonObject result;
    result["initialized"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverReader()
{
    qDebug() << "KeycardPlugin::discoverReader() called";

    bool success = m_manager->discoverReader();

    QJsonObject result;
    if (success) {
        result["readerFound"] = true;
        result["state"] = Keycard::stateToString(m_manager->currentState());
    } else {
        result["readerFound"] = false;
        result["error"] = Keycard::errorToString(m_manager->lastError());
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverCard()
{
    qDebug() << "KeycardPlugin::discoverCard() called";

    bool success = m_manager->discoverCard();

    QJsonObject result;
    if (success) {
        result["cardPresent"] = true;
        result["cardUID"] = QString::fromUtf8(m_manager->cardUID().toHex());
        result["state"] = Keycard::stateToString(m_manager->currentState());
    } else {
        result["cardPresent"] = false;
        result["error"] = Keycard::errorToString(m_manager->lastError());
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::authorize(const QString& pin)
{
    qDebug() << "KeycardPlugin::authorize() called";

    int remainingAttempts = 0;
    bool success = m_manager->authorize(pin, remainingAttempts);

    QJsonObject result;
    if (success) {
        result["authorized"] = true;
        result["state"] = Keycard::stateToString(m_manager->currentState());
    } else {
        result["authorized"] = false;
        result["remainingAttempts"] = remainingAttempts;
        result["error"] = Keycard::errorToString(m_manager->lastError());

        if (m_manager->currentState() == Keycard::State::BLOCKED) {
            result["blocked"] = true;
        }
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::deriveKey(const QString& domain)
{
    qDebug() << "KeycardPlugin::deriveKey() called, domain:" << domain;

    SecureBuffer derivedKey;
    bool success = m_manager->deriveKey(domain, derivedKey);

    QJsonObject result;
    if (success) {
        result["derived"] = true;
        result["domain"] = domain;
        result["keyHex"] = QString::fromUtf8(derivedKey.toByteArray().toHex());
        result["state"] = Keycard::stateToString(m_manager->currentState());
    } else {
        result["derived"] = false;
        result["error"] = Keycard::errorToString(m_manager->lastError());
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getState()
{
    QJsonObject result;
    result["state"] = Keycard::stateToString(m_manager->currentState());

    if (m_manager->lastError() != Keycard::Error::NONE) {
        result["lastError"] = Keycard::errorToString(m_manager->lastError());
    }

    if (!m_manager->cardUID().isEmpty()) {
        result["cardUID"] = QString::fromUtf8(m_manager->cardUID().toHex());
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::closeSession()
{
    qDebug() << "KeycardPlugin::closeSession() called";

    m_manager->closeSession();

    QJsonObject result;
    result["closed"] = true;
    result["state"] = Keycard::stateToString(m_manager->currentState());

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getLastError()
{
    QJsonObject result;

    Keycard::Error lastError = m_manager->lastError();
    if (lastError == Keycard::Error::NONE) {
        result["error"] = "";
    } else {
        result["error"] = Keycard::errorToString(lastError);
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
