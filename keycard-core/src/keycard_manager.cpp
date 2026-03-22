#include "keycard_manager.h"
#include <QDebug>
#include <QCryptographicHash>
#include <sodium.h>

namespace Keycard {

KeycardManager::KeycardManager(QObject* parent)
    : QObject(parent)
    , m_pollTimer(new QTimer(this))
{
    connect(m_pollTimer, &QTimer::timeout, this, &KeycardManager::pollCardPresence);
}

KeycardManager::~KeycardManager()
{
    closeSession();
    releaseContext();
}

// ============================================================================
// State Machine
// ============================================================================

void KeycardManager::transitionTo(State newState)
{
    if (m_state == newState) {
        return;
    }

    qDebug() << "Keycard state transition:" << stateToString(m_state)
             << "->" << stateToString(newState);

    // Exit actions for old state
    switch (m_state) {
        case State::SESSION_ACTIVE:
            // Wipe key when leaving active session
            m_derivedKey.wipe();
            m_currentDomain.clear();
            break;
        default:
            break;
    }

    m_state = newState;

    // Entry actions for new state
    switch (newState) {
        case State::CARD_NOT_PRESENT:
        case State::READER_NOT_FOUND:
            // Card gone - clear card identity
            m_cardUID.clear();
            m_sessionCardUID.clear();
            disconnectCard();
            break;

        case State::SESSION_CLOSED:
            // Explicit session close - wipe everything
            m_derivedKey.wipe();
            m_currentDomain.clear();
            m_sessionCardUID.clear();
            break;

        case State::BLOCKED:
            // Card blocked - disconnect
            disconnectCard();
            break;

        default:
            break;
    }

    emit stateChanged(newState);
}

void KeycardManager::setError(Error error)
{
    m_lastError = error;
    if (error != Error::NONE) {
        qDebug() << "Keycard error:" << errorToString(error);
    }
}

// ============================================================================
// PC/SC Context Management
// ============================================================================

bool KeycardManager::establishContext()
{
    if (m_context != 0) {
        return true; // Already established
    }

    LONG rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, nullptr, nullptr, &m_context);
    if (rv != SCARD_S_SUCCESS) {
        qDebug() << "SCardEstablishContext failed:" << QString::number(rv, 16);
        setError(Error::READER_NOT_FOUND);
        return false;
    }

    qDebug() << "PC/SC context established";
    return true;
}

void KeycardManager::releaseContext()
{
    stopPolling();

    if (m_cardHandle != 0) {
        disconnectCard();
    }

    if (m_context != 0) {
        SCardReleaseContext(m_context);
        m_context = 0;
        qDebug() << "PC/SC context released";
    }
}

// ============================================================================
// Reader Discovery
// ============================================================================

bool KeycardManager::discoverReader()
{
    if (!establishContext()) {
        transitionTo(State::READER_NOT_FOUND);
        return false;
    }

    // Get list of readers
    DWORD readersLen = 0;
    LONG rv = SCardListReaders(m_context, nullptr, nullptr, &readersLen);

    if (rv != SCARD_S_SUCCESS || readersLen == 0) {
        qDebug() << "No PC/SC readers found";
        setError(Error::READER_NOT_FOUND);
        transitionTo(State::READER_NOT_FOUND);
        return false;
    }

    QByteArray readersBuf(readersLen, '\0');
    rv = SCardListReaders(m_context, nullptr, readersBuf.data(), &readersLen);

    if (rv != SCARD_S_SUCCESS) {
        qDebug() << "SCardListReaders failed:" << QString::number(rv, 16);
        setError(Error::READER_NOT_FOUND);
        transitionTo(State::READER_NOT_FOUND);
        return false;
    }

    // Take first reader (multi-string format: name1\0name2\0\0)
    m_readerName = QString::fromUtf8(readersBuf.data());

    qDebug() << "PC/SC reader found:" << m_readerName;
    setError(Error::NONE);
    transitionTo(State::CARD_NOT_PRESENT);

    // Start polling for card presence
    startPolling();

    return true;
}

// ============================================================================
// Card Discovery
// ============================================================================

bool KeycardManager::discoverCard()
{
    if (m_state == State::READER_NOT_FOUND) {
        setError(Error::READER_NOT_FOUND);
        return false;
    }

    if (!connectToCard()) {
        setError(Error::CARD_NOT_PRESENT);
        transitionTo(State::CARD_NOT_PRESENT);
        return false;
    }

    if (!selectKeycardApplet()) {
        qDebug() << "Card present but Keycard applet not found";
        setError(Error::APDU_FAILED);
        disconnectCard();
        transitionTo(State::CARD_NOT_PRESENT);
        return false;
    }

    // Read card UID
    m_cardUID = readCardUID();
    if (m_cardUID.isEmpty()) {
        qDebug() << "Failed to read card UID";
        setError(Error::APDU_FAILED);
        disconnectCard();
        transitionTo(State::CARD_NOT_PRESENT);
        return false;
    }

    qDebug() << "Keycard detected, UID:" << m_cardUID.toHex();
    setError(Error::NONE);
    transitionTo(State::CARD_PRESENT);

    return true;
}

