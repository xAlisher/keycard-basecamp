# keycard-basecamp

Standalone Keycard smartcard authentication module for Logos Basecamp.

## Overview

This module provides smartcard authentication primitives for the Logos Basecamp ecosystem. Any Basecamp app can consume Keycard functionality via `logos.callModule("keycard", ...)`.

**Status:** ✅ Core functionality complete (Phases 1-3)

**What works:**
- Reader and card discovery
- PIN authentication
- Domain-based key derivation (unique keys per app)
- Session management (authorize, derive, close, re-auth)
- Live state updates
- Card removal detection

## Architecture

- **keycard-core**: C++ plugin wrapping libkeycard.so (status-keycard-go via CGO)
  - KeycardBridge: JSON-RPC communication with Go library
  - 7-state machine: READER_NOT_FOUND → CARD_PRESENT → AUTHORIZED → SESSION_ACTIVE → SESSION_CLOSED
  - Domain-based derivation: EIP-1581 compliant paths (v2, default) or legacy SHA256 (v1, deprecated)
- **keycard-ui**: QML debug UI test harness
  - 7 action rows (one per API method)
  - Live state indicator (500ms polling)
  - Prerequisites gating

## Security Properties

✅ PIN verification on-card
✅ BIP32 key derivation on-card
✅ Domain separation for multi-app support
✅ Secure memory wiping (sodium_memzero)
✅ Card UID verification (prevents card-swap attacks)

## Documentation

See [SPEC.md](SPEC.md) for complete implementation specification.

## Usage

### API Methods

All methods return JSON strings:

```javascript
// 1. Discover reader
logos.callModule("keycard", "discoverReader", [])
// → {"found": true, "name": "Smart card reader"}

// 2. Discover card
logos.callModule("keycard", "discoverCard", [])
// → {"found": true, "uid": "0bcddc71091899..."}

// 3. Authorize with PIN
logos.callModule("keycard", "authorize", ["000000"])
// → {"authorized": true}

// 4. Derive app-specific key (EIP-1581 standard, default)
logos.callModule("keycard", "deriveKey", ["my-app-domain"])
// → {"key": "64-char-hex-key", "version": 2}

// 4b. Derive with legacy approach (for backward compatibility)
logos.callModule("keycard", "deriveKey", ["my-app-domain", 1])
// → {"key": "64-char-hex-key", "version": 1}

// 5. Get current state
logos.callModule("keycard", "getState", [])
// → {"state": "SESSION_ACTIVE"}

// 6. Close session (wipe key)
logos.callModule("keycard", "closeSession", [])
// → {"closed": true}

// 7. Get last error
logos.callModule("keycard", "getLastError", [])
// → {"error": "error message or empty"}
```

### Example Flow

```javascript
// Full authentication + key derivation flow
const reader = JSON.parse(logos.callModule("keycard", "discoverReader", []))
if (!reader.found) throw new Error("Reader not found")

const card = JSON.parse(logos.callModule("keycard", "discoverCard", []))
if (!card.found) throw new Error("Card not present")

const auth = JSON.parse(logos.callModule("keycard", "authorize", ["000000"]))
if (!auth.authorized) throw new Error("Authorization failed")

const key = JSON.parse(logos.callModule("keycard", "deriveKey", ["notes-encryption"]))
// Use key.key for encryption...

// When done:
logos.callModule("keycard", "closeSession", [])
```

## Development

### Build & Install

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cmake --install build
```

Installs to: `~/.local/share/Logos/LogosBasecamp/`

### Test

Use the debug UI (keycard-ui plugin in Basecamp) to test all flows.

See [TESTING.md](TESTING.md) for comprehensive test checklist.

## Implementation Status

- ✅ **Phase 1:** Scaffolding (Issue #1)
- ✅ **Phase 2:** Core module implementation (Issue #2)
- ✅ **Phase 3:** Debug UI test harness (Issue #3)
- 🚧 **Phase 4:** Testing strategy (Issue #4) - in progress
- ⏳ **Phase 5:** Nix flake & LGX packaging (Issue #5)

## Source

Keycard logic uses libkeycard.so (status-keycard-go compiled via CGO).

## Documentation

- [SPEC.md](SPEC.md) - Complete API specification & state machine
- [LESSONS.md](LESSONS.md) - Implementation lessons learned
- [PROJECT_KNOWLEDGE.md](PROJECT_KNOWLEDGE.md) - Architecture decisions & patterns
- [TESTING.md](TESTING.md) - Manual testing checklist

## License

TBD
