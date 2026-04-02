#include "plugin.h"
#include "KeycardBridge.h"
#include <keycard-qt/command_set.h>
#include <keycard-qt/types.h>
#include <keycard-qt/tlv_utils.h>
#include <PCSC/winscard.h>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUuid>
#include <QDateTime>
#include <QCryptographicHash>
#include <QDebug>
#include <QRegularExpression>
#include <algorithm>
#include <array>
#include <sodium.h>
#include <vector>

KeycardPlugin::KeycardPlugin(QObject* parent)
    : QObject(parent)
    , m_bridge(nullptr)
{
    qDebug() << "KeycardPlugin constructed";
}

KeycardPlugin::~KeycardPlugin()
{
    // Wipe all pending requests on unload — SecureBuffer destructors wipe key material via RAII
    purgeCompletedRequests();
    m_authRequests.clear();
    m_signRequests.clear();
    m_xpubRequests.clear();

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

    logActivity("Looking for smart card reader...", "info");

    if (!m_bridge) {
        m_bridge = new KeycardBridge(this);
    }

    // Always start (initializes if needed)
    bool success = m_bridge->start();

    // Fresh poll even if bridge was already running (fixes #9: cached reader state)
    if (m_bridge->isRunning()) {
        m_bridge->pollStatus();
        KeycardBridge::State state = m_bridge->state();
        success = (state != KeycardBridge::State::WaitingForReader &&
                   state != KeycardBridge::State::NoPCSC &&
                   state != KeycardBridge::State::Unknown);
    }

    QJsonObject result;
    result["found"] = success;
    if (success) {
        result["name"] = "Smart card reader";
        logActivity("Smart card reader detected", "success");
    } else {
        logActivity("Smart card reader not found", "error");
    }

    addActivityToResponse(result);
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
        QString uid = m_bridge->keyUID();
        result["uid"] = uid;
        logActivity(QString("Keycard detected, UID: %1").arg(uid), "success");

        // Check pairing status
        logActivity("Pairing...", "info");
        QJsonObject pairingCheck = m_bridge->checkPairing();
        if (pairingCheck["paired"].toBool()) {
            int slot = pairingCheck["pairingIndex"].toInt();
            logActivity(QString("Existing pairing found, slot %1").arg(slot), "success");
        }

        logActivity("Ready", "success");
    } else {
        result["found"] = false;
        logActivity("Keycard not found", "error");

        // Card removed/not present - clear any active session state
        // Ensures SESSION_ACTIVE doesn't persist after card removal
        if (m_sessionState == SessionState::Active || m_sessionState == SessionState::NoSession) {
            m_sessionState = SessionState::NoSession;
        }
    }

    addActivityToResponse(result);
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

    logActivity("Pairing...", "info");

    QJsonObject checkResult = m_bridge->checkPairing();

    if (checkResult["paired"].toBool()) {
        int slot = checkResult["pairingIndex"].toInt();
        logActivity(QString("Existing pairing found, slot %1").arg(slot), "success");
    }

    addActivityToResponse(checkResult);
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

    logActivity("Creating new pairing...", "info");

    QJsonObject pairResult = m_bridge->pairCard(pairingPassword);

    if (!pairResult["paired"].toBool()) {
        QString error = pairResult["error"].toString();
        // Check for no free slots error
        if (error.contains("no free", Qt::CaseInsensitive) ||
            error.contains("no slot", Qt::CaseInsensitive) ||
            error.contains("slots", Qt::CaseInsensitive)) {
            logActivity("No free pairing slots available", "error");
        }
    }

    addActivityToResponse(pairResult);
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

    // Check if session is closed - require re-authorization
    if (m_sessionState == SessionState::NoSession) {
        QJsonObject result;
        result["unpaired"] = false;
        result["error"] = "Session closed - authorize again to unpair card";
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

    // Accept JSON object {"pin":"XXXXXX"} or raw string (logoscore CLI compat)
    QString actualPin = pin;
    QJsonDocument doc = QJsonDocument::fromJson(pin.toUtf8());
    if (!doc.isNull() && doc.isObject()) {
        actualPin = doc.object().value("pin").toString();
    }

    // Authorize with card
    QJsonObject authResult = m_bridge->authorize(actualPin);

    // If successful, start session
    if (authResult.value("authorized").toBool()) {
        m_sessionState = SessionState::Active;
        logActivity("Session active", "success");
    } else {
        m_sessionState = SessionState::NoSession;
        int remaining = authResult.value("remainingAttempts").toInt(-1);
        if (remaining == 0) {
            logActivity("Wrong PIN, Keycard blocked", "error");
        } else if (remaining == 1) {
            logActivity("Wrong PIN, 1 attempt left", "error");
            logActivity("Try again", "warning");
        } else if (remaining > 1) {
            logActivity(QString("Wrong PIN, %1 attempts left").arg(remaining), "error");
            logActivity("Try again", "warning");
        } else {
            // remaining == -1 (unknown)
            logActivity("Wrong PIN", "error");
            logActivity("Try again", "warning");
        }
    }

    addActivityToResponse(authResult);
    return QJsonDocument(authResult).toJson(QJsonDocument::Compact);
}

// domainToIndices — SHA256("logos-"||domain), take first 16 bytes as four hardened BIP32 indices.
// "logos-" prefix for namespace separation; 16 bytes of hash for collision resistance.
static std::array<uint32_t, 4> domainToIndices(const QString& domain)
{
    QByteArray namespaced = ("logos-" + domain).toUtf8();
    unsigned char hash[32];
    crypto_hash_sha256(hash, reinterpret_cast<const unsigned char*>(namespaced.constData()), namespaced.size());

    return {{
        (uint32_t(hash[0])  << 24 | uint32_t(hash[1])  << 16 | uint32_t(hash[2])  << 8 | uint32_t(hash[3]))  & 0x7FFFFFFF,
        (uint32_t(hash[4])  << 24 | uint32_t(hash[5])  << 16 | uint32_t(hash[6])  << 8 | uint32_t(hash[7]))  & 0x7FFFFFFF,
        (uint32_t(hash[8])  << 24 | uint32_t(hash[9])  << 16 | uint32_t(hash[10]) << 8 | uint32_t(hash[11])) & 0x7FFFFFFF,
        (uint32_t(hash[12]) << 24 | uint32_t(hash[13]) << 16 | uint32_t(hash[14]) << 8 | uint32_t(hash[15])) & 0x7FFFFFFF,
    }};
}

QString KeycardPlugin::domainToPath(const QString& domain)
{
    auto idx = domainToIndices(domain);
    return QString("m/43'/60'/1581'/%1'/%2'/%3'/%4'").arg(idx[0]).arg(idx[1]).arg(idx[2]).arg(idx[3]);
}

// domainToSignPath — same hash → indices as domainToPath, but rooted at m/43'/60'/1582'.
// 1582' is a non-exportable subtree: chain code export is not permitted there, so signing
// keys derived here cannot be exfiltrated via the EXPORT_KEY APDU. (#150)
QString KeycardPlugin::domainToSignPath(const QString& domain)
{
    auto idx = domainToIndices(domain);
    return QString("m/43'/60'/1582'/%1'/%2'/%3'/%4'").arg(idx[0]).arg(idx[1]).arg(idx[2]).arg(idx[3]);
}

