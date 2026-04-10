# Lessons — keycard-basecamp

All numbered lessons and issue/phase completion lessons. Original numbering preserved.

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

## Phase X: keycard-qt Migration Lessons (Issue #10)

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

---

## Phase 5: Nix Flake and LGX Packaging Lessons (Issue #5)

### Lesson: Nix sandbox blocks FetchContent git clones
Pass keycard-qt via `-DKEYCARD_QT_SOURCE_DIR=${keycard-qt-src}` CMake flag instead. CMake checks this variable before falling back to FetchContent git.

### Lesson: Relative paths become invalid in subshells
`$OUTPUT_DIR` as relative path becomes invalid after `cd $TEMP_DIR` in subshell. Convert to absolute path before subshell: `OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)`.

### Lesson: Both metadata.json and manifest.json required
Bundler needs metadata.json (with `"main": "keycard_plugin"` — no extension), runtime needs manifest.json. Must provide both.

---

## Phase 2 Completion Lessons (Issue #2)

### Lesson: API contract mismatches can hide in JSON key names
JSON keys in responses must match SPEC.md exactly. Caught in Round 1 review.

### Lesson: Session overlay must clear on card removal
If session state doesn't reset when card is removed, the security model breaks — an attacker could remove the authorized card and the system would still report SESSION_ACTIVE. Caught in Round 3 review.

### Lesson: Dead code should be removed before review
Unreferenced source files (e.g., keycard_manager.cpp that never compiled) signal incomplete cleanup.

---

## Phase 3 Debug UI Lessons (Issue #3)

### Lesson: Signals don't return values — use function properties
QML signals can't return values. Use `property var executeFunc: function() { return logos.callModule(...) }` pattern for action rows that need return values.

### Lesson: State-based prerequisites beat flag-based
Single source of truth (`root.currentState` from polling) is more reliable than maintaining local flags (`readerFound`, `cardFound`). Prerequisites check state machine, not local flags.

### Lesson: Polling vs signals trade-off
500ms Timer polling `getState()` is simpler than signal wiring. Acceptable for test harness (not production UI). Trade-off: 500ms latency vs complexity.

---

## Issue #29: Production UI Lessons

### Lesson: Signal-based parent communication for Loader contexts
Dynamically loaded components can't directly access parent properties. Declare signals in loaded component, connect in `Loader.onLoaded`.

### Lesson: Check if function actually does anything (stub function trap)
When UI interaction "doesn't work," check if the handler function actually does anything, not just whether the click event fires. `lockSession()` was just logging to console.

### Lesson: QML plugins need focus delay (100ms timer)
Focus chain not fully established when component first loads. 100ms Timer gives Qt time to complete initialization.

### Lesson: No QtGraphicalEffects in Basecamp sandbox
ColorOverlay causes blank screen. QtQuick.Shapes also unstable. Modify SVG source files directly. In sandboxed QML, prefer static assets over runtime effects.

### Lesson: Item clip for rounded edges when Shapes unavailable
Use `Item { clip: true }` wrapper with oversized Rectangle for one-sided rounded corners.

### Lesson: Visual-first PR scope
Separate UI polish from backend integration in PRs. Prevents scope confusion in review.

---

## Issue #42: Authorization Screen Lessons

### Lesson: Issue scope management — split before review
If PR is "UI first," the issue must say visual foundation only. Don't leave backend requirements in the same issue unless you want them to block LGTM. Create follow-up issues immediately when splitting (#48, #49, #50).

**Senty's rule:** "Do not leave backend requirements in same issue unless you want them to block LGTM."

### Lesson: Review thread tracking
Check where reviewer is commenting and respond in same thread. If review is in issue comments, respond there, not in PR comments. Senty didn't see PR comment when reviewing via issue thread.

### Lesson: Content width alignment matters
Subtitle and info box widths should match (both 345px). Small detail but improves visual cohesion.

### Lesson: Title size consistency across screens
When changing title size on one screen (20px -> 24px), update all screens to match.

