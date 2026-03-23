#include "KeycardBridge.h"
#include <keycard-qt/keycard_channel.h>
#include <keycard-qt/command_set.h>
#include <keycard-qt/types.h>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>

// Simple in-memory pairing storage
class MemoryPairingStorage : public Keycard::IPairingStorage {
public:
    bool save(const QString& instanceUID, const Keycard::PairingInfo& pairing) override {
        m_pairings[instanceUID] = pairing;
        return true;
    }

    Keycard::PairingInfo load(const QString& instanceUID) override {
        auto it = m_pairings.find(instanceUID);
        if (it != m_pairings.end()) {
            return it->second;
        }
        return Keycard::PairingInfo();  // Invalid pairing (index=-1)
    }

    bool remove(const QString& instanceUID) override {
        return m_pairings.erase(instanceUID) > 0;
    }

private:
    std::map<QString, Keycard::PairingInfo> m_pairings;
};

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

        // Create pairing storage
        m_pairingStorage = std::make_shared<MemoryPairingStorage>();

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
    if (!m_commandSet || !m_cardReady) {
        return;
    }

    updateStatusFromCommandSet();
}

QJsonObject KeycardBridge::authorize(const QString &pin)
{
    qDebug() << "KeycardBridge::authorize() called";

    QJsonObject result;

    if (!m_commandSet || !m_cardReady) {
        result["authorized"] = false;
        result["error"] = "Card not ready";
        m_lastError = "Card not ready";
        return result;
    }

    try {
        // Verify PIN
        bool success = m_commandSet->verifyPIN(pin);

        if (success) {
            result["authorized"] = true;
            setState(State::Authorized);
            updateStatusFromCommandSet();
        } else {
            result["authorized"] = false;
            updateStatusFromCommandSet();
            result["remainingAttempts"] = m_remainingPIN;

            if (m_remainingPIN == 0) {
                setState(State::BlockedPIN);
            }
        }

    } catch (const std::exception& e) {
        result["authorized"] = false;
        result["error"] = e.what();
        m_lastError = e.what();
        qWarning() << "KeycardBridge::authorize() failed:" << e.what();
    }

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
    qDebug() << "KeycardBridge::onCardReady() uid:" << uid;

    m_cardReady = true;
    m_keyUID = uid;

    // Get application status
    updateStatusFromCommandSet();

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
            m_remainingPIN = status.pinRetryCount;
            m_remainingPUK = status.pukRetryCount;
            m_keyInitialized = status.keyInitialized;
        } else {
            // No cached status, query it
            auto status = m_commandSet->getStatus();
            m_remainingPIN = status.pinRetryCount;
            m_remainingPUK = status.pukRetryCount;
            m_keyInitialized = status.keyInitialized;
        }
    } catch (const std::exception& e) {
        qWarning() << "KeycardBridge::updateStatusFromCommandSet() failed:" << e.what();
    }
}

QByteArray KeycardBridge::parsePrivateKeyFromTLV(const QByteArray& tlv)
{
    // TLV format from keycard-qt exportKey:
    // Tag 0xA1 (private key template)
    //   Tag 0x81 (public key - 65 bytes)
    //   Tag 0x80 (private key - 32 bytes)
    //   Tag 0x82 (chain code - 32 bytes)

    if (tlv.size() < 10) {
        qWarning() << "TLV too short:" << tlv.size();
        return QByteArray();
    }

    // Find tag 0x80 (private key)
    for (int i = 0; i < tlv.size() - 2; ++i) {
        if (static_cast<unsigned char>(tlv[i]) == 0x80) {
            int length = static_cast<unsigned char>(tlv[i + 1]);
            if (length == 32 && i + 2 + length <= tlv.size()) {
                return tlv.mid(i + 2, length);
            }
        }
    }

    qWarning() << "Private key tag 0x80 not found in TLV";
    return QByteArray();
}
