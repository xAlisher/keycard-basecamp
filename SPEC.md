# Task: Create logos-keycard — Standalone Keycard Module for Logos Basecamp

## Context & Reasoning

We are extracting Keycard functionality from logos-notes into a standalone,
independently deployable Logos Basecamp module.

logos-notes currently owns all smartcard logic directly. The goal is to make
Keycard a first-class Basecamp module that any Logos app can consume via
`logos.callModule("keycard", ...)` — notes being the first consumer, other
Logos apps following.

This repo is built FIRST, before touching logos-notes. Notes will not be
modified until this module is proven working in isolation via the debug UI.

---

## State Machine (explicit transitions)

```
READER_NOT_FOUND
  → discoverReader() succeeds → CARD_NOT_PRESENT

CARD_NOT_PRESENT
  → discoverCard() succeeds → CARD_PRESENT
  → card reinserted after SESSION_CLOSED → CARD_PRESENT

CARD_PRESENT
  → authorize(pin) succeeds → AUTHORIZED
  → card removed → CARD_NOT_PRESENT

AUTHORIZED
  → deriveKey(domain) succeeds → SESSION_ACTIVE
  → card removed → SESSION_CLOSED

SESSION_ACTIVE
  → closeSession() → SESSION_CLOSED
  → card removed → SESSION_CLOSED
  → deriveKey(different domain) → returns new key, stays SESSION_ACTIVE

SESSION_CLOSED
  → card still present + discoverCard() → CARD_PRESENT (ready for re-auth)
  → card removed → CARD_NOT_PRESENT
  → sodium_memzero fires on derived key immediately on entry

BLOCKED (PIN lockout — 3 failed attempts)
  → card removed and reinserted → still BLOCKED
  → only PUK/admin can recover
  → authorize() must refuse in this state
```

---

## Critical Semantic Distinctions

**BLOCKED** = 3 failed PINs, card is bricked, re-entry requires PUK
**SESSION_CLOSED** = voluntary or physical disconnect, card reinsert → re-auth
**CARD_NOT_PRESENT** = no card detected, reader is fine

UI must distinguish these — re-entry path is different for each:
- **BLOCKED:** "Card is locked. Use PUK to recover."
- **SESSION_CLOSED:** "Session ended. Reinsert card to authenticate."
- **CARD_NOT_PRESENT:** "No card detected."

---

## Card Presence Polling

Use QTimer at 500ms interval calling SCardGetStatusChange with 0 timeout
(non-blocking poll — background thread is overkill for presence detection).

Poller drives these transitions:
- `SESSION_ACTIVE + card removed → SESSION_CLOSED` (sodium_memzero fires)
- `CARD_PRESENT + card removed → CARD_NOT_PRESENT`
- `SESSION_CLOSED + card detected → CARD_PRESENT`
- `CARD_NOT_PRESENT + card detected → CARD_PRESENT`

Poller does NOT fire during BLOCKED — card removal/reinsertion does not
clear lockout.

---

## State Change Notifications

**Signal-based updates** for QML reactivity:

```cpp
signals:
    void stateChanged(const QString& newState);
```

QML connects once:
```qml
Connections {
    target: keycard
    function onStateChanged(newState) {
        stateIndicator.text = newState
        // Update button enabled states based on prerequisites
    }
}
```

Emitted on every state transition. QML doesn't need to poll `getState()`.

---

## Card UID Verification (Security)

**On authorize() success:**
- Store card UID
- On card reinsertion during `SESSION_ACTIVE` or `AUTHORIZED`:
  - If UID mismatch → `SESSION_CLOSED` + error
  - Prevents card-swap attacks mid-session

**Implementation:**
```cpp
QString m_expectedUID;  // set on first successful authorize()

// On card re-detection:
if (currentUID != m_expectedUID && state >= AUTHORIZED) {
    transitionTo(SESSION_CLOSED);
    return errorJson("Card changed during session. Re-authenticate.");
}
```

---

## Key Flow (hybrid approach proven in logos-notes)

### 1. authorize(pin)
- PIN verified **ON-CARD**
- Returns: `{"authorized": bool, "remainingAttempts": N}`
- On 3rd failure → state = BLOCKED

### 2. deriveKey(domain)
- **Prerequisite:** state == AUTHORIZED or SESSION_ACTIVE
- **Standards-compliant:** EIP-1581 BIP32 path-based derivation

**EIP-1581 Derivation (Production):**
- BIP32 derivation **ON-CARD** at domain-specific EIP-1581 paths
- Domain → deterministic BIP32 path mapping:
  ```
  domain → SHA256("logos-" + domain) → extract 4 indices (16 bytes)
  Path: m/43'/60'/1581'/<idx1>'/<idx2>'/<idx3>'/<idx4>'
  ```
