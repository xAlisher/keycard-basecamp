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

*Lessons will be added here during implementation*

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
