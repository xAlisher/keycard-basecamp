#include "KeycardBridge.h"
#include "FilePairingStorage.h"
#include <keycard-qt/keycard_channel.h>
#include <keycard-qt/command_set.h>
#include <keycard-qt/types.h>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <PCSC/winscard.h>  // For direct PC/SC reader detection
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QStandardPaths>

// Debug logging helper
static void debugLog(const QString& msg) {
    QFile file("/tmp/keycard-debug.log");
    if (file.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream out(&file);
        out << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") << " " << msg << "\n";
        file.flush();
    }
    qDebug() << msg;  // Also try qDebug
}

KeycardBridge::KeycardBridge(QObject *parent)
    : QObject(parent)
{
    qDebug() << "KeycardBridge: Constructed (keycard-qt backend)";
}

KeycardBridge::~KeycardBridge()
{
    stop();
}

bool KeycardBridge::start()
{
    qDebug() << "KeycardBridge::start() called";

    if (m_running) {
        qWarning() << "KeycardBridge: Already running";
        return true;
    }

    try {
        // Create channel (PC/SC backend on desktop, NFC on mobile)
        m_channel = std::make_shared<Keycard::KeycardChannel>(this);

        // Create persistent pairing storage
        QString dataDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
        QString pairingFile = dataDir + "/Logos/LogosBasecamp/keycard-pairings.json";
        m_pairingStorage = std::make_shared<FilePairingStorage>(pairingFile);

        // Pairing password provider (returns empty - no auto-pairing for now)
        auto passwordProvider = [](const QString&) -> QString {
            return QString();  // No automatic pairing
        };

        // Create command set
        m_commandSet = std::make_shared<Keycard::CommandSet>(
            m_channel,
            m_pairingStorage,
            passwordProvider,
            this
        );

        // Connect signals
        connect(m_commandSet.get(), &Keycard::CommandSet::cardReady,
                this, &KeycardBridge::onCardReady);
        connect(m_commandSet.get(), &Keycard::CommandSet::cardLost,
                this, &KeycardBridge::onCardLost);

        // Start card detection
        m_commandSet->startDetection();

        m_running = true;
        setState(State::WaitingForCard);

        qDebug() << "KeycardBridge: Started successfully";
        return true;

    } catch (const std::exception& e) {
        m_lastError = QString("Exception in start(): %1").arg(e.what());
        qWarning() << "KeycardBridge:" << m_lastError;
        setState(State::ConnectionError);
        return false;
    }
}

void KeycardBridge::stop()
{
    qDebug() << "KeycardBridge::stop() called";

    if (!m_running) {
        return;
    }

    if (m_commandSet) {
        m_commandSet->stopDetection();
        m_commandSet.reset();
    }

    m_channel.reset();
    m_pairingStorage.reset();

    m_running = false;
    m_cardReady = false;
    setState(State::Unknown);

    qDebug() << "KeycardBridge: Stopped";
}

QString KeycardBridge::statusText() const
{
    switch (m_state) {
    case State::Unknown:            return "Not initialized";
    case State::NoPCSC:             return "PC/SC not available";
    case State::WaitingForReader:   return "Waiting for card reader";
    case State::WaitingForCard:     return "Waiting for card";
    case State::ConnectingCard:     return "Connecting to card...";
    case State::ConnectionError:    return "Connection error";
    case State::NotKeycard:         return "Not a Keycard";
    case State::EmptyKeycard:       return "Uninitialized Keycard";
    case State::BlockedPIN:         return "PIN blocked";
    case State::BlockedPUK:         return "PUK blocked (card bricked)";
    case State::Ready:              return "Ready for PIN";
    case State::Authorized:         return "Authorized";
    }
    return "Unknown state";
}

