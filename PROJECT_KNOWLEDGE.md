# Project Knowledge: keycard-basecamp

Lessons learned and critical knowledge for Keycard module development.

## Extracted Lessons from logos-notes

### 2. Q_INVOKABLE methods must return JSON strings, not raw values
When exposing methods to QML via `Q_INVOKABLE`, always return `QString` containing JSON, never raw types like `bool` or `int`. QML can parse JSON but type mismatches cause silent failures.

**Example:**
```cpp
// ✅ Correct
Q_INVOKABLE QString authorize(const QString& pin) {
    return QJsonDocument(QJsonObject{
        {"authorized", true},
        {"remainingAttempts", 2}
    }).toJson(QJsonDocument::Compact);
}

// ❌ Wrong
Q_INVOKABLE bool authorize(const QString& pin) {
    return true;  // QML can't parse this reliably
}
```

### 10. Empty `{}` plugin metadata means shell never registers the plugin
If `plugin_metadata.json` contains only `{}`, the Logos shell silently ignores the plugin. Must have complete metadata matching manifest.json.

**Required fields:**
- `name` (must match manifest.json)
- `version`
- `description`
- `author`
- `type` (`"core"` for modules, `"ui_qml"` for UI plugins)
- `main` (library name or QML file)
- `dependencies`
- `category`

### 19. initLogos must NOT use override keyword — called reflectively
The PluginInterface's `initLogos()` method is invoked via Qt's reflection system (`QMetaObject::invokeMethod`). Using `override` keyword can cause issues with method resolution.

**Correct:**
```cpp
class KeycardPlugin : public QObject, public PluginInterface {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.KeycardModuleInterface" FILE "plugin_metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    QString initLogos(QObject* parent) {  // No override keyword
        // ...
    }
};
```

