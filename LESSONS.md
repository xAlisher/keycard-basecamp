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

## Issue #5 - Nix Flake and LGX Packaging

### Lesson #37: Nix FetchContent Requires Git in Sandbox
**Date:** 2026-03-23
**Context:** Building keycard-core with Nix, CMakeLists.txt uses FetchContent for keycard-qt

**What went wrong:**
- Copied keycard-qt to build dir in `preConfigure`, but CMake checked source dir
- In Nix, source and build dirs are separate (source is read-only)
- CMake fell through to `FetchContent_MakeAvailable()` needing git
- Nix sandbox doesn't have git → build failed

**How to prevent:**
- Pass externally-fetched deps via CMake variables: `-DVAR=${src}`
- Use `if(DEFINED VAR)` check before falling back to FetchContent
- Pattern: `add_subdirectory(${EXTERNAL_SRC} ${CMAKE_CURRENT_BINARY_DIR}/name)`

**Evidence:** PR #17, Senty review finding, commit 0e4ae2a

### Lesson #38: Relative Paths Break in Subshells with cd
**Date:** 2026-03-23
**Context:** LGX packaging script using tar to repack after removing libpcsclite

**What went wrong:**
- Used `(cd "$TEMP_DIR" && tar -czf "$OUTPUT_DIR/file.lgx" *)`
- `$OUTPUT_DIR` was `.` (relative)
- After `cd`, relative path pointed to wrong location
- File written to temp dir, not output dir

**How to prevent:**
- Convert relative to absolute before subshells: `OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)`
- Always use absolute paths when changing directories

**Evidence:** PR #17, commit 049f2a9

### Lesson #39: LGX Bundler Needs metadata.json with Simple main Field
**Date:** 2026-03-23
**Context:** LGX bundler failing - "no 'main' field in metadata.json"

**What went wrong:**
- Only provided `manifest.json` (runtime format with `main` as dict)
- LGX bundler expected `metadata.json` (build format with `main` as string)

**Two different formats:**
```json
// metadata.json (for LGX bundler)
{"main": "keycard_plugin"}  // String, no extension

// manifest.json (for Basecamp runtime)
{"main": {"linux-amd64": "keycard_plugin.so"}}  // Dict with platforms
```