void KeycardBridge::pollStatus()
{
    static int pollCount = 0;
    if (++pollCount % 20 == 0) {  // Log every 20th call to avoid spam
        qDebug() << "pollStatus() called" << pollCount << "times, state:" << static_cast<int>(m_state);
    }

    if (!m_commandSet) {
        return;
    }

    // If we think card is ready and authorized, verify it's still there
    // Don't call getStatus() before authorization as it needs secure channel
    if (m_cardReady && m_state == State::Authorized) {
        // Throttle getStatus() calls - they take ~600ms each
        // Only call every 5 seconds instead of every timer tick
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastStatusCheck < 5000) {
            // Too soon, skip this check
            return;
        }
        m_lastStatusCheck = now;

        try {
            auto status = m_commandSet->getStatus();
            if (status.valid) {
                updateStatusFromCommandSet();
            }
        } catch (const std::exception& e) {
            qDebug() << "KeycardBridge::pollStatus: getStatus failed:" << e.what();
        }
    } else {
        // No card detected - check reader presence
        if (m_state == State::WaitingForCard) {
            // Reader was present, verify it's still there
            if (!isReaderPresent()) {
                qDebug() << "KeycardBridge::pollStatus: Reader no longer present";
                setState(State::WaitingForReader);
            }
        } else if (m_state == State::WaitingForReader) {
            // Reader was gone, check if it's back
            if (isReaderPresent()) {
                qDebug() << "========================================";
                qDebug() << "KeycardBridge::pollStatus: Reader detected after disconnect, reinitializing channel";
                qDebug() << "This should ONLY happen after physical reader reconnection";
                qDebug() << "========================================";
                // Recreate channel and CommandSet - old channel has stale PC/SC handles
                try {
                    // Stop old detection if running
                    if (m_commandSet) {
                        m_commandSet->stopDetection();
                    }

                    // Recreate channel (clears stale PC/SC state)
                    m_channel = std::make_shared<Keycard::KeycardChannel>(this);

                    // Recreate CommandSet with fresh channel
                    auto passwordProvider = [](const QString&) -> QString {
                        return QString();  // No automatic pairing
                    };
                    m_commandSet = std::make_shared<Keycard::CommandSet>(
                        m_channel,
                        m_pairingStorage,  // Keep same storage (persists pairings)
                        passwordProvider,
                        this
                    );

                    // Reconnect signals
                    connect(m_commandSet.get(), &Keycard::CommandSet::cardReady,
                            this, &KeycardBridge::onCardReady);
                    connect(m_commandSet.get(), &Keycard::CommandSet::cardLost,
                            this, &KeycardBridge::onCardLost);

                    // Start fresh detection
                    m_commandSet->startDetection();
                    setState(State::WaitingForCard);

                    qDebug() << "KeycardBridge::pollStatus: Channel and CommandSet recreated";

                } catch (const std::exception& e) {
                    qWarning() << "KeycardBridge::pollStatus: Failed to recreate channel:" << e.what();
                    setState(State::ConnectionError);
                }
            }
        }
    }
}

QJsonObject KeycardBridge::checkPairing()
{
    QJsonObject result;

    if (!m_cardReady || m_keyUID.isEmpty()) {
        result["paired"] = false;
        result["reason"] = "No card detected";
        return result;
    }

    auto pairing = m_pairingStorage->load(m_keyUID);

    if (pairing.index != -1) {
        result["paired"] = true;
        result["pairingIndex"] = pairing.index;
        result["cardUID"] = m_keyUID;
    } else {
        result["paired"] = false;
        result["reason"] = "Card not paired yet";
        result["cardUID"] = m_keyUID;
    }

    return result;
}