bool KeycardManager::connectToCard()
{
    if (m_readerName.isEmpty()) {
        return false;
    }

    QByteArray readerBytes = m_readerName.toUtf8();
    LONG rv = SCardConnect(
        m_context,
        readerBytes.constData(),
        SCARD_SHARE_SHARED,
        SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1,
        &m_cardHandle,
        &m_activeProtocol
    );

    if (rv != SCARD_S_SUCCESS) {
        qDebug() << "SCardConnect failed:" << QString::number(rv, 16);
        m_cardHandle = 0;
        return false;
    }

    qDebug() << "Connected to card via" << (m_activeProtocol == SCARD_PROTOCOL_T0 ? "T=0" : "T=1");
    return true;
}

void KeycardManager::disconnectCard()
{
    if (m_cardHandle != 0) {
        SCardDisconnect(m_cardHandle, SCARD_LEAVE_CARD);
        m_cardHandle = 0;
        qDebug() << "Disconnected from card";
    }
}

// ============================================================================
// APDU Transmission
// ============================================================================

bool KeycardManager::transmitAPDU(const QByteArray& command, QByteArray& response)
{
    if (m_cardHandle == 0) {
        qDebug() << "transmitAPDU: no card handle";
        return false;
    }

    // Response buffer (max APDU response)
    uint8_t recvBuf[258];
    DWORD recvLen = sizeof(recvBuf);

    SCARD_IO_REQUEST pioSendPci;
    pioSendPci.dwProtocol = m_activeProtocol;
    pioSendPci.cbPciLength = sizeof(SCARD_IO_REQUEST);

    LONG rv = SCardTransmit(
        m_cardHandle,
        &pioSendPci,
        reinterpret_cast<const uint8_t*>(command.constData()),
        command.size(),
        nullptr,
        recvBuf,
        &recvLen
    );

    if (rv != SCARD_S_SUCCESS) {
        qDebug() << "SCardTransmit failed:" << QString::number(rv, 16);
        return false;
    }

    response = QByteArray(reinterpret_cast<const char*>(recvBuf), recvLen);
    return true;
}

// ============================================================================
// Card Operations
// ============================================================================

bool KeycardManager::selectKeycardApplet()
{
    // SELECT command: CLA=00 INS=A4 P1=04 P2=00 Lc=09 AID
    QByteArray cmd;
    cmd.append(static_cast<char>(0x00));                    // CLA
    cmd.append(static_cast<char>(APDU::INS_SELECT));        // INS
    cmd.append(static_cast<char>(0x04));                    // P1 (select by name)
    cmd.append(static_cast<char>(0x00));                    // P2
    cmd.append(static_cast<char>(APDU::KEYCARD_AID_LEN));   // Lc
    cmd.append(reinterpret_cast<const char*>(APDU::KEYCARD_AID), APDU::KEYCARD_AID_LEN);

    QByteArray resp;
    if (!transmitAPDU(cmd, resp)) {
        return false;
    }

    // Check SW (last 2 bytes)
    if (resp.size() < 2) {
        return false;
    }

    uint16_t sw = (static_cast<uint8_t>(resp[resp.size()-2]) << 8) |
                   static_cast<uint8_t>(resp[resp.size()-1]);

    if (sw != APDU::SW_SUCCESS) {
        qDebug() << "SELECT Keycard applet failed, SW:" << QString::number(sw, 16);
        return false;
    }

    qDebug() << "Keycard applet selected";
    return true;
}

QByteArray KeycardManager::readCardUID()
{
    // GET STATUS command to read UID
    // CLA=80 INS=F2 P1=00 P2=00
    QByteArray cmd;
    cmd.append(static_cast<char>(APDU::CLA_KEYCARD));
    cmd.append(static_cast<char>(APDU::INS_GET_STATUS));
    cmd.append(static_cast<char>(0x00));
    cmd.append(static_cast<char>(0x00));

    QByteArray resp;
    if (!transmitAPDU(cmd, resp)) {
        return QByteArray();
    }

    if (resp.size() < 2) {
        return QByteArray();
    }

    uint16_t sw = (static_cast<uint8_t>(resp[resp.size()-2]) << 8) |
                   static_cast<uint8_t>(resp[resp.size()-1]);

    if (sw != APDU::SW_SUCCESS) {
        qDebug() << "GET STATUS failed, SW:" << QString::number(sw, 16);
        return QByteArray();
    }

    // Response format: TLV data + SW
    // Extract UID from TLV (implementation depends on Keycard applet format)
    // For now, use first 16 bytes as UID
    QByteArray uid = resp.left(resp.size() - 2); // Remove SW bytes
    if (uid.size() > 16) {
        uid = uid.left(16);
    }

    return uid;
}

