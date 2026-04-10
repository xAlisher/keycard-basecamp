# Architecture — keycard-basecamp

## Hybrid Key Derivation Architecture

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
- PIN never leaves card
- BIP32 derivation on-card
- Domain separation prevents cross-app key reuse

---

## State Machine Semantics

### 7-State Session Contract

1. **READER_NOT_FOUND** — no PC/SC or reader
2. **CARD_NOT_PRESENT** — reader found, no card (physical state, not security state)
3. **CARD_PRESENT** — card detected, not authorized
4. **AUTHORIZED** — PIN verified
5. **SESSION_ACTIVE** — key derived, in use
6. **SESSION_CLOSED** — session explicitly closed or card removed during active session; key wiped via `sodium_memzero` on entry; card reinsertion -> CARD_PRESENT
7. **BLOCKED** — 3 failed PINs, card locked, requires PUK recovery; card removal/reinsertion does NOT clear BLOCKED; `authorize()` must refuse

**Critical distinction:** BLOCKED, SESSION_CLOSED, and CARD_NOT_PRESENT have different re-entry paths. UI must distinguish them clearly.

### Session Overlay Pattern
- Plugin-level `SessionState` enum (NoSession/Active/Closed)
- Layered over KeycardBridge physical states
- Cleared on card state changes (removal/rediscovery)
- Allows SESSION_ACTIVE and SESSION_CLOSED to exist without conflicting with bridge states

---

## EIP-1581 BIP32 Paths

`exportKey(path)` does on-card BIP32 derivation at custom paths. Domain-based key derivation:

```cpp
QByteArray baseKey = bridge->exportKey();  // From card
QByteArray domain = "notes".toUtf8();
QByteArray combined = baseKey + domain;
crypto_hash_sha256(derivedKey, combined);  // Unique per domain
```

### Multi-Key Derivation
`deriveKey()` can be called multiple times from `AUTHORIZED` or `SESSION_ACTIVE` with different domain strings. Each call returns a fresh key for that domain.

```cpp
// logos-notes might call:
QString encKey = logos.callModule("keycard", "deriveKey", ["logos-notes-encryption"]);
QString signKey = logos.callModule("keycard", "deriveKey", ["logos-notes-signing"]);
// Two different keys from same card session
```

**Determinism:** Same card + same domain = same key across sessions (BIP32 ensures this).

---

## PC/SC Integration

### keycard-qt Native Stack
Complete architecture migration from libkeycard.so (CGO/JSON-RPC) to keycard-qt (native C++/Qt):
- 54% binary size reduction (14MB CGO -> ~6.4MB integrated)
- Direct C++ API calls instead of JSON-RPC
- Real EIP-1581 support (on-card BIP32 custom paths)

```cpp
// Direct C++ API calls
m_commandSet = std::make_shared<Keycard::CommandSet>(
    m_channel, m_pairingStorage, passwordProvider, this
);
bool success = m_commandSet->verifyPIN(pin);

// Real on-card derivation at custom paths:
QByteArray keyTLV = m_commandSet->exportKey(
    /*derive=*/true, /*makeCurrent=*/false,
    /*path=*/path, /*exportType=*/Keycard::APDU::P2ExportKeyPrivateAndPublic
);
```

### TLV Parsing for Key Export
```cpp
QByteArray KeycardBridge::parsePrivateKeyFromTLV(const QByteArray& tlv) {
    // TLV format: Tag 0xA1 (private key template)
    //   Tag 0x81 (public key - 65 bytes)
    //   Tag 0x80 (private key - 32 bytes)  <- WE WANT THIS
    //   Tag 0x82 (chain code - 32 bytes)
    for (int i = 0; i < tlv.size() - 2; ++i) {
        if (static_cast<unsigned char>(tlv[i]) == 0x80) {
            int length = static_cast<unsigned char>(tlv[i + 1]);
            if (length == 32 && i + 2 + length <= tlv.size()) {
                return tlv.mid(i + 2, length);
            }
        }
    }
    return QByteArray();
}
```

### Card Presence Polling
**Pattern:** QTimer at 500ms calling `SCardGetStatusChange` with 0 timeout (non-blocking).

**Why not background thread:** Polling is lightweight, 500ms is responsive enough, avoids thread synchronization complexity.

**Poller responsibilities:**
- Detect card removal during `SESSION_ACTIVE` -> `SESSION_CLOSED` (key wipe)
- Detect card removal during `CARD_PRESENT` -> `CARD_NOT_PRESENT`
- Detect card insertion -> `CARD_PRESENT`
- Does NOT fire during `BLOCKED` (card state irrelevant when locked)

```cpp
QTimer* m_pollTimer = new QTimer(this);
m_pollTimer->setInterval(500);
connect(m_pollTimer, &QTimer::timeout, this, &KeycardManager::pollCardPresence);

void KeycardManager::pollCardPresence() {
    SCARD_READERSTATE readerState = { /* ... */ };
    LONG rv = SCardGetStatusChange(m_context, 0, &readerState, 1);
    if (readerState.dwEventState & SCARD_STATE_EMPTY) {
        if (m_state == SESSION_ACTIVE) {
            transitionTo(SESSION_CLOSED);  // Wipes key
        }
    }
}
```