QJsonObject KeycardBridge::pairCard(const QString &pairingPassword)
{
    qDebug() << "KeycardBridge::pairCard() called";

    QJsonObject result;

    if (!m_commandSet || !m_cardReady) {
        result["paired"] = false;
        result["error"] = "Card not ready";
        m_lastError = "Card not ready";
        return result;
    }

    try {
        qDebug() << "KeycardBridge: Selecting applet for pairing...";
        m_commandSet->select();

        qDebug() << "KeycardBridge: Pairing with password (length:" << pairingPassword.length() << ")...";
        auto pairingInfo = m_commandSet->pair(pairingPassword);

        qDebug() << "KeycardBridge: Pairing result - index:" << pairingInfo.index;

        if (pairingInfo.index == -1) {
            QString lastErr = m_commandSet->lastError();
            result["paired"] = false;
            result["error"] = "Pairing failed: " + (lastErr.isEmpty() ? "check password" : lastErr);
            m_lastError = "Pairing failed: " + lastErr;
            qDebug() << "KeycardBridge: Pairing failed, error:" << lastErr;
            return result;
        }

        qDebug() << "KeycardBridge: Pairing successful, index:" << pairingInfo.index;
        qDebug() << "KeycardBridge: Saving pairing for UID:" << m_keyUID;

        // Save pairing - CRITICAL: must persist to disk
        bool saved = m_pairingStorage->save(m_keyUID, pairingInfo);
        qDebug() << "KeycardBridge: Pairing save result:" << saved;

        if (!saved) {
            qWarning() << "KeycardBridge: CRITICAL - Failed to save pairing to disk!";
            result["paired"] = true;  // Card is paired, but storage failed
            result["pairingIndex"] = pairingInfo.index;
            result["warning"] = "Pairing succeeded but failed to save - will be lost on restart";
            return result;
        }

        result["paired"] = true;
        result["pairingIndex"] = pairingInfo.index;

    } catch (const std::exception& e) {
        result["paired"] = false;
        result["error"] = e.what();
        m_lastError = e.what();
        qWarning() << "KeycardBridge::pairCard() exception:" << e.what();
    }

    return result;
}

QJsonObject KeycardBridge::unpairCard()
{
    qDebug() << "KeycardBridge::unpairCard() called";

    QJsonObject result;

    if (!m_commandSet || !m_cardReady) {
        result["unpaired"] = false;
        result["error"] = "Card not ready";
        m_lastError = "Card not ready";
        return result;
    }

    if (m_keyUID.isEmpty()) {
        result["unpaired"] = false;
        result["error"] = "No card UID available";
        m_lastError = "No card UID available";
        return result;
    }

    // Unpair requires authorization - user must authorize first
    if (m_state != State::Authorized) {
        result["unpaired"] = false;
        result["error"] = "Authorization required - please enter PIN before unpair";
        m_lastError = "Not authorized";
        qDebug() << "KeycardBridge: Unpair requires authorization, current state:" << static_cast<int>(m_state);
        return result;
    }

    try {
        // Load current pairing to get slot index
        auto pairing = m_pairingStorage->load(m_keyUID);
        if (pairing.index == -1) {
            result["unpaired"] = false;
            result["error"] = "Card not paired";
            m_lastError = "Card not paired";
            return result;
        }

        qDebug() << "KeycardBridge: Unpairing card, slot:" << pairing.index;

        // Unpair on card (secure channel already open from authorization)
        qDebug() << "KeycardBridge: Calling unpair on card...";
        bool success = m_commandSet->unpair(pairing.index);

        if (!success) {
            QString lastErr = m_commandSet->lastError();
            result["unpaired"] = false;
            result["error"] = "Unpair failed on card: " + lastErr;
            m_lastError = "Unpair failed: " + lastErr;
            qWarning() << "KeycardBridge: Unpair failed on card, error:" << lastErr;
            return result;
        }

        // Remove from local storage
        qDebug() << "KeycardBridge: Removing pairing from storage for UID:" << m_keyUID;
        bool removed = m_pairingStorage->remove(m_keyUID);
        qDebug() << "KeycardBridge: Storage remove result:" << removed;

        if (!removed) {
            qWarning() << "KeycardBridge: CRITICAL - Failed to remove pairing from storage!";
            result["unpaired"] = true;  // Card is unpaired, but storage remove failed
            result["warning"] = "Card unpaired but failed to remove from storage";
            return result;
        }

        qDebug() << "KeycardBridge: Unpaired successfully (card + storage)";
        result["unpaired"] = true;

    } catch (const std::exception& e) {
        result["unpaired"] = false;
        result["error"] = e.what();
        m_lastError = e.what();
        qWarning() << "KeycardBridge::unpairCard() exception:" << e.what();
    }

    return result;
}