// ============================================================================
// Authorization
// ============================================================================

bool KeycardManager::authorize(const QString& pin, int& remainingAttempts)
{
    remainingAttempts = 0;

    if (m_state != State::CARD_PRESENT && m_state != State::AUTHORIZED) {
        setError(Error::INVALID_STATE);
        return false;
    }

    if (!verifyPIN(pin, remainingAttempts)) {
        if (remainingAttempts == 0) {
            transitionTo(State::BLOCKED);
            setError(Error::PIN_BLOCKED);
        } else {
            setError(Error::INVALID_PIN);
        }
        return false;
    }

    setError(Error::NONE);
    transitionTo(State::AUTHORIZED);
    return true;
}

bool KeycardManager::verifyPIN(const QString& pin, int& remainingAttempts)
{
    QByteArray pinBytes = pin.toUtf8();

    // VERIFY PIN command: CLA=80 INS=20 P1=00 P2=00 Lc=<len> <PIN>
    QByteArray cmd;
    cmd.append(static_cast<char>(APDU::CLA_KEYCARD));
    cmd.append(static_cast<char>(APDU::INS_VERIFY_PIN));
    cmd.append(static_cast<char>(0x00));
    cmd.append(static_cast<char>(0x00));
    cmd.append(static_cast<char>(pinBytes.size()));
    cmd.append(pinBytes);

    QByteArray resp;
    if (!transmitAPDU(cmd, resp)) {
        return false;
    }

    if (resp.size() < 2) {
        return false;
    }

    uint16_t sw = (static_cast<uint8_t>(resp[resp.size()-2]) << 8) |
                   static_cast<uint8_t>(resp[resp.size()-1]);

    if (sw == APDU::SW_SUCCESS) {
        qDebug() << "PIN verified successfully";
        return true;
    }

    // Check for wrong PIN with remaining attempts
    if ((sw & 0xFFF0) == APDU::SW_WRONG_PIN) {
        remainingAttempts = sw & 0x0F;
        qDebug() << "Wrong PIN, remaining attempts:" << remainingAttempts;
        return false;
    }

    if (sw == APDU::SW_PIN_BLOCKED) {
        qDebug() << "PIN blocked";
        remainingAttempts = 0;
        return false;
    }

    qDebug() << "VERIFY PIN failed, SW:" << QString::number(sw, 16);
    return false;
}

// ============================================================================
// Key Derivation
// ============================================================================

bool KeycardManager::deriveKey(const QString& domain, SecureBuffer& outKey)
{
    if (m_state != State::AUTHORIZED && m_state != State::SESSION_ACTIVE) {
        setError(Error::INVALID_STATE);
        return false;
    }

    // Verify card UID if session already active (card swap detection)
    if (m_state == State::SESSION_ACTIVE) {
        QByteArray currentUID = readCardUID();
        if (currentUID != m_sessionCardUID) {
            qDebug() << "Card UID mismatch - card was swapped!";
            setError(Error::UID_MISMATCH);
            transitionTo(State::CARD_PRESENT);
            return false;
        }
    } else {
        // First derivation - record session UID
        m_sessionCardUID = m_cardUID;
    }

    // Export master key from card
    SecureBuffer cardKey;
    if (!exportMasterKey(cardKey)) {
        setError(Error::DERIVATION_FAILED);
        return false;
    }

    // Derive Keycard master key
    SecureBuffer masterKey = deriveKeycardMasterKey(cardKey);
    cardKey.wipe(); // Wipe intermediate

    // Derive domain-specific key
    m_derivedKey = deriveDomainKey(masterKey, domain);
    masterKey.wipe(); // Wipe intermediate

    m_currentDomain = domain;
    outKey = SecureBuffer(m_derivedKey.toByteArray()); // Copy for caller

    setError(Error::NONE);
    transitionTo(State::SESSION_ACTIVE);

    qDebug() << "Key derived for domain:" << domain;
    return true;
}