---

## Issue #48: Request Binding Lessons

### Lesson: Visual testing when console logs unavailable
QML console.log messages may not appear in log files. Use visual confirmation: check UI displays correct data, verify interactions work as expected.

### Lesson: Request data architecture — parent owns lifecycle
Store request data in parent, pass to loaded component via `Loader.onLoaded`. Loaded component is stateless (receives data, emits results). QML Loader doesn't support constructor parameters.

### Lesson: Signal parameters should include request ID
Always include request/action ID in signals for backend operations: `signal approved(string authRequestId, string pin)`. Allows parent to correlate UI events with backend state.

### Lesson: Keyboard shortcuts for testing
Ctrl+Key shortcuts for triggering test scenarios are valuable. Accepted by reviewers if clearly marked as temporary developer scaffolding.

### Lesson: Clear scope prevents review friction
When scope is clear and implementation matches, reviews are fast (single-round LGTM).

---

## Issue #49: Backend API Integration Lessons

### Lesson: Hardware-dependent vs pure software operations
When integrating with hardware APIs, distinguish early:
- **Pure software:** Request state management (create, list, reject) — testable without hardware
- **Hardware-dependent:** PIN verification, key derivation — require physical device
- Don't treat "needs hardware" as a bug. Don't block PR on untestable hardware operations if software layer is sound.

### Lesson: Mock triggers must create real backend state
UI-only mock data won't work for backend API testing. Ctrl+A trigger must call `requestAuth()` first to create real backend request before showing authorization screen.

### Lesson: Don't assume debug APIs exist
`logos.showMessage()` may not exist. Fallback to visual UI changes (error text fields, color changes).

---

## Issue #41: ActivityLog UI Lessons

### Lesson: Read issue descriptions carefully before branching
Started on `issue-45-activity-log` branch thinking it was backend. Actually Issue #41 (UI). Had to cherry-pick to correct branch. Always check if issue is backend or UI.

### Lesson: Hidden TextEdit is standard QML clipboard pattern
No direct `Clipboard.setText()` in basic QML. Use hidden TextEdit: `clipboardHelper.text = text; clipboardHelper.selectAll(); clipboardHelper.copy()`.

### Lesson: Cherry-pick for branch corrections
`git cherry-pick <sha>` preserves commit content while allowing branch/message changes. Cleaner than merge or rebase for single-commit moves.

### Lesson: TextEdit vs Text for selectable content
`Text` is NOT selectable by default. Use `TextEdit { readOnly: true; selectByMouse: true }`.

### Lesson: Subtle interactive elements
Copy button: small (20x20), low opacity (0.5), tooltip with 500ms delay, simple geometric icon. Visual feedback: 200ms opacity flash confirms action.

---

## Epic #56 Lessons — Basecamp Upstream Compatibility

### Lesson: logos-module PluginInterface is identical to logos-liblogos
The `PluginInterface` in `module_lib/interface.h` (logos-module) is byte-for-byte identical to `core/interface.h` (logos-liblogos). Migration is just an include path change.

### Lesson: nix flake replace_all misses blocks with different indentation
`preConfigure` blocks with 10-space indent vs 12-space indent are treated as different strings. Always verify all blocks individually. Senty caught this when `nix build .#lib` failed while dev build passed.

### Lesson: verify both build surfaces — dev shell AND nix build
`nix develop --command cmake --build build` and `nix build .#lib` exercise different code paths. A change can pass one and fail the other. Always check both.

### Lesson: don't add speculative upstream schema fields
Only add manifest fields with confirmed upstream evidence. Senty found that `permissions` and `requiredLogosVersion` had no upstream code consuming them. Adding guessed fields creates schema drift.

### Lesson: CMake install paths should be relative to CMAKE_INSTALL_PREFIX
Hardcoding absolute install paths breaks `cmake --install --prefix`. Use relative paths (`modules/keycard`, `plugins/keycard-ui`).

---

## Epic #55 Lessons — Single-Screen Architecture

