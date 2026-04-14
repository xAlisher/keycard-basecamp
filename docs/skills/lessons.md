# Lessons — keycard-basecamp

All numbered lessons and issue/phase completion lessons. Original numbering preserved.

---

## Issue #107 — Dev Card Setup (2026-04-14)

### gp.jar only tries the GP default key — always pass Keycard dev key explicitly
`gp.jar` defaults to `404142...` only. `keycard-cli` tries two keys in sequence: `KeycardDevelopmentKey` (`c212e073ff8b4bbfaff4de8ab655221f`) first, then GP default. Our dev card uses the Keycard dev key. If `gp.jar` returns "Card cryptogram invalid!" with default key, try `--key c212e073ff8b4bbfaff4de8ab655221f` before declaring keys lost.

### gp.jar --install fails on multi-applet CAP files — use --load then --install-only
`gp --install <capfile>` fails with "CAP contains more than one applet" when the package has multiple applets (Keycard, NDEF, Cash, Ident). Pattern: `--load` the package first, then `--install-only <appletAID> --pkg <pkgAID> --applet <appletAID> --create <instanceAID>` for each applet separately.

### Factory reset only clears Keycard applet state — ISD keys unchanged
Card factory reset (via Keycard Shell 3-wrong-PINs flow) resets PIN/PUK/keys/pairing but does NOT touch GlobalPlatform. ISD keys survive factory reset. You still need the correct ISD key to install a new applet after reset.

### LEE mode probe requires Keycard secure channel — raw APDU returns 6D00
The mode probe APDU (`80 C3 F0 00`) is not accessible outside the Keycard secure channel. Sending raw after SELECT returns SW=6D00. Probe must be wrapped in SC — see #96 `detectMode()`.

### keycard-cli v0.7.0 has no LEE/P2=0x01 support
`keycard-load-seed` in keycard-cli v0.7.0 has P2 hardcoded to 0x00. Loading a seed in LEE mode (P2=0x01) requires a patched CLI or raw APDU via the Keycard SC. The latest Linux binary is v0.7.0; v0.8.2 dropped Linux support.

---

## Extracted Lessons from logos-notes

### Lesson #2: Q_INVOKABLE methods must return JSON strings, not raw values
When exposing methods to QML via `Q_INVOKABLE`, always return `QString` containing JSON, never raw types like `bool` or `int`. QML can parse JSON but type mismatches cause silent failures.

```cpp
// CORRECT
Q_INVOKABLE QString authorize(const QString& pin) {
    return QJsonDocument(QJsonObject{
        {"authorized", true}, {"remainingAttempts", 2}
    }).toJson(QJsonDocument::Compact);
}
// WRONG
Q_INVOKABLE bool authorize(const QString& pin) { return true; }
```

### Lesson #10: Empty `{}` plugin metadata means shell never registers the plugin
If `plugin_metadata.json` contains only `{}`, the Logos shell silently ignores the plugin. Must have complete metadata matching manifest.json.

**Required fields:** `name`, `version`, `description`, `author`, `type` (`"core"` or `"ui_qml"`), `main`, `dependencies`, `category`.

### Lesson #19: initLogos must NOT use override keyword — called reflectively
The PluginInterface's `initLogos()` method is invoked via Qt's reflection system (`QMetaObject::invokeMethod`). Using `override` keyword can cause issues with method resolution.

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