bool KeycardManager::exportMasterKey(SecureBuffer& outKey)
{
    // EXPORT KEY command: CLA=80 INS=C2 P1=00 P2=00
    QByteArray cmd;
    cmd.append(static_cast<char>(APDU::CLA_KEYCARD));
    cmd.append(static_cast<char>(APDU::INS_EXPORT_KEY));
    cmd.append(static_cast<char>(0x00));
    cmd.append(static_cast<char>(0x00));

    QByteArray resp;
    if (!transmitAPDU(cmd, resp)) {
        return false;
    }

    if (resp.size() < 2) {
        return false;
    }

    uint16_t sw = (static_cast<uint8_t>(resp[resp.size()-2]) << 8) |
                   static_cast<uint8_t>(resp[resp.size()-1]);

    if (sw != APDU::SW_SUCCESS) {
        qDebug() << "EXPORT KEY failed, SW:" << QString::number(sw, 16);
        return false;
    }

    // Extract key data (everything except SW bytes)
    QByteArray keyData = resp.left(resp.size() - 2);

    if (keyData.size() < KeyDerivation::MASTER_KEY_SIZE) {
        qDebug() << "Exported key too short:" << keyData.size();
        return false;
    }

    outKey = SecureBuffer(keyData);
    qDebug() << "Master key exported, size:" << outKey.size();
    return true;
}

SecureBuffer KeycardManager::deriveKeycardMasterKey(const SecureBuffer& cardKey)
{
    // Derive "Keycard master key" from card's exported key
    // Use HKDF with salt = "keycard-master"

    const char* salt = "keycard-master";
    SecureBuffer masterKey(KeyDerivation::MASTER_KEY_SIZE);

    if (crypto_kdf_hkdf_sha256_extract(
            reinterpret_cast<uint8_t*>(masterKey.data()),
            reinterpret_cast<const uint8_t*>(salt),
            strlen(salt),
            reinterpret_cast<const uint8_t*>(cardKey.constData()),
            cardKey.size()) != 0) {
        qDebug() << "HKDF extract failed";
        return SecureBuffer();
    }

    return masterKey;
}

SecureBuffer KeycardManager::deriveDomainKey(const SecureBuffer& masterKey, const QString& domain)
{
    // Derive domain-specific key using HKDF-Expand
    // Info = "keycard-domain:" + domain

    QByteArray info = QStringLiteral("keycard-domain:").toUtf8() + domain.toUtf8();
    SecureBuffer domainKey(KeyDerivation::DERIVED_KEY_SIZE);

    if (crypto_kdf_hkdf_sha256_expand(
            reinterpret_cast<uint8_t*>(domainKey.data()),
            domainKey.size(),
            info.constData(),  // ctx is const char*, not const uint8_t*
            info.size(),
            reinterpret_cast<const uint8_t*>(masterKey.constData())) != 0) {
        qDebug() << "HKDF expand failed";
        return SecureBuffer();
    }

    return domainKey;
}

// ============================================================================
// Session Management
// ============================================================================

void KeycardManager::closeSession()
{
    if (m_state == State::SESSION_ACTIVE || m_state == State::AUTHORIZED) {
        transitionTo(State::SESSION_CLOSED);
        qDebug() << "Session closed";
    }
}

// ============================================================================
// Card Presence Polling
// ============================================================================

void KeycardManager::startPolling()
{
    if (!m_pollTimer->isActive()) {
        m_pollTimer->start(POLL_INTERVAL_MS);
        qDebug() << "Card presence polling started";
    }
}

void KeycardManager::stopPolling()
{
    if (m_pollTimer->isActive()) {
        m_pollTimer->stop();
        qDebug() << "Card presence polling stopped";
    }
}

void KeycardManager::pollCardPresence()
{
    if (m_state == State::READER_NOT_FOUND) {
        return; // No reader, don't poll
    }

    // Check if card is still present
    DWORD state, protocol;
    uint8_t atr[33];
    DWORD atrLen = sizeof(atr);
    DWORD readerLen = 0;

    LONG rv = SCardStatus(m_cardHandle, nullptr, &readerLen, &state, &protocol, atr, &atrLen);

    if (rv == SCARD_W_REMOVED_CARD || rv == SCARD_E_NO_SMARTCARD) {
        // Card removed
        if (m_state != State::CARD_NOT_PRESENT) {
            qDebug() << "Card removed";
            emit cardRemoved();

            if (m_state == State::SESSION_ACTIVE) {
                // Active session interrupted - wipe key
                transitionTo(State::SESSION_CLOSED);
            }

            transitionTo(State::CARD_NOT_PRESENT);
        }
    } else if (rv == SCARD_S_SUCCESS) {
        // Card still present
        if (m_state == State::CARD_NOT_PRESENT) {
            qDebug() << "Card inserted";
            emit cardInserted();
            // Don't auto-discover - wait for explicit discoverCard() call
        }
    }
}

} // namespace Keycard