### Card UID Verification (Security)
**Purpose:** Prevent card-swap attacks during active session.

```cpp
QString m_expectedUID;  // Set on first successful authorize()

// On card re-detection during SESSION_ACTIVE or AUTHORIZED:
if (currentUID != m_expectedUID && state >= AUTHORIZED) {
    transitionTo(SESSION_CLOSED);
    return errorJson("Card changed during session. Re-authenticate.");
}
```

### MemoryPairingStorage
```cpp
class MemoryPairingStorage : public Keycard::IPairingStorage {
public:
    bool save(const QString& instanceUID, const Keycard::PairingInfo& pairing) override {
        m_pairings[instanceUID] = pairing;
        return true;
    }
    Keycard::PairingInfo load(const QString& instanceUID) override {
        auto it = m_pairings.find(instanceUID);
        if (it != m_pairings.end()) return it->second;
        return Keycard::PairingInfo();  // Invalid pairing (index=-1)
    }
    bool remove(const QString& instanceUID) override {
        return m_pairings.erase(instanceUID) > 0;
    }
private:
    std::map<QString, Keycard::PairingInfo> m_pairings;
};
```

---

## SecureBuffer RAII

```cpp
class SecureBuffer {
    QByteArray data;
public:
    SecureBuffer(const QByteArray& d) : data(d) {}
    ~SecureBuffer() { sodium_memzero(data.data(), data.size()); }
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

---

## Plugin Interface Contract

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
- `keycard-core` -> Basecamp module
- `keycard-ui` -> Basecamp UI plugin (debug harness)

### API Methods
- `initialize()` — Create KeycardBridge instance
- `discoverReader()` — Start PC/SC polling
- `discoverCard()` — Poll for card presence
- `authorize(pin)` — Verify PIN via libkeycard
- `deriveKey(domain)` — SHA256(baseKey || domain) with libsodium
- `getState()` — Return current state from 7-state model
- `closeSession()` — Wipe key, enter SESSION_CLOSED
- `getLastError()` — Retrieve error message
- `requestAuth(domain, module)` — Create authorization request
- `authorizeRequest(authId, pin)` — Hardware-dependent: verify PIN + derive key
- `rejectRequest(authId)` — Software-only: update request state

### Hardware vs Software Operations
**Pure software:** Request state management (create, list, reject) — can test without hardware.
**Hardware-dependent:** PIN verification, key derivation, card pairing — require physical device.

---

## Build Patterns

### Install Paths
**Development:** `~/.local/share/Logos/LogosBasecampDev/`
**Production:** `~/.local/share/Logos/LogosBasecamp/`
- Modules: `modules/keycard/`
- UI plugins: `plugins/keycard-ui/`

CMake install paths should be relative to `CMAKE_INSTALL_PREFIX` (not hardcoded absolute).

### CMake Configuration
```cmake
set(LOGOS_INSTALL_PREFIX "$ENV{HOME}/.local/share/Logos/LogosBasecampDev")
install(TARGETS keycard_plugin LIBRARY DESTINATION "${LOGOS_INSTALL_PREFIX}/modules/keycard")
```

### keycard-qt Build Integration
```cmake
# OpenSSL for secp256k1 ECDH
find_package(OpenSSL REQUIRED)
# Qt6::Nfc optional (mobile only)
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)
# Link keycard-qt + OpenSSL + libsodium
target_link_libraries(keycard_plugin PRIVATE
    Qt6::Core "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
    keycard-qt OpenSSL::Crypto PkgConfig::sodium
)
if(TARGET Qt6::Nfc)
    target_link_libraries(keycard_plugin PRIVATE Qt6::Nfc)
endif()
```

### Nix Build: keycard-qt Source Dir
Nix sandbox blocks FetchContent git clones. Pass keycard-qt via `-DKEYCARD_QT_SOURCE_DIR=${keycard-qt-src}` CMake flag.

### Porting from logos-notes
**Source files to port:**
- `src/core/SecureBuffer.h` -> `keycard-core/src/secure_buffer.{h,cpp}`
- `src/core/KeycardBridge.{h,cpp}` -> `keycard-core/src/keycard_manager.{h,cpp}`

**Adaptations:** Remove NotesBackend dependencies, expose via Q_INVOKABLE, return JSON strings, add stateChanged signal, make state machine explicit.

**Do not rewrite from scratch** — PC/SC integration and key handling patterns are proven.

---

## QML Patterns

### Action Row Component Pattern
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
}
```

### State Polling Pattern
```qml
property string currentState: "READER_NOT_FOUND"
Timer {
    interval: 500; running: true; repeat: true
    onTriggered: {
        var result = logos.callModule("keycard", "getState", [])
        try { var obj = JSON.parse(result); if (obj.state) root.currentState = obj.state } catch (e) {}
    }
}
```