### Lesson #20: Consider logos-module-builder for shared build infrastructure
The [logos-module-builder](https://github.com/logos-innovation-lab/logos-module-builder) provides standardized Nix flakes and CMake templates. Consider migrating after initial version works.
Benefits: shared dependency management, consistent packaging, reduced flake.nix complexity.
**Caveat:** Builder is experimental (official warning: "do not use"), has basic bugs (cp without -r flag). Don't block on stabilization.

### Lesson #31: AppImage wraps processes via ld-linux — use full command in pkill
```bash
# CORRECT
pkill -9 -f "LogosApp.elf"
pkill -9 -f "logos_host.elf"
# WRONG (won't match AppImage processes)
pkill -9 LogosApp
```

### Lesson #33: CMake install must clean stale backups before installing
Logos shell creates `.bak` and `.bak.old` backups. Clean them before installing:
```cmake
install(CODE "
    file(GLOB _old \"${CMAKE_INSTALL_PREFIX}/modules/keycard.*\")
    foreach(_dir \${_old})
        file(REMOVE_RECURSE \"\${_dir}\")
    endforeach()
")
```

### Lesson #36: libpcsclite must NOT be bundled — use system library
**Critical:** Never bundle `libpcsclite.so` in LGX packages. It must communicate with system pcscd daemon. Bundling breaks smartcard detection because bundled version has wrong socket paths and version mismatches.

```bash
# After creating LGX with bundler, remove pcsclite:
find temp/ -name "libpcsclite.so*" -delete
```

### Lesson #37: Authorization APIs must never accept external keys
Backend must derive keys internally. Never accept keys as parameters from UI or other modules. QML is an untrusted boundary. Session state ensures PIN was verified before key derivation. Violating this boundary breaks the entire security model.

Related: Issue #44 code review caught this flaw in original implementation.

---

## Issue #1 — Scaffolding

### SDK header path must match actual location
Used `#include <plugin_interface.h>` but actual Logos SDK header is `core/interface.h`. MOC failed with "Undefined interface" error. Always verify SDK header paths before writing includes — search actual SDK directory or cross-reference with working code (logos-notes).

### Hardcoded Nix paths required for initial build
CMake couldn't find Logos SDK with relative path `../logos-cpp-sdk`. Logos ecosystem uses Nix store paths (absolute, hash-prefixed). Copy SDK path resolution pattern from logos-notes: `if(DEFINED ENV{VAR}) ... else() set(VAR "/nix/store/...") endif()`.

### Verification scripts validate all install steps
Created `verify-install.sh` to automate checking file existence, symbols, JSON validity. Repeatable for every build. Add verification scripts for each phase.

### Plugin must have execute permission to load
`keycard_plugin.so` installed with `-rw-r--r--` (not executable) was silently ignored. Working modules have `-rwxr-xr-x`. After install, run `chmod +x` on the .so file.

### LogosApp vs LogosBasecamp directory confusion
CMake installed to LogosApp but app loaded from LogosBasecamp. Check which directory app is actually using: `ps aux | grep logos_host`. Match CMake install path to runtime path.

### Missing eventResponse signal prevented module loading
Plugin loaded but method calls failed. `QObject::connect: No such signal KeycardPlugin::eventResponse`. ModuleProxy expects this signal for event communication. Always check working plugin (NotesPlugin) for required signals:
```cpp
signals:
    void eventResponse(const QString& eventName, const QVariantList& data);
```

### Hiding base class logosAPI member broke method discovery
Declaring `private: LogosAPI* logosAPI = nullptr;` hid the base class PluginInterface's `public: LogosAPI* logosAPI` member. ModuleProxy checks base class member. Use base class's public members instead of redeclaring.

### UI plugin requires BOTH manifest.json AND metadata.json
Only creating metadata.json for UI plugin caused it not to appear. QML UI plugins need TWO JSON files: `manifest.json` (module manifest) and `metadata.json` (UI-specific metadata).

### Directory name must match plugin name exactly
Directory `keycard-ui` with metadata name `keycard_ui` caused Basecamp mismatch. Plugin directory name MUST exactly match the `name` field in metadata.

### Manifest platform keys — only include current platform
Having both `linux-amd64` and `darwin-arm64` in manifest's main dict prevented loading. Only include current platform: `{"main": {"linux-amd64": "plugin.so"}}`.

### Plugin icon format: PNG required, not SVG
SVG icons showed as text fallback. Working plugins all use PNG. Required: 28x28 PNG, 8-bit RGBA. Must be in both root and icons/ subdirectory.

### Plugin icons: manifest.json vs metadata.json
Icon set only in metadata.json didn't display. UI framework loads icons from manifest.json. BOTH manifest.json and metadata.json need icon fields populated.

### Icon design: must have contrast for inactive gray state
UI framework applies desaturation filter to inactive icons. Light/white icons become invisible when desaturated. Use colors with good saturation and contrast. Test how icon looks in grayscale.

---

## Issue #2 — Core Module

### PC/SC protocol version mismatch prevented direct integration
Plugin linked against Nix libpcsclite 2.3.0 (protocol 4:5) but system pcscd was 2.0.3 (protocol 4:4). No readers found despite hardware present. Solution: use libkeycard.so (status-keycard-go) via JSON-RPC instead of direct PC/SC. Same library used by Status desktop wallet.

### KeycardBridge is the proven pattern
Copied KeycardBridge from logos-notes. Uses libkeycard.so (Go library) via JSON-RPC. Works immediately — detects reader and card. Simpler code (RPC calls vs APDU commands).

### Bundled libpcsclite.so breaks PC/SC communication (repeated mistake)
Tried bundling system libpcsclite.so.1 in module directory — same mistake from logos-notes Lesson #36. Bundled library can't communicate with pcscd. Only libkeycard.so is OK to bundle, never libpcsclite.

### API contract mismatches can hide in JSON key names
JSON keys in responses must match SPEC.md exactly. Caught in Round 1 review.

### Session overlay must clear on card removal
If session state doesn't reset when card is removed, the security model breaks — an attacker could remove the authorized card and the system would still report SESSION_ACTIVE. Session states are logical overlays over physical states, not replacements:
```cpp
// In getState() — clear overlay if card gone
if (bridge_reports_card_gone && m_sessionState != NoSession) {
    m_sessionState = NoSession;
}
```

### Dead code should be removed before review
Unreferenced source files (e.g., keycard_manager.cpp that never compiled) signal incomplete cleanup.

### QML Text must be TextEdit for copy/paste
`Text` component is read-only and not selectable. Change to `TextEdit` with `selectByMouse: true`, `selectByKeyboard: true`, and `readOnly: true`.

### Module process logs not in main app log
`qDebug()` output from keycard module doesn't appear in `/tmp/logos-app.log`. Module runs in separate `logos_host.elf` process. Implemented file-based logging to `/tmp/keycard-debug.log`. Or check `journalctl --user` for module process output.

---

## Issue #3 — Debug UI

### QML signals don't return values — use function properties
Defined `signal execute()` but `var result = row.execute()` returns undefined. Signals are for notifications. Use `property var executeFunc: function() { return logos.callModule(...) }` when return value needed.

### State-based prerequisites beat flag-based
Maintaining separate `readerFound`, `cardFound` flags created synchronization issues. Use single source of truth: `root.currentState` from polling. State updates automatically from Timer, always current.

```qml
// WRONG - flag-based
property bool cardFound: false
prereqText: root.cardFound ? "check Card found" : "Not found"

// RIGHT - state-based
property string currentState: "READER_NOT_FOUND"  // Auto-updated by Timer
prereqText: (root.currentState === "CARD_PRESENT" || ...) ? "check Card found" : "Not found"
```

### Polling vs signals trade-off
500ms Timer polling `getState()` is simpler than signal wiring. Acceptable for test harness (not production UI). Trade-off: 500ms latency vs complexity.

### Prerequisites must account for all relevant states
`closeSession` only enabled for SESSION_ACTIVE but should also be enabled for AUTHORIZED. `authorize` only enabled for CARD_PRESENT but should also be enabled for SESSION_CLOSED. Check SPEC.md state machine diagram — for each action, list ALL valid source states.

### UI polish: less is more
Redundant visual indicators (colored borders duplicating status text color, long UID in status duplicating result field) add clutter. One indicator per piece of information. User approved after simplification.

---

## Issue #10 — keycard-qt Migration

### Lesson #38: keycard-qt requires OpenSSL for secp256k1 ECDH
The keycard-qt library uses OpenSSL's EC_KEY functions for ECDH pairing. Build fails without `find_package(OpenSSL REQUIRED)`.

### Lesson #39: PairingStorage interface returns values, not optionals
`IPairingStorage::load()` returns `PairingInfo` directly (with index=-1 for invalid), not `std::optional<PairingInfo>`.

### Lesson #40: Qt6::Nfc should be optional, not required
Desktop Linux doesn't have Qt6::Nfc. Use `OPTIONAL_COMPONENTS` and conditional linking:
```cmake
find_package(Qt6 OPTIONAL_COMPONENTS Nfc)
if(TARGET Qt6::Nfc)
    target_link_libraries(keycard_plugin PRIVATE Qt6::Nfc)
endif()
```

### Lesson #41: keycard-qt TLV format for exportKey
The exportKey() response is TLV-encoded:
- Tag 0xA1: Private key template container
- Tag 0x80 (32 bytes): Private key (secp256k1)
- Tag 0x81 (65 bytes): Public key
- Tag 0x82 (32 bytes): Chain code

Parse tag 0x80 to extract the 32-byte private key.

### Lesson #42: Nix-built Logos Basecamp may have missing Qt dependencies
The Nix-built binary can fail if Qt6RemoteObjects or other Qt libraries are missing. Use AppImage for development if Nix build is broken.

### Lesson #43: libpcsclite-dev required for keycard-qt PC/SC backend
```bash
sudo apt-get install libpcsclite-dev
```
Clean rebuild required after installing: `rm -rf build && cmake -B build`.

### UI freeze from blocking calls in event loop
`getStatus()` called every 500ms via QML timer blocked for ~600ms (PC/SC communication), freezing entire UI. Solution: throttle to once every 5 seconds with timestamp tracking:
```cpp
void pollStatus() {
    if (m_state == Authorized) {
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastStatusCheck < 5000) return;
        m_lastStatusCheck = now;
        m_commandSet->getStatus();
    }
}
```

### Session state reset by auto-detection logic
`closeSession()` set Closed state, but `discoverCard()` 500ms later auto-reset to NoSession (card still present = "rediscovery"). Session state is user intent, not hardware state. Only auto-clear session on card removal.

### deriveKey allowed after session closed
`deriveKey()` didn't check session state, allowing key derivation after explicit session close. Add state guard: `if (m_sessionState == Closed) return error(...)`.

### Git submodules don't work in archives
`git archive` (GitHub tarballs) doesn't include submodule contents. Use CMake FetchContent as fallback: check for local submodule first, download from GitHub if missing. Pin to commit hashes.

---

## Issue #23 — Modal Authorization Window

### Don't fix working infrastructure
Changed plugin name (`keycard-ui` to `keycard_ui`), switched install paths, used wrong AppImage while adding AuthWindow.qml feature. Plugin appeared twice, neither opened. Root cause: changed working master configuration while adding unrelated feature. **Key principle: when adding features, only modify what the feature needs.**

Red flags: "Let me fix the naming to match other plugins" (is current naming broken?), "The memory file says use LogosApp" (does master work?). Always test master branch first.

---

## Phase 5: Nix Flake and LGX Packaging (Issue #5)

### Nix sandbox blocks FetchContent git clones
Pass keycard-qt via `-DKEYCARD_QT_SOURCE_DIR=${keycard-qt-src}` CMake flag instead. CMake checks this variable before falling back to FetchContent git.

### Relative paths become invalid in subshells
`$OUTPUT_DIR` as relative path becomes invalid after `cd $TEMP_DIR` in subshell. Convert to absolute path before subshell: `OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)`.

### Both metadata.json and manifest.json required for LGX
Bundler needs metadata.json (with `"main": "keycard_plugin"` — no extension), runtime needs manifest.json. Must provide both.

```json
// metadata.json (for LGX bundler)
{"main": "keycard_plugin"}  // String, no extension

// manifest.json (for Basecamp runtime)
{"main": {"linux-amd64": "keycard_plugin.so"}}  // Dict with platforms
```

---

## Issue #29 — Production UI

### Signal-based parent communication for Loader contexts
Dynamically loaded components can't directly access parent properties. Declare signals in loaded component, connect in `Loader.onLoaded`.

### Check if function actually does anything (stub function trap)
When UI interaction "doesn't work," check if the handler function actually does anything, not just whether the click event fires. `lockSession()` was just logging to console.

### QML plugins need focus delay (100ms timer)
Focus chain not fully established when component first loads. 100ms Timer gives Qt time to complete initialization.

### No QtGraphicalEffects in Basecamp sandbox
ColorOverlay causes blank screen. QtQuick.Shapes also unstable. Modify SVG source files directly. In sandboxed QML, prefer static assets over runtime effects.

### Item clip for rounded edges when Shapes unavailable
Use `Item { clip: true }` wrapper with oversized Rectangle for one-sided rounded corners.

### Visual-first PR scope
Separate UI polish from backend integration in PRs. Prevents scope confusion in review.

---

## Issue #41 — ActivityLog UI

### Read issue descriptions carefully before branching
Started on `issue-45-activity-log` branch thinking it was backend. Actually Issue #41 (UI). Had to cherry-pick to correct branch. Always check if issue is backend or UI.

### Hidden TextEdit is standard QML clipboard pattern
No direct `Clipboard.setText()` in basic QML. Use hidden TextEdit: `clipboardHelper.text = text; clipboardHelper.selectAll(); clipboardHelper.copy()`.

### Cherry-pick for branch corrections
`git cherry-pick <sha>` preserves commit content while allowing branch/message changes. Cleaner than merge or rebase for single-commit moves.

### TextEdit vs Text for selectable content
`Text` is NOT selectable by default. Use `TextEdit { readOnly: true; selectByMouse: true }`.

### Subtle interactive elements
Copy button: small (20x20), low opacity (0.5), tooltip with 500ms delay, simple geometric icon. Visual feedback: 200ms opacity flash confirms action.

---

## Issue #42 — Authorization Screen

### Issue scope management — split before review
If PR is "UI first," the issue must say visual foundation only. Don't leave backend requirements in the same issue unless you want them to block LGTM. Create follow-up issues immediately when splitting.

**Senty's rule:** "Do not leave backend requirements in same issue unless you want them to block LGTM."

### Review thread tracking
Check where reviewer is commenting and respond in same thread. If review is in issue comments, respond there, not in PR comments. Senty didn't see PR comment when reviewing via issue thread.

### Content width alignment matters
Subtitle and info box widths should match (both 345px). Small detail but improves visual cohesion.

### Title size consistency across screens
When changing title size on one screen (20px -> 24px), update all screens to match.

---

## Issue #44 — Session Management + Core APIs

### Security boundaries must be enforced in backend, not UI
Initial `completeAuthRequest(authId, key)` accepted key parameter from QML. Senty caught this as critical security flaw. QML is untrusted boundary — malicious code could inject fake keys. Backend must derive keys internally when session is active:
```cpp
// CORRECT: Backend derives key internally
QString KeycardPlugin::completeAuthRequest(const QString& authId) {
    if (m_sessionState != SessionState::Active) return error("Session not active");
    QJsonObject keyResult = QJsonDocument::fromJson(deriveKey(domain).toUtf8()).object();
    targetRequest->key = keyResult.value("key").toString();
}
// WRONG: Accepts external key
QString KeycardPlugin::completeAuthRequest(const QString& authId, const QString& key) {
    targetRequest->key = key;  // DANGER: No verification
}
```

### UI state changes must call backend APIs to sync state
Lock button only changed UI mode to "pin" without calling backend `lockSession()`. Session state remained active, keys stayed in memory. UI state transitions should always call corresponding backend API. Search codebase for "TODO" before declaring complete.

### Public API contracts must use consistent naming
`getSessionInfo()` returned `"SESSION_LOCKED"` while `getState()` returned `"SESSION_CLOSED"` for same state. Define state constants in header, reference everywhere. Grep for state strings across all API implementations.

### ListView vs ScrollView for dynamic QML content
ScrollView + Repeater caused blank screen when width references broke. ListView is better: built-in scrolling/clipping, proper width management, only renders visible items. Use ListView for dynamic lists, ScrollView for static mixed-layout content.

### Activity log deduplication pattern
Pending requests logged multiple times across screens. Solution: `QSet<QString>` tracking request IDs. Each request logged exactly once, cleanup on completion, O(1) lookup.

### Polling timer pattern for backend state sync
1Hz Timer polling `getPendingAuths()` keeps UI in sync with backend. Works across module boundaries, handles race conditions. Acceptable for dashboard UIs, not ideal for mobile (battery).

### Activity log processing with _activity arrays
Backend injects `_activity` array into API responses via `addActivityToResponse()`. Frontend `processActivity()` helper extracts and displays. Activity tied to the response that caused it — no race conditions.

---

## Issue #48 — Request Binding

### Visual testing when console logs unavailable
QML console.log messages may not appear in log files. Use visual confirmation: check UI displays correct data, verify interactions work as expected.

### Request data architecture — parent owns lifecycle
Store request data in parent, pass to loaded component via `Loader.onLoaded`. Loaded component is stateless (receives data, emits results). QML Loader doesn't support constructor parameters.

### Signal parameters should include request ID
Always include request/action ID in signals for backend operations: `signal approved(string authRequestId, string pin)`. Allows parent to correlate UI events with backend state.

### Keyboard shortcuts for testing
Ctrl+Key shortcuts for triggering test scenarios are valuable. Accepted by reviewers if clearly marked as temporary developer scaffolding.

### Clear scope prevents review friction
When scope is clear and implementation matches, reviews are fast (single-round LGTM).

---

## Issue #49 — Backend API Integration

### Hardware-dependent vs pure software operations
Distinguish early: pure software (request state management) is testable without hardware; hardware-dependent (PIN verification, key derivation) requires physical device. Don't block PR on untestable hardware operations if software layer is sound.

### Mock triggers must create real backend state
UI-only mock data won't work for backend API testing. Ctrl+A trigger must call `requestAuth()` first to create real backend request before showing authorization screen.

### Don't assume debug APIs exist
`logos.showMessage()` may not exist. Fallback to visual UI changes (error text fields, color changes).

---

## Epic #55 — Single-Screen Architecture

### UI-first, then backend cleanup
When removing backend APIs that the UI calls, do the UI cutover first (stop calling old APIs), then remove backend code. Backend-first deletion creates broken intermediate builds.

### replace_all on enum values is dangerous
Blindly replacing `SessionState::Locked` -> `SessionState::NoSession` broke guard conditions. Each replacement site needs individual review — some guards should be removed entirely, not just have the enum swapped.

### QML field names must exactly match backend response keys
`getPendingAuths()` returns `{ pending: [...] }` with `authId` field. QML expected `{ requests: [...] }` with `id` field. Always verify backend response shape before writing QML consumers.

### DesignTokens — don't reference undefined properties
Using `DesignTokens.surface` when it doesn't exist causes QML to default to white/transparent, breaking dark theme.

### Basecamp loads plugins from LogosBasecamp/, not LogosApp/
Despite CLAUDE.md saying LogosApp/, Basecamp actually loads from `~/.local/share/Logos/LogosBasecamp/`. Check `ps aux | grep logos_host` to verify.

### nix flake update can break pcsclite protocol compatibility
After `nix flake update`, nix pcsclite (2.3.0, protocol 4:5) may not match system pcscd (2.0.3, protocol 4:4). `SCardEstablishContext` fails silently, reader detection loops forever. Fix: patch RPATH to use system libpcsclite. Tracked in #67.

### Every GitHub comment needs a tmux-bridge ping
Un-pinged updates are invisible to the other agent. Rule: always ping Senty after posting.

### Always document lessons after merge
Should happen automatically as part of merge workflow. Not require a prompt from the user.

---

## Epic #56 — Basecamp Upstream Compatibility

### logos-module PluginInterface is identical to logos-liblogos
The `PluginInterface` in `module_lib/interface.h` (logos-module) is byte-for-byte identical to `core/interface.h` (logos-liblogos). Migration is just an include path change.

### nix flake replace_all misses blocks with different indentation
`preConfigure` blocks with 10-space indent vs 12-space indent are treated as different strings. Always verify all blocks individually. Senty caught this when `nix build .#lib` failed while dev build passed.

### Verify both build surfaces — dev shell AND nix build
`nix develop --command cmake --build build` and `nix build .#lib` exercise different code paths. A change can pass one and fail the other. Always check both.

### Don't add speculative upstream schema fields
Only add manifest fields with confirmed upstream evidence. Senty found that `permissions` and `requiredLogosVersion` had no upstream code consuming them. Adding guessed fields creates schema drift.

### CMake install paths should be relative to CMAKE_INSTALL_PREFIX
Hardcoding absolute install paths breaks `cmake --install --prefix`. Use relative paths (`modules/keycard`, `plugins/keycard-ui`).

---

## Issue #70 — Auto-close Session

### Keep demo script and code in sync
Issue #70 was created during Epic #55 but only implemented when the demo script revealed the session wasn't actually closing. If a feature is described in user-facing copy, verify the code matches before release.

---

## Issue #43 — Encrypted Pairing Storage

### Migration must happen AFTER the operation it validates
Encrypting a legacy plaintext file with a user-provided PIN must wait until the card confirms the PIN is correct. Migrating before verification means a wrong PIN can encrypt the file under the wrong secret, bricking access.

### Every write path must be fail-closed on corruption
If `readFile()` returns empty on parse error, all consumers (probe, load, save, remove) must distinguish "file missing" from "file corrupted". Otherwise a corrupted file gets silently overwritten.

### API signature changes must update ALL callers
When `pairCard(password)` became `pairCard(password, pin)`, the DebugPanel QML still called the old one-arg version. Always grep for all callers before committing an API change.

### Security reviews need multiple rounds — plan for it
Issue #43 took 3 review rounds. Each round caught real issues the previous fix introduced or missed. For security-critical code, expect iterative review.

---

## Epic #82 — Developer Integration Kit

### Internal API methods need full documentation too
Senty caught that listing internal methods as a name-purpose table without response shapes was incomplete. If the doc claims "complete reference," every method needs exact shapes.

### New components must be in install lists
Adding a QML file to the repo without adding it to CMakeLists.txt and flake.nix means it doesn't ship. Always update install manifests when adding new files.

---

## Security Fixes (Issue #16, PR #20)

### Conditional compilation for debug logging
Replace `debugLog()` with `KEYCARD_LOG()` macro gated by `KEYCARD_DEBUG`. No file logging to `/tmp` (file-based attack surface).

### Sanitize UID logging — log metadata not values
Card UIDs are stable identifiers enabling user tracking. Log `uid.length()` not raw `uid`. Per SECURITY_REVIEW.md: "Unconditional UID logs are sensitive telemetry."

### Security fixes often require multiple review rounds
Round 1 removed `/tmp` logging but missed 4 unconditional UID locations. Round 2 caught them all.

---

## Issue #93 — JOURNEYS.md

### Docs-only PRs still need a code-audit pass before claiming security properties
Drafted `JOURNEYS.md` and merged without Senty review. Post-merge review found three substantive issues:
1. **Key-erasure claim stronger than reality** — `authorizeRequest()` stores derived key on `AuthRequest` struct, completed requests never purged, `closeSession()` doesn't zero stored keys. Filed as #94.
2. **`failed` terminal status doesn't exist** — code only returns `pending | complete | rejected`, but docs listed `failed`. Consumer following docs would wait forever.
3. **Product narrative ahead of shipped UI** — described unified approval panel but pairing and blocked-card recovery only in DebugPanel.qml.

**Rules derived:**
- For any doc describing security properties or API contracts, read the relevant source file first and cite line numbers in PR description.
- Cross-reference between docs is not code verification — both can be wrong the same way.
- "Docs-only" PRs describing security surface are not low-risk. Fast Senty review round before merge, every time.
- Flag identifiers pulled from local state (installed binaries, private repos) and verify from public sources.

---

## Issue #94 — Key Persistence Fix

### Nix RUNPATH overrides CMake INSTALL_RPATH
CMake's `INSTALL_RPATH "$ORIGIN"` is ignored when building inside `nix develop` — Nix's cc-wrapper injects `-rpath /nix/store/...` for every dependency at link time. For libraries that must match the system daemon version (like libpcsclite ↔ pcscd), this causes protocol mismatches at runtime. Fix: add a post-install `patchelf --set-rpath '$ORIGIN'` step in both CMakeLists.txt and package-lgx.sh. Diagnosis: `journalctl -u pcscd` shows "Communication protocol mismatch" with client/server version numbers.

### One-read-and-drop for derived key material
Security-sensitive keys should be returned exactly once via the polling API (`checkAuthStatus`), then immediately wiped from memory. Store keys in SecureBuffer (RAII + sodium_memzero), not QString. Convert to hex only at serialization time, wipe the hex intermediate, erase the request from the vector. This matches the "no persistent key storage" claim in docs.

## Planning Phase

### Communication protocol established
Agent identities (Fergie = implementer, Senty = reviewer), GitHub tagging, and explicit review handoff ("Ready for review, Senty!") reduce ambiguity and make history readable.