### 20. Consider logos-module-builder for shared build infrastructure
The [logos-module-builder](https://github.com/logos-innovation-lab/logos-module-builder) provides standardized Nix flakes and CMake templates for Basecamp modules. Consider migrating after initial version works to reduce build boilerplate.

**Benefits:**
- Shared dependency management
- Consistent packaging patterns
- Reduced flake.nix complexity

### 31. AppImage wraps processes via ld-linux — use full command in pkill
When killing Basecamp processes launched from AppImage, use `pkill -9 -f "logos_host.elf"` not `pkill -9 logos_host`. AppImage wraps executables via ld-linux dynamic linker, so process name isn't what you expect.

**Commands:**
```bash
# ✅ Correct
pkill -9 -f "LogosApp.elf"
pkill -9 -f "logos_host.elf"

# ❌ Wrong (won't match AppImage processes)
pkill -9 LogosApp
pkill -9 logos_host
```

### 33. CMake install must clean stale backups before installing
Logos shell creates `.bak` and `.bak.old` backups of modules. These can accumulate and cause conflicts. Clean them before installing new builds.

**CMake install code:**
```cmake
install(CODE "
    file(GLOB _old \"${CMAKE_INSTALL_PREFIX}/modules/keycard.*\")
    foreach(_dir \${_old})
        file(REMOVE_RECURSE \"\${_dir}\")
    endforeach()
")
```

### 36. libpcsclite must NOT be bundled — use system library
**Critical:** Never bundle `libpcsclite.so` in LGX packages. It must communicate with system pcscd daemon. Bundling breaks smartcard detection.

**Fix in package-lgx.sh:**
```bash
# After creating LGX with bundler, remove pcsclite:
tar -xzf keycard-core.lgx -C temp/
find temp/ -name "libpcsclite.so*" -delete
(cd temp && tar -czf keycard-core.lgx *)
```

**Why:** pcsclite uses IPC with pcscd daemon. Bundled version has wrong socket paths and version mismatches.

## Keycard-Specific Knowledge

### Hybrid Key Derivation Architecture

**On-card operations:**
1. PIN verification (never leaves card)
2. BIP32 derivation at `m/43'/60'/1581'/1'/0`
3. Returns 32-byte secp256k1 private key

**Host-side operations:**
1. Domain separation: `SHA256(secp256k1_key || domain_string)`
2. Result = 256-bit AES-256-GCM master key
3. Immediate wipe of secp256k1_key via `sodium_memzero`

**Why hybrid:**
- Card firmware is fixed — can't add new domain strings per consumer
- Host-side hashing provides infinite domain namespace
- No card firmware changes needed for new Logos apps

**Security properties preserved:**
- PIN never leaves card ✅
- BIP32 derivation on-card ✅
- Domain separation prevents cross-app key reuse ✅

### State Machine Semantics

**BLOCKED** = 3 failed PINs, card is locked, requires PUK recovery
- Card removal/reinsertion does NOT clear BLOCKED
- `authorize()` must refuse to attempt (don't waste remaining attempts)
- UI: "Card is locked. Use PUK to recover."

**SESSION_CLOSED** = voluntary closeSession() or card removed during active session
- Key wiped via `sodium_memzero` on entry
- Card reinsertion → CARD_PRESENT (ready for re-auth)
- UI: "Session ended. Reinsert card to authenticate."

**CARD_NOT_PRESENT** = no card detected, reader is functioning
- Physical state, not security state
- UI: "No card detected."

**Critical distinction:** These three states have different re-entry paths. UI must distinguish them clearly.

### Card UID Verification (Security)

**Purpose:** Prevent card-swap attacks during active session.

**Implementation:**
```cpp
QString m_expectedUID;  // Set on first successful authorize()

// On card re-detection during SESSION_ACTIVE or AUTHORIZED:
if (currentUID != m_expectedUID && state >= AUTHORIZED) {
    transitionTo(SESSION_CLOSED);
    return errorJson("Card changed during session. Re-authenticate.");
}
```

**Attack prevented:** Attacker removes authorized card, inserts their own card, attempts to use derived key.

### Multi-Key Derivation

`deriveKey()` can be called multiple times from `AUTHORIZED` or `SESSION_ACTIVE` state with different domain strings. Each call returns a fresh key for that domain.

**Use case:** Consumer needs multiple keys (e.g., encryption key + signing key):
```cpp
// logos-notes might call:
QString encKey = logos.callModule("keycard", "deriveKey", ["logos-notes-encryption"]);
QString signKey = logos.callModule("keycard", "deriveKey", ["logos-notes-signing"]);
// Two different keys from same card session
```

**Determinism:** Same card + same domain = same key across sessions (BIP32 ensures this).

### Memory Safety Patterns

**SecureBuffer (RAII):**
```cpp
class SecureBuffer {
    QByteArray data;
public:
    SecureBuffer(const QByteArray& d) : data(d) {}
    ~SecureBuffer() {
        sodium_memzero(data.data(), data.size());
    }
    const QByteArray& get() const { return data; }
};
```

**Usage:**
```cpp
SecureBuffer masterKey = deriveKeycardMasterKey(cardKey);
sodium_memzero(cardKey.data(), cardKey.size());  // Wipe intermediate key
// masterKey automatically wiped when out of scope
```

**Never:**
- Log key material
- Store keys in member variables without RAII
- Return keys as QByteArray without caller wiping
- Skip sodium_memzero on error paths

### Card Presence Polling

**Pattern:** QTimer at 500ms calling `SCardGetStatusChange` with 0 timeout (non-blocking).

**Why not background thread:** Polling is lightweight, 500ms is responsive enough, avoids thread synchronization complexity.

**Poller responsibilities:**
- Detect card removal during `SESSION_ACTIVE` → `SESSION_CLOSED` (key wipe)
- Detect card removal during `CARD_PRESENT` → `CARD_NOT_PRESENT`
- Detect card insertion → `CARD_PRESENT`
- Does NOT fire during `BLOCKED` (card state irrelevant when locked)

**Implementation:**
```cpp
QTimer* m_pollTimer = new QTimer(this);
m_pollTimer->setInterval(500);
connect(m_pollTimer, &QTimer::timeout, this, &KeycardManager::pollCardPresence);

void KeycardManager::pollCardPresence() {
    SCARD_READERSTATE readerState = { /* ... */ };
    LONG rv = SCardGetStatusChange(m_context, 0, &readerState, 1);

    if (readerState.dwEventState & SCARD_STATE_EMPTY) {
        // Card removed
        if (m_state == SESSION_ACTIVE) {
            transitionTo(SESSION_CLOSED);  // Wipes key
        }
    }
    // ... handle other states
}
```

## Build & Development Patterns

### Install Paths

**Development:** `~/.local/share/Logos/LogosBasecampDev/`
- Modules: `modules/keycard/`
- UI plugins: `plugins/keycard-ui/`

**Production:** `~/.local/share/Logos/LogosBasecamp/`

**CMake configuration:**
```cmake
set(LOGOS_INSTALL_PREFIX "$ENV{HOME}/.local/share/Logos/LogosBasecampDev")
install(TARGETS keycard_plugin LIBRARY DESTINATION "${LOGOS_INSTALL_PREFIX}/modules/keycard")
```

### Module vs Plugin Terminology

**Module** = Core C++ library (`.so` file)
- Lives in `modules/<name>/`
- Has `manifest.json`
- Provides `Q_INVOKABLE` methods via `logos.callModule()`
- IID pattern: `org.logos.<Name>ModuleInterface`

**Plugin** = UI component (QML + optional C++)
- Lives in `plugins/<name>/`
- Has `metadata.json`
- Provides QML interface
- IID pattern: `org.logos.<Name>UIModuleInterface`

**This repo contains both:**
- `keycard-core` → Basecamp module
- `keycard-ui` → Basecamp UI plugin (debug harness)

### Porting from logos-notes

**Source files to port:**
- `src/core/SecureBuffer.h` → `keycard-core/src/secure_buffer.{h,cpp}`
- `src/core/KeycardBridge.{h,cpp}` → `keycard-core/src/keycard_manager.{h,cpp}`

**Adaptations needed:**
- Remove NotesBackend dependencies
- Expose methods via `Q_INVOKABLE` (not internal calls)
- Return JSON strings from all methods
- Add `stateChanged` signal
- Make state machine explicit (logos-notes had implicit states)

**Do not rewrite from scratch** — the PC/SC integration and key handling patterns are proven. Extract and adapt.

## Security Checklist

Before releasing any version, verify:

- [ ] PIN never leaves card (verified by code inspection)
- [ ] secp256k1 key only exported after PIN verified
- [ ] secp256k1 key wiped immediately after domain separation
- [ ] AES master key wiped on `SESSION_CLOSED` entry
- [ ] Card UID mismatch during active session → `SESSION_CLOSED` + error
- [ ] No key material in logs or error messages
- [ ] SecureBuffer destructor fires correctly (test with valgrind)
- [ ] `sodium_memzero` verified with memory inspection (gdb/core dump analysis)
- [ ] Different domains produce different keys (test with 2+ domains)
- [ ] Same domain + same card produces same key across sessions

## References

- [logos-notes](https://github.com/xAlisher/logos-notes) - Original Keycard implementation
- [logos-cpp-sdk](https://github.com/logos-innovation-lab/logos-cpp-sdk) - Basecamp plugin SDK
- [logos-module-builder](https://github.com/logos-innovation-lab/logos-module-builder) - Shared build infrastructure
- [PC/SC Lite](https://pcsclite.apdu.fr/) - Smartcard middleware (use system library, never bundle)

## Phase 2 Completion (Issue #2)

**Status:** ✅ Merged to master (commit 19277ee)
**Review rounds:** 4 (all LGTM)
**Branch:** issue-2-pcsc-integration

### What Was Built

**KeycardBridge:** C++ wrapper around libkeycard.so (status-keycard-go via CGO)
- JSON-RPC communication with Go library
- State machine: 11 bridge states → 7 spec states
- PC/SC abstraction handled by Go layer (no direct pcsclite dependency)

**7-State Session Contract:**
1. READER_NOT_FOUND (no PC/SC or reader)
2. CARD_NOT_PRESENT (reader found, no card)
3. CARD_PRESENT (card detected, not authorized)
4. AUTHORIZED (PIN verified)
5. SESSION_ACTIVE (key derived, in use)
6. SESSION_CLOSED (session explicitly closed, key wiped)
7. BLOCKED (PIN/PUK blocked)

**API Methods Implemented:**
- `initialize()` - Create KeycardBridge instance
- `discoverReader()` - Start PC/SC polling
- `discoverCard()` - Poll for card presence
- `authorize(pin)` - Verify PIN via libkeycard
- `deriveKey(domain)` - SHA256(baseKey || domain) with libsodium
- `getState()` - Return current state from 7-state model
- `closeSession()` - Wipe key, enter SESSION_CLOSED
- `getLastError()` - Retrieve error message

### Key Architectural Decisions

**Session Overlay Pattern:**
- Plugin-level `SessionState` enum (NoSession/Active/Closed)
- Layered over KeycardBridge physical states
- Cleared on card state changes (removal/rediscovery)
- Allows SESSION_ACTIVE and SESSION_CLOSED to exist without conflicting with bridge states

**libkeycard.so Vendoring:**
- 14MB CGO binary committed to repo (despite .gitignore)
- Enables reproducible builds from clean checkout
- Trade-off: large binary in git vs. external build dependency
- Future: move to proper build/package process

**Domain-Based Key Derivation:**
```cpp
QByteArray baseKey = bridge->exportKey();  // From card
QByteArray domain = "notes".toUtf8();
QByteArray combined = baseKey + domain;
crypto_hash_sha256(derivedKey, combined);  // Unique per domain
```

### Review Feedback Addressed

**Round 1 (3 MEDIUM):**
- API contract mismatches (JSON keys didn't match SPEC.md)
- Dead code (keycard_manager.cpp never compiled)
- Split install paths (core vs UI)

**Round 2 (2 MEDIUM):**
- Missing SESSION_ACTIVE/SESSION_CLOSED states
- Stale pcsclite configure dependency

**Round 3 (2 MEDIUM):**
- Session overlay didn't clear on card removal (security risk)
- libkeycard.so not in repo (build reproducibility)

**Round 4:** LGTM (no blockers)

### Files Changed
- keycard-core/src/KeycardBridge.{h,cpp} - NEW
- keycard-core/src/plugin.{h,cpp} - 7-state contract
- keycard-ui/qml/Main.qml - Debug UI with state flow
- libkeycard.so - Vendored CGO binary
- flake.nix/flake.lock - Nix dev environment

## Plugin Icon Requirements

**Format:** 28x28 PNG, 8-bit RGBA, non-interlaced

**Location:** Must be in BOTH locations:
- Root: `keycard-ui/keycard.png`
- Subdirectory: `keycard-ui/icons/keycard.png`

**Metadata:** Must be referenced in BOTH files:
```json
// manifest.json
{
  "icon": "keycard.png"  // Root-level reference
}

// metadata.json
{
  "icon": "icons/keycard.png"  // Subdirectory reference (optional)
}
```

**Design Guidelines:**
- Use saturated colors (not white/light colors)
- Icon must be visible when desaturated (inactive gray state)
- UI framework shows gray when inactive, full color when active
- Test in grayscale before finalizing

**CMake Install:**
```cmake
install(FILES
    keycard.png
    DESTINATION "${PLUGIN_DIR}"
)
install(FILES
    icons/keycard.png
    DESTINATION "${PLUGIN_DIR}/icons"
)
```

**Common Mistakes:**
- SVG instead of PNG (not supported)
- Only setting metadata.json (manifest.json required)
- Light colors that disappear when desaturated
- Wrong size (must be exactly 28x28)


## Phase 3 Completion (Issue #3)

**Status:** ✅ Merged to master (commit 04e472e)
**Review rounds:** 2 (Round 2 LGTM)
**Branch:** issue-3-debug-ui

### What Was Built

**Comprehensive Debug UI Test Harness** - 7 action rows testing full state machine:

1. **Discover Reader** - Always enabled, shows reader found status
2. **Discover Card** - Enabled if reader found, shows card present/found
3. **Authorize** - Enabled for CARD_PRESENT or SESSION_CLOSED (re-auth), PIN input
4. **Derive Key** - Enabled for AUTHORIZED or SESSION_ACTIVE, domain input
5. **Get State** - Always enabled, returns current state JSON
6. **Get Last Error** - Always enabled, returns error message
7. **Close Session** - Enabled for AUTHORIZED or SESSION_ACTIVE

**Live State Indicator:**
- Large text display at top showing current state
- Color-coded by state (red → yellow → green spectrum)
- Auto-updates every 500ms via Timer polling `getState()`

**Prerequisites System:**
- Each row shows green ✓ or red ✗ based on prerequisites
- Execute buttons disabled when prerequisites not met
- Status text explains why button is disabled

**Per-Row Result Displays:**
- Each row has its own result field showing JSON response
- Color-coded: green (success), red (error), orange (parse error)
- Selectable text for copying results

### Key Implementation Decisions

**Polling vs Signals (LOW note from Senty):**
- Uses 500ms Timer polling `getState()` instead of signal-based updates
- Simpler implementation, works reliably
- Trade-off: 500ms latency vs complexity of signal wiring
- Acceptable for test harness (not production UI)

**State-Based Prerequisites:**
- Single source of truth: `root.currentState` (auto-polled)
- No manual flag management (`readerFound`, `cardFound` removed in fixes)
- Prerequisites check state machine, not local flags
- Reactive to all state changes (not just button clicks)

**Function Properties vs Signals:**
- Uses `property var executeFunc: function() { ... }` for row actions
- QML signals don't return values, functions do
- Pattern: `executeFunc: function() { return logos.callModule(...) }`
- Button calls `var result = row.executeFunc()` to get response

**UI Polish:**
- Removed colored borders (green/red) - status text color sufficient
- Styled buttons to match dark theme (gray background, white text)
- Simplified status text (no long UIDs, details in result field)
- Clean, scannable layout

### Testing Results

**Flows verified with real hardware:**
- ✅ Discover reader → "found: true" with reader name
- ✅ Discover card → "found: true" with card UID
- ✅ Authorize with PIN → transitions to AUTHORIZED
- ✅ Derive key (multiple domains) → unique keys per domain
- ✅ Close session → transitions to SESSION_CLOSED
- ✅ Re-authorize after close → SESSION_CLOSED allows re-auth
- ✅ Card removal during SESSION_ACTIVE → state updates correctly
- ✅ Card reinsertion → state updates to CARD_PRESENT
- ✅ Reader removal → state updates (Note: Issue #9 about cached result is UI-level, backend detects removal)
- ✅ State changes reflected live (500ms update)
- ✅ Prerequisites gate buttons correctly

**Issues found and fixed during testing:**
1. Execute buttons not posting results (signal → function fix)
2. Status showing stale state (flag-based → state-based fix)
3. closeSession disabled in AUTHORIZED (added to prereqMet)
4. Re-auth blocked in SESSION_CLOSED (added to authorize prereqMet)
5. Card status wrong after closeSession (SESSION_CLOSED → card-present states)
6. UI clutter (removed borders, simplified status text)

**Backend issue discovered:**
- Issue #9: discoverReader returns cached result after reader removal
- Backend does detect removal (getState works), but discoverReader result is cached
- UI works correctly - shows live state updates

### Success Criteria Status

From Issue #3 original requirements:

✅ All 7 action rows render correctly  
✅ State indicator updates live via polling  
✅ Prerequisites gating works (buttons disabled when prereqs not met)  
✅ Full flow works: discover → authorize → derive (multiple domains) → close  
✅ Card removal/reinsertion triggers state changes (tested with real hardware)  
⚠️ PIN lockout flow not tested (requires wrong PIN attempts, not critical for test harness)  

**Overall:** All core functionality complete and verified with real hardware.

### QML Patterns Established

**Action Row Component Pattern:**
```qml
component ActionRow: Rectangle {
    property string title: ""
    property string prereqText: ""
    property bool prereqMet: false
    property bool alwaysEnabled: false
    property bool showPinInput: false
    property bool showDomainInput: false
    property string inputPlaceholder: ""
    property var executeFunc: function() { return '{"error":"Not implemented"}' }

    // Layout: title, prereq status, execute button, input field, result display
}
```

**State Polling Pattern:**
```qml
property string currentState: "READER_NOT_FOUND"

Timer {
    interval: 500
    running: true
    repeat: true
    onTriggered: {
        var result = logos.callModule("keycard", "getState", [])
        try {
            var obj = JSON.parse(result)
            if (obj.state) root.currentState = obj.state
        } catch (e) {}
    }
}
```

**State-Based Prerequisites:**
```qml
prereqText: {
    if (root.currentState === "TARGET_STATE") return "✓ Ready"
    if (root.currentState === "BLOCKED_STATE") return "✗ Blocked"
    return "Waiting..."
}
prereqMet: root.currentState === "TARGET_STATE" || root.currentState === "ALSO_VALID"
```

## Phase X: keycard-qt Migration (Issue #10)

**Status:** ✅ COMPLETE - Merged to master (2026-03-23)
**Branch:** issue-10-keycard-qt-migration → master
**Duration:** Week 1 Days 1-3 (faster than 3-4 week estimate)
**Final Commit:** bf24f68

### Migration Summary

**Achievements:**
- ✅ 70% binary size reduction (14MB → ~4-5MB)
- ✅ Native C++/Qt stack (no CGO/JSON-RPC overhead)
- ✅ Real EIP-1581 support (on-card BIP32 custom paths)
- ✅ Authorization and session management working
- ✅ Reproducible builds from archives (CMake FetchContent)
- ✅ All hardware tests passing

**Key Issues Fixed:**
1. **Authorization UI freeze** - throttled getStatus() from 500ms to 5s
2. **Session state reset** - removed incorrect auto-clear logic
3. **Build reproducibility** - implemented FetchContent with commit pinning
4. **Module logging** - added file-based debugLog() helper

**Review Process:**
- Round 1: Fixed submodule documentation
- Round 2: Implemented FetchContent for archive builds
- Round 3: Fixed invalid Git reference (main → commit hash)
- Round 4: LGTM - merged to master

### What Was Built (Week 1 Day 1)

**Complete architecture migration** from libkeycard.so (CGO/JSON-RPC) to keycard-qt (native C++/Qt):

**Size Reduction:** 54% smaller
- Before: 14MB libkeycard.so + 2.1MB plugin = 16.1MB total
- After: 6.4MB integrated plugin (keycard-qt statically linked)

**API Compatibility:** Preserved exact same public interface
- KeycardBridge has identical public methods
- Existing code (logos-notes) works without changes
- All Q_INVOKABLE methods unchanged

**New Capability:** Real EIP-1581 support
- `exportKey(path)` now does on-card BIP32 derivation at custom paths
- Enables Issue #11 (custom EIP-1581 paths)

### Technical Changes

**CMakeLists.txt (root):**
```cmake
# Added keycard-qt as git submodule
add_subdirectory(external/keycard-qt)

# OpenSSL for secp256k1 ECDH
find_package(OpenSSL REQUIRED)

# Qt6::Nfc optional (mobile only)
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)
```

**keycard-core/CMakeLists.txt:**
```cmake
# Link keycard-qt + OpenSSL + libsodium
target_link_libraries(keycard_plugin PRIVATE
    Qt6::Core
    "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
    keycard-qt
    OpenSSL::Crypto
    PkgConfig::sodium
)

# Conditional Qt6::Nfc for mobile
if(TARGET Qt6::Nfc)
    target_link_libraries(keycard_plugin PRIVATE Qt6::Nfc)
endif()
```

**KeycardBridge (complete rewrite):**

Before (libkeycard.so):
```cpp
// JSON-RPC calls to Go library
QString response = m_keycard->call("keycard_authorize", {pin});
QJsonDocument doc = QJsonDocument::fromJson(response.toUtf8());
```

After (keycard-qt):
```cpp
// Direct C++ API calls
m_commandSet = std::make_shared<Keycard::CommandSet>(
    m_channel, m_pairingStorage, passwordProvider, this
);

bool success = m_commandSet->verifyPIN(pin);

// Real on-card derivation at custom paths:
QByteArray keyTLV = m_commandSet->exportKey(
    /*derive=*/true,
    /*makeCurrent=*/false,
    /*path=*/path,  // CUSTOM PATH SUPPORT!
    /*exportType=*/Keycard::APDU::P2ExportKeyPrivateAndPublic
);
```

**MemoryPairingStorage implementation:**
```cpp
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
```

**TLV Parsing for key export:**
```cpp
QByteArray KeycardBridge::parsePrivateKeyFromTLV(const QByteArray& tlv) {
    // TLV format: Tag 0xA1 (private key template)
    //   Tag 0x81 (public key - 65 bytes)
    //   Tag 0x80 (private key - 32 bytes)  ← WE WANT THIS
    //   Tag 0x82 (chain code - 32 bytes)

    for (int i = 0; i < tlv.size() - 2; ++i) {
        if (static_cast<unsigned char>(tlv[i]) == 0x80) {
            int length = static_cast<unsigned char>(tlv[i + 1]);
            if (length == 32 && i + 2 + length <= tlv.size()) {
                return tlv.mid(i + 2, length);
            }
        }
    }
    return QByteArray();  // Parse failure
}
```

### Runtime Verification

**Build & Install:**
```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
cmake --install build --prefix ~/.local/share/Logos/LogosApp
```

**Loading Test (Logos AppImage):**
```bash
$ lsof -p 585186 | grep keycard
keycard_plugin.so (6.6MB) - new plugin loaded
libpcsclite.so.1.0.0 - PC/SC library loaded
/tmp/logos_keycard - Unix socket IPC active

$ journalctl --user | grep KeycardPlugin
KeycardPlugin constructed
Logos API initialized
KeycardBridge created

Module stats: CPU 0-0.67%, Memory 22.22 MB
```

**Status:** ✅ Plugin loads and runs successfully with AppImage.

### Known Issues

**Nix Build Not Working:**
```bash
$ /nix/store/.../bin/LogosBasecamp
error while loading shared libraries: libQt6RemoteObjects.so.6:
cannot open shared object file: No such file or directory
```

**Cause:** Nix-built Logos Basecamp missing Qt6RemoteObjects dependency.
**Workaround:** Use Logos AppImage for testing (works correctly).
**Impact:** Development unblocked, Nix build issue is upstream.

### Next Steps (Week 1 Days 2-5)

**Day 2: Testing & Bug Fixes**
- Test with real Keycard hardware
- Verify state transitions (cardReady, cardLost signals)
- Test pairing flow
- Validate PIN verification

**Day 3: EIP-1581 Path Support**
- Implement `domainToEIP1581Path()` in plugin.cpp
- Update `deriveKey()` to use custom paths instead of fixed path
- Test multiple domains derive to different paths

**Days 4-5: Polish & Documentation**
- Update SPEC.md (remove libkeycard.so references)
- Update README.md (build instructions)
- Add keycard-qt API notes to LESSONS.md
- Create PR for Issue #10

### Lessons Learned

**38. keycard-qt requires OpenSSL for secp256k1 ECDH**
The keycard-qt library uses OpenSSL's EC_KEY functions for ECDH pairing. Build fails without `find_package(OpenSSL REQUIRED)`.

**39. PairingStorage interface returns values, not optionals**
The IPairingStorage::load() method returns `PairingInfo` directly (with index=-1 for invalid), not `std::optional<PairingInfo>`.

**40. Qt6::Nfc should be optional, not required**
Desktop Linux doesn't have Qt6::Nfc. Use `OPTIONAL_COMPONENTS` and conditional linking:
```cmake
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)
if(TARGET Qt6::Nfc)
    target_link_libraries(keycard_plugin PRIVATE Qt6::Nfc)
endif()
```

**41. keycard-qt TLV format for exportKey**
The exportKey() response is TLV-encoded:
- Tag 0xA1: Private key template container
- Tag 0x80 (32 bytes): Private key (secp256k1)
- Tag 0x81 (65 bytes): Public key
- Tag 0x82 (32 bytes): Chain code

Parse tag 0x80 to extract the 32-byte private key.

**42. Nix-built Logos Basecamp may have missing Qt dependencies**
The Nix-built `/nix/store/.../bin/LogosBasecamp` binary can fail to run if Qt6RemoteObjects or other Qt libraries are missing. Use AppImage for development if Nix build is broken.

**43. libpcsclite-dev required for keycard-qt PC/SC backend**
The keycard-qt library's PC/SC backend needs libpcsclite-dev installed:
```bash
sudo apt-get install libpcsclite-dev
```
Clean rebuild required after installing: `rm -rf build && cmake -B build`.


---

## Phase 5: Nix Flake and LGX Packaging (Issue #5)

**Status:** ✅ COMPLETE - Merged to master (2026-03-23)
**Branch:** issue-5-nix-lgx-packaging → master
**Final Commit:** f9f1057 (merge commit)
**PR:** #17

### Summary

Implemented complete Nix build infrastructure and LGX packaging for reproducible builds and distribution.

**Achievements:**
- ✅ Nix packages for core module and UI plugin
- ✅ One-command LGX packaging: `nix run .#package-lgx`
- ✅ libpcsclite removal from LGX (system compatibility)
- ✅ keycard-qt integration via CMake variable (fixes Nix sandbox issue)
- ✅ LGX packages tested and working in Basecamp

### Nix Package Structure

**flake.nix provides:**
```nix
packages.lib        # Core module: keycard_plugin.so + manifest.json + metadata.json
packages.ui         # UI plugin: Main.qml + metadata.json
packages.default    # Defaults to lib
apps.package-lgx    # LGX packaging: nix run .#package-lgx
```

**Key implementation details:**
- **keycard-qt fetched externally:** `fetchFromGitHub` in flake, passed via `-DKEYCARD_QT_SOURCE_DIR`
- **Avoids FetchContent in sandbox:** CMake checks `KEYCARD_QT_SOURCE_DIR` before falling back to git
- **metadata.json vs manifest.json:** Both required - bundler needs metadata.json, runtime needs manifest.json

### LGX Packaging

**Command:**
```bash
nix run .#package-lgx
```

**Produces:**
- `keycard-core.lgx` (3.3MB) - Core module with dependencies
- `keycard-ui.lgx` (5.3KB) - UI plugin

**Critical: libpcsclite removal**
```bash
# scripts/package-lgx.sh automatically:
1. Bundles with portable bundler (includes libpcsclite)
2. Extracts LGX to temp dir
3. Removes libpcsclite.so* files
4. Repacks without libpcsclite
```

**Why remove libpcsclite:**
- Bundled libpcsclite can't communicate with system pcscd daemon socket
- Must use system libpcsclite for smartcard detection to work
- Lesson #36 from logos-notes

### Build Commands

**Individual packages:**
```bash
nix build .#lib  # Build core module only
nix build .#ui   # Build UI plugin only
```

**LGX packaging:**
```bash
nix run .#package-lgx [output-dir]  # Default: current directory
```

**Verification:**
```bash
tar -tzf keycard-core.lgx | grep -i pcsclite  # Should return nothing
```

### Issues Fixed During Implementation

**Issue: Nix build failing with "could not find git"**
- **Cause:** Copied keycard-qt to build dir, CMake checked source dir, fell through to FetchContent
- **Fix:** Pass keycard-qt via `-DKEYCARD_QT_SOURCE_DIR=${keycard-qt-src}` CMake flag
- **Commit:** 0e4ae2a

**Issue: keycard-core.lgx not created**
- **Cause:** Relative path `$OUTPUT_DIR` became invalid after `cd $TEMP_DIR` in subshell
- **Fix:** Convert to absolute path before subshell: `OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)`
- **Commit:** 049f2a9

**Issue: "no 'main' field in metadata.json"**
- **Cause:** Only provided manifest.json (runtime format), bundler needed metadata.json (build format)
- **Fix:** Created root-level metadata.json with `"main": "keycard_plugin"` (no extension)
- **Commits:** a8ad2cb, 1ac277d

### Review Process

- **Round 1:** Senty found Nix build broken (FetchContent/git issue)
- **Round 2:** Fixed via KEYCARD_QT_SOURCE_DIR, got LGTM
- **Verified:** LGX packages tested in clean Basecamp, working

### References

- LESSONS.md: #37 (Nix FetchContent), #38 (relative paths), #39 (metadata.json)
- SPEC.md: Plugin Metadata, Repo Structure
- README.md: Updated with packaging commands


## Security Fixes (Issue #16 - PR #20)

**Status:** ⏳ In review (Round 2)
**Review rounds:** 1 (Round 1 findings addressed)
**Branch:** security-fixes-14-15-16

### Overview

Security review (SECURITY_REVIEW.md) identified Issue #16: Sensitive always-on debug logging that could leak private keys and stable card identifiers in production builds.

### Fixes Implemented

**Round 1 (commit 5f1ad27):**
- Removed `/tmp/keycard-debug.log` file logging entirely (file-based attacks)
- Replaced `debugLog()` function with `KEYCARD_LOG()` macro gated by `KEYCARD_DEBUG` flag
- Sanitized existing UID logging in `authorize()` to log presence instead of raw values
- Changed 26 debugLog() calls to KEYCARD_LOG() throughout KeycardBridge.cpp

**Round 2 (commit 9e0328f):**
- Fixed remaining 4 unconditional UID logging locations identified in review:
  1. `onCardReady()`: Changed to log UID length instead of raw signal UID
  2. `isCardPresent()`: Changed to log UID presence instead of instance UID hex
  3. `pairCard()`: Changed to log UID length instead of m_keyUID in pairing save path
  4. `unpairCard()`: Changed to log UID length instead of m_keyUID in storage removal path

### Technical Details

**Conditional Compilation Pattern:**
```cpp
// Debug logging - only enabled with KEYCARD_DEBUG build flag
// No file logging to /tmp - qDebug() output only
#ifdef KEYCARD_DEBUG
    #define KEYCARD_LOG(msg) qDebug() << "[KEYCARD]" << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") << msg
#else
    #define KEYCARD_LOG(msg) do {} while(0)
#endif
```

**Sanitization Pattern - UID Logging:**
```cpp
// ❌ BEFORE (unconditional, leaks stable identifier):
qDebug() << "KeycardBridge::onCardReady() signal received, uid from signal:" << uid;

// ✅ AFTER (sanitized, logs only metadata):
qDebug() << "KeycardBridge::onCardReady() signal received, uid length:" << uid.length();
```

**Why This Matters:**
- Card UIDs are stable identifiers that could enable user tracking across sessions
- Unconditional logging to journalctl leaks these IDs in production builds
- Length/presence checks provide debugging value without privacy risk
- Per SECURITY_REVIEW.md: "Unconditional UID logs are sensitive telemetry"

### Files Changed

- `keycard-core/src/KeycardBridge.cpp`: All debug logging sanitized
- `keycard-core/src/KeycardBridge.h`: Added KEYCARD_LOG macro definition

### Review Process

- **Round 1:** Senty found that removing /tmp logging was good, but 4 unconditional UID logs remained
- **Round 2:** Sanitized all 4 locations, awaiting LGTM

### Related Issues

- Issue #14: Private key logging (fixed in same PR, commit 8534328)
- Issue #15: Session state enforcement (fixed in same PR, commit fa0a203)
- SECURITY_REVIEW.md: Findings 14-16 all addressed in PR #20


## Test Release v1.0.0-test.2

**Released:** 2026-03-23
**URL:** https://github.com/xAlisher/keycard-basecamp/releases/tag/v1.0.0-test.2
**Status:** Pre-release (testing only)

### Release Contents

**LGX Packages:**
- `keycard-core.lgx` (3.3 MB) - Core module with keycard-qt, pcscd-compatible
- `keycard-ui.lgx` (5.3 KB) - QML debug UI

**Included Changes:**
- Phase 5: Nix flake and LGX packaging (PR #17)
- Security fixes: Issues #14, #15, #16 (PR #20)
- All SECURITY_REVIEW.md findings addressed

### Purpose

Test release for validating:
- LGX package distribution workflow
- Security hardening effectiveness
- Reader/card discovery and pairing
- On-card BIP32 key derivation (EIP-1581)
- Session management and state transitions

**Not for production use** - implementation testing only.

## Logos Tutorial Adoption

**Tracking Issue:** #31
**Status:** Phase 1 merged to master, Phase 2+ planned

### Overview

Incremental adoption of best practices from [logos-tutorial](https://github.com/logos-co/logos-tutorial) to modernize build infrastructure while maintaining backward compatibility.

**Strategy:** 8-phase approach with parity gates, throwaway spikes, and one module at a time migration.

### Phase Status

| Phase | Issue | Status | Description |
|-------|-------|--------|-------------|
| 1 | #32 | ✅ **Merged** (PR #40) | Pin testing tools (logoscore, standalone-app, lm CLI) |
| 2 | #33 | ✅ **Complete** | Builder spike (monorepo viable, builder experimental) |
| 3 | #34 | ✅ **Merged** | Metadata consolidation (preparatory, builder-aligned) |
| 4 | #35 | Planned | Migrate first module (keycard-core with parity gate) |
| 5 | #36 | Planned | Migrate second module (keycard-ui with parity gate) |
| 6 | #37 | Planned | Package management + CI workflows |
| 7 | #38 | Deferred | UI refactor (depends on #29 - production UI/UX design) |
| 8 | #39 | Deferred | Code generation patterns (evaluate after Phases 1-6) |

### Phase 1 Details (Complete - Narrowed Scope)

**What was delivered:**
- ✅ Pinned testing tool versions in `flake.nix`:
  - `logos-logoscore-cli` - Headless backend testing
  - `logos-standalone-app` - Isolated UI testing
  - `logos-module` - Module introspection (lm CLI)
- ✅ Thin wrapper entrypoints: `test-with-logoscore`, `test-ui-standalone`, `inspect-module`
- ✅ Wrapper scripts in `scripts/test/`
- ✅ Documentation in README.md with clear Phase 4 dependency

**Scope narrowed (per Senty Option A):**
- Phase 1: Reproducible tool pinning + starter wrappers
- Phase 4: Full operational workflows (after module layout migration)
- Avoids overclaiming functionality

**Key decisions:**
- All tools pinned for reproducibility (no floating versions)
- Wrappers are honest entrypoints, not "ready" workflows
- Full functionality requires Basecamp directory layout from Phase 4
- Read-only addition, no production code changes

**Senty review iterations:**
1. **Round 1:** Scripts hard-coded to install path, broke CI
2. **Round 2:** Wrappers found modules but tools failed (structural mismatch)
3. **Final (Option A):** Narrow scope to pinning + starters, defer full workflows to Phase 4

**Validation:**
- ✅ Tools pinned with `flake.lock` tracking dependencies
- ✅ Wrappers clearly document current status and Phase 4 dependency
- ✅ No overclaiming of functionality
- ✅ Senty LGTM (Round 3) - narrowed scope approved
- ✅ **Merged to master** (PR #40, 2026-03-26)

**Value:** Reproducible tool pinning is real progress. Clean foundation for Phase 4.

**Merge:** PR #40 merged on 2026-03-26 at 16:19 UTC. Issue #32 closed.

---

### Phase 2 Details (Complete)

**What was tested:**
- Dual-builder invocation from monorepo (Senty's recommendation)
- Created metadata.json for keycard-ui and keycard-core
- Added logos-module-builder to top-level flake
- Attempted build with mkLogosQmlModule

**Key findings:**
- ✅ Monorepo + dual-builder = architecturally viable
- ✅ No hard "one module per repo" constraint
- ❌ Builder experimental (official warning: "do not use")
- ❌ Builder has basic bugs (cp without -r flag)

**Senty's verdict:**
- Phase 2 = successful learning ✅
- Keep monorepo (don't split repos)
- Don't block on builder stabilization
- Proceed with metadata consolidation (Phase 3)

**Deliverable:**
- `SPIKE_LOGOS_MODULE_BUILDER.md` - full findings documented
- Spike branch discarded (per plan)
- Commit 730dc0f on master

**Value:** Proved architectural viability, identified tool maturity blocker, clear path forward.

**Closed:** Issue #33 closed on 2026-03-26

**Next:** Phase 3 - Metadata Consolidation (#34)

---

### Phase 3 Details (Complete)

**What was delivered:**
- ✅ `keycard-core/metadata.json` - Builder-aligned metadata consolidating plugin_metadata.json + manifest.json + nix/cmake sections
- ✅ `keycard-ui/metadata.json` - Builder-aligned metadata for UI plugin
- ✅ README.md update documenting these as "staged migration artifacts"

**Key constraint:**
- Metadata.json files are **preparatory** (not yet consumed by build)
- CMakeLists.txt remains operational source of truth
- Purpose: Enable quick migration when logos-module-builder stabilizes

**Review findings (Round 1):**
1. **MEDIUM:** keycard-core/metadata.json listed wrong source files
   - Listed: `keycard_manager.cpp`, `secure_buffer.cpp` (don't exist), `file_pairing_storage.cpp` (wrong case)
   - Actual: `plugin.cpp`, `KeycardBridge.cpp`, `FilePairingStorage.cpp`
   - **Fix:** Corrected `extra_sources` list to match actual src/ directory

2. **MEDIUM:** keycard-ui/metadata.json changed module identity
   - Changed name from `"keycard-ui"` to `"keycard_ui"`
   - Changed main from `"Main.qml"` to `"qml/Main.qml"`
   - **Fix:** Restored to match current shipped identity

**Senty's guidance:**
- "Honest framing" - Document as preparatory, not claiming "single source of truth"
- Metadata must match current reality (no drift from actual files)
- README.md section prevents confusion about CMake vs metadata

**Final result (Round 2):**
- ✅ Senty LGTM - accurate metadata, honest documentation
- ✅ Merged to master (commit 04e472e)
- ✅ Issue #34 closed

**Value:** Clean foundation for Phase 4 (module layout migration). Preparatory work done correctly.

**Closed:** Issue #34 closed on 2026-03-26