QJsonObject KeycardBridge::authorize(const QString &pin)
{
    debugLog("========================================");
    debugLog("KeycardBridge::authorize() START");
    debugLog(QString("PIN length: %1").arg(pin.length()));
    debugLog(QString("m_cardReady: %1").arg(m_cardReady));
    debugLog(QString("m_keyUID: %1").arg(m_keyUID));
    debugLog("========================================");

    QJsonObject result;

    if (!m_commandSet || !m_cardReady) {
        result["authorized"] = false;
        result["error"] = "Card not ready";
        m_lastError = "Card not ready";
        debugLog(QString("ERROR: Card not ready - m_commandSet: %1 m_cardReady: %2").arg(m_commandSet != nullptr).arg(m_cardReady));
        return result;
    }

    try {
        debugLog("STEP 1: Loading pairing from storage...");
        // Check if we have pairing, if not, try to load it
        auto pairing = m_pairingStorage->load(m_keyUID);
        debugLog(QString("STEP 1: Pairing loaded - index: %1").arg(pairing.index));

        if (pairing.index == -1) {
            // No pairing stored - need to pair first
            result["authorized"] = false;
            result["error"] = "Card not paired - pairing required";
            m_lastError = "Not paired";
            debugLog(QString("ERROR: Card not paired, instanceUID: %1").arg(m_keyUID));
            return result;
        }

        // Re-select applet to ensure fresh connection
        debugLog("STEP 2: Calling select() to re-select applet...");
        debugLog("STEP 2: BEFORE select() call");
        m_commandSet->select();
        debugLog("STEP 2: AFTER select() call - SUCCESS");

        debugLog("STEP 3: Opening secure channel...");
        debugLog("STEP 3: BEFORE openSecureChannel() call");

        // Open secure channel
        bool scOpened = m_commandSet->openSecureChannel(pairing);

        debugLog(QString("STEP 3: AFTER openSecureChannel() call - result: %1").arg(scOpened));

        if (!scOpened) {
            QString err = m_commandSet->lastError();
            result["authorized"] = false;
            result["error"] = "Failed to open secure channel: " + err;
            m_lastError = "Secure channel failed: " + err;
            debugLog(QString("ERROR: Secure channel failed: %1").arg(err));
            return result;
        }

        debugLog("STEP 4: Verifying PIN...");
        debugLog("STEP 4: BEFORE verifyPIN() call");

        // Verify PIN
        bool success = m_commandSet->verifyPIN(pin);

        debugLog(QString("STEP 4: AFTER verifyPIN() call - result: %1").arg(success));

        if (success) {
            result["authorized"] = true;
            setState(State::Authorized);

            // Now we can get valid status
            auto status = m_commandSet->getStatus();
            if (status.valid) {
                m_remainingPIN = status.pinRetryCount;
                m_remainingPUK = status.pukRetryCount;
                m_keyInitialized = status.keyInitialized;
                debugLog(QString("KeycardBridge: Authorized! PIN: %1 PUK: %2 Initialized: %3")
                         .arg(m_remainingPIN).arg(m_remainingPUK).arg(m_keyInitialized));
            }
        } else {
            result["authorized"] = false;

            // Get updated status after failed PIN
            auto status = m_commandSet->getStatus();
            if (status.valid) {
                m_remainingPIN = status.pinRetryCount;
                result["remainingAttempts"] = m_remainingPIN;
                debugLog(QString("KeycardBridge: PIN verification failed, remaining: %1").arg(m_remainingPIN));

                if (m_remainingPIN == 0) {
                    setState(State::BlockedPIN);
                } else {
                    // PIN was wrong but not blocked - go back to Ready state
                    setState(State::Ready);
                }
            } else {
                result["remainingAttempts"] = -1;
                result["error"] = "PIN verification failed, could not get remaining attempts";
                // Without valid status, assume Ready state
                setState(State::Ready);
            }
        }

    } catch (const std::exception& e) {
        result["authorized"] = false;
        result["error"] = e.what();
        m_lastError = e.what();
        debugLog(QString("KeycardBridge::authorize() exception: %1").arg(e.what()));
    }

    debugLog("KeycardBridge::authorize() END");
    return result;
}

