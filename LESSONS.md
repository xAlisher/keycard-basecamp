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
