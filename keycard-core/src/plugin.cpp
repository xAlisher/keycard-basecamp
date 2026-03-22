#include "plugin.h"
#include "KeycardBridge.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <sodium.h>

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
    result["found"] = success;
    if (success) {
        // Get reader name from state
        result["name"] = "Smart card reader";
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::discoverCard()
{
    qDebug() << "KeycardPlugin::discoverCard() called";

    if (!m_bridge) {
        QJsonObject result;
        result["found"] = false;
        result["error"] = "Bridge not initialized - call discoverReader first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    m_bridge->pollStatus();

    QJsonObject result;
    KeycardBridge::State state = m_bridge->state();

    if (state == KeycardBridge::State::Ready || state == KeycardBridge::State::Authorized) {
        result["found"] = true;
        result["uid"] = m_bridge->keyUID();
    } else {
        result["found"] = false;
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

    // Export base encryption key
    QByteArray baseKey = m_bridge->exportKey();

    if (baseKey.isEmpty()) {
        QJsonObject result;
        result["error"] = m_bridge->lastError();
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Derive domain-specific key: SHA256(baseKey || domain)
    QByteArray domainBytes = domain.toUtf8();
    QByteArray combined = baseKey + domainBytes;

    unsigned char hash[32];
    crypto_hash_sha256(hash, reinterpret_cast<const unsigned char*>(combined.constData()), combined.size());

    QByteArray derivedKey(reinterpret_cast<const char*>(hash), 32);

    QJsonObject result;
    result["key"] = QString::fromUtf8(derivedKey.toHex());

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getState()
{
    if (!m_bridge) {
        QJsonObject result;
        result["state"] = "READER_NOT_FOUND";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject result;
    result["state"] = mapBridgeStateToSpec(m_bridge->state());

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

QString KeycardPlugin::mapBridgeStateToSpec(KeycardBridge::State state)
{
    // Map KeycardBridge states to SPEC.md 7-state model
    switch (state) {
    case KeycardBridge::State::Unknown:
    case KeycardBridge::State::NoPCSC:
    case KeycardBridge::State::WaitingForReader:
        return "READER_NOT_FOUND";

    case KeycardBridge::State::WaitingForCard:
        return "CARD_NOT_PRESENT";

    case KeycardBridge::State::ConnectingCard:
    case KeycardBridge::State::Ready:
    case KeycardBridge::State::EmptyKeycard:
    case KeycardBridge::State::NotKeycard:
        return "CARD_PRESENT";

    case KeycardBridge::State::Authorized:
        return "AUTHORIZED";

    case KeycardBridge::State::BlockedPIN:
    case KeycardBridge::State::BlockedPUK:
        return "BLOCKED";

    case KeycardBridge::State::ConnectionError:
        return "CARD_NOT_PRESENT";
    }
    return "READER_NOT_FOUND";
}