### State-Based Prerequisites
```qml
prereqText: {
    if (root.currentState === "TARGET_STATE") return "Ready"
    if (root.currentState === "BLOCKED_STATE") return "Blocked"
    return "Waiting..."
}
prereqMet: root.currentState === "TARGET_STATE" || root.currentState === "ALSO_VALID"
```

### Signal-Based Communication in Loader Contexts
```qml
// Loaded component (ManagementDashboard.qml)
Rectangle {
    signal lockRequested()
    function lockSession() { lockRequested() }
}
// Parent (Main.qml)
Loader {
    onLoaded: {
        if (item && item.lockRequested) {
            item.lockRequested.connect(function() { root.lockSession() })
        }
    }
}
```

### Request Data Architecture
Store request data in parent, pass to dynamically loaded component via `Loader.onLoaded`:
```qml
property var currentAuthRequest: null
function showAuthorizationRequest(id, module, domain, path) {
    currentAuthRequest = { id: id, moduleName: module, domain: domain, path: path }
    mode = "authorization"
}
Loader {
    onLoaded: {
        if (item && item.authRequestId !== undefined && root.currentAuthRequest) {
            item.authRequestId = root.currentAuthRequest.id
            item.moduleName = root.currentAuthRequest.moduleName
            // ...
        }
    }
}
```

### Timer-Based Auto-Focus
QML plugins need slight delay for focus chain:
```qml
Timer {
    id: focusTimer; interval: 100; running: true; repeat: false
    onTriggered: { root.forceActiveFocus(); hiddenInput.forceActiveFocus() }
}
```

### Clipboard via Hidden TextEdit
```qml
TextEdit { id: clipboardHelper; visible: false }
function copyAllToClipboard() {
    clipboardHelper.text = allLogsText
    clipboardHelper.selectAll()
    clipboardHelper.copy()
}
```

### Disabled Button with Visual Feedback
```qml
Rectangle {
    opacity: root.pinValue.length === root.maxPinLength ? 1.0 : 0.5
    MouseArea {
        enabled: root.pinValue.length === root.maxPinLength
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
```

### Visual Effects Without QtGraphicalEffects
Modify SVG source files directly (set `stroke="#ffffff"`) instead of using ColorOverlay. In sandboxed QML environment, prefer static assets over runtime effects. QtQuick.Shapes also unstable in Basecamp.

### Item Clip for Rounded Edges
```qml
Item {
    width: 8; clip: true
    Rectangle { width: 16; color: DesignTokens.warning; radius: 8 }
}
```

### Reusable ActivityLog Component
```qml
ActivityLog {
    id: activityLog
    Layout.fillWidth: true; Layout.preferredHeight: 167
    Component.onCompleted: { addEntry("[09:12:03]", "card reader detected", "success") }
}
```
Public API: `addEntry(timestamp, message, level)`, `clear()`, `model` alias. 100-entry memory limit.

### Selectable Text
Use `TextEdit { readOnly: true; selectByMouse: true }` instead of `Text` for selectable content.

---

## Plugin Icon Requirements

**Format:** 28x28 PNG, 8-bit RGBA, non-interlaced

**Location:** Must be in BOTH:
- Root: `keycard-ui/keycard.png`
- Subdirectory: `keycard-ui/icons/keycard.png`

**Metadata:** Referenced in BOTH `manifest.json` (`"icon": "keycard.png"`) and `metadata.json` (`"icon": "icons/keycard.png"`).

**Design:** Use saturated colors (not white/light). Test in grayscale. UI shows gray when inactive.

**Common Mistakes:** SVG (not supported), only metadata.json (manifest.json required), light colors, wrong size.

---

## Security Checklist

Before releasing any version, verify:

- [ ] PIN never leaves card (verified by code inspection)
- [ ] secp256k1 key only exported after PIN verified
- [ ] secp256k1 key wiped immediately after domain separation
- [ ] AES master key wiped on `SESSION_CLOSED` entry
- [ ] Card UID mismatch during active session -> `SESSION_CLOSED` + error
- [ ] No key material in logs or error messages
- [ ] SecureBuffer destructor fires correctly (test with valgrind)
- [ ] `sodium_memzero` verified with memory inspection (gdb/core dump analysis)
- [ ] Different domains produce different keys (test with 2+ domains)
- [ ] Same domain + same card produces same key across sessions

### Conditional Debug Logging
```cpp
#ifdef KEYCARD_DEBUG
    #define KEYCARD_LOG(msg) qDebug() << "[KEYCARD]" << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") << msg
#else
    #define KEYCARD_LOG(msg) do {} while(0)
#endif
```

### UID Sanitization Pattern
```cpp
// WRONG: qDebug() << "uid:" << uid;
// RIGHT: qDebug() << "uid length:" << uid.length();
```
Card UIDs are stable identifiers that could enable user tracking. Log only metadata (length/presence), not raw values.

### Authorization Security Boundary
Backend must derive keys internally. Never accept keys as parameters from UI/modules:
```cpp
// WRONG: completeAuthRequest(authId, key) - UI can inject arbitrary keys
// RIGHT: completeAuthRequest(authId) - backend derives from hardware when session active
```
