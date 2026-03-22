#include "plugin.h"
#include "KeycardBridge.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

KeycardPlugin::KeycardPlugin(QObject* parent)
    : QObject(parent)
    , m_bridge(nullptr)
{
    qDebug() << "KeycardPlugin constructed";
}

KeycardPlugin::~KeycardPlugin()
{
    if (m_bridge) {
        m_bridge->stop();
        delete m_bridge;
    }
}

void KeycardPlugin::initLogos(LogosAPI* api)
{
    logosAPI = api;
    qDebug() << "KeycardPlugin: Logos API initialized";
}

QString KeycardPlugin::initialize()
{
    qDebug() << "KeycardPlugin::initialize() called";

    if (!m_bridge) {
        m_bridge = new KeycardBridge(this);
        connect(m_bridge, &KeycardBridge::stateChanged,
                this, [](KeycardBridge::State state) {
            qDebug() << "Keycard state changed:" << static_cast<int>(state);
        });
    }

    QJsonObject result;
    result["initialized"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverReader()
{
    qDebug() << "KeycardPlugin::discoverReader() called";

    if (!m_bridge) {
        m_bridge = new KeycardBridge(this);
    }

    bool success = m_bridge->start();

    QJsonObject result;
    if (success) {
        result["readerFound"] = true;
        result["state"] = stateToString(m_bridge->state());
    } else {
        result["readerFound"] = false;
        result["error"] = m_bridge->lastError();
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverCard()
{
    qDebug() << "KeycardPlugin::discoverCard() called";

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized - call discoverReader first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    m_bridge->pollStatus();

    QJsonObject result;
    KeycardBridge::State state = m_bridge->state();

    if (state == KeycardBridge::State::Ready || state == KeycardBridge::State::Authorized) {
        result["cardPresent"] = true;
        result["state"] = stateToString(state);
        result["keyUID"] = m_bridge->keyUID();
    } else {
        result["cardPresent"] = false;
        result["state"] = stateToString(state);
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::authorize(const QString& pin)
{
    qDebug() << "KeycardPlugin::authorize() called";

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized - call discoverReader first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject authResult = m_bridge->authorize(pin);
    return QJsonDocument(authResult).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::deriveKey(const QString& domain)
{
    qDebug() << "KeycardPlugin::deriveKey() called, domain:" << domain;

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Export the encryption key
    QByteArray key = m_bridge->exportKey();

    QJsonObject result;
    if (!key.isEmpty()) {
        result["derived"] = true;
        result["domain"] = domain;
        result["keyHex"] = QString::fromUtf8(key.toHex());
    } else {
        result["derived"] = false;
        result["error"] = m_bridge->lastError();
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getState()
{
    if (!m_bridge) {
        QJsonObject result;
        result["state"] = "NOT_STARTED";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject result;
    result["state"] = stateToString(m_bridge->state());
    result["statusText"] = m_bridge->statusText();

    if (m_bridge->remainingPINAttempts() >= 0) {
        result["remainingPINAttempts"] = m_bridge->remainingPINAttempts();
    }

    if (!m_bridge->keyUID().isEmpty()) {
        result["keyUID"] = m_bridge->keyUID();
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::closeSession()
{
    qDebug() << "KeycardPlugin::closeSession() called";

    if (m_bridge) {
        m_bridge->stop();
    }

    QJsonObject result;
    result["closed"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getLastError()
{
    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject result;
    QString error = m_bridge->lastError();
    result["error"] = error.isEmpty() ? "" : error;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::stateToString(KeycardBridge::State state)
{
    switch (state) {
    case KeycardBridge::State::Unknown:          return "UNKNOWN";
    case KeycardBridge::State::NoPCSC:           return "NO_PCSC";
    case KeycardBridge::State::WaitingForReader: return "WAITING_FOR_READER";
    case KeycardBridge::State::WaitingForCard:   return "WAITING_FOR_CARD";
    case KeycardBridge::State::ConnectingCard:   return "CONNECTING_CARD";
    case KeycardBridge::State::ConnectionError:  return "CONNECTION_ERROR";
    case KeycardBridge::State::NotKeycard:       return "NOT_KEYCARD";
    case KeycardBridge::State::EmptyKeycard:     return "EMPTY_KEYCARD";
    case KeycardBridge::State::BlockedPIN:       return "BLOCKED_PIN";
    case KeycardBridge::State::BlockedPUK:       return "BLOCKED_PUK";
    case KeycardBridge::State::Ready:            return "READY";
    case KeycardBridge::State::Authorized:       return "AUTHORIZED";
    }
    return "UNKNOWN";
}
