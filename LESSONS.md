# Implementation Lessons

Lessons learned during building keycard-basecamp. Update this after corrections, bugs, or discoveries.

**Purpose:** Self-improvement loop. Prevent repeating mistakes. Document what went wrong and how to fix it.

---

## Planning Phase

### Communication Protocol Established
**Date:** 2026-03-22
**Context:** Initial repo setup

**What we learned:**
- Agent identities matter for team feel: Fergie (implementer) + Senty (reviewer)
- GitHub comments must be tagged: `Fergie:` and `Senty:`
- Handoffs should explicitly ask for review: "Ready for review, Senty!"

**Why it matters:** Clear communication protocol reduces ambiguity and makes GitHub history readable.

**Evidence:** [Commit f811eb6](https://github.com/xAlisher/keycard-basecamp/commit/f811eb6)

---

## Issue #1 - Scaffolding

### SDK Header Path Must Match Actual Location
**Date:** 2026-03-22
**Context:** Initial CMake build failed with "Undefined interface" MOC error

**What went wrong:**
- Used `#include <plugin_interface.h>` in plugin.h
- MOC failed with "Undefined interface" error
- Build stopped during AutoMOC phase

**Why it happened:**
- Assumed header was named `plugin_interface.h` based on interface name
- Actual Logos SDK header is `core/interface.h`
- Plan didn't verify exact header path before writing code

**How to prevent:**
- ALWAYS verify SDK header paths before writing includes
- Search actual SDK directory: `find /nix/store/*logos*headers* -name "*.h"`
- Cross-reference with working code (logos-notes)

**Evidence:** Build error at 17:08, fixed by changing include to `<core/interface.h>`

---

### Hardcoded Nix Paths Required for Initial Build
**Date:** 2026-03-22
**Context:** CMake couldn't find Logos SDK with default relative path

**What went wrong:**
- Initial CMakeLists.txt used `../logos-cpp-sdk` as fallback
- Path didn't exist, no environment variables set
- Would have failed at configure step

**Why it happened:**
- Plan assumed SDK would be at predictable relative path
- Logos ecosystem uses Nix store paths (absolute, hash-prefixed)
- Environment variables only set in Nix shell (not in regular shell)

**How to prevent:**
- Copy SDK path resolution pattern directly from logos-notes CMakeLists.txt
- Hardcode Nix store paths as fallback (env vars override for CI/Nix)
- Pattern: `if(DEFINED ENV{VAR}) ... else() set(VAR "/nix/store/...") endif()`

**Evidence:** `/home/alisher/keycard-basecamp/keycard-core/CMakeLists.txt:1-16`

---

### Verification Script Validates All Install Steps
**Date:** 2026-03-22
**Context:** After installation, needed to verify files and symbols

**What went right:**
- Created `verify-install.sh` to check all install requirements
- Automated checks: file existence, symbols, JSON validity
- Provides clear test instructions for next step

**Why it matters:**
- Manual checking is error-prone and tedious
- Script is repeatable for every build
- Documents expected state for Phase 1 completion

**How to repeat:**
- Add verification scripts for each phase
- Check both file presence AND content/symbols
- Output clear next steps for manual testing

**Evidence:** `/home/alisher/keycard-basecamp/scripts/verify-install.sh`

---

## Issue #2 - Core Module

### PC/SC Protocol Version Mismatch Prevented Direct Integration
**Date:** 2026-03-22
**Context:** Tried direct PC/SC implementation with libpcsclite, reader not detected

**What went wrong:**
- Plugin linked against Nix libpcsclite 2.3.0 (protocol 4:5)
- System pcscd daemon version 2.0.3 (protocol 4:4)
- pcscd logs showed: "Communication protocol mismatch!"
- No readers found despite ACR39U being present and working

**Why it happened:**
- Nix environment provides newer libpcsclite than system pcscd
- Protocol versions must match between client library and daemon
- Direct PC/SC implementation harder to maintain than proven Go library

**How to prevent:**
- Use libkeycard.so (status-keycard-go) instead of direct PC/SC
- Port KeycardBridge wrapper from logos-notes (proven working)
- Let Go library handle PC/SC compatibility issues
- Smaller codebase (wrapper vs full PC/SC implementation)

**Evidence:**
- pcscd logs at 20:22:11 showing protocol 4:5 vs 4:4 mismatch
- Switching to libkeycard.so fixed issue immediately
- `/home/alisher/keycard-basecamp/keycard-core/src/KeycardBridge.{h,cpp}`

---

### Plugin Must Have Execute Permission to Load
**Date:** 2026-03-22
**Context:** Module not appearing in app's module stats despite correct files

**What went wrong:**
- keycard_plugin.so installed with `-rw-r--r--` (not executable)
- Module not loaded by app (only capability_module and package_manager visible)
- No error messages, silently ignored

**Why it happened:**
- CMake install doesn't preserve executable permissions by default
- Working modules have `-rwxr-xr-x` permissions

**How to prevent:**
- After install, run: `chmod +x ~/.local/share/Logos/LogosBasecamp/modules/keycard/keycard_plugin.so`
- Check working module permissions and match them
- Verify with: `ls -la ~/.local/share/Logos/LogosBasecamp/modules/*/`

**Evidence:** Module appeared in stats after chmod +x

---

### LogosApp vs LogosBasecamp Directory Confusion
**Date:** 2026-03-22
**Context:** CMake installed to LogosApp but app loaded from LogosBasecamp

**What went wrong:**
- CMakeLists.txt set `LOGOS_APP_DATA` to LogosApp
- App actually ran from LogosBasecamp directory
- Had to manually copy files between directories

**Why it happened:**
- Earlier testing used regular mode (LogosApp)
- Current session app using dev mode data (LogosBasecamp)
- Install path hardcoded without checking app runtime path

**How to prevent:**
- Check which directory app is actually using: `ps aux | grep logos_host`
- Match CMake install path to runtime path
- For development: install to LogosBasecamp
- For production: install to LogosApp

**Evidence:** Changed CMakeLists.txt line 54 to use LogosBasecamp

---

### Bundled libpcsclite.so Breaks PC/SC Communication
**Date:** 2026-03-22
**Context:** Removed Nix libpcsclite, copied system version to module dir

**What went wrong:**
- Tried to bundle system libpcsclite.so.1 (2.0.3) in module directory
- This is the same mistake from logos-notes (Lesson #36)
- Bundled library can't communicate with pcscd properly

**Why it happened:**
- Thought bundling system version would fix protocol mismatch
- Forgot the lesson from logos-notes about not bundling libpcsclite

**How to prevent:**
- NEVER bundle libpcsclite.so in module packages
- Always use system libpcsclite dynamically
- Remember: libkeycard.so is OK to bundle, but not libpcsclite

**Evidence:** Removed libpcsclite.so.1 from module directory after realizing error

---

### KeycardBridge is the Proven Pattern
**Date:** 2026-03-22
**Context:** After protocol mismatch, switched from direct PC/SC to KeycardBridge

**What went right:**
- Copied KeycardBridge.{h,cpp} from logos-notes
- Uses libkeycard.so (Go library) via JSON-RPC
- Works immediately with no modifications
- Detects reader and card: `{"readerFound":true,"state":"READY"}`

**Why it matters:**
- libkeycard.so handles all PC/SC complexity
- Proven to work across different pcscd versions
- Simpler code (RPC calls vs APDU commands)
- Same library used by Status desktop wallet

**How to repeat:**
- Port KeycardBridge as thin wrapper over libkeycard.so
- Bundle libkeycard.so (14MB) with module
- Use KeycardBridge API: start(), authorize(), exportKey()
- Update plugin to call bridge methods instead of direct PC/SC

**Evidence:** Working integration showing READY state with actual hardware

---

### QML Text Must Be TextEdit for Copy/Paste
**Date:** 2026-03-22
**Context:** User couldn't copy JSON errors from debug UI

**What went wrong:**
- Used `Text` component for result display
- Text is read-only and not selectable

**How to fix:**
- Change `Text` to `TextEdit`
- Add `selectByMouse: true` and `selectByKeyboard: true`
- Keep `readOnly: true` to prevent editing
- User can now select and copy JSON results

**Evidence:** `/home/alisher/keycard-basecamp/keycard-ui/qml/Main.qml`

---

## Issue #3 - Debug UI

*Lessons will be added here during implementation*

---

## Issue #4 - Testing

*Lessons will be added here during implementation*

---

## Issue #5 - Packaging

*Lessons will be added here during implementation*

---

## Template for New Lessons

```markdown
### Lesson Title
**Date:** YYYY-MM-DD
**Context:** What you were doing

**What went wrong:**
- Specific error or mistake

**Why it happened:**
- Root cause

**How to prevent:**
- Rule or pattern to follow

**Evidence:** [Commit SHA / File:Line / Issue comment link]
```

---

### Missing eventResponse Signal Prevented Module Loading
**Date:** 2026-03-22
**Context:** Core module loaded but methods returned `false` from QML

**What went wrong:**
- Plugin loaded successfully but method calls failed
- Log showed: `QObject::connect: No such signal KeycardPlugin::eventResponse`
- ModuleProxy expects this signal for event communication

**Why it happened:**
- Copied basic PluginInterface but didn't check NotesPlugin for required signals
- eventResponse is mandatory but not enforced by interface (comment says "TODO")

**How to prevent:**
- ALWAYS check working plugin (NotesPlugin) for signals section
- Required: `signals: void eventResponse(const QString& eventName, const QVariantList& data);`
- Also need `#include <QVariantList>` in header

**Evidence:** Log line "ModuleProxy: Connected to wrapped object's eventResponse signal" appeared after fix

---

### Hiding Base Class logosAPI Member Broke Method Discovery
**Date:** 2026-03-22
**Context:** After adding eventResponse, still got "LogosAPI not available"

**What went wrong:**
- Declared `private: LogosAPI* logosAPI = nullptr;` in KeycardPlugin
- This hid the base class PluginInterface's `public: LogosAPI* logosAPI` member
- ModuleProxy checks base class member to verify initialization

**Why it happened:**
- Didn't notice PluginInterface already has logosAPI as public member
- Assumed we needed to declare our own copy

**How to prevent:**
- Read base class definition carefully before adding members
- Use base class's public members instead of redeclaring
- Don't add private members that hide base class public members

**Evidence:** Removing private declaration fixed "LogosAPI not available" error

---

### UI Plugin Requires BOTH manifest.json AND metadata.json
**Date:** 2026-03-22
**Context:** keycard_ui not appearing in UI Modules list

**What went wrong:**
- Only created metadata.json for UI plugin
- UI plugin didn't appear in Basecamp's plugin list

**Why it happened:**
- Spec showed both files but didn't emphasize BOTH are required
- Assumed metadata.json was enough

**How to prevent:**
- QML UI plugins need TWO JSON files:
  - `manifest.json`: Module manifest (like core modules)
  - `metadata.json`: Additional UI-specific metadata
- Check working example (notes_ui) which has both

**Evidence:** Plugin appeared immediately after adding manifest.json

---

### Directory Name Must Match Plugin Name Exactly
**Date:** 2026-03-22
**Context:** UI plugin files installed but not discovered

**What went wrong:**
- Directory: `keycard-ui` (hyphen)
- Metadata name: `keycard_ui` (underscore)
- Basecamp couldn't match them

**Why it happened:**
- Used hyphen in directory name but underscore in metadata (inconsistent naming)

**How to prevent:**
- Plugin directory name MUST exactly match the `name` field in metadata
- All working plugins follow this pattern (notes_ui/notes_ui, counter/counter)
- Use underscores consistently, avoid hyphens in plugin names

**Evidence:** Renamed `keycard-ui` → `keycard_ui` and plugin appeared in list

---

### Manifest Platform Keys: Only Include Current Platform
**Date:** 2026-03-22  
**Context:** Core module not loading initially

**What went wrong:**
- manifest.json had both `"linux-amd64"` and `"darwin-arm64"` in main dict
- Module didn't load

**Why it happened:**
- Spec showed multi-platform example, assumed all platforms should be listed
- Working modules only list single platform

**How to prevent:**
- Only include current platform in manifest's `main` dict
- For Linux: `{"main": {"linux-amd64": "plugin.so"}}`
- Don't add other platforms until testing on them

**Evidence:** After removing darwin-arm64 key, module loaded successfully

## Issue #2 - Core Module Implementation

### Session State Overlay Must Clear on Card State Changes
**Date:** 2026-03-22
**Context:** Senty Round 3 review - session transition semantics violation

**What went wrong:**
- After `deriveKey()` set `SessionState::Active`, card removal still showed `SESSION_ACTIVE`
- After `closeSession()` set `SessionState::Closed`, `discoverCard()` didn't reset to show `CARD_PRESENT`
- Session overlay took precedence but wasn't cleared on physical card state changes

**Why it happened:**
- Session state was only set in `authorize()`, `deriveKey()`, and `closeSession()`
- `getState()` checked overlay first without validating card still present
- `discoverCard()` didn't manage session lifecycle

**How to prevent:**
- Session overlay must be conditional on card presence, not absolute
- `getState()` must check bridge state and clear overlay if card gone
- `discoverCard()` must clear overlay on state transitions (found/not-found)
- Session states are logical overlays over physical states, not replacements

**Evidence:** 
- Senty Round 3 review identified security risk (SESSION_ACTIVE persisting after card removal)
- Fixed in commit 19277ee with dual clearing approach (discoverCard + getState)

**Fix pattern:**
```cpp
// In discoverCard()
if (card_found && m_sessionState == Closed) {
    m_sessionState = NoSession;  // Allow CARD_PRESENT to show
}
if (!card_found && m_sessionState != NoSession) {
    m_sessionState = NoSession;  // Clear stale session
}

// In getState()
if (bridge_reports_card_gone && m_sessionState != NoSession) {
    m_sessionState = NoSession;  // Proactive clearing
}
```

---

### Plugin Icons: manifest.json vs metadata.json
**Date:** 2026-03-22
**Context:** Icon showing as "keyc" text instead of image

**What went wrong:**
- Set `"icon": "keycard.svg"` only in metadata.json
- manifest.json had `"icon": ""`
- Icon displayed as text fallback

**Why it happened:**
- Assumed metadata.json was sufficient (where other UI settings live)
- Didn't notice counter_qml has icon references in BOTH files
- UI framework loads icons from manifest.json, not metadata.json

**How to prevent:**
- BOTH manifest.json and metadata.json need icon fields populated
- manifest.json: `"icon": "keycard.png"` (root-level reference)
- metadata.json: `"icon": "icons/keycard.png"` (can be subdirectory)
- Check working plugin structure (counter_qml) before assuming

**Evidence:** After updating manifest.json icon field, icon displayed correctly

---

### Plugin Icon Format: PNG Required, Not SVG
**Date:** 2026-03-22
**Context:** Icon still not displaying after setting paths

**What went wrong:**
- Created SVG icon (text-based, good for version control)
- Icon still showed as text fallback

**Why it happened:**
- Assumed SVG would work (modern format, scalable)
- Working plugins all use PNG (counter_qml, etc.)
- UI framework expects raster format

**Required format:**
- 28x28 PNG, 8-bit RGBA
- Must be in both root and icons/ subdirectory
- No SVG support (at least not verified working)

**Evidence:** After converting to PNG, icon displayed correctly

---

### Icon Design: Must Have Contrast for Inactive Gray State
**Date:** 2026-03-22
**Context:** User observation about counter icon gray/color transition

**What we learned:**
- UI framework applies desaturation filter to inactive icons (gray)
- Shows full color when plugin is active/selected
- Light/white icons become invisible when desaturated
- Counter icon works because it has strong colors (blue, orange)

**Design guideline:**
- Use colors with good saturation and contrast
- Avoid white/light colors as primary elements
- Test how icon looks in grayscale (inactive state)
- Icon should be visible on both light and dark backgrounds

**Evidence:** User-designed icon from Figma with proper contrast worked correctly

---


## Issue #3 - Debug UI Implementation

### QML Signals Don't Return Values
**Date:** 2026-03-22
**Context:** Execute buttons not posting results

**What went wrong:**
- Defined `signal execute()` in ActionRow component
- Button's onClicked called `var result = row.execute()`
- Nothing happened - execute button didn't show results

**Why it happened:**
- In QML, signals are for notifications, not function calls
- Signals emit but don't return values
- Can't do `var result = someSignal()` - syntax works but returns undefined

**How to prevent:**
- Use `property var executeFunc: function() { ... }` instead of signals when return value needed
- Signals: for notifications (onStateChanged, onClicked)
- Function properties: for callbacks that return values

**Evidence:** After changing to executeFunc property, all buttons posted results correctly

---

### State-Based UI vs Flag-Based UI
**Date:** 2026-03-22
**Context:** Row status showing stale "not discovered yet" when state was CARD_PRESENT

**What went wrong:**
- Maintained separate `readerFound`, `cardFound` flags
- Updated flags in executeFunc callbacks
- Prerequisite text checked flags: `root.readerFound ? "✓ Reader found" : "Not found"`
- Flags weren't updating reactively, showed stale status

**Why it happened:**
- Flags only updated when Execute button clicked
- Didn't account for state changes from other sources (polling, card insertion)
- State already tracked via 500ms Timer polling `getState()`
- Duplicated state in flags created synchronization issues

**How to prevent:**
- Use single source of truth: `root.currentState` (already being polled)
- Check state instead of flags: `root.currentState !== "READER_NOT_FOUND" ? "✓ Reader found" : ...`
- State updates automatically from Timer, always current
- No manual flag management needed

**Evidence:** After switching to state-based checks, all status text updated correctly and reactively

**Pattern:**
```qml
// ❌ Wrong - flag-based
property bool cardFound: false
prereqText: root.cardFound ? "✓ Card found" : "Not found"
executeFunc: function() {
    var result = logos.callModule("keycard", "discoverCard", [])
    root.cardFound = JSON.parse(result).found  // Manual sync
}

// ✅ Right - state-based
property string currentState: "READER_NOT_FOUND"  // Auto-updated by Timer
prereqText: {
    if (root.currentState === "CARD_PRESENT" ||
        root.currentState === "AUTHORIZED" ||
        root.currentState === "SESSION_ACTIVE") {
        return "✓ Card found"
    }
    return "Not found"
}
```

---

### Prerequisites Must Account for All Relevant States
**Date:** 2026-03-22
**Context:** Multiple issues with button enabling after state transitions

**What went wrong:**
- closeSession only enabled for SESSION_ACTIVE, disabled in AUTHORIZED
- authorize only enabled for CARD_PRESENT, disabled in SESSION_CLOSED
- discoverCard showed "Ready to discover" in SESSION_CLOSED

**Why it happened:**
- Prerequisites checked narrow state conditions
- Didn't consider full state machine transitions
- SESSION_CLOSED means card present but session ended - should allow re-auth
- AUTHORIZED means authorized but key not derived - should allow closeSession

**How to prevent:**
- Check SPEC.md state machine diagram
- For each action, list ALL valid source states, not just primary one
- closeSession: enable for AUTHORIZED || SESSION_ACTIVE (both are session states)
- authorize: enable for CARD_PRESENT || SESSION_CLOSED (re-auth use case)
- Card-present checks: include SESSION_CLOSED (card still there, session just closed)

**Evidence:** 
- User couldn't close session in AUTHORIZED state (had to derive key first)
- User couldn't re-authorize in SESSION_CLOSED (had to remove/reinsert card)
- Fixed by adding missing states to prereqMet conditions

---

### UI Polish: Less is More
**Date:** 2026-03-22
**Context:** User feedback on visual design

**What we learned:**
- Initially: colored borders (green/red), long UID in status text
- User: "don't show colored borders - color of status is enough"
- User: "don't show UID after card found in status - showing it in text field is enough"

**Why it matters:**
- Redundant visual indicators add clutter without value
- Green/red borders duplicated status text color
- Long UID (64 hex chars) in status duplicated result field below
- Simpler UI is easier to scan and read

**Design guideline:**
- One indicator per piece of information (not multiple redundant ones)
- Status text color + text is sufficient (borders were redundant)
- Show details once in appropriate place (UID in result field, not status)
- Ask "what information does this add?" before adding visual elements

**Evidence:** User said "cool we good" after simplification, not before

---


## Issue #10 - keycard-qt Migration

### UI Freeze from Blocking Calls in Event Loop
**Date:** 2026-03-23
**Context:** Authorization worked but froze entire UI for several seconds

**What went wrong:**
- After authorization, `getStatus()` called every 500ms via QML timer
- Each `getStatus()` call blocked for ~600ms (PC/SC communication)
- UI timer running in main thread → entire UI frozen during blocking calls
- User couldn't interact with app after clicking "Authorize"

**Root cause:**
- `pollStatus()` called `getStatus()` on every timer tick when authorized
- No throttling - if timer interval < call duration, UI constantly blocked
- keycard-qt uses synchronous API, not Qt async signals for this call

**Solution:**
- Added timestamp tracking (`m_lastStatusCheck`)
- Throttle `getStatus()` to once every 5 seconds instead of 500ms
- UI responsive 90% of time, brief freeze every 5 seconds acceptable

**Code pattern:**
```cpp
void pollStatus() {
    if (m_state == Authorized) {
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastStatusCheck < 5000) {
            return;  // Skip, too soon
        }
        m_lastStatusCheck = now;
        m_commandSet->getStatus();  // Now called infrequently
    }
}
```

**Prevention:**
- Profile blocking calls duration before adding to tight loops
- If call duration > loop interval, throttle aggressively
- Consider moving blocking I/O to worker thread
- QML timers run on main thread - keep handlers fast

**Evidence:** Debug logs showed getStatus() taking 600-614ms per call

---

### Session State Reset by Auto-Detection Logic
**Date:** 2026-03-23
**Context:** closeSession() worked but state immediately reverted to AUTHORIZED

**What went wrong:**
- `closeSession()` set `m_sessionState = Closed`
- QML timer called `discoverCard()` 500ms later
- `discoverCard()` had: `if (cardPresent && sessionState == Closed) { sessionState = NoSession; }`
- Result: Closed state lasted <1 second before being cleared

**Root cause:**
- Incorrect assumption: "card rediscovered means clear Closed state"
- Session state is logical (user action), card presence is physical
- Card staying present after closeSession() is normal, not a rediscovery

**Solution:**
- Remove auto-reset logic from `discoverCard()`
- Session state persists until explicit action (authorize) or card removal
- Only clear session state when card actually removed

**Code before:**
```cpp
if (cardPresent && m_sessionState == Closed) {
    m_sessionState = NoSession;  // WRONG: card still present!
}
```

**Code after:**
```cpp
if (cardPresent) {
    // Session state persists - don't touch it
}
```

**Prevention:**
- Session state = user intent, not hardware state
- Only auto-clear session on card removal (hardware change)
- State transitions from user actions should persist until next user action

**Evidence:** User saw state flip from CLOSED → AUTHORIZED in 1 second

---

### deriveKey Allowed After Session Closed
**Date:** 2026-03-23
**Context:** After closeSession(), deriveKey() still worked

**What went wrong:**
- `deriveKey()` didn't check session state
- Could derive keys even after session explicitly closed
- Violated security model: closed session should require re-auth

**Solution:**
- Add session state check at top of `deriveKey()`:
```cpp
if (m_sessionState == SessionState::Closed) {
    return error("Session closed - authorize again");
}
```

**Prevention:**
- Security operations must check authorization state
- Session closure means "no more operations until re-auth"
- Add state guards to all sensitive operations, not just some

---

### Git Submodules Don't Work in Archives
**Date:** 2026-03-23
**Context:** Senty review found branch not buildable from `git archive`

**What went wrong:**
- Used git submodule for keycard-qt dependency
- `git archive` (used by GitHub tarballs) doesn't include submodule contents
- Clean archive extracts showed empty `external/keycard-qt/` directory
- Build failed: "CMakeLists.txt not found"

**Why this matters:**
- CI systems often use archives, not full git clones
- Release tarballs from GitHub don't include submodules
- Breaks reproducibility: developer checkout works, but clean archive doesn't

**Solution - CMake FetchContent:**
```cmake
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/external/keycard-qt/CMakeLists.txt")
    add_subdirectory(external/keycard-qt)  # Use local if present
else()
    FetchContent_Declare(
        keycard-qt
        GIT_REPOSITORY https://github.com/status-im/keycard-qt.git
        GIT_TAG        3c01bc114f0a38e91147793e96d7a4ebd68301a6
    )
    FetchContent_MakeAvailable(keycard-qt)  # Download if missing
endif()
```

**Benefits:**
- Developer workflow: uses local submodule (fast, offline capable)
- Archive/CI workflow: auto-downloads from GitHub
- Reproducible: same commit hash every time

**Prevention:**
- For cross-project dependencies, use FetchContent or find_package, not submodules alone
- Test build from `git archive` extract, not just live git checkout
- Pin to commit hashes for reproducibility, not branch names

**Evidence:** Senty verified clean archive build after FetchContent added

---

### Module Process Logs Not in Main App Log
**Date:** 2026-03-23
**Context:** qDebug() output from authorize() not appearing anywhere

**What went wrong:**
- Added debug logging with `qDebug()` in KeycardBridge
- Expected to see output in `/tmp/logos-app.log`
- No output appeared - logs were "lost"

**Root cause:**
- Keycard module runs in separate `logos_host.elf` process
- Each module has its own stdout/stderr
- Main app log only captures main process output
- Module process stderr likely goes to journal or separate streams

**Solution:**
- Implemented file-based logging helper:
```cpp
static void debugLog(const QString& msg) {
    QFile file("/tmp/keycard-debug.log");
    if (file.open(QIODevice::Append)) {
        QTextStream out(&file);
        out << QDateTime::currentDateTime().toString("hh:mm:ss.zzz") 
            << " " << msg << "\n";
        file.flush();
    }
}
```

**Prevention:**
- Module debugging needs separate log file, not qDebug()
- Or check `journalctl --user` for module process output
- Don't assume module qDebug() appears in main app log

**Evidence:** After adding file logging, all debug output visible in `/tmp/keycard-debug.log`

---