- **On-card derivation:** Card derives secp256k1 key at custom path
- **No host-side crypto:** No custom hashing, pure BIP32 standard
- **Standards-compliant:** Follows EIP-1581 specification
- **Interoperable:** Compatible with Keycard ecosystem
- **Deeper nesting:** 4-level paths for better collision resistance (2^128 space)
- Reference: https://eips.ethereum.org/EIPS/eip-1581
- Recommended by @mikkoph (Keycard core dev) - fully implemented

**Behavior:**
- Caller supplies domain string:
  - notes: `"notes-encryption"`
  - wallet: `"wallet-signing"`
- "logos-" prefix added for namespace separation
- Same card + same domain = same key (deterministic)
- Different domains = different keys (domain isolation via different paths)
- Derived key wiped immediately after return
- Returns: `{"key": hex_string}` (32-byte secp256k1 private key)
- **Caller responsibility:** Wipe key immediately after use

### 3. Memory management
- SecureBuffer (RAII, auto-wiped)
- sodium_memzero on SESSION_CLOSED entry
- Derived keys never persisted

**Multi-key derivation:** `deriveKey()` can be called multiple times from
`AUTHORIZED` or `SESSION_ACTIVE` state with different domain strings. Each
call returns a fresh key for that domain. Useful if one consumer needs
multiple keys (e.g., encryption key + signing key).

---

## Security Properties to Preserve