QByteArray KeycardBridge::exportKey(const QString &path)
{
    qDebug() << "KeycardBridge::exportKey() called, path:" << path;

    if (!m_commandSet || !m_cardReady) {
        m_lastError = "Card not ready";
        qWarning() << "KeycardBridge::exportKey():" << m_lastError;
        return QByteArray();
    }

    if (m_state != State::Authorized) {
        m_lastError = "Not authorized - call authorize() first";
        qWarning() << "KeycardBridge::exportKey():" << m_lastError;
        return QByteArray();
    }

    try {
        // Export key at the specified BIP32 path
        // This is REAL EIP-1581 - derives on-card at custom path!
        QByteArray keyTLV = m_commandSet->exportKey(
            /*derive=*/true,
            /*makeCurrent=*/false,
            /*path=*/path,
            /*exportType=*/Keycard::APDU::P2ExportKeyPrivateAndPublic
        );

        if (keyTLV.isEmpty()) {
            m_lastError = m_commandSet->lastError();
            qWarning() << "KeycardBridge::exportKey() failed:" << m_lastError;
            return QByteArray();
        }

        // Parse TLV to extract private key
        QByteArray privateKey = parsePrivateKeyFromTLV(keyTLV);

        if (privateKey.isEmpty()) {
            m_lastError = "Failed to parse private key from TLV";
            qWarning() << "KeycardBridge::exportKey():" << m_lastError;
            return QByteArray();
        }

        qDebug() << "KeycardBridge::exportKey() success, key size:" << privateKey.size();
        return privateKey;

    } catch (const std::exception& e) {
        m_lastError = e.what();
        qWarning() << "KeycardBridge::exportKey() exception:" << e.what();
        return QByteArray();
    }
}

QByteArray KeycardBridge::loginFlow(const QString &pin)
{
    qDebug() << "KeycardBridge::loginFlow() called";

    // Authorize first
    QJsonObject authResult = authorize(pin);
    if (!authResult["authorized"].toBool()) {
        m_lastError = "Authorization failed";
        return QByteArray();
    }

    // Export key at default path
    return exportKey();
}

void KeycardBridge::onCardReady(const QString& uid)
{
    qDebug() << "KeycardBridge::onCardReady() signal received, uid from signal:" << uid;

    m_cardReady = true;

    // Select applet and get status to get the REAL instance UID
    // (The uid parameter from the signal is often truncated - it's the ATR/physical serial)
    try {
        auto appInfo = m_commandSet->select();
        qDebug() << "KeycardBridge: Applet selected, getting status...";

        // Get instance UID from appInfo (full 16 bytes)
        QString instanceUID = QString::fromUtf8(appInfo.instanceUID.toHex());
        qDebug() << "KeycardBridge::onCardReady() - instanceUID from appInfo:" << instanceUID;

        if (!instanceUID.isEmpty() && instanceUID.length() == 32) {
            m_keyUID = instanceUID;
        } else {
            qWarning() << "KeycardBridge::onCardReady() - Invalid instanceUID, using signal UID as fallback";
            m_keyUID = uid;
        }

        auto status = m_commandSet->getStatus();
        if (status.valid) {
            m_remainingPIN = status.pinRetryCount;
            m_remainingPUK = status.pukRetryCount;
            m_keyInitialized = status.keyInitialized;
            qDebug() << "KeycardBridge: Status - PIN:" << m_remainingPIN
                     << "PUK:" << m_remainingPUK
                     << "Initialized:" << m_keyInitialized;
        } else {
            qWarning() << "KeycardBridge: Invalid status returned";
        }
    } catch (const std::exception& e) {
        qWarning() << "KeycardBridge: Failed to select/getStatus:" << e.what();
    }

    // Determine state based on card status
    if (m_remainingPIN == 0) {
        setState(State::BlockedPIN);
    } else if (m_remainingPUK == 0) {
        setState(State::BlockedPUK);
    } else if (!m_keyInitialized) {
        setState(State::EmptyKeycard);
    } else {
        setState(State::Ready);
    }
}

