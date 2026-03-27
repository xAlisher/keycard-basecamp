#include "plugin.h"
#include "KeycardBridge.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUuid>
#include <QDateTime>
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

    logActivity("Looking for smart card reader...", "info");

    if (!m_bridge) {
        m_bridge = new KeycardBridge(this);
    }

    bool success = m_bridge->start();

    QJsonObject result;
    result["found"] = success;
    if (success) {
        // Get reader name from state
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

        logActivity("Enter PIN", "warning");

        // Session state persists until card is removed or user re-authorizes
        // (Closed state should stay closed until explicit re-auth)
    } else {
        result["found"] = false;
        logActivity("Keycard not found", "error");

        // Card removed/not present - clear any active session state
        // Ensures SESSION_ACTIVE doesn't persist after card removal
        if (m_sessionState == SessionState::Active || m_sessionState == SessionState::Locked) {
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
    if (m_sessionState == SessionState::Locked) {
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

    // Authorize with card
    QJsonObject authResult = m_bridge->authorize(pin);

    // If successful, start session
    if (authResult.value("authorized").toBool()) {
        m_sessionState = SessionState::Active;
        startSessionTimer();
        logActivity("Session active", "success");
        qDebug() << "Session activated, timer started";
    } else {
        m_sessionState = SessionState::NoSession;
        int remaining = authResult.value("remainingAttempts").toInt(-1);
        if (remaining == 0) {
            logActivity("Wrong PIN, Keycard blocked", "error");
        } else if (remaining == 1) {
            logActivity("Wrong PIN, 1 attempt left", "error");
            logActivity("Enter PIN", "warning");
        } else if (remaining > 1) {
            logActivity(QString("Wrong PIN, %1 attempts left").arg(remaining), "error");
            logActivity("Enter PIN", "warning");
        } else {
            // remaining == -1 (unknown)
            logActivity("Wrong PIN", "error");
            logActivity("Enter PIN", "warning");
        }
    }

    addActivityToResponse(authResult);
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

    // Check if session is not active - require authorization
    if (m_sessionState != SessionState::Active) {
        QJsonObject result;
        QString reason = (m_sessionState == SessionState::Locked) ? "locked" : "no session";
        result["error"] = QString("Session %1 - authorize to derive keys").arg(reason);
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

    if (cardGone && (m_sessionState == SessionState::Active || m_sessionState == SessionState::Locked)) {
        qDebug() << "KeycardPlugin::getState() - card gone, clearing session state";
        m_sessionState = SessionState::NoSession;
    }

    // Session state takes precedence over bridge state (only if card still present)
    if (m_sessionState == SessionState::Active) {
        qDebug() << "KeycardPlugin::getState() - returning SESSION_ACTIVE";
        result["state"] = "SESSION_ACTIVE";
    } else if (m_sessionState == SessionState::Locked) {
        qDebug() << "KeycardPlugin::getState() - returning SESSION_LOCKED";
        result["state"] = "SESSION_LOCKED";
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

    // Enter SESSION_LOCKED state (keep bridge running for re-auth)
    m_sessionState = SessionState::Locked;

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

    m_authRequests.append(request);

    logActivity(QString("Module %1 is requesting access to domain %2").arg(caller, domain), "warning");

    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "pending";
    result["message"] = "Authorization request created. Open Keycard UI to complete.";

    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::checkAuthStatus(const QString& authId)
{
    for (const auto& req : m_authRequests) {
        if (req.id == authId) {
            QJsonObject result;
            result["authId"] = authId;
            result["status"] = req.status;
            result["domain"] = req.domain;
            result["caller"] = req.caller;

            if (req.status == "complete") {
                result["key"] = req.key;
            } else if (req.status == "failed") {
                result["error"] = req.error;
            }

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

    for (const auto& req : m_authRequests) {
        if (req.status == "pending") {
            QJsonObject obj;
            obj["authId"] = req.id;
            obj["domain"] = req.domain;
            obj["caller"] = req.caller;
            obj["timestamp"] = req.timestamp;
            pending.append(obj);

            // Log new requests that haven't been logged yet
            if (!m_loggedRequestIds.contains(req.id)) {
                logActivity(QString("New request from module %1 for domain %2").arg(req.caller, req.domain), "warning");
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

    // SECURITY: Verify PIN first (hardware verification)
    QJsonObject authResult = QJsonDocument::fromJson(authorize(pin).toUtf8()).object();

    if (!authResult.value("authorized").toBool()) {
        targetRequest->status = "failed";
        targetRequest->error = authResult.value("error").toString("PIN verification failed");

        QJsonObject result;
        result["authId"] = authId;
        result["status"] = "failed";
        result["error"] = targetRequest->error;
        result["remainingAttempts"] = authResult.value("remainingAttempts").toInt();

        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // SECURITY: Derive key from hardware (only after PIN verified)
    QString domain = targetRequest->domain;
    QJsonObject keyResult = QJsonDocument::fromJson(deriveKey(domain).toUtf8()).object();

    if (keyResult.contains("error")) {
        targetRequest->status = "failed";
        targetRequest->error = keyResult.value("error").toString();

        QJsonObject result;
        result["authId"] = authId;
        result["status"] = "failed";
        result["error"] = targetRequest->error;

        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Success - store legitimate hardware-derived key
    targetRequest->status = "complete";
    targetRequest->key = keyResult.value("key").toString();

    // Track authorized module (Issue #44)
    QString moduleName = targetRequest->caller;
    if (m_authorizedModules.contains(moduleName)) {
        // Update existing record
        m_authorizedModules[moduleName].lastAccess = QDateTime::currentDateTime();
        m_authorizedModules[moduleName].accessCount++;
    } else {
        // Create new record
        AuthorizationRecord record;
        record.moduleName = moduleName;
        record.domain = domain;
        record.lastAccess = QDateTime::currentDateTime();
        record.accessCount = 1;
        m_authorizedModules[moduleName] = record;
    }

    // Log authorization
    QString keyPrefix = targetRequest->key.left(8);
    logActivity(QString("Request from module %1 approved").arg(moduleName), "success");
    logActivity(QString("Module %1 derived key %2...").arg(moduleName, keyPrefix), "success");

    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "complete";
    result["message"] = "Authorization completed successfully";
    result["key"] = targetRequest->key;  // Return key immediately for UI

    addActivityToResponse(result);
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::completeAuthRequest(const QString& authId)
{
    qDebug() << "KeycardPlugin::completeAuthRequest() called for authId:" << authId;

    // SECURITY: Session must be active to complete without PIN
    if (m_sessionState != SessionState::Active) {
        QJsonObject result;
        result["error"] = "Session not active - cannot complete request";
        result["authId"] = authId;
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

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

    // SECURITY: Derive key from hardware (session is active, no PIN needed)
    QString domain = targetRequest->domain;
    QJsonObject keyResult = QJsonDocument::fromJson(deriveKey(domain).toUtf8()).object();

    if (keyResult.contains("error")) {
        targetRequest->status = "failed";
        targetRequest->error = keyResult.value("error").toString();

        QJsonObject result;
        result["authId"] = authId;
        result["status"] = "failed";
        result["error"] = targetRequest->error;

        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Success - mark as complete with hardware-derived key
    targetRequest->status = "complete";
    targetRequest->key = keyResult.value("key").toString();

    // Remove from logged set (cleanup)
    m_loggedRequestIds.remove(authId);

    // Track authorized module
    QString moduleName = targetRequest->caller;

    if (m_authorizedModules.contains(moduleName)) {
        m_authorizedModules[moduleName].lastAccess = QDateTime::currentDateTime();
        m_authorizedModules[moduleName].accessCount++;
    } else {
        AuthorizationRecord record;
        record.moduleName = moduleName;
        record.domain = domain;
        record.lastAccess = QDateTime::currentDateTime();
        record.accessCount = 1;
        m_authorizedModules[moduleName] = record;
    }

    // Log authorization
    QString keyPrefix = targetRequest->key.left(8);
    logActivity(QString("Request from module %1 approved").arg(moduleName), "success");
    logActivity(QString("Module %1 derived key %2...").arg(moduleName, keyPrefix), "success");

    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "complete";
    result["message"] = "Authorization completed successfully";

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
    targetRequest->status = "rejected";

    // Remove from logged set (cleanup)
    m_loggedRequestIds.remove(authId);

    QJsonObject result;
    result["authId"] = authId;
    result["status"] = "rejected";
    result["message"] = "Authorization request declined by user";

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::lockSession()
{
    qDebug() << "KeycardPlugin::lockSession() called";

    // Clear session data
    clearSessionData();

    // Stop session timer
    if (m_sessionTimer) {
        m_sessionTimer->stop();
    }

    // Update state
    m_sessionState = SessionState::Locked;

    logActivity("session locked (manual)", "warning");

    QJsonObject result;
    result["locked"] = true;
    result["reason"] = "manual";

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getSessionInfo()
{
    qDebug() << "KeycardPlugin::getSessionInfo() called";

    QJsonObject result;

    // Map state to string
    QString stateStr;
    switch (m_sessionState) {
        case SessionState::NoSession:
            stateStr = "NO_SESSION";
            break;
        case SessionState::Active:
            stateStr = "SESSION_ACTIVE";
            break;
        case SessionState::Locked:
            stateStr = "SESSION_LOCKED";
            break;
    }

    result["state"] = stateStr;
    result["timeoutSeconds"] = m_sessionTimeoutMs / 1000;

    if (m_sessionState == SessionState::Active && m_sessionTimer) {
        int remainingMs = m_sessionTimer->remainingTime();
        result["remainingSeconds"] = remainingMs >= 0 ? remainingMs / 1000 : 0;
    } else {
        result["remainingSeconds"] = 0;
    }

    if (m_sessionState == SessionState::Active) {
        result["activeSeconds"] = m_sessionStartTime.secsTo(QDateTime::currentDateTime());
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::getAuthorizedModules()
{
    qDebug() << "KeycardPlugin::getAuthorizedModules() called";

    QJsonArray modules;

    for (auto it = m_authorizedModules.constBegin(); it != m_authorizedModules.constEnd(); ++it) {
        const auto& record = it.value();

        QJsonObject obj;
        obj["name"] = record.moduleName;
        obj["domain"] = record.domain;
        obj["lastAccess"] = record.lastAccess.toString(Qt::ISODate);
        obj["accessCount"] = record.accessCount;

        modules.append(obj);
    }

    QJsonObject result;
    result["modules"] = modules;

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

QString KeycardPlugin::revokeModule(const QString& moduleName)
{
    qDebug() << "KeycardPlugin::revokeModule() called for module:" << moduleName;

    if (!m_authorizedModules.contains(moduleName)) {
        QJsonObject result;
        result["error"] = "Module not found in authorized list";
        return QJsonDocument(result).toJson(QJsonDocument::Compact);
    }

    // Get domain before removing
    QString domain = m_authorizedModules[moduleName].domain;

    // Remove from authorized list
    m_authorizedModules.remove(moduleName);

    QJsonObject result;
    result["success"] = true;
    result["revokedModule"] = moduleName;
    result["revokedDomain"] = domain;

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

void KeycardPlugin::startSessionTimer()
{
    qDebug() << "KeycardPlugin::startSessionTimer() called";

    if (!m_sessionTimer) {
        m_sessionTimer = new QTimer(this);
        connect(m_sessionTimer, &QTimer::timeout, this, &KeycardPlugin::handleSessionTimeout);
    }

    m_sessionTimer->start(m_sessionTimeoutMs);
    m_sessionStartTime = QDateTime::currentDateTime();

    qDebug() << "Session timer started for" << (m_sessionTimeoutMs / 1000) << "seconds";
}

void KeycardPlugin::clearSessionData()
{
    qDebug() << "KeycardPlugin::clearSessionData() called";

    // Clear authorized modules (session-specific data)
    m_authorizedModules.clear();

    // Note: m_bridge maintains its own secure key storage
    // and will clear keys on session close
}

void KeycardPlugin::handleSessionTimeout()
{
    qDebug() << "KeycardPlugin::handleSessionTimeout() - session timed out";

    // Clear session data
    clearSessionData();

    // Update state
    m_sessionState = SessionState::Locked;

    logActivity("session locked (timeout)", "warning");

    // Emit signal for UI
    emit sessionLocked("timeout");

    qDebug() << "Session locked due to timeout";
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