✅ PIN never leaves card
✅ Key only exported after PIN verified
✅ BIP32 derivation on-card
✅ Domain separation on host — no firmware changes needed per consumer
✅ No persistent key storage — card required every time
✅ Card UID verified on reinsertion during active session
✅ libpcsclite must NOT be bundled — use system library (Lesson #36)

---

## Q_INVOKABLE Methods

All methods return JSON strings — never raw values (Lesson #2).
`initLogos` must NOT use override keyword — called reflectively (Lesson #19).

```cpp
// Discovery
QString discoverReader()          → {"found": bool, "name": string}
QString discoverCard()            → {"found": bool, "uid": string}

// Authentication & Key Derivation
QString authorize(pin)            → {"authorized": bool, "remainingAttempts": N}
                                     returns error if state == BLOCKED
QString deriveKey(domain)         → {"key": hex_string}
                                     prereq: AUTHORIZED or SESSION_ACTIVE
                                     returns error if state != AUTHORIZED
                                     can be called multiple times for different domains
                                     version: 1=production (default), 2=experimental (incomplete)

// State Management
QString getState()                → {"state": "READER_NOT_FOUND"|
                                              "CARD_NOT_PRESENT"|
                                              "CARD_PRESENT"|
                                              "AUTHORIZED"|
                                              "SESSION_ACTIVE"|
                                              "SESSION_CLOSED"|
                                              "BLOCKED"}
QString closeSession()            → {"closed": true}
                                     wipes key via sodium_memzero
                                     does NOT release reader
                                     state → SESSION_CLOSED

// Diagnostics
QString getLastError()            → {"error": string}
                                     returns detailed PC/SC error codes
                                     useful for debugging (e.g., "SCardConnect: 0x8010000C")
```

**Transition guards:**
- `authorize()` called when state != CARD_PRESENT → error with helpful message:
  ```json
  {"error": "No card present. Call discoverCard() first.", "state": "CARD_NOT_PRESENT"}
  ```
- `deriveKey()` called when state < AUTHORIZED → error:
  ```json
  {"error": "Not authorized. Call authorize() first.", "state": "CARD_PRESENT"}
  ```

---

## Plugin Metadata

### IID Naming

```cpp
// Core module (keycard-core/src/plugin.h):
Q_PLUGIN_METADATA(IID "org.logos.KeycardModuleInterface" FILE "plugin_metadata.json")

// UI module uses pure-QML approach (no C++ plugin)
// QML calls core module directly via: logos.callModule("keycard", "method")
```

### Manifest Files

**modules/keycard/manifest.json** (core module):
```json
{
  "author": "Logos Keycard",
  "category": "security",
  "dependencies": [],
  "description": "Keycard smartcard authentication for Logos ecosystem",
  "icon": "",
  "main": {
    "linux-amd64": "keycard_plugin.so",
    "darwin-arm64": "keycard_plugin.dylib"
  },
  "manifestVersion": "0.1.0",
  "name": "keycard",
  "type": "core",
  "version": "1.0.0"
}
```

**Note:** Module name is `"keycard"` (not `"keycard-core"`). Directory can be `keycard-core/` for organization.

**plugins/keycard-ui/metadata.json** (UI plugin):
```json
{
  "name": "keycard-ui",
  "version": "1.0.0",
  "description": "Keycard debug UI and test harness",
  "author": "Logos Keycard",
  "type": "ui_qml",
  "pluginType": "qml",
  "main": "Main.qml",
  "dependencies": ["keycard"],
  "category": "security",
  "capabilities": [],
  "icon": ""
}
```

**src/plugin/plugin_metadata.json** (for Q_PLUGIN_METADATA):
```json
{
  "author": "Logos Keycard",
  "category": "security",
  "dependencies": [],
  "description": "Keycard smartcard authentication for Logos ecosystem",
  "main": "keycard_plugin",
  "name": "keycard",
  "type": "core",
  "version": "1.0.0"
}
```

**Key lesson (#10):** Empty `{}` metadata means the shell never registers the plugin. Must be fully populated and match manifest.json.

---

## Cleanup

- `SCardReleaseContext` called in destructor on module unload
- No explicit `disconnect()` method needed
- `closeSession()` wipes keys without releasing reader — reader stays acquired

---

## Debug UI (keycard-ui module)

**Purpose:** Test every Keycard primitive explicitly before hiding behind
product UX. This is the test harness and living documentation of the
state machine.

**UI model:** action → prerequisites → result

### Layout

**Top panel:** Current state indicator (always visible, updates live via `stateChanged` signal)

**Action rows** (one per method):

Each row contains:
1. Action name
2. Current prerequisites and whether met (green ✓ / red ✗)
3. Input fields (if needed)
4. Trigger button (disabled if prerequisites not met)
5. Result display (JSON response, color-coded success/error)

### Actions

| # | Action | Prerequisite | Input Fields | Button |
|---|--------|--------------|--------------|--------|
| 1 | Discover Reader | none | — | "Discover Reader" |
| 2 | Discover Card | READER_NOT_FOUND resolved | — | "Discover Card" |
| 3 | Authorize | CARD_PRESENT | PIN (TextField, echoMode: Password) | "Authorize" |
| 4 | Derive Key | AUTHORIZED or SESSION_ACTIVE | Domain (TextField, default: "logos-notes-encryption") | "Derive Key" |
| 5 | Get State | none | — | "Get State" |
| 6 | Get Last Error | none | — | "Get Last Error" |
| 7 | Close Session | SESSION_ACTIVE | — | "Close Session" |

**QML sandbox rules:**
- No `Logos.Theme` or `Logos.Controls` imports
- No `FileDialog`
- Hardcode palette colors
- All logic via C++ plugin, QML is thin UI only

---

## Repo Structure

```
logos-keycard/
├── CMakeLists.txt                     ← top-level, includes both modules
├── README.md
├── flake.nix                          ← Nix build configuration
├── scripts/
│   └── package-lgx.sh                 ← LGX packaging script
├── keycard-core/
│   ├── CMakeLists.txt
│   ├── src/
│   │   ├── plugin.h
│   │   ├── plugin.cpp
│   │   ├── keycard_manager.h         ← smartcard logic, state machine, poller
│   │   ├── keycard_manager.cpp
│   │   ├── secure_buffer.h           ← RAII key memory (port from logos-notes)
│   │   ├── secure_buffer.cpp
│   │   └── plugin_metadata.json
│   └── modules/
│       └── keycard/
│           └── manifest.json
└── keycard-ui/
    ├── CMakeLists.txt                ← installs QML + metadata (no C++ build)
    ├── qml/
    │   └── Main.qml                  ← debug panel (pure QML)
    └── plugins/
        └── keycard-ui/
            ├── manifest.json         ← module manifest
            └── metadata.json         ← UI plugin metadata
```

---

## CMake Notes

- Each module has its own `CMakeLists.txt` — independent build and install
- Top-level `CMakeLists.txt` includes both via `add_subdirectory()`
- Use `$ORIGIN` RPATH for bundled dependencies
- **libpcsclite:** link dynamically, do NOT bundle (Lesson #36)
- **libsodium:** link via `PkgConfig::sodium`
- **Install paths:**
  - Portable: `~/.local/share/Logos/LogosBasecamp/modules/keycard/`
  - Dev: `~/.local/share/Logos/LogosBasecampDev/modules/keycard/`
- **CMake install must clean stale backups** before installing (Lesson #33):
  ```cmake
  install(CODE "
      file(GLOB _old \"~/.local/share/Logos/LogosBasecampDev/modules/keycard.*\")
      foreach(_dir \${_old})
          file(REMOVE_RECURSE \"\${_dir}\")
      endforeach()
  ")
  ```

---

## Nix/LGX Packaging

**flake.nix structure:**
```nix
{
  outputs = { nixpkgs, logos-cpp-sdk, ... }: {
    packages.x86_64-linux = {
      keycard-core = ...;  # Core module library
      keycard-ui = ...;    # UI plugin
    };

    apps.x86_64-linux.package-lgx = {
      type = "app";
      program = "${pkgs.writeShellScript "package-lgx" ''
        ${builtins.readFile ./scripts/package-lgx.sh}
      ''}";
    };
  };
}
```

**Packaging command:**
```bash
nix run .#package-lgx
# Produces: keycard-core.lgx, keycard-ui.lgx
```

**Integration with logos-module-builder (Lesson #20):** Consider migration after initial version works.

---

## Process Management

**Kill command:**
```bash
pkill -9 -f "logos_host.elf"  # NOT pkill -9 logos_host
```

**Reason:** AppImage wraps processes via ld-linux (Lesson #31)

---

## Source Material

**Port from logos-notes:**
- `src/core/KeycardBridge.{h,cpp}` → keycard_manager.{h,cpp}
- `src/core/SecureBuffer.h` → secure_buffer.{h,cpp}
- PC/SC initialization, authorize flow, exportKey flow
- sodium_memzero usage patterns

**Do not rewrite from scratch** — extract and adapt proven code.

---

## Definition of Done

### Phase 1: Scaffolding
1. ✅ Repo created with structure above
2. ✅ Empty CMakeLists.txt builds both modules
3. ✅ Empty manifests and metadata.json present
4. ✅ `cmake --install` installs to Basecamp dev path
5. ✅ Basecamp loads both modules without errors (even if they do nothing)

### Phase 2: Core Module
6. ✅ State machine implemented with all transitions
7. ✅ All Q_INVOKABLE methods return correct JSON
8. ✅ Card presence polling works (500ms)
9. ✅ `stateChanged` signal emits on every transition
10. ✅ Card UID verification on reinsertion works
11. ✅ 3 failed PIN attempts → BLOCKED state
12. ✅ `authorize()` returns error when state == BLOCKED
13. ✅ `deriveKey()` with different domains produces different keys from same card
14. ✅ Card removal during SESSION_ACTIVE → SESSION_CLOSED (key wiped)
15. ✅ SecureBuffer and sodium_memzero verified working

### Phase 3: Debug UI
16. ✅ All 7 action rows render with correct prerequisite gating
17. ✅ State indicator updates live via `stateChanged` signal
18. ✅ Full flow via debug UI:
    - discover reader → discover card → authorize → derive key → close session
19. ✅ Card removal during CARD_PRESENT → CARD_NOT_PRESENT (UI reflects change)
20. ✅ Card reinsertion from SESSION_CLOSED → CARD_PRESENT (not BLOCKED)
21. ✅ Derive key with multiple domains in same session works

### Phase 4: Packaging
22. ✅ LGX packages build via `nix run .#package-lgx`
23. ✅ LGX packages install correctly to Basecamp
24. ✅ libpcsclite NOT bundled (verified with `tar -tzf keycard-core.lgx`)

---

## Security Review Checklist (Post-Implementation)

- [ ] PIN never leaves card
- [ ] secp256k1 key only exported after PIN verified
- [ ] secp256k1 key wiped immediately after domain separation
- [ ] AES master key wiped on SESSION_CLOSED
- [ ] Card UID mismatch during active session → SESSION_CLOSED + error
- [ ] No key material logged or exposed in error messages
- [ ] SecureBuffer destructor fires correctly
- [ ] sodium_memzero verified with memory inspection
- [ ] Different domains produce different keys (test with 2+ domains)
- [ ] Same domain + same card produces same key across sessions

---

## Notes

- This module is **security-critical** — all key handling must be audited
- Debug UI is **not** for production — it's a test harness
- Production UIs (like notes) will hide the state machine behind UX
- The core module should remain **minimal** — no business logic, just smartcard primitives

## Pure-QML UI Approach (Phase 1-3)

The `keycard-ui` plugin uses a **pure-QML approach** with no C++ scaffolding. This is simpler and sufficient for the debug UI requirements.

**How it works:**
- QML calls core module directly: `logos.callModule("keycard", "getState", [])`
- Core module returns JSON strings
- QML parses and displays results
- No C++ types need to be exposed to QML

**When C++ UI plugin would be needed:**
- Complex data models (QAbstractListModel, custom QObject types)
- Real-time event pushing from core to UI
- Heavy computation in UI layer
- Direct manipulation of core module's C++ objects

For Phases 1-3, none of these apply. The pure-QML approach is maintained.