void KeycardBridge::onCardLost()
{
    qDebug() << "KeycardBridge::onCardLost()";

    m_cardReady = false;
    m_keyUID.clear();
    m_remainingPIN = -1;
    m_remainingPUK = -1;
    m_keyInitialized = false;

    setState(State::WaitingForCard);
}

void KeycardBridge::setState(State newState)
{
    if (m_state != newState) {
        m_state = newState;
        qDebug() << "KeycardBridge: State changed to" << static_cast<int>(newState);
        emit stateChanged(newState);
    }
}

void KeycardBridge::updateStatusFromCommandSet()
{
    if (!m_commandSet || !m_cardReady) {
        return;
    }

    try {
        // Get cached status (avoids blocking call)
        if (m_commandSet->hasCachedStatus()) {
            auto status = m_commandSet->cachedApplicationStatus();
            if (status.valid) {
                m_remainingPIN = status.pinRetryCount;
                m_remainingPUK = status.pukRetryCount;
                m_keyInitialized = status.keyInitialized;
            }
        } else {
            // No cached status, query it
            auto status = m_commandSet->getStatus();
            if (status.valid) {
                m_remainingPIN = status.pinRetryCount;
                m_remainingPUK = status.pukRetryCount;
                m_keyInitialized = status.keyInitialized;
            }
        }
    } catch (const std::exception& e) {
        qWarning() << "KeycardBridge::updateStatusFromCommandSet() failed:" << e.what();
    }
}

bool KeycardBridge::isReaderPresent()
{
    // Query PC/SC directly to check if any readers are present
    // This works even when no card is inserted

    SCARDCONTEXT hContext;
    LONG rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);

    if (rv != SCARD_S_SUCCESS) {
        qDebug() << "KeycardBridge::isReaderPresent: PC/SC not available, error:" << rv;
        return false;  // PC/SC not available
    }

    LPSTR readers = NULL;
    DWORD dwReaders = SCARD_AUTOALLOCATE;
    rv = SCardListReaders(hContext, NULL, (LPSTR)&readers, &dwReaders);

    bool hasReaders = (rv == SCARD_S_SUCCESS && dwReaders > 1);  // dwReaders includes null terminator

    if (hasReaders) {
        qDebug() << "KeycardBridge::isReaderPresent: Found readers";
    } else {
        qDebug() << "KeycardBridge::isReaderPresent: No readers found, error:" << rv;
    }

    if (readers) {
        SCardFreeMemory(hContext, readers);
    }
    SCardReleaseContext(hContext);

    return hasReaders;
}