QString KeycardPlugin::deriveKey(const QString& domain)
{
    qDebug() << "KeycardPlugin::deriveKey() called, domain:" << domain;

    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Check if session is not active - require authorization
    if (m_sessionState != SessionState::Active) {
        QJsonObject result;
        result["error"] = "No active session - authorize to derive keys";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QString eip1581Path = domainToPath(domain);
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
    result["path"] = eip1581Path;

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

    // Poll status to detect card/reader removal (skip during authorize)
    if (!m_bridge->isOperationInProgress())
        m_bridge->pollStatus();

    QJsonObject result;

    // Check bridge state first - clear session overlay if card is gone
    KeycardBridge::State bridgeState = m_bridge->state();
    bool cardGone = (bridgeState == KeycardBridge::State::WaitingForCard ||
                     bridgeState == KeycardBridge::State::WaitingForReader ||
                     bridgeState == KeycardBridge::State::NoPCSC ||
                     bridgeState == KeycardBridge::State::Unknown ||
                     bridgeState == KeycardBridge::State::ConnectionError);

    if (cardGone && (m_sessionState == SessionState::Active || m_sessionState == SessionState::NoSession)) {
        qDebug() << "KeycardPlugin::getState() - card gone, clearing session state";
        m_sessionState = SessionState::NoSession;
        purgeCompletedRequests();
    }

    // Session state takes precedence over bridge state (only if card still present)
    if (m_sessionState == SessionState::Active) {
        qDebug() << "KeycardPlugin::getState() - returning SESSION_ACTIVE";
        result["state"] = "SESSION_ACTIVE";
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

    // Reset session state (keep bridge running for future requests)
    m_sessionState = SessionState::NoSession;

    // SECURITY: Wipe and remove all completed/consumed auth requests
    purgeCompletedRequests();

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

QString KeycardPlugin::checkReaderPresent()
{
    // Skip during multi-step operations to avoid PC/SC contention
    if (m_bridge && m_bridge->isOperationInProgress()) {
        QJsonObject result;
        result["found"] = true;  // Optimistic — card was present when operation started
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Direct PC/SC check — no bridge, no cache
    SCARDCONTEXT hContext;
    LONG rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
    if (rv != SCARD_S_SUCCESS) {
        QJsonObject result;
        result["found"] = false;
        result["error"] = "PC/SC not available";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Two-step: get required size first, then fill — avoids SCARD_AUTOALLOCATE type-pun
    DWORD dwReaders = 0;
    rv = SCardListReaders(hContext, NULL, NULL, &dwReaders);
    bool found = false;
    if (rv == SCARD_S_SUCCESS && dwReaders > 1) {
        std::vector<char> readersBuf(dwReaders);
        rv = SCardListReaders(hContext, NULL, readersBuf.data(), &dwReaders);
        found = (rv == SCARD_S_SUCCESS && dwReaders > 1);
    }

    SCardReleaseContext(hContext);

    QJsonObject result;
    result["found"] = found;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::checkCardPresent()
{
    // Skip during multi-step operations to avoid PC/SC contention
    if (m_bridge && m_bridge->isOperationInProgress()) {
        QJsonObject result;
        result["found"] = true;  // Optimistic — card was present when operation started
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Direct PC/SC check — no bridge, no cache
    SCARDCONTEXT hContext;
    LONG rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
    if (rv != SCARD_S_SUCCESS) {
        QJsonObject result;
        result["found"] = false;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Two-step: get required size first, then fill — avoids SCARD_AUTOALLOCATE type-pun
    DWORD dwReaders = 0;
    rv = SCardListReaders(hContext, NULL, NULL, &dwReaders);
    if (rv != SCARD_S_SUCCESS || dwReaders <= 1) {
        SCardReleaseContext(hContext);
        QJsonObject result;
        result["found"] = false;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
    std::vector<char> readersBuf(dwReaders);
    rv = SCardListReaders(hContext, NULL, readersBuf.data(), &dwReaders);
    if (rv != SCARD_S_SUCCESS) {
        SCardReleaseContext(hContext);
        QJsonObject result;
        result["found"] = false;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    bool cardFound = false;
    char* reader = readersBuf.data();
    while (*reader != '\0') {
        SCARD_READERSTATE readerState;
        memset(&readerState, 0, sizeof(readerState));
        readerState.szReader = reader;
        readerState.dwCurrentState = SCARD_STATE_UNAWARE;

        rv = SCardGetStatusChange(hContext, 0, &readerState, 1);
        if (rv == SCARD_S_SUCCESS && (readerState.dwEventState & SCARD_STATE_PRESENT)) {
            cardFound = true;
            break;
        }
        reader += strlen(reader) + 1;
    }

    SCardReleaseContext(hContext);

    QJsonObject result;
    result["found"] = cardFound;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::unblockPIN(const QString& puk, const QString& newPIN)
{
    qDebug() << "KeycardPlugin::unblockPIN() called";

    if (!m_bridge) {
        QJsonObject result;
        result["success"] = false;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    if (!m_bridge->commandSet()) {
        QJsonObject result;
        result["success"] = false;
        result["error"] = "No command set - card not connected";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    try {
        auto cs = m_bridge->commandSet();
        if (!cs) {
            QJsonObject result;
            result["success"] = false;
            result["error"] = "Command set not available";
            return QJsonDocument(result).toJson(QJsonDocument::Compact);
        }

        // Select applet and open secure channel for unblock
        cs->select();

        // Load pairing for secure channel
        auto pairingResult = m_bridge->checkPairing();
        if (!pairingResult.value("paired").toBool()) {
            QJsonObject result;
            result["success"] = false;
            result["error"] = "Card not paired - cannot open secure channel";
            addActivityToResponse(result);
            return QJsonDocument(result).toJson(QJsonDocument::Compact);
        }

        bool success = cs->unblockPIN(puk, newPIN);

        QJsonObject result;
        result["success"] = success;
        if (success) {
            logActivity("PIN unblocked successfully", "success");
        } else {
            result["error"] = "Unblock failed - wrong PUK?";
            logActivity("PIN unblock failed", "error");
        }
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);

    } catch (const std::exception& e) {
        QJsonObject result;
        result["success"] = false;
        result["error"] = QString(e.what());
        logActivity(QString("PIN unblock error: %1").arg(e.what()), "error");
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
}

QString KeycardPlugin::getCardStatus()
{
    if (!m_bridge) {
        QJsonObject result;
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject result;
    result["state"] = static_cast<int>(m_bridge->state());
    result["pinAttempts"] = m_bridge->remainingPINAttempts();
    result["pukAttempts"] = m_bridge->remainingPUKAttempts();
    result["blocked"] = (m_bridge->state() == KeycardBridge::State::BlockedPIN);
    result["keyInitialized"] = m_bridge->keyInitialized();
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::detectMode()
{
    QJsonObject result;
    if (!m_bridge) {
        result["error"] = "Bridge not initialized";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    switch (m_bridge->keyMode()) {
    case KeycardBridge::KeyMode::LEE:
        result["mode"] = "LEE";
        break;
    case KeycardBridge::KeyMode::BIP39:
        result["mode"] = "BIP39";
        break;
    default:
        result["mode"] = "none";
        break;
    }
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::loadKey(const QString& jsonArgs)
{
    QJsonObject result;
    if (!m_bridge || !m_bridge->commandSet()) {
        result["error"] = "Not connected";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
    QJsonDocument doc = QJsonDocument::fromJson(jsonArgs.toUtf8());
    if (doc.isNull() || !doc.isObject()) {
        result["error"] = "Expected JSON object {\"seedHex\":\"...\",\"keyType\":\"lee\"|\"bip39\"}";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
    QJsonObject args = doc.object();
    QString seedHex    = args.value("seedHex").toString();
    QString keyTypeStr = args.value("keyType").toString().toLower();
    if (keyTypeStr != "lee" && keyTypeStr != "bip39") {
        result["error"] = "Invalid keyType — must be \"lee\" or \"bip39\"";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QByteArray seed = QByteArray::fromHex(seedHex.toLatin1());
    if (seed.size() != 64) {
        result["error"] = "Seed must be 64 bytes (128 hex chars)";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
    auto cs = m_bridge->commandSet();
    QByteArray keyUID = cs->loadKey(seed, keyTypeStr == "lee" ? uint8_t(1) : uint8_t(0));
    if (keyUID.isEmpty()) {
        result["error"] = cs->lastError();
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
    // Update cached key mode so detectMode() reflects the new state without requiring SELECT
    m_bridge->setKeyMode(keyTypeStr == "lee" ? KeycardBridge::KeyMode::LEE : KeycardBridge::KeyMode::BIP39);
    result["keyUID"] = QString::fromUtf8(keyUID.toHex());
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::removeKey()
{
    QJsonObject result;
    if (!m_bridge || !m_bridge->commandSet()) {
        result["error"] = "Not connected";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }
    bool ok = m_bridge->commandSet()->removeKey();
    result["ok"] = ok;
    if (!ok) {
        result["error"] = m_bridge->commandSet()->lastError();
    } else {
        // Update cached key mode so detectMode() reflects the new state
        m_bridge->setKeyMode(KeycardBridge::KeyMode::None);
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

QString KeycardPlugin::getCardPresence()
{
    QJsonObject result;

    if (!m_bridge) {
        result["present"] = false;
        result["readerConnected"] = false;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    m_bridge->pollStatus();
    KeycardBridge::State bridgeState = m_bridge->state();

    bool cardPresent = (bridgeState == KeycardBridge::State::Ready ||
                        bridgeState == KeycardBridge::State::Authorized ||
                        bridgeState == KeycardBridge::State::ConnectingCard ||
                        bridgeState == KeycardBridge::State::EmptyKeycard ||
                        bridgeState == KeycardBridge::State::NotKeycard ||
                        bridgeState == KeycardBridge::State::BlockedPIN ||
                        bridgeState == KeycardBridge::State::BlockedPUK);

    bool readerConnected = (bridgeState != KeycardBridge::State::Unknown &&
                            bridgeState != KeycardBridge::State::NoPCSC &&
                            bridgeState != KeycardBridge::State::WaitingForReader);

    result["present"] = cardPresent;
    result["readerConnected"] = readerConnected;
    if (cardPresent && !m_bridge->keyUID().isEmpty()) {
        result["uid"] = m_bridge->keyUID();
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

// Authorization request API implementation (Option C: Module-Managed Auth State)

QString KeycardPlugin::requestAuth(const QString& domain, const QString& caller)
{
    // Generate unique auth request ID
    QString authId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    AuthRequest request;
    request.id = authId;
    request.domain = domain;
    request.caller = caller;
    request.status = "pending";
    request.timestamp = QDateTime::currentMSecsSinceEpoch();

    m_authRequests.push_back(std::move(request));

    QString shortId = authId.left(8);
    logActivity(QString("[%1] Module %2 requesting access to domain %3").arg(shortId, caller, domain), "warning");

    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "pending";
    result["message"] = "Authorization request created. Open Keycard UI to complete.";

    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::checkAuthStatus(const QString& authId)
{
    for (size_t i = 0; i < m_authRequests.size(); ++i) {
        auto& req = m_authRequests[i];
        if (req.id == authId) {
            QJsonObject result;
            result["authId"] = authId;
            result["domain"] = req.domain;
            result["caller"] = req.caller;

            if (req.status == "complete") {
                // SECURITY: One-read-and-drop — return key exactly once,
                // then wipe the SecureBuffer and remove the request.
                result["status"] = "complete";
                QByteArray keyHex = req.key.ref().toHex();
                result["key"] = QString::fromUtf8(keyHex);
                // Wipe the hex intermediate before it leaves scope
                sodium_memzero(keyHex.data(), keyHex.size());
                req.key.wipe();
                m_loggedRequestIds.remove(authId);
                m_authRequests.erase(m_authRequests.begin() + i);

                return QJsonDocument(result).toJson(QJsonDocument::Compact);
            }

            // Only expose pending/complete/declined to calling modules
            // Wrong PIN / internal errors stay as "pending"
            result["status"] = req.status;
            return QJsonDocument(result).toJson(QJsonDocument::Compact);
        }
    }

    QJsonObject result;
    result["error"] = "Auth request not found";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getPendingAuths()
{
    QJsonArray pending;

    for (auto& req : m_authRequests) {
        if (req.status == "pending") {
            QJsonObject obj;
            obj["authId"] = req.id;
            obj["domain"] = req.domain;
            obj["caller"] = req.caller;
            obj["timestamp"] = req.timestamp;
            pending.append(obj);

            // Log new requests that haven't been logged yet
            if (!m_loggedRequestIds.contains(req.id)) {
                QString shortId = req.id.left(8);
                logActivity(QString("[%1] New request from module %2 for domain %3").arg(shortId, req.caller, req.domain), "warning");
                m_loggedRequestIds.insert(req.id);
            }
        }
    }

    QJsonObject result;
    result["pending"] = pending;
    result["count"] = pending.size();

    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::authorizeRequest(const QString& authId, const QString& pin)
{
    qDebug() << "KeycardPlugin::authorizeRequest() called for authId:" << authId;

    // Find pending request
    AuthRequest* targetRequest = nullptr;
    for (auto& req : m_authRequests) {
        if (req.id == authId && req.status == "pending") {
            targetRequest = &req;
            break;
        }
    }

    if (!targetRequest) {
        QJsonObject result;
        result["error"] = "Auth request not found or already completed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Lock out concurrent PC/SC access for the entire authorize+derive sequence
    if (m_bridge) m_bridge->setOperationInProgress(true);

    // SECURITY: Verify PIN first (hardware verification)
    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();

    if (!authResult.value("authorized").toBool()) {
        if (m_bridge) m_bridge->setOperationInProgress(false);

        // Request stays "pending" — wrong PIN is keycard-internal,
        // calling module only sees pending/complete/declined
        int remaining = authResult.value("remainingAttempts").toInt(-1);

        QJsonObject result;
        result["authId"] = authId;
        result["status"] = "retry";
        result["remainingAttempts"] = remaining;
        // Propagate error from authorize() so UI shows real failure reason
        if (authResult.contains("error"))
            result["error"] = authResult["error"];

        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // SECURITY: Derive key from hardware (only after PIN verified)
    QString domain = targetRequest->domain;
    QString deriveResponse = deriveKey(domain);
    QByteArray deriveResponseUtf8 = deriveResponse.toUtf8();
    QJsonObject keyResult = QJsonDocument::fromJson(deriveResponseUtf8).object();
    // Wipe the raw JSON response bytes (contains key hex)
    sodium_memzero(deriveResponseUtf8.data(), deriveResponseUtf8.size());
    sodium_memzero(deriveResponse.data(), deriveResponse.size() * sizeof(QChar));

    if (keyResult.contains("error")) {
        if (m_bridge) m_bridge->setOperationInProgress(false);

        // Key derivation failed — request stays pending, user can retry
        logActivity("Key derivation failed: " + keyResult.value("error").toString(), "error");

        QJsonObject result;
        result["authId"] = authId;
        result["status"] = "retry";

        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // SECURITY: Extract key from JSON, store in SecureBuffer, wipe all intermediates.
    targetRequest->status = "complete";
    QString hexKey = keyResult.value("key").toString();
    QByteArray hexKeyUtf8 = hexKey.toUtf8();
    QByteArray keyBytes = QByteArray::fromHex(hexKeyUtf8);
    targetRequest->key = SecureBuffer(std::move(keyBytes));
    // Wipe all intermediate buffers that touched key material
    sodium_memzero(hexKeyUtf8.data(), hexKeyUtf8.size());
    sodium_memzero(hexKey.data(), hexKey.size() * sizeof(QChar));

    // Extract non-secret fields before wiping the JSON object's key entry
    QString moduleName = targetRequest->caller;
    QString derivedPath = keyResult.value("path").toString();
    // Remove key from the parsed JSON object so it doesn't linger
    keyResult.remove("key");
    QString shortId = authId.left(8);
    logActivity(QString("[%1] Request from %2 approved for domain %3").arg(shortId, moduleName, domain), "success");
    logActivity(QString("[%1] Key derived for %2 via path %3").arg(shortId, moduleName, derivedPath), "success");

    // Release operation lock before session cleanup
    if (m_bridge) m_bridge->setOperationInProgress(false);

    // Auto-close session after approval (Epic #55: no persistent session)
    m_sessionState = SessionState::NoSession;
    logActivity("Session closed", "success");
    logActivity(QString("Go back to %1 module to continue").arg(moduleName), "warning");

    // Notify caller module — no key material in event, just authId + caller as signal.
    // Receiver calls checkAuthStatus(authId) to retrieve the key (one-read-and-drop).
    emit eventResponse("keycardAuthComplete", {authId, moduleName});

    // SECURITY: Do NOT return key here. The only path that hands out
    // the derived key is checkAuthStatus() — one-read-and-drop.
    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "complete";
    result["message"] = "Authorization completed. Poll checkAuthStatus to retrieve key.";

    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::rejectRequest(const QString& authId)
{
    qDebug() << "KeycardPlugin::rejectRequest() called for authId:" << authId;

    // Find pending request
    AuthRequest* targetRequest = nullptr;
    for (auto& req : m_authRequests) {
        if (req.id == authId && req.status == "pending") {
            targetRequest = &req;
            break;
        }
    }

    if (!targetRequest) {
        QJsonObject result;
        result["error"] = "Auth request not found or already completed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Mark as rejected
    QString caller = targetRequest->caller;
    targetRequest->status = "rejected";
    QString shortId = authId.left(8);
    logActivity(QString("[%1] Request from %2 declined for domain %3").arg(shortId, caller, targetRequest->domain), "warning");

    // Remove from logged set (cleanup)
    m_loggedRequestIds.remove(authId);

    // Notify caller module — event-driven, no polling needed.
    emit eventResponse("keycardAuthRejected", {authId, caller});

    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "rejected";
    result["message"] = "Authorization request declined by user";

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::hashMessage(const QString& message)
{
    QByteArray hash = QCryptographicHash::hash(message.toUtf8(), QCryptographicHash::Sha256);
    QJsonObject result;
    result["hash"] = QString::fromLatin1(hash.toHex());
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

// --- Signing request API (#98) ---

QString KeycardPlugin::requestSign(const QString& jsonArgs)
{
    QJsonDocument doc = QJsonDocument::fromJson(jsonArgs.toUtf8());
    if (doc.isNull() || !doc.isObject()) {
        QJsonObject err;
        err["error"] = "Expected JSON object: {\"domain\",\"payloadHash\",\"caller\",\"scheme\"}";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    QJsonObject args = doc.object();
    QString domain      = args.value("domain").toString();
    QString payloadHash = args.value("payloadHash").toString();
    QString caller      = args.value("caller").toString();
    QString scheme      = args.value("scheme").toString().toLower();
    QString bip32_path  = args.value("bip32_path").toString();  // optional (#149)

    // Either domain or bip32_path must be present (bip32_path takes precedence)
    if (bip32_path.isEmpty() && domain.isEmpty()) {
        QJsonObject err;
        err["error"] = "Provide either domain or bip32_path";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    if (payloadHash.isEmpty() || caller.isEmpty()) {
        QJsonObject err;
        err["error"] = "Missing required fields: payloadHash, caller";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    if (scheme != "ecdsa" && scheme != "schnorr") {
        QJsonObject err;
        err["error"] = "scheme must be \"ecdsa\" or \"schnorr\"";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    if (QByteArray::fromHex(payloadHash.toUtf8()).size() != 32) {
        QJsonObject err;
        err["error"] = "payloadHash must be hex-encoded 32 bytes";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    if (!bip32_path.isEmpty()) {
        // Format-only validation — card enforces all policy (0x6985 for restricted paths).
        static const QRegularExpression kPathRe(R"(^m(/\d+'?){0,10}$)");
        if (!kPathRe.match(bip32_path).hasMatch()) {
            QJsonObject err;
            err["error"] = QStringLiteral("bip32_path format invalid — expected m(/N'?){0,10}");
            return QJsonDocument(err).toJson(QJsonDocument::Compact);
        }
    }

    // No card-presence check here — requests are queued before the card is inserted.
    // keycard-ui polls getPendingSignRequests after card detection and calls approveSign.
    // Mode-mismatch check happens in approveSign when the card is actually present.

    QString signId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    SignRequest req;
    req.id          = signId;
    req.domain      = domain;
    req.payloadHash = payloadHash;
    req.caller      = caller;
    req.scheme      = scheme;
    req.bip32_path  = bip32_path;
    req.status      = "pending";
    req.timestamp   = QDateTime::currentMSecsSinceEpoch();
    m_signRequests.push_back(std::move(req));

    QString shortId = signId.left(8);
    logActivity(QString("[%1] Module %2 requesting %3 sign for domain %4 (payload: %5…)")
        .arg(shortId, caller, scheme, domain, payloadHash.left(16)), "warning");

    QJsonObject result;
    result["signId"] = signId;
    result["status"] = "pending";
    result["message"] = "Sign request created. Open Keycard UI to approve.";
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::checkSignStatus(const QString& jsonOrId)
{
    // Accept {"signId":"..."} or plain UUID string
    QString signId = jsonOrId;
    QJsonDocument doc = QJsonDocument::fromJson(jsonOrId.toUtf8());
    if (!doc.isNull() && doc.isObject())
        signId = doc.object().value("signId").toString();

    for (size_t i = 0; i < m_signRequests.size(); ++i) {
        auto& req = m_signRequests[i];
        if (req.id != signId) continue;

        QJsonObject result;
        result["signId"] = signId;
        result["domain"] = req.domain;
        result["caller"] = req.caller;
        result["scheme"] = req.scheme;

        if (req.status == "complete") {
            // SECURITY: One-read-and-drop — return signature exactly once, then wipe.
            result["status"] = "complete";
            QByteArray sigHex = req.signature.ref().toHex();
            result["signature"] = QString::fromUtf8(sigHex);
            sodium_memzero(sigHex.data(), sigHex.size());
            req.signature.wipe();
            m_loggedRequestIds.remove(signId);
            m_signRequests.erase(m_signRequests.begin() + i);
            return QJsonDocument(result).toJson(QJsonDocument::Compact);
        }

        result["status"] = req.status;
        if (!req.error.isEmpty()) result["error"] = req.error;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject result;
    result["error"] = "Sign request not found";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getPendingSigns()
{
    QJsonArray pending;
    for (auto& req : m_signRequests) {
        if (req.status != "pending") continue;
        QJsonObject obj;
        obj["signId"]      = req.id;
        obj["domain"]      = req.domain;
        obj["caller"]      = req.caller;
        obj["scheme"]      = req.scheme;
        obj["payloadHash"] = req.payloadHash;
        obj["timestamp"]   = req.timestamp;
        if (!req.bip32_path.isEmpty())
            obj["bip32_path"] = req.bip32_path;
        // effective_path is what will actually be signed on-card — shown in approval UI.
        obj["effective_path"] = req.bip32_path.isEmpty()
                                ? domainToSignPath(req.domain)
                                : req.bip32_path;
        pending.append(obj);

        if (!m_loggedRequestIds.contains(req.id)) {
            QString shortId = req.id.left(8);
            QString pathDesc = req.bip32_path.isEmpty()
                ? QString("domain %1").arg(req.domain)
                : QString("path %1").arg(req.bip32_path);
            logActivity(QString("[%1] New %2 sign request from %3 for %4")
                .arg(shortId, req.scheme, req.caller, pathDesc), "warning");
            m_loggedRequestIds.insert(req.id);
        }
    }
    QJsonObject result;
    result["pending"] = pending;
    result["count"]   = pending.size();
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::approveSign(const QString& jsonArgs)
{
    QJsonDocument doc = QJsonDocument::fromJson(jsonArgs.toUtf8());
    if (doc.isNull() || !doc.isObject()) {
        QJsonObject err;
        err["error"] = "Expected JSON object: {\"signId\",\"pin\"}";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    QString signId = doc.object().value("signId").toString();
    QString pin    = doc.object().value("pin").toString();

    if (signId.isEmpty() || pin.isEmpty()) {
        QJsonObject err;
        err["error"] = "Missing required fields: signId, pin";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }

    qDebug() << "KeycardPlugin::approveSign() called for signId:" << signId;

    SignRequest* req = nullptr;
    for (auto& r : m_signRequests) {
        if (r.id == signId && r.status == "pending") { req = &r; break; }
    }
    if (!req) {
        QJsonObject result;
        result["error"] = "Sign request not found or already completed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    if (m_bridge) m_bridge->setOperationInProgress(true);

    // Step 1: verify PIN (opens SC)
    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();
    if (!authResult.value("authorized").toBool()) {
        if (m_bridge) m_bridge->setOperationInProgress(false);
        QJsonObject result;
        result["signId"] = signId;
        if (authResult.contains("error")) {
            // Transport or readiness failure (card removed, reader missing, bridge not init)
            // Surface the real error instead of normalising to retry
            result["status"] = "failed";
            result["error"] = authResult.value("error").toString();
        } else {
            // Card returned wrong PIN — safe to retry
            result["status"] = "retry";
            result["remainingAttempts"] = authResult.value("remainingAttempts").toInt(-1);
        }
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Step 2: sign on-card — private key never leaves card.
    // bip32_path takes precedence (wallet use case, #149).
    // Domain-based signing uses 1582' subtree — non-exportable, separate from XPUB (#150).
    QString path = req->bip32_path.isEmpty()
                   ? domainToSignPath(req->domain)
                   : req->bip32_path;
    QByteArray hashBytes = QByteArray::fromHex(req->payloadHash.toUtf8());

    uint8_t schemeP2 = (req->scheme == "schnorr") ? Keycard::APDU::P2SignSchnorr
                                                   : Keycard::APDU::P2SignECDSA;

    QByteArray sigBytes = m_bridge->commandSet()->signWithPath(hashBytes, path, false, schemeP2);
    sodium_memzero(hashBytes.data(), hashBytes.size());

    if (m_bridge) m_bridge->setOperationInProgress(false);

    if (sigBytes.isEmpty()) {
        req->status = "failed";
        req->error  = m_bridge ? m_bridge->commandSet()->lastError() : "Signing failed";
        QString shortId = signId.left(8);
        logActivity(QString("[%1] Signing failed: %2").arg(shortId, req->error), "error");
        QJsonObject result;
        result["signId"] = signId;
        result["status"] = "failed";
        result["error"]  = req->error;
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // SECURITY: Store in SecureBuffer; hand out only via checkSignStatus (one-read-and-drop).
    req->status    = "complete";
    req->signature = SecureBuffer(std::move(sigBytes));

    QString shortId = signId.left(8);
    logActivity(QString("[%1] %2 signature produced for %3 domain %4")
        .arg(shortId, req->scheme, req->caller, req->domain), "success");

    m_sessionState = SessionState::NoSession;
    logActivity("Session closed", "success");

    QJsonObject result;
    result["signId"]  = signId;
    result["status"]  = "complete";
    result["message"] = "Signing completed. Poll checkSignStatus to retrieve signature.";
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::rejectSign(const QString& jsonOrId)
{
    // Accept {"signId":"..."} or plain UUID string
    QString signId = jsonOrId;
    QJsonDocument doc = QJsonDocument::fromJson(jsonOrId.toUtf8());
    if (!doc.isNull() && doc.isObject())
        signId = doc.object().value("signId").toString();

    SignRequest* req = nullptr;
    for (auto& r : m_signRequests) {
        if (r.id == signId && r.status == "pending") { req = &r; break; }
    }
    if (!req) {
        QJsonObject result;
        result["error"] = "Sign request not found or already completed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    req->status = "rejected";
    QString shortId = signId.left(8);
    logActivity(QString("[%1] Sign request from %2 rejected").arg(shortId, req->caller), "warning");
    m_loggedRequestIds.remove(signId);

    QJsonObject result;
    result["signId"]  = signId;
    result["status"]  = "rejected";
    result["message"] = "Sign request rejected by user";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

// --- XPUB export API (#142) ---

QString KeycardPlugin::requestXPUB(const QString& jsonArgs)
{
    QJsonDocument doc = QJsonDocument::fromJson(jsonArgs.toUtf8());
    if (doc.isNull() || !doc.isObject()) {
        QJsonObject err;
        err["error"] = "Expected JSON object: {\"bip32_path\",\"caller\"}";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    QJsonObject args = doc.object();
    QString bip32_path = args.value("bip32_path").toString();
    QString caller     = args.value("caller").toString();

    if (bip32_path.isEmpty() || caller.isEmpty()) {
        QJsonObject err;
        err["error"] = "Missing required fields: bip32_path, caller";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    // Format-only validation — card enforces all policy (0x6985 for restricted paths).
    static const QRegularExpression kPathRe(R"(^m(/\d+'?){0,10}$)");
    if (!kPathRe.match(bip32_path).hasMatch()) {
        QJsonObject err;
        err["error"] = QStringLiteral("bip32_path format invalid — expected m(/N'?){0,10}");
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }

    QString xpubId = QUuid::createUuid().toString(QUuid::WithoutBraces);

    XPUBRequest req;
    req.id         = xpubId;
    req.bip32_path = bip32_path;
    req.caller     = caller;
    req.status     = "pending";
    req.timestamp  = QDateTime::currentMSecsSinceEpoch();
    m_xpubRequests.push_back(std::move(req));

    QString shortId = xpubId.left(8);
    logActivity(QString("[%1] Module %2 requesting XPUB at path %3")
        .arg(shortId, caller, bip32_path), "warning");

    QJsonObject result;
    result["xpubId"]  = xpubId;
    result["status"]  = "pending";
    result["message"] = "XPUB request created. Open Keycard UI to approve.";
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::checkXPUBStatus(const QString& jsonOrId)
{
    // Accept {"xpubId":"..."} or plain UUID string
    QString xpubId = jsonOrId;
    QJsonDocument doc = QJsonDocument::fromJson(jsonOrId.toUtf8());
    if (!doc.isNull() && doc.isObject())
        xpubId = doc.object().value("xpubId").toString();

    for (size_t i = 0; i < m_xpubRequests.size(); ++i) {
        auto& req = m_xpubRequests[i];
        if (req.id != xpubId) continue;

        QJsonObject result;
        result["xpubId"]     = xpubId;
        result["bip32_path"] = req.bip32_path;
        result["caller"]     = req.caller;

        if (req.status == "complete") {
            // SECURITY: One-read-and-drop — return xpub exactly once, then wipe.
            result["status"] = "complete";
            QByteArray xpubHex = req.xpub.ref().toHex();
            result["xpub"] = QString::fromUtf8(xpubHex);
            sodium_memzero(xpubHex.data(), xpubHex.size());
            req.xpub.wipe();
            m_loggedRequestIds.remove(xpubId);
            m_xpubRequests.erase(m_xpubRequests.begin() + i);
            return QJsonDocument(result).toJson(QJsonDocument::Compact);
        }

        result["status"] = req.status;
        if (!req.error.isEmpty()) result["error"] = req.error;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject result;
    result["error"] = "XPUB request not found";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getPendingXPUBs()
{
    QJsonArray pending;
    for (auto& req : m_xpubRequests) {
        if (req.status != "pending") continue;
        QJsonObject obj;
        obj["xpubId"]     = req.id;
        obj["bip32_path"] = req.bip32_path;
        obj["caller"]     = req.caller;
        obj["timestamp"]  = req.timestamp;
        pending.append(obj);

        if (!m_loggedRequestIds.contains(req.id)) {
            QString shortId = req.id.left(8);
            logActivity(QString("[%1] New XPUB request from %2 at path %3")
                .arg(shortId, req.caller, req.bip32_path), "warning");
            m_loggedRequestIds.insert(req.id);
        }
    }
    QJsonObject result;
    result["pending"] = pending;
    result["count"]   = pending.size();
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::approveXPUB(const QString& jsonArgs)
{
    QJsonDocument doc = QJsonDocument::fromJson(jsonArgs.toUtf8());
    if (doc.isNull() || !doc.isObject()) {
        QJsonObject err;
        err["error"] = "Expected JSON object: {\"xpubId\",\"pin\"}";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    QString xpubId = doc.object().value("xpubId").toString();
    QString pin    = doc.object().value("pin").toString();

    if (xpubId.isEmpty() || pin.isEmpty()) {
        QJsonObject err;
        err["error"] = "Missing required fields: xpubId, pin";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }

    qDebug() << "KeycardPlugin::approveXPUB() called for xpubId:" << xpubId;

    XPUBRequest* req = nullptr;
    for (auto& r : m_xpubRequests) {
        if (r.id == xpubId && r.status == "pending") { req = &r; break; }
    }
    if (!req) {
        QJsonObject result;
        result["error"] = "XPUB request not found or already completed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    if (m_bridge) m_bridge->setOperationInProgress(true);

    // Step 1: verify PIN (opens secure channel)
    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();
    if (!authResult.value("authorized").toBool()) {
        if (m_bridge) m_bridge->setOperationInProgress(false);
        QJsonObject result;
        result["xpubId"] = xpubId;
        if (authResult.contains("error")) {
            result["status"] = "failed";
            result["error"]  = authResult.value("error").toString();
        } else {
            result["status"]            = "retry";
            result["remainingAttempts"] = authResult.value("remainingAttempts").toInt(-1);
        }
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Step 2a: log applet version + keyUID for diagnostics
    {
        auto info = m_bridge->commandSet()->applicationInfo();
        qDebug() << "KeycardPlugin::approveXPUB() applet version:"
                 << info.appVersion << "." << info.appVersionMinor
                 << "keyUID:" << info.keyUID.toHex()
                 << "capabilities:" << QString("0x%1").arg(info.capabilities, 2, 16, QChar('0'));
        logActivity(QString("[%1] Applet v%2.%3 keyUID=%4 caps=0x%5")
                        .arg(xpubId.left(8))
                        .arg(info.appVersion).arg(info.appVersionMinor)
                        .arg(QString::fromUtf8(info.keyUID.toHex()))
                        .arg(info.capabilities, 2, 16, QChar('0')), "info");
    }

    // Step 2b: probe master-key extended export to verify card has BIP32 chain code.
    // SW 0x6985 here means the card was loaded without a BIP32 seed (raw keypair only)
    // and XPUB export is not possible regardless of path.
    {
        QByteArray probe = m_bridge->commandSet()->exportKeyExtended(
            false, false, QString(), Keycard::APDU::P2ExportKeyExtendedPublic);
        if (probe.isEmpty()) {
            QString probeErr = m_bridge->commandSet()->lastError();
            qDebug() << "KeycardPlugin::approveXPUB() master probe failed:" << probeErr;
            if (probeErr.contains("6985", Qt::CaseInsensitive)) {
                if (m_bridge) m_bridge->setOperationInProgress(false);
                req->status = "failed";
                req->error  = "Card has no BIP32 seed — XPUB export requires BIP39 initialisation. "
                              "Re-initialise card with generateMnemonic or loadKey with chain code.";
                logActivity(QString("[%1] XPUB probe: no chain code on card").arg(xpubId.left(8)), "error");
                m_sessionState = SessionState::NoSession;
                logActivity("Session closed", "info");
                QJsonObject result;
                result["xpubId"] = xpubId;
                result["status"] = "failed";
                result["error"]  = req->error;
                addActivityToResponse(result);
                return QJsonDocument(result).toJson(QJsonDocument::Compact);
            }
            // Other error — log but proceed; derive+export may still work
            qDebug() << "KeycardPlugin::approveXPUB() master probe non-6985 error (proceeding):" << probeErr;
        } else {
            qDebug() << "KeycardPlugin::approveXPUB() master probe succeeded (" << probe.size() << " bytes) — card has BIP32 seed";
        }
    }

    // Step 2c: export XPUB at the caller-supplied path.
    // No host-side path policy — the card enforces all restrictions via 0x6985.
    QByteArray tlvData = m_bridge->commandSet()->exportKeyExtended(
        true, false, req->bip32_path, Keycard::APDU::P2ExportKeyExtendedPublic);

    if (m_bridge) m_bridge->setOperationInProgress(false);

    if (tlvData.isEmpty()) {
        req->status = "failed";
        req->error  = m_bridge ? m_bridge->commandSet()->lastError() : "XPUB export failed";
        QString shortId = xpubId.left(8);
        logActivity(QString("[%1] XPUB export failed: %2").arg(shortId, req->error), "error");
        m_sessionState = SessionState::NoSession;
        logActivity("Session closed", "info");
        QJsonObject result;
        result["xpubId"] = xpubId;
        result["status"] = "failed";
        result["error"]  = req->error;
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Step 3: parse TLV — outer 0xA1, pubkey 0x80 (65B), chain code 0x82 (32B)
    QByteArray inner = Keycard::TLV::findTag(tlvData, 0xA1);
    if (inner.isEmpty()) inner = tlvData;

    QByteArray pubkeyBytes    = Keycard::TLV::findTag(inner, 0x80);
    QByteArray chainCodeBytes = Keycard::TLV::findTag(inner, 0x82);

    if (pubkeyBytes.size() != 65 || chainCodeBytes.size() != 32) {
        req->status = "failed";
        req->error  = QString("TLV parse error: pubkey=%1B chain=%2B (expected 65+32)")
                          .arg(pubkeyBytes.size()).arg(chainCodeBytes.size());
        QString shortId = xpubId.left(8);
        logActivity(QString("[%1] XPUB TLV parse failed: %2").arg(shortId, req->error), "error");
        sodium_memzero(pubkeyBytes.data(), pubkeyBytes.size());
        sodium_memzero(chainCodeBytes.data(), chainCodeBytes.size());
        sodium_memzero(inner.data(), inner.size());
        sodium_memzero(tlvData.data(), tlvData.size());
        m_sessionState = SessionState::NoSession;
        logActivity("Session closed", "info");
        QJsonObject result;
        result["xpubId"] = xpubId;
        result["status"] = "failed";
        result["error"]  = req->error;
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // SECURITY: concatenate pubkey + chain code, move into SecureBuffer, wipe all intermediates
    QByteArray xpubRaw = pubkeyBytes + chainCodeBytes;
    sodium_memzero(pubkeyBytes.data(), pubkeyBytes.size());
    sodium_memzero(chainCodeBytes.data(), chainCodeBytes.size());
    sodium_memzero(inner.data(), inner.size());
    sodium_memzero(tlvData.data(), tlvData.size());

    req->status = "complete";
    req->xpub   = SecureBuffer(std::move(xpubRaw));

    QString shortId = xpubId.left(8);
    logActivity(QString("[%1] XPUB exported for %2 at path %3")
        .arg(shortId, req->caller, req->bip32_path), "success");

    m_sessionState = SessionState::NoSession;
    logActivity("Session closed", "success");

    QJsonObject result;
    result["xpubId"]  = xpubId;
    result["status"]  = "complete";
    result["message"] = "XPUB export completed. Poll checkXPUBStatus to retrieve.";
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::rejectXPUB(const QString& jsonOrId)
{
    // Accept {"xpubId":"..."} or plain UUID string
    QString xpubId = jsonOrId;
    QJsonDocument doc = QJsonDocument::fromJson(jsonOrId.toUtf8());
    if (!doc.isNull() && doc.isObject())
        xpubId = doc.object().value("xpubId").toString();

    XPUBRequest* req = nullptr;
    for (auto& r : m_xpubRequests) {
        if (r.id == xpubId && r.status == "pending") { req = &r; break; }
    }
    if (!req) {
        QJsonObject result;
        result["error"] = "XPUB request not found or already completed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    req->status = "rejected";
    QString shortId = xpubId.left(8);
    logActivity(QString("[%1] XPUB request from %2 rejected").arg(shortId, req->caller), "warning");
    m_loggedRequestIds.remove(xpubId);

    QJsonObject result;
    result["xpubId"]  = xpubId;
    result["status"]  = "rejected";
    result["message"] = "XPUB request rejected by user";
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::testXPUBExport(const QString& jsonArgs)
{
    // Debug method: authorize + derive + exportKeyExtended in one call.
    // Used for headless testing where the request/approve queue can't be chained.
    // NOT exposed in production API — for logoscore testing only.
    QJsonDocument doc = QJsonDocument::fromJson(jsonArgs.toUtf8());
    if (doc.isNull() || !doc.isObject()) {
        QJsonObject err;
        err["error"] = "Expected JSON object: {\"domain\",\"pin\"}";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }
    QString domain = doc.object().value("domain").toString();
    QString pin    = doc.object().value("pin").toString();
    if (domain.isEmpty() || pin.isEmpty()) {
        QJsonObject err;
        err["error"] = "Missing required fields: domain, pin";
        return QJsonDocument(err).toJson(QJsonDocument::Compact);
    }

    qDebug() << "KeycardPlugin::testXPUBExport() domain:" << domain;

    // Step 1: verify PIN
    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();
    if (!authResult.value("authorized").toBool()) {
        QJsonObject result;
        result["error"] = authResult.contains("error")
            ? authResult.value("error").toString()
            : QString("PIN rejected, remaining=%1").arg(authResult.value("remainingAttempts").toInt(-1));
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Step 2+3: export standard wallet XPUB at the EIP-1581 root m/43'/60'/1581'.
    // The domain is a label only — derivation always uses this fixed path.
    // Returns pubkey (65B) + chain code (32B). Wallet derives child keys from this offline.
    static const QString kEip1581Path = QStringLiteral("m/43'/60'/1581'");
    logActivity(QString("Exporting wallet XPUB at %1 (domain label: %2)").arg(kEip1581Path, domain), "info");
    QByteArray tlvData = m_bridge->commandSet()->exportKeyExtended(
        true, false, kEip1581Path, Keycard::APDU::P2ExportKeyExtendedPublic);

    if (tlvData.isEmpty()) {
        QJsonObject result;
        result["error"] = m_bridge ? m_bridge->commandSet()->lastError() : "exportKeyExtended failed";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Step 4: parse TLV — outer 0xA1, pubkey 0x80 (65B), chain code 0x82 (32B)
    QByteArray inner         = Keycard::TLV::findTag(tlvData, 0xA1);
    if (inner.isEmpty()) inner = tlvData;
    QByteArray pubkeyBytes    = Keycard::TLV::findTag(inner, 0x80);
    QByteArray chainCodeBytes = Keycard::TLV::findTag(inner, 0x82);

    QJsonObject result;
    result["domain"]       = domain;
    result["path"]         = kEip1581Path;
    result["pubkeyBytes"]  = pubkeyBytes.size();
    result["chainBytes"]   = chainCodeBytes.size();
    result["pubkeyHex"]    = QString::fromLatin1(pubkeyBytes.toHex());
    result["chainCodeHex"] = QString::fromLatin1(chainCodeBytes.toHex());
    result["xpubHex"]      = QString::fromLatin1((pubkeyBytes + chainCodeBytes).toHex());
    result["ok"]           = (pubkeyBytes.size() == 65 && chainCodeBytes.size() == 32);

    sodium_memzero(pubkeyBytes.data(), pubkeyBytes.size());
    sodium_memzero(chainCodeBytes.data(), chainCodeBytes.size());
    sodium_memzero(inner.data(), inner.size());
    sodium_memzero(tlvData.data(), tlvData.size());

    m_sessionState = SessionState::NoSession;
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

void KeycardPlugin::purgeCompletedRequests()
{
    // SECURITY: Wipe key material and remove completed/consumed requests.
    // SecureBuffer destructor handles sodium_memzero via RAII,
    // but we wipe explicitly for defense-in-depth.
    for (auto& req : m_authRequests) {
        if (req.status == "complete" || req.status == "consumed") {
            req.key.wipe();
            m_loggedRequestIds.remove(req.id);
        }
    }
    auto it = std::remove_if(m_authRequests.begin(), m_authRequests.end(),
        [](const AuthRequest& req) {
            return req.status == "complete" || req.status == "consumed";
        });
    m_authRequests.erase(it, m_authRequests.end());
}

void KeycardPlugin::logActivity(const QString& message, const QString& level)
{
    QString timestamp = QDateTime::currentDateTime().toString("[HH:mm:ss]");

    // Store in queue for API responses
    ActivityEntry entry{timestamp, message, level};
    m_recentActivity.append(entry);

    // Keep only last 10 entries in queue
    if (m_recentActivity.size() > 10) {
        m_recentActivity.removeFirst();
    }

    qDebug() << "Activity:" << timestamp << level.toUpper() << message;
}

void KeycardPlugin::addActivityToResponse(QJsonObject& response)
{
    if (m_recentActivity.isEmpty()) {
        return;
    }

    QJsonArray activities;
    for (const auto& entry : m_recentActivity) {
        QJsonObject activityObj;
        activityObj["timestamp"] = entry.timestamp;
        activityObj["message"] = entry.message;
        activityObj["level"] = entry.level;
        activities.append(activityObj);
    }

    response["_activity"] = activities;

    // Clear queue after adding to response
    m_recentActivity.clear();
}

// testMasterExport — diagnostic: authorize + export master key (no derivation)
// This probes whether the loaded key has chain code at root level.
// 0x6985 here → BIP39 load didn't store chain code
// OK here but testXPUBExport fails → derivation issue
QString KeycardPlugin::testMasterExport(const QString& pin)
{
    QJsonObject result;
    if (!m_bridge || !m_bridge->commandSet()) {
        result["error"] = "Not connected";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();
    if (!authResult.value("authorized").toBool()) {
        result["error"] = authResult.contains("error")
            ? authResult.value("error").toString()
            : QString("PIN rejected");
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Export current key (master, no derivation) as extended public key
    QByteArray tlvData = m_bridge->commandSet()->exportKeyExtended(
        false, false, QString(), Keycard::APDU::P2ExportKeyExtendedPublic);

    if (tlvData.isEmpty()) {
        result["masterExport"] = "FAILED";
        result["error"] = m_bridge->commandSet()->lastError();
        m_sessionState = SessionState::NoSession;
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QByteArray inner = Keycard::TLV::findTag(tlvData, 0xA1);
    if (inner.isEmpty()) inner = tlvData;
    QByteArray pubkeyBytes    = Keycard::TLV::findTag(inner, 0x80);
    QByteArray chainCodeBytes = Keycard::TLV::findTag(inner, 0x82);

    result["masterExport"] = "OK";
    result["pubkeyBytes"]  = pubkeyBytes.size();
    result["chainBytes"]   = chainCodeBytes.size();
    result["pubkeyHex"]    = QString::fromLatin1(pubkeyBytes.toHex());
    result["chainCodeHex"] = QString::fromLatin1(chainCodeBytes.toHex());

    sodium_memzero(pubkeyBytes.data(), pubkeyBytes.size());
    sodium_memzero(chainCodeBytes.data(), chainCodeBytes.size());
    sodium_memzero(inner.data(), inner.size());
    sodium_memzero(tlvData.data(), tlvData.size());

    m_sessionState = SessionState::NoSession;
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

// testEip1581Export — diagnostic: export XPUB at m/43'/60'/1581' (EIP-1581 root).
// Firmware forbids chain code export at this root and at master. No depth restriction.
// Prior 0x6985 at deeper paths was due to wrong TLV tags + two-step export (fixed).
QString KeycardPlugin::testEip1581Export(const QString& pin)
{
    QJsonObject result;
    if (!m_bridge || !m_bridge->commandSet()) {
        result["error"] = "Not connected";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();
    if (!authResult.value("authorized").toBool()) {
        result["error"] = authResult.contains("error")
            ? authResult.value("error").toString()
            : QString("PIN rejected");
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Export with one-step derive at exactly m/43'/60'/1581' (EIP-1581 root)
    const QString eip1581Path = QStringLiteral("m/43'/60'/1581'");
    logActivity(QString("Testing EIP-1581 root export at %1").arg(eip1581Path), "info");

    QByteArray tlvData = m_bridge->commandSet()->exportKeyExtended(
        true, false, eip1581Path, Keycard::APDU::P2ExportKeyExtendedPublic);

    if (tlvData.isEmpty()) {
        result["error"] = m_bridge->commandSet()->lastError();
        result["path"]  = eip1581Path;
        m_sessionState = SessionState::NoSession;
        addActivityToResponse(result);
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    QByteArray inner = Keycard::TLV::findTag(tlvData, 0xA1);
    if (inner.isEmpty()) inner = tlvData;
    QByteArray pubkeyBytes    = Keycard::TLV::findTag(inner, 0x80);
    QByteArray chainCodeBytes = Keycard::TLV::findTag(inner, 0x82);

    result["path"]         = eip1581Path;
    result["pubkeyBytes"]  = pubkeyBytes.size();
    result["chainBytes"]   = chainCodeBytes.size();
    result["pubkeyHex"]    = QString::fromLatin1(pubkeyBytes.toHex());
    result["chainCodeHex"] = QString::fromLatin1(chainCodeBytes.toHex());
    result["ok"]           = (pubkeyBytes.size() == 65 && chainCodeBytes.size() == 32);

    sodium_memzero(pubkeyBytes.data(), pubkeyBytes.size());
    sodium_memzero(chainCodeBytes.data(), chainCodeBytes.size());
    sodium_memzero(inner.data(), inner.size());
    sodium_memzero(tlvData.data(), tlvData.size());

    m_sessionState = SessionState::NoSession;
    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
