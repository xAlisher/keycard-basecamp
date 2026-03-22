#pragma once

#include <QString>

namespace Keycard {

// State machine states (from SPEC.md)
enum class State {
    READER_NOT_FOUND,    // No PC/SC reader detected
    CARD_NOT_PRESENT,    // Reader found, no card inserted
    CARD_PRESENT,        // Card detected but not authorized
    AUTHORIZED,          // PIN verified successfully
    SESSION_ACTIVE,      // Key derived and available
    SESSION_CLOSED,      // Session ended, key wiped
    BLOCKED              // Card locked after 3 failed PIN attempts
};

// Error codes for JSON responses
enum class Error {
    NONE,
    READER_NOT_FOUND,
    CARD_NOT_PRESENT,
    CARD_REMOVED,
    INVALID_PIN,
    PIN_BLOCKED,
    INVALID_STATE,
    APDU_FAILED,
    DERIVATION_FAILED,
    UID_MISMATCH,
    UNKNOWN
};

// Convert state to string for JSON
inline QString stateToString(State state) {
    switch (state) {
        case State::READER_NOT_FOUND:  return QStringLiteral("READER_NOT_FOUND");
        case State::CARD_NOT_PRESENT:  return QStringLiteral("CARD_NOT_PRESENT");
        case State::CARD_PRESENT:      return QStringLiteral("CARD_PRESENT");
        case State::AUTHORIZED:        return QStringLiteral("AUTHORIZED");
        case State::SESSION_ACTIVE:    return QStringLiteral("SESSION_ACTIVE");
        case State::SESSION_CLOSED:    return QStringLiteral("SESSION_CLOSED");
        case State::BLOCKED:           return QStringLiteral("BLOCKED");
    }
    return QStringLiteral("UNKNOWN");
}

// Convert error to string for JSON
inline QString errorToString(Error error) {
    switch (error) {
        case Error::NONE:               return QStringLiteral("");
        case Error::READER_NOT_FOUND:   return QStringLiteral("Reader not found");
        case Error::CARD_NOT_PRESENT:   return QStringLiteral("Card not present");
        case Error::CARD_REMOVED:       return QStringLiteral("Card was removed");
        case Error::INVALID_PIN:        return QStringLiteral("Invalid PIN");
        case Error::PIN_BLOCKED:        return QStringLiteral("Card blocked - too many failed attempts");
        case Error::INVALID_STATE:      return QStringLiteral("Operation not valid in current state");
        case Error::APDU_FAILED:        return QStringLiteral("Smartcard command failed");
        case Error::DERIVATION_FAILED:  return QStringLiteral("Key derivation failed");
        case Error::UID_MISMATCH:       return QStringLiteral("Card UID mismatch - different card inserted");
        case Error::UNKNOWN:            return QStringLiteral("Unknown error");
    }
    return QStringLiteral("Unknown error");
}

// APDU Constants for Keycard communication
namespace APDU {
    // Command classes
    constexpr uint8_t CLA_KEYCARD = 0x80;

    // Instruction codes
    constexpr uint8_t INS_SELECT       = 0xA4;
    constexpr uint8_t INS_VERIFY_PIN   = 0x20;
    constexpr uint8_t INS_GET_STATUS   = 0xF2;
    constexpr uint8_t INS_EXPORT_KEY   = 0xC2;
    constexpr uint8_t INS_DERIVE_KEY   = 0xD1;

    // Response codes
    constexpr uint16_t SW_SUCCESS      = 0x9000;
    constexpr uint16_t SW_WRONG_PIN    = 0x63C0;  // + remaining attempts in low nibble
    constexpr uint16_t SW_PIN_BLOCKED  = 0x6983;
    constexpr uint16_t SW_WRONG_DATA   = 0x6A80;
    constexpr uint16_t SW_CONDITIONS_NOT_SATISFIED = 0x6985;

    // Keycard AID (Application Identifier)
    // From Keycard applet spec
    const uint8_t KEYCARD_AID[] = {
        0xA0, 0x00, 0x00, 0x08, 0x04, 0x00, 0x01, 0x01, 0x01
    };
    constexpr int KEYCARD_AID_LEN = 9;
}

// PIN constraints
namespace PIN {
    constexpr int MIN_LENGTH = 4;
    constexpr int MAX_LENGTH = 12;
    constexpr int MAX_ATTEMPTS = 3;
}

// Key derivation constants
namespace KeyDerivation {
    // BIP32 path depth
    constexpr int MAX_PATH_DEPTH = 5;

    // Master key size (from card)
    constexpr int MASTER_KEY_SIZE = 32;

    // Derived key size (after domain separation)
    constexpr int DERIVED_KEY_SIZE = 32;
}

} // namespace Keycard