bool KeycardBridge::isCardPresent()
{
    // Query PC/SC to check if a card is inserted in any reader

    SCARDCONTEXT hContext;
    LONG rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);

    if (rv != SCARD_S_SUCCESS) {
        return false;
    }

    LPSTR readers = NULL;
    DWORD dwReaders = SCARD_AUTOALLOCATE;
    rv = SCardListReaders(hContext, NULL, (LPSTR)&readers, &dwReaders);

    if (rv != SCARD_S_SUCCESS || !readers) {
        SCardReleaseContext(hContext);
        return false;
    }

    // Check status of each reader
    LPSTR reader = readers;
    bool cardFound = false;

    while (*reader != '\0') {
        SCARD_READERSTATE readerState;
        readerState.szReader = reader;
        readerState.dwCurrentState = SCARD_STATE_UNAWARE;

        rv = SCardGetStatusChange(hContext, 0, &readerState, 1);

        if (rv == SCARD_S_SUCCESS) {
            // Check if card is present
            if (readerState.dwEventState & SCARD_STATE_PRESENT) {
                qDebug() << "KeycardBridge::isCardPresent: Card found in reader:" << reader;
                cardFound = true;

                // Trigger card ready if not already detected
                if (!m_cardReady && m_commandSet) {
                    // Manual card detection - try to connect
                    qDebug() << "KeycardBridge::isCardPresent: Card found, attempting to select applet";
                    try {
                        auto appInfo = m_commandSet->select();
                        QString uid = QString::fromUtf8(appInfo.instanceUID.toHex());
                        qDebug() << "KeycardBridge::isCardPresent: Select successful, UID:" << uid << "initialized:" << appInfo.initialized;

                        if (!uid.isEmpty()) {
                            // Set card info from ApplicationInfo (doesn't need secure channel)
                            m_cardReady = true;
                            m_keyUID = uid;
                            m_keyInitialized = appInfo.initialized;

                            // Set state based on initialization status
                            if (appInfo.initialized) {
                                setState(State::Ready);
                                qDebug() << "KeycardBridge::isCardPresent: Card initialized, set to Ready";
                            } else {
                                setState(State::EmptyKeycard);
                                qDebug() << "KeycardBridge::isCardPresent: Card not initialized, set to EmptyKeycard";
                            }

                            // Emit signal for any listeners
                            emit stateChanged(m_state);
                        } else {
                            qDebug() << "KeycardBridge::isCardPresent: UID is empty, setting state to NotKeycard";
                            setState(State::NotKeycard);
                        }
                    } catch (const std::exception& e) {
                        qDebug() << "KeycardBridge::isCardPresent: Select failed:" << e.what();
                        // Card is present but not responding - set to ConnectingCard
                        setState(State::ConnectingCard);
                    }
                } else if (m_cardReady) {
                    qDebug() << "KeycardBridge::isCardPresent: Card already detected in ready state";
                }
                break;
            }
        }

        // Move to next reader
        reader += strlen(reader) + 1;
    }

    SCardFreeMemory(hContext, readers);
    SCardReleaseContext(hContext);

    return cardFound;
}

QByteArray KeycardBridge::parsePrivateKeyFromTLV(const QByteArray& tlv)
{
    // TLV format from keycard-qt exportKey:
    // When exporting private key only (no public key):
    // Tag 0xA1 (private key template)
    //   Tag 0x81 (private key - 32 bytes) OR
    //   Tag 0x80 (private key - 32 bytes)
    //
    // When exporting both:
    // Tag 0xA1 (private key template)
    //   Tag 0x81 (public key - 65 bytes)
    //   Tag 0x80 (private key - 32 bytes)
    //   Tag 0x82 (chain code - 32 bytes)

    qDebug() << "KeycardBridge: Parsing TLV, size:" << tlv.size() << "hex:" << tlv.toHex();

    if (tlv.size() < 10) {
        qWarning() << "TLV too short:" << tlv.size();
        return QByteArray();
    }

    // Find tag 0x80 or 0x81 with 32-byte length (private key)
    for (int i = 0; i < tlv.size() - 2; ++i) {
        unsigned char tag = static_cast<unsigned char>(tlv[i]);
        if (tag == 0x80 || tag == 0x81) {
            int length = static_cast<unsigned char>(tlv[i + 1]);
            qDebug() << "Found tag" << QString("0x%1").arg(tag, 2, 16, QChar('0'))
                     << "at offset" << i << "with length" << length;

            // Private key is always 32 bytes
            if (length == 32 && i + 2 + length <= tlv.size()) {
                QByteArray key = tlv.mid(i + 2, length);
                qDebug() << "Extracted private key:" << key.toHex();
                return key;
            } else if (length != 32) {
                // Might be public key (65 bytes), skip it
                qDebug() << "Skipping tag (wrong length for private key)";
                i += length + 1;  // Skip this tag's data
            }
        }
    }

    qWarning() << "Private key tag (0x80 or 0x81 with 32 bytes) not found in TLV";
    qDebug() << "TLV dump: First 40 bytes:" << tlv.left(40).toHex();
    return QByteArray();
}
