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

    // Actively check for card presence (helps detect cards that were inserted before detection started)
    m_bridge->isCardPresent();

    // Poll status after card check to update state
    m_bridge->pollStatus();

    QJsonObject result;
    KeycardBridge::State state = m_bridge->state();

    // Card is found if state indicates card presence (not just Ready/Authorized)
    bool cardPresent = (state == KeycardBridge::State::Ready ||
                       state == KeycardBridge::State::Authorized ||
                       state == KeycardBridge::State::ConnectingCard ||
                       state == KeycardBridge::State::EmptyKeycard ||
                       state == KeycardBridge::State::NotKeycard ||
                       state == KeycardBridge::State::BlockedPIN ||
                       state == KeycardBridge::State::BlockedPUK);

    if (cardPresent) {
        result["found"] = true;
        result["uid"] = m_bridge->keyUID();

        // Session state persists until card is removed or user re-authorizes
        // (Closed state should stay closed until explicit re-auth)
    } else {
        result["found"] = false;

        // Card removed/not present - clear any active session state
        // Ensures SESSION_ACTIVE doesn't persist after card removal
        if (m_sessionState == SessionState::Active || m_sessionState == SessionState::Closed) {
            m_sessionState = SessionState::NoSession;
        }
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::checkPairing()
{
    if (!m_bridge) {
        QJsonObject result;
        result["paired"] = false;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject checkResult = m_bridge->checkPairing();
    return QJsonDocument(checkResult).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::pairCard(const QString& pairingPassword)
{
    qDebug() << "KeycardPlugin::pairCard() called";

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized - call discoverReader first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject pairResult = m_bridge->pairCard(pairingPassword);
    return QJsonDocument(pairResult).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::unpairCard()
{
    qDebug() << "KeycardPlugin::unpairCard() called";

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized - call discoverReader first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject unpairResult = m_bridge->unpairCard();
    return QJsonDocument(unpairResult).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::authorize(const QString& pin)
{
    qDebug() << "KeycardPlugin::authorize() called";

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized - call discoverReader first";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Reset session state on new authorization
    m_sessionState = SessionState::NoSession;

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

    // Check if session is closed - require re-authorization
    if (m_sessionState == SessionState::Closed) {
        QJsonObject result;
        result["error"] = "Session closed - authorize again to derive keys";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // EIP-1581 standard: on-card BIP32 derivation at custom paths
    // Map domain to EIP-1581 BIP32 path with deeper nesting (per mikkoph feedback)
    // Path: m/43'/60'/1581'/<idx1>'/<idx2>'/<idx3>'/<idx4>'
    // Uses 16 bytes of hash for better collision resistance
    // Add "logos-" prefix for namespace separation
    QByteArray namespaced = ("logos-" + domain).toUtf8();
    unsigned char hash[32];
    crypto_hash_sha256(hash, reinterpret_cast<const unsigned char*>(namespaced.constData()), namespaced.size());

    // Extract 4 indices from hash (use hardened derivation, 31-bit values)
    uint32_t idx1 = (uint32_t(hash[0])  << 24 | uint32_t(hash[1])  << 16 |
                     uint32_t(hash[2])  << 8  | uint32_t(hash[3]))  & 0x7FFFFFFF;
    uint32_t idx2 = (uint32_t(hash[4])  << 24 | uint32_t(hash[5])  << 16 |
                     uint32_t(hash[6])  << 8  | uint32_t(hash[7]))  & 0x7FFFFFFF;
    uint32_t idx3 = (uint32_t(hash[8])  << 24 | uint32_t(hash[9])  << 16 |
                     uint32_t(hash[10]) << 8  | uint32_t(hash[11])) & 0x7FFFFFFF;
    uint32_t idx4 = (uint32_t(hash[12]) << 24 | uint32_t(hash[13]) << 16 |
                     uint32_t(hash[14]) << 8  | uint32_t(hash[15])) & 0x7FFFFFFF;

    // Construct EIP-1581 path with deeper nesting (uses 16 bytes of hash)
    QString eip1581Path = QString("m/43'/60'/1581'/%1'/%2'/%3'/%4'")
        .arg(idx1).arg(idx2).arg(idx3).arg(idx4);
    qDebug() << "KeycardPlugin::deriveKey() - domain:" << domain << "→ path:" << eip1581Path;

    // Derive key on-card at custom EIP-1581 path (real BIP32 derivation)
    QByteArray derivedKey = m_bridge->exportKey(eip1581Path);

    if (derivedKey.isEmpty()) {
        QJsonObject result;
        result["error"] = m_bridge->lastError();
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Enter SESSION_ACTIVE state
    m_sessionState = SessionState::Active;

    QJsonObject result;
    result["key"] = QString::fromUtf8(derivedKey.toHex());

    // Clear sensitive data
    sodium_memzero(derivedKey.data(), derivedKey.size());

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getState()
{
    if (!m_bridge) {
        QJsonObject result;
        result["state"] = "READER_NOT_FOUND";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Poll status to detect card/reader removal
    m_bridge->pollStatus();

    QJsonObject result;

    // Check bridge state first - clear session overlay if card is gone
    KeycardBridge::State bridgeState = m_bridge->state();
    bool cardGone = (bridgeState == KeycardBridge::State::WaitingForCard ||
                     bridgeState == KeycardBridge::State::WaitingForReader ||
                     bridgeState == KeycardBridge::State::NoPCSC ||
                     bridgeState == KeycardBridge::State::Unknown ||
                     bridgeState == KeycardBridge::State::ConnectionError);

    if (cardGone && (m_sessionState == SessionState::Active || m_sessionState == SessionState::Closed)) {
        qDebug() << "KeycardPlugin::getState() - card gone, clearing session state";
        m_sessionState = SessionState::NoSession;
    }

    // Session state takes precedence over bridge state (only if card still present)
    if (m_sessionState == SessionState::Active) {
        qDebug() << "KeycardPlugin::getState() - returning SESSION_ACTIVE";
        result["state"] = "SESSION_ACTIVE";
    } else if (m_sessionState == SessionState::Closed) {
        qDebug() << "KeycardPlugin::getState() - returning SESSION_CLOSED";
        result["state"] = "SESSION_CLOSED";
    } else {
        QString mappedState = mapBridgeStateToSpec(bridgeState);
        qDebug() << "KeycardPlugin::getState() - returning bridge state:" << mappedState << "(bridge state enum:" << static_cast<int>(bridgeState) << ")";
        result["state"] = mappedState;
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::closeSession()
{
    qDebug() << "KeycardPlugin::closeSession() called";

    // Enter SESSION_CLOSED state (keep bridge running for re-auth)
    m_sessionState = SessionState::Closed;

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

QString KeycardPlugin::testPCSC()
{
    qDebug() << "KeycardPlugin::testPCSC() - testing PC/SC directly";

    QJsonObject result;
    result["pcsc_working"] = m_bridge ? m_bridge->isCardPresent() : false;
    result["bridge_initialized"] = m_bridge != nullptr;
    if (m_bridge) {
        result["bridge_state"] = static_cast<int>(m_bridge->state());
    }

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
