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

        // Clear session overlay when card rediscovered after closeSession()
        // Allows CARD_PRESENT/AUTHORIZED to show through (SPEC.md transition semantics)
        if (m_sessionState == SessionState::Closed) {
            m_sessionState = SessionState::NoSession;
        }
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

QString KeycardPlugin::deriveKey(const QString& domain, int version)
{
    qDebug() << "KeycardPlugin::deriveKey() called, domain:" << domain << "version:" << version;

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QByteArray derivedKey;

    if (version == 1) {
        // ============================================================
        // Version 1: Current production approach (DEFAULT)
        // ============================================================
        // Uses fixed BIP32 path + SHA256 hashing for domain separation
        // Path: m/43'/60'/1581'/1'/0 (always the same)
        // Derivation: SHA256(baseKey || domain)
        //
        // Security: Cryptographically sound (SHA256 collision resistance)
        // Standard: Custom (Logos-specific)
        // Kept for backward compatibility with existing encrypted data
        // ============================================================

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

        derivedKey = QByteArray(reinterpret_cast<const char*>(hash), 32);

        // Securely wipe baseKey from memory
        sodium_memzero(baseKey.data(), baseKey.size());

        qDebug() << "KeycardPlugin::deriveKey() - using legacy v1 derivation (deprecated)";

    } else if (version == 2) {
        // ============================================================
        // Version 2: EIP-1581 path mapping (EXPERIMENTAL / INCOMPLETE)
        // ============================================================
        // CURRENT STATE: Partial implementation, not yet standards-compliant
        //
        // What works:
        // - Deterministic domain → EIP-1581 path mapping
        // - Path: m/43'/60'/1581'/key_type'/key_index (calculated from domain)
        //
        // What's missing:
        // - KeycardBridge::exportKey() doesn't use path parameter yet
        // - Still does SHA256(baseKey || eip1581Path) on host side
        // - NOT true on-card BIP32 derivation at different paths
        //
        // This is SCAFFOLDING for future real EIP-1581 implementation.
        // Do NOT use in production until KeycardBridge supports custom paths.
        //
        // TODO: Update KeycardBridge::exportKey() to actually derive at path
        // Reference: https://eips.ethereum.org/EIPS/eip-1581
        // Feedback: Recommended by @mikkoph (Keycard core dev)
        // ============================================================

        QString eip1581Path = domainToEIP1581Path(domain);
        qDebug() << "KeycardPlugin::deriveKey() - EIP-1581 path (NOT YET USED):" << eip1581Path;

        QByteArray baseKey = m_bridge->exportKey();  // Still fixed path!

        if (baseKey.isEmpty()) {
            QJsonObject result;
            result["error"] = m_bridge->lastError();
            return QJsonDocument(result).toJson(QJsonDocument::Compact);
        }

        // WARNING: Still using host-side hashing, not real EIP-1581!
        // This is just v1 with path string instead of domain string
        QByteArray pathBytes = eip1581Path.toUtf8();
        QByteArray combined = baseKey + pathBytes;

        unsigned char hash[32];
        crypto_hash_sha256(hash, reinterpret_cast<const unsigned char*>(combined.constData()), combined.size());

        derivedKey = QByteArray(reinterpret_cast<const char*>(hash), 32);

        // Securely wipe baseKey from memory
        sodium_memzero(baseKey.data(), baseKey.size());

        qDebug() << "KeycardPlugin::deriveKey() - using EIP-1581 v2 derivation (default)";

    } else {
        QJsonObject result;
        result["error"] = QString("Invalid version: %1 (supported: 1=legacy, 2=EIP-1581)").arg(version);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Enter SESSION_ACTIVE state
    m_sessionState = SessionState::Active;

    QJsonObject result;
    result["key"] = QString::fromUtf8(derivedKey.toHex());
    result["version"] = version;  // Include version in response for debugging

    // Securely wipe derivedKey from stack memory
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

    QJsonObject result;

    // Check bridge state first - clear session overlay if card is gone
    KeycardBridge::State bridgeState = m_bridge->state();
    bool cardGone = (bridgeState == KeycardBridge::State::WaitingForCard ||
                     bridgeState == KeycardBridge::State::WaitingForReader ||
                     bridgeState == KeycardBridge::State::NoPCSC ||
                     bridgeState == KeycardBridge::State::Unknown ||
                     bridgeState == KeycardBridge::State::ConnectionError);

    if (cardGone && (m_sessionState == SessionState::Active || m_sessionState == SessionState::Closed)) {
        m_sessionState = SessionState::NoSession;
    }

    // Session state takes precedence over bridge state (only if card still present)
    if (m_sessionState == SessionState::Active) {
        result["state"] = "SESSION_ACTIVE";
    } else if (m_sessionState == SessionState::Closed) {
        result["state"] = "SESSION_CLOSED";
    } else {
        result["state"] = mapBridgeStateToSpec(bridgeState);
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

QString KeycardPlugin::domainToEIP1581Path(const QString& domain)
{
    // EIP-1581 compliant path derivation: map domain string to BIP32 indices
    // Reference: https://eips.ethereum.org/EIPS/eip-1581
    // Path structure: m/43'/60'/1581'/key_type'/key_index

    // Namespace separation: prefix with "logos-" to prevent collision with other apps
    QByteArray namespaced = ("logos-" + domain).toUtf8();

    // Hash to get deterministic indices
    unsigned char hash[32];
    crypto_hash_sha256(hash,
        reinterpret_cast<const unsigned char*>(namespaced.constData()),
        namespaced.size());

    // Extract two 31-bit values from hash
    // First 4 bytes → key_type (hardened)
    uint32_t keyType = (
        (static_cast<uint32_t>(hash[0]) << 24) |
        (static_cast<uint32_t>(hash[1]) << 16) |
        (static_cast<uint32_t>(hash[2]) << 8) |
        static_cast<uint32_t>(hash[3])
    ) & 0x7FFFFFFF;  // Mask to 31 bits (hardened derivation range)

    // Next 4 bytes → key_index (unhardened at final level)
    uint32_t keyIndex = (
        (static_cast<uint32_t>(hash[4]) << 24) |
        (static_cast<uint32_t>(hash[5]) << 16) |
        (static_cast<uint32_t>(hash[6]) << 8) |
        static_cast<uint32_t>(hash[7])
    ) & 0x7FFFFFFF;  // Mask to 31 bits

    // Build full EIP-1581 path
    // m/43'/60'/1581' is the fixed EIP-1581 prefix for Ethereum non-wallet keys
    return QString("m/43'/60'/1581'/%1'/%2").arg(keyType).arg(keyIndex);
}