### Lesson: UI-first, then backend cleanup
When removing backend APIs that the UI calls, do the UI cutover first (stop calling old APIs), then remove backend code. Backend-first deletion creates broken intermediate builds.

### Lesson: replace_all on enum values is dangerous
Blindly replacing `SessionState::Locked` -> `SessionState::NoSession` broke guard conditions. Each replacement site needs individual review — some guards should be removed entirely, not just have the enum swapped.

### Lesson: QML field names must exactly match backend response keys
`getPendingAuths()` returns `{ pending: [...] }` with `authId` field. QML expected `{ requests: [...] }` with `id` field. Always verify backend response shape before writing QML consumers.

### Lesson: DesignTokens — don't reference undefined properties
Using `DesignTokens.surface` when it doesn't exist causes QML to default to white/transparent, breaking dark theme.

### Lesson: Basecamp loads plugins from LogosBasecamp/, not LogosApp/
Despite CLAUDE.md saying LogosApp/, Basecamp actually loads from `~/.local/share/Logos/LogosBasecamp/`. Check `ps aux | grep logos_host` to verify.

### Lesson: nix flake update can break pcsclite protocol compatibility
After `nix flake update`, nix pcsclite (2.3.0, protocol 4:5) may not match system pcscd (2.0.3, protocol 4:4). Symptoms: `SCardEstablishContext` fails silently, reader detection loops forever. Fix: patch RPATH to use system libpcsclite. Tracked in #67.

### Lesson: every GitHub comment needs a tmux-bridge ping
Un-pinged updates are invisible to the other agent. Rule: always ping Senty after posting.

### Lesson: always document lessons after merge
Should happen automatically as part of merge workflow. Not require a prompt from the user.

---

## Issue #70 Lessons — Auto-close Session

### Lesson: keep demo script and code in sync
Issue #70 was created during Epic #55 but only implemented when the demo script revealed the session wasn't actually closing. If a feature is described in user-facing copy, verify the code matches before release.

---

## Issue #43 Lessons — Encrypted Pairing Storage

### Lesson: migration must happen AFTER the operation it validates
Encrypting a legacy plaintext file with a user-provided PIN must wait until the card confirms the PIN is correct. Migrating before verification means a wrong PIN can encrypt the file under the wrong secret, bricking access.

### Lesson: every write path must be fail-closed on corruption
If `readFile()` returns empty on parse error, all consumers (probe, load, save, remove) must distinguish "file missing" from "file corrupted". Otherwise a corrupted file gets silently overwritten.

### Lesson: API signature changes must update ALL callers
When `pairCard(password)` became `pairCard(password, pin)`, the DebugPanel QML still called the old one-arg version. Always grep for all callers before committing an API change.

### Lesson: security reviews need multiple rounds — plan for it
Issue #43 took 3 review rounds. Each round caught real issues the previous fix introduced or missed. For security-critical code, expect iterative review.

---

## Epic #82 Lessons — Developer Integration Kit

### Lesson: internal API methods need full documentation too
Senty caught that listing internal methods as a name-purpose table without response shapes was incomplete. If the doc claims "complete reference," every method needs exact shapes.

### Lesson: new components must be in install lists
Adding a QML file to the repo without adding it to CMakeLists.txt and flake.nix means it doesn't ship. Always update install manifests when adding new files.

---

## Security Fixes Lessons (Issue #16, PR #20)

### Lesson: Conditional compilation for debug logging
Replace `debugLog()` with `KEYCARD_LOG()` macro gated by `KEYCARD_DEBUG`. No file logging to `/tmp` (file-based attack surface).

### Lesson: Sanitize UID logging — log metadata not values
Card UIDs are stable identifiers enabling user tracking. Log `uid.length()` not raw `uid`. Per SECURITY_REVIEW.md: "Unconditional UID logs are sensitive telemetry."

### Lesson: Security fixes often require multiple review rounds
Round 1 removed `/tmp` logging but missed 4 unconditional UID locations. Round 2 caught them all.