**How to prevent:**
- Always provide both files
- metadata.json at repo root for bundler
- manifest.json in modules/ for runtime
- Bundler appends .so automatically (don't include in main field)

**Evidence:** PR #17, commits a8ad2cb, 1ac277d

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

## Issue #23 - Modal Authorization Window

### Don't Fix Working Infrastructure
**Date:** 2026-03-24
**Context:** Feature branch broke plugin loading by changing working configuration

**What went wrong:**
1. Changed plugin name: `keycard-ui` → `keycard_ui` (hyphen to underscore)
2. Switched install paths: LogosBasecamp ↔ LogosApp (multiple times)
3. Used wrong AppImage: `/nix/store/.../logos-basecamp.AppImage` instead of `~/logos-app/logos-app.AppImage`
4. Created duplicate plugins in multiple locations
5. Result: UI plugin appeared twice in sidebar, neither opened

**Root cause:**
- **Changed working master configuration while adding new feature (AuthWindow.qml)**
- Assumed plugin naming was wrong (it wasn't - master used hyphen correctly)
- Followed misleading memory file about LogosApp vs LogosBasecamp paths
- Didn't verify what configuration worked before making changes

**Why master worked:**
- `keycard-ui` (hyphen) in LogosBasecamp
- Launched with `~/logos-app/logos-app.AppImage`
- Single plugin in correct location

**Solution:**
- Reverted to master configuration (keycard-ui, LogosBasecamp, correct AppImage)
- Removed duplicate plugin directories
- Created RUN.md with explicit launch instructions

**Key principle:**
> **When adding features, only modify what the feature needs. Don't "improve" working infrastructure.**

**Correct approach for Issue #23:**
1. ✅ Add AuthWindow.qml (new feature)
2. ✅ Update Main.qml to use AuthWindow (new feature)
3. ✅ Update CMakeLists.txt to install AuthWindow.qml (required for feature)
4. ❌ Change plugin name (NOT needed for feature)
5. ❌ Change install paths (NOT needed for feature)
6. ❌ Change AppImage (NOT needed for feature)

**Prevention checklist:**
- [ ] Before changing infrastructure, verify it's actually broken
- [ ] Test master branch first to confirm what works
- [ ] Only change what's required for the specific feature
- [ ] When in doubt, consult RUN.md for current configuration
- [ ] Kill and verify processes before every test launch

**Red flags:**
- "Let me fix the naming to match other plugins" ← Is current naming broken? No? Don't fix.
- "The memory file says use LogosApp" ← Does master work? Yes? Keep master config.
- "Maybe it's the AppImage" ← Did yesterday work with same AppImage? Yes? Don't change.

**Testing protocol:**
1. Checkout master
2. Build and install
3. Kill processes (verify with `ps aux | grep logos`)
4. Launch correct AppImage from RUN.md
5. Verify UI opens correctly
6. **Only then** checkout feature branch and make minimal changes

**Evidence:**
- Feature branch: Plugin didn't load (multiple naming/path issues)
- Master branch: Plugin loaded immediately after reverting changes
- Created RUN.md to prevent future configuration drift

---


## Issue #44 - Session Management + Core APIs

**Date:** 2026-03-27  
**Context:** Implementing session timeout, lock functionality, and module authorization tracking for production dashboard UI.

### Lesson: Security Boundaries Must Be Enforced in Backend, Not UI

**What happened:**
Initial implementation exposed `completeAuthRequest(authId, key)` accepting key parameter from QML. Senty caught this in code review as a critical security flaw - it allowed UI code to inject arbitrary keys instead of forcing backend to derive from hardware.

**Why it's wrong:**
- QML is untrusted boundary - malicious code could inject fake keys
- Breaks security model where only keycard module talks to hardware
- Session state becomes meaningless if keys can be supplied externally
- Same pattern was already rejected in Issue #23

**Correct pattern:**
```cpp
// ✅ Backend derives key internally when session active
QString KeycardPlugin::completeAuthRequest(const QString& authId) {
    if (m_sessionState != SessionState::Active) {
        return error("Session not active");
    }

    // SECURITY: Derive from hardware, don't accept external keys
    QString domain = targetRequest->domain;
    QJsonObject keyResult = QJsonDocument::fromJson(deriveKey(domain).toUtf8()).object();
    targetRequest->key = keyResult.value("key").toString();
}
```

**Wrong pattern:**
```cpp
// ❌ Accepts external key - security boundary violated
QString KeycardPlugin::completeAuthRequest(const QString& authId, const QString& key) {
    targetRequest->key = key;  // DANGER: No verification
}
```

**Prevention:**
- Security operations (PIN, keys, crypto) must happen in backend
- UI should only pass identifiers (authId, domain, moduleName), never secrets
- Code review security checklist: "Does any Q_INVOKABLE method accept key material?"

### Lesson: UI State Changes Must Call Backend APIs to Sync State

**What happened:**
Lock button only changed UI mode to "pin" without calling backend `lockSession()` API. Session state remained active, keys stayed in memory, timer kept running.

**Why it's wrong:**
- Backend and frontend state diverged
- Security risk: UI shows locked but keys still accessible
- Success criterion "keys cleared on lock" not met

**Correct pattern:**
```qml
function lockSession() {
    // Call backend FIRST to clear state
    var result = logos.callModule("keycard", "lockSession", [])
    processActivity(result)
    
    // Then update UI
    mode = "pin"
}
```

**Wrong pattern:**
```qml
function lockSession() {
    // TODO: Call backend lockSession
    mode = "pin"  // Only UI change, backend state unchanged
}
```

**Prevention:**
- Search codebase for "TODO" before declaring feature complete
- UI state transitions should always call corresponding backend API
- Test backend state (logs, getSessionInfo) after UI state changes

### Lesson: Public API Contracts Must Use Consistent Naming

**What happened:**
`getSessionInfo()` returned `"SESSION_LOCKED"` while `getState()` returned `"SESSION_CLOSED"` for the same state. Different APIs described same state with different names.

**Why it's wrong:**
- Consumers can't key UI behavior off documented states
- Forces clients to maintain mapping tables
- Creates confusion: are LOCKED and CLOSED different states or same?

**Correct pattern:**
```cpp
// All APIs use same name for same state
if (m_sessionState == SessionState::Locked) {
    result["state"] = "SESSION_LOCKED";  // getState()
}

// Elsewhere
info["state"] = "SESSION_LOCKED";  // getSessionInfo()
```

**Prevention:**
- Define state constants in header, reference them everywhere
- Code review: grep for state strings across all API implementations
- Integration test: verify getState() matches getSessionInfo() state

### Lesson: ListView vs ScrollView for Dynamic QML Content

**What happened:**
Used ScrollView + Repeater for pending requests. Resulted in blank screen after unlock when width references broke.

**Why ListView is better:**
- Built-in scrolling and clipping
- Proper width/height management
- Performance: only renders visible items
- No manual width calculations needed

**Correct pattern:**
```qml
ListView {
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 16
    clip: true
    model: root.pendingRequests
    delegate: Rectangle {
        width: ListView.view.width  // Automatic width from ListView
        height: 64
        // ... delegate content
    }
}
```

**Wrong pattern:**
```qml
ScrollView {
    Layout.fillWidth: true
    Layout.fillHeight: true
    ColumnLayout {
        width: parent.width  // Can break when parent not ready
        Repeater {
            model: root.pendingRequests
            // ... item content
        }
    }
}
```

**When to use each:**
- ListView: Dynamic lists of identical-structure items (requests, modules, messages)
- ScrollView: Static content with mixed layouts (settings panels, forms)

### Lesson: Activity Log Deduplication Pattern

**What happened:**
Pending requests were logged multiple times - once on PIN screen, again on dashboard, then on every poll.

**Solution: QSet + request ID tracking:**
```cpp
// In plugin.h
QSet<QString> m_loggedRequestIds;

// In getPendingAuths()
for (const auto& req : m_authRequests) {
    if (req.status == "pending") {
        // Only log if not already logged
        if (!m_loggedRequestIds.contains(req.id)) {
            logActivity(QString("New request from %1").arg(req.caller), "warning");
            m_loggedRequestIds.insert(req.id);
        }
    }
}

// Cleanup when request completes
m_loggedRequestIds.remove(authId);
```

**Why this pattern works:**
- Each request logged exactly once
- Works across multiple screens polling same API
- Automatic cleanup prevents memory leak
- QSet provides O(1) lookup and insert

**Alternative considered:**
- Timestamp-based deduplication: Fragile, breaks if system clock changes
- Count-based: Doesn't work when count goes down then up
- Client-side tracking: Duplicates logic across QML files

### Lesson: Polling Timer Pattern for Backend State Sync

**Pattern implemented:**
```qml
Timer {
    id: requestPoller
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
        checkPendingRequests()
        updateSessionTime()
    }
}

function checkPendingRequests() {
    var result = logos.callModule("keycard", "getPendingAuths", [])
    var response = JSON.parse(result)
    
    // Process activity log
    if (response._activity && Array.isArray(response._activity)) {
        for (var i = 0; i < response._activity.length; i++) {
            activityLog.addEntry(response._activity[i].timestamp, ...)
        }
    }
    
    // Update UI model
    root.pendingRequests = response.pending.map(...)
}
```

**Benefits:**
- UI always shows current backend state
- Works across module boundaries (other modules create requests)
- Handles race conditions (approve while polling)
- Activity logs automatically synced

**Tradeoffs:**
- 1Hz polling overhead (acceptable for dashboard, would drain battery on mobile)
- Could use signals for instant updates, but polling is simpler and works

**When to use:**
- Dashboard/management UIs where real-time state matters
- Cross-module coordination (keycard sees requests from other modules)
- States that change externally (timeouts, background operations)

### Lesson: Activity Log Processing Pattern with _activity Arrays

**Backend pattern:**
```cpp
// In any API method
void KeycardPlugin::someMethod() {
    logActivity("Something happened", "info");
    
    // At end of method
    QJsonObject result;
    result["success"] = true;
    addActivityToResponse(result);  // Injects _activity array
    return QJsonDocument(result).toJson();
}

void KeycardPlugin::addActivityToResponse(QJsonObject& response) {
    QJsonArray activity;
    for (const auto& entry : m_recentActivity) {
        QJsonObject obj;
        obj["timestamp"] = entry.timestamp;
        obj["message"] = entry.message;
        obj["level"] = entry.level;
        activity.append(obj);
    }
    response["_activity"] = activity;
    m_recentActivity.clear();  // Consume queue
}
```

**Frontend pattern:**
```qml
function processActivity(responseJson) {
    var response = JSON.parse(responseJson)
    if (response._activity && Array.isArray(response._activity)) {
        for (var i = 0; i < response._activity.length; i++) {
            var entry = response._activity[i]
            activityLog.addEntry(entry.timestamp, entry.message, entry.level)
        }
    }
}

// After any callModule
var result = logos.callModule("keycard", "someMethod", [])
processActivity(result)
```

**Benefits:**
- Activity logs sync with API responses (no separate logging calls)
- Works with polling (getPendingAuths returns its own activity)
- No race conditions (activity tied to response that caused it)
- QML code stays DRY (processActivity helper reused everywhere)

### Files Changed

**Backend:**
- `keycard-core/src/plugin.h` - Added SessionState, AuthorizationRecord, m_loggedRequestIds
- `keycard-core/src/plugin.cpp` - Implemented session timer, completeAuthRequest, activity logging

**Frontend:**
- `keycard-ui/qml/Main.qml` - Lock button handler, approval/decline signal wiring
- `keycard-ui/qml/ManagementDashboard.qml` - Countdown timer, ListView, polling
- `keycard-ui/qml/PinEntryScreen.qml` - Pending count, activity processing

**Demo:**
- `auth_showcase-core/` - Example module showing Keycard integration
- `auth_showcase-ui/qml/Main.qml` - "Connect with Keycard" demo

### Review Feedback

**Senty Round 1 (3 blocking issues):**
1. HIGH - Security: completeAuthRequest accepted external keys
2. MEDIUM - Functionality: Lock button didn't call backend
3. MEDIUM - Consistency: SESSION_CLOSED vs SESSION_LOCKED naming

**Senty Round 2 (LGTM):**
All issues resolved, noted residual drift in DebugPanel.qml (non-blocking).

### Commits

- `32ceae6` - Main session management implementation
- `ca92527` - UI improvements (countdown, pending count, activity logs)
- `516f55c` - Fix security and consistency issues from code review
- `8466ca6` - Document lesson #37: Authorization API security boundary

### Value Delivered

- ✅ Session timeout prevents unauthorized access after 5 minutes
- ✅ Lock button gives users explicit control over security
- ✅ Module authorization tracking enables "who has access" visibility
- ✅ Countdown timer provides session awareness
- ✅ Activity logs improve observability
- ✅ Auth showcase demonstrates integration pattern for other modules
- ✅ Security boundary maintained (keys never leave backend)

