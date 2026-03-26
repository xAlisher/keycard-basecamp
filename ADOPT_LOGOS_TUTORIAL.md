# Adopting Logos Tutorial Best Practices for Keycard Module

**Source:** https://github.com/logos-co/logos-tutorial
**Branch:** `adopt-logos-tutorial-patterns`
**Status:** Planning (Do Not Implement Yet)

## Executive Summary

The [logos-tutorial](https://github.com/logos-co/logos-tutorial) repository provides comprehensive guides and reference implementations for building Logos modules. This document analyzes what patterns and tools we can adopt to improve the keycard module's architecture, build system, testing, and distribution.

---

## Key Learnings from logos-tutorial

### 1. Use logos-module-builder Templates

**Current state:** Custom CMake setup with manual configuration across multiple files.

**Tutorial approach:** Single command scaffolding with `logos-module-builder`:

```bash
# For wrapping external libraries (like keycard-qt)
nix flake init -t github:logos-co/logos-module-builder#with-external-lib

# For QML UI modules
nix flake init -t github:logos-co/logos-module-builder#ui-qml-module
```

**Benefits:**
- ✅ Reduces ~600 lines of config to ~70 lines
- ✅ Single source of truth: `metadata.json`
- ✅ Built-in CMake macros via `LogosModule.cmake`
- ✅ Automatic code generation setup
- ✅ Consistent structure across all Logos modules

**Adoption plan:**
- Migrate `keycard-core` to use `logos-module-builder#with-external-lib` template
- Migrate `keycard-ui` to use `logos-module-builder#ui-qml-module` template
- Consolidate build config into `metadata.json`

---

### 2. Consolidate metadata.json as Single Source of Truth

**Current state:** Separate files for:
- `keycard-core/src/plugin_metadata.json` (Qt plugin metadata)
- `keycard-core/modules/keycard/manifest.json` (LGX runtime manifest)
- `keycard-ui/plugins/keycard-ui/metadata.json` (UI plugin metadata)
- CMakeLists.txt (build configuration)

**Tutorial approach:** Single `metadata.json` used for:
- Qt plugin metadata (embedded via `Q_PLUGIN_METADATA`)
- Nix build configuration (read by `logos-module-builder`)
- CMake dependency resolution
- LGX manifest generation

**Example metadata.json structure:**

```json
{
  "name": "keycard",
  "version": "1.0.0",
  "type": "core",
  "category": "security",
  "description": "Keycard hardware wallet integration",
  "main": "keycard_plugin",
  "dependencies": [],

  "nix": {
    "packages": {
      "build": ["openssl", "libsodium", "pcsclite"],
      "runtime": []
    },
    "vendorLibs": [
      {
        "path": "external/keycard-qt",
        "type": "git-submodule",
        "cmakeTarget": "keycard-qt"
      }
    ]
  }
}
```

**Benefits:**
- ✅ No duplicate metadata across files
- ✅ CMake reads from same source as runtime
- ✅ Easier maintenance (single file to update)
- ✅ Automatic manifest generation for LGX

**Adoption plan:**
- Create unified `metadata.json` for keycard-core
- Remove redundant manifest.json and plugin_metadata.json
- Update CMakeLists.txt to use `logos_module()` macro
- Use metadata.json for LGX packaging

---

### 3. Use C++ SDK Code Generator for Typed APIs

**Current state:** Manual string-based `logos.callModule()` calls from QML:

```qml
// Current (untyped)
var result = logos.callModule("keycard", "authorize", [pin])
var obj = JSON.parse(result)
```

**Tutorial approach:** Generate typed C++ bindings from interface definitions:

**Step 1:** Define interface in `keycard_interface.h`:

```cpp
// keycard-core/src/keycard_interface.h
class KeycardInterface {
public:
    virtual ~KeycardInterface() = default;

    // Core operations
    virtual LogosResult<QString> initialize() = 0;
    virtual LogosResult<QString> authorize(const QString& pin) = 0;
    virtual LogosResult<QString> deriveKey(const QString& domain) = 0;
    virtual LogosResult<QString> getState() = 0;
};
```

**Step 2:** Code generator creates typed proxy class:

```cpp
// Auto-generated: keycard_proxy.h
class KeycardProxy : public QObject {
    Q_OBJECT
public:
    LogosResult<QString> initialize();
    LogosResult<QString> authorize(const QString& pin);
    LogosResult<QString> deriveKey(const QString& domain);
    LogosResult<QString> getState();
private:
    LogosAPI* m_api;
};
```

**Step 3:** Use typed API in C++ UI:

```cpp
// Type-safe calls with compile-time checking
KeycardProxy keycard(logosAPI);
auto result = keycard.authorize(pin);
if (result.isOk()) {
    qDebug() << "Authorized:" << result.value();
}
```

**Benefits:**
- ✅ Compile-time type checking
- ✅ No manual JSON parsing
- ✅ Auto-completion in IDE
- ✅ Refactoring safety

**Adoption plan:**
- Create `keycard_interface.h` with pure virtual interface
- Configure code generator in metadata.json
- Generate KeycardProxy class
- Use in C++ UI if we add one (currently QML-only)

---

### 4. Test with logoscore Before UI Integration

**Current state:** Testing requires full Logos Basecamp + UI plugin.

**Tutorial approach:** Use `logoscore` CLI for headless module testing:

```bash
# Build module
nix build

# Test with logoscore (headless)
nix run github:logos-co/logos-logoscore-cli -- \
  --module result/lib/Logos/Modules/keycard

# Call methods directly
$ logoscore
> keycard.initialize()
{"initialized": true}

> keycard.authorize("123456")
{"authorized": true, "remainingAttempts": 2}

> keycard.deriveKey("notes.private")
{"key": "ff21fc1c..."}
```

**Benefits:**
- ✅ Faster iteration (no UI compilation)
- ✅ Scriptable testing
- ✅ CI/CD friendly
- ✅ Debug backend without UI complexity

**Adoption plan:**
- Add logoscore test commands to README.md
- Create test scripts in `scripts/test-with-logoscore.sh`
- Add to CI pipeline

---

### 5. Use logos-standalone-app for UI Testing

**Current state:** QML UI testing requires full Logos Basecamp.

**Tutorial approach:** Use `logos-standalone-app` for isolated UI testing:

```bash
# Test QML UI in isolation (without Basecamp)
nix run github:logos-co/logos-standalone-app -- \
  --ui result/lib/Logos/Plugins/keycard-ui \
  --module result/lib/Logos/Modules/keycard
```

**Benefits:**
- ✅ Faster UI iteration
- ✅ Isolated testing (no other modules)
- ✅ Simpler debugging
- ✅ Works without Basecamp installed

**Adoption plan:**
- Document logos-standalone-app usage in README.md
- Add `nix run .#test-ui` command to flake.nix
- Use for development workflow

---

### 6. Adopt Proper QML Plugin Structure

**Current state:** Debug harness in `keycard-ui/qml/Main.qml` with test buttons.

**Tutorial approach:** Clean separation of concerns:

**File structure:**
```
keycard-ui/
├── flake.nix
├── metadata.json           # Single source of truth
├── Main.qml                # Entry point (dashboard)
├── AuthWindow.qml          # Authorization modal
├── PendingRequests.qml     # Pending auth list
└── ActivityLog.qml         # Terminal log panel
```

**Main.qml pattern:**
```qml
import QtQuick
import QtQuick.Controls
import Logos.Theme 1.0
import Logos.Controls 1.0

Item {
    id: root

    // State from backend
    property string keycardState: "READER_NOT_FOUND"

    // Load initial state
    Component.onCompleted: {
        updateState()
    }

    function updateState() {
        var result = logos.callModule("keycard", "getState", [])
        var obj = JSON.parse(result)
        if (obj.state) {
            keycardState = obj.state
        }
    }

    // UI layout
    ManagementDashboard {
        visible: !authWindow.visible
        state: root.keycardState
    }

    AuthorizationWindow {
        id: authWindow
        visible: false
    }
}
```

**Benefits:**
- ✅ Clean component hierarchy
- ✅ Separation of concerns
- ✅ Reusable components
- ✅ Easier to maintain

**Adoption plan:**
- Split Main.qml into logical components
- Remove debug test harness (move to separate DebugPanel.qml)
- Use Ctrl+D toggle for debug mode

---

### 7. Use lm CLI for Module Introspection

**Current state:** Manual inspection with `ldd`, `nm`, etc.

**Tutorial approach:** Use `lm` CLI tool:

```bash
# Inspect module metadata
nix run github:logos-co/logos-module -- info result/lib/Logos/Modules/keycard/keycard_plugin.so

# List available methods
nix run github:logos-co/logos-module -- methods result/lib/Logos/Modules/keycard/keycard_plugin.so

# Validate plugin structure
nix run github:logos-co/logos-module -- validate result/lib/Logos/Modules/keycard/keycard_plugin.so
```

**Benefits:**
- ✅ Structured metadata display
- ✅ Method signature listing
- ✅ Validation checks
- ✅ Dependency resolution

**Adoption plan:**
- Add `lm` usage examples to README.md
- Use in CI for validation
- Document in DEVELOPMENT.md

---

### 8. Use lgpm for Package Management

**Current state:** Manual install via `cmake --install`.

**Tutorial approach:** Package as LGX and install via lgpm:

```bash
# Build LGX package
nix run .#package-lgx

# Install via lgpm
nix run github:logos-co/logos-package-manager-module -- install keycard-core.lgx

# Uninstall
nix run github:logos-co/logos-package-manager-module -- uninstall keycard

# List installed
nix run github:logos-co/logos-package-manager-module -- list
```

**Benefits:**
- ✅ Proper dependency tracking
- ✅ Clean uninstall
- ✅ Version management
- ✅ Module registry support (future)

**Adoption plan:**
- Use lgpm in development workflow
- Document in README.md
- Add to release process

---

### 9. Improve Documentation Structure

**Current state:** README.md with build instructions, SPEC.md with architecture.

**Tutorial approach:** Structured documentation:

```
docs/
├── README.md               # Overview + quick start
├── ARCHITECTURE.md         # System design
├── DEVELOPMENT.md          # Developer guide
├── API_REFERENCE.md        # Method signatures
├── SECURITY.md             # Security model
└── TUTORIALS/
    ├── 01-basic-usage.md
    ├── 02-integration.md
    └── 03-encryption.md
```

**Adoption plan:**
- Split SPEC.md into focused docs
- Add step-by-step tutorials
- Link to logos-tutorial for general concepts

---

## Implementation Roadmap (Revised per Senty's Review - Issue #31)

**Key principle:** Optimize for reversibility and reproducibility first, then builder adoption, then ergonomics.

### Phase 0: Analysis ✅ COMPLETE
- ✅ Review logos-tutorial patterns
- ✅ Document learnings in ADOPT_LOGOS_TUTORIAL.md
- ✅ Create GitHub issue #31
- ✅ Get Senty review feedback

### Phase 1: Pin Tools + Wrapper Scripts ⏳ IN PROGRESS
**Goal:** Reproducible testing infrastructure without changing production code.

**Tasks:**
- [ ] Pin `logos-logoscore-cli` in flake.nix
- [ ] Pin `logos-standalone-app` in flake.nix
- [ ] Pin `logos-module` (lm CLI) in flake.nix
- [ ] Create `scripts/test/test-with-logoscore.sh` (calls pinned logoscore)
- [ ] Create `scripts/test/test-ui-standalone.sh` (calls pinned standalone-app)
- [ ] Create `scripts/test/inspect-module.sh` (calls pinned lm)
- [ ] Document usage in README.md
- [ ] Validate scripts work with current build

**Exit criteria:**
- ✅ Tools pinned to specific revisions (no floating `nix run github:...`)
- ✅ Scripts reproducible across dev/CI environments
- ✅ Documentation complete
- ✅ Independently valuable (can merge even if later phases delayed)

**Estimated effort:** 3-4 hours
**Risk:** None (no production code changes)

---

### Phase 2: Builder Spike (Throwaway Branch)
**Goal:** Learn `logos-module-builder` contract before committing to migration.

**Tasks:**
- [ ] Create throwaway spike branch from master
- [ ] Pick easier module (probably keycard-ui, QML-only)
- [ ] Scaffold using `logos-module-builder#ui-qml-module` template
- [ ] Port current functionality to new structure
- [ ] Document what metadata.json structure builder expects
- [ ] Identify migration gotchas and risks
- [ ] Compare artifacts: does LGX look similar?
- [ ] Test loading in Basecamp
- [ ] **Discard spike branch** (knowledge retained, code thrown away)

**Exit criteria:**
- ✅ Understand builder's metadata contract
- ✅ Know what CMake patterns builder expects
- ✅ Documented migration path with lessons learned
- ✅ Identified risks and blockers

**Estimated effort:** 4-6 hours
**Risk:** None (throwaway branch, learning exercise)

---

### Phase 3: Metadata Consolidation (After Builder Proven)
**Goal:** Single source of truth using format learned from Phase 2 spike.

**Tasks:**
- [ ] Create unified `metadata.json` matching builder's expected structure
- [ ] Update CMakeLists.txt to read from it (incremental changes)
- [ ] Keep old files until new system validated
- [ ] Run parity checks:
  - [ ] Plugin loads same methods (`lm methods` comparison)
  - [ ] LGX contents materially identical where expected
  - [ ] Install paths remain correct
  - [ ] Package validation passes
  - [ ] Manual test flows work
- [ ] Compare binaries to ensure identical behavior

**Exit criteria:**
- ✅ All parity checks pass
- ✅ Build reproducibility maintained
- ✅ Old files can be safely removed
- ✅ Documentation updated

**Estimated effort:** 4-6 hours
**Risk:** Medium (mitigated by parity checks + keeping old files as backup)

---

### Phase 4: Migrate First Module
**Goal:** Adopt logos-module-builder for one module with full validation.

**Tasks:**
- [ ] Pick easier module based on Phase 2 learning (UI or core)
- [ ] Add `logos-module-builder` as flake input
- [ ] Update CMakeLists.txt to use `logos_module()` macro
- [ ] Keep old CMakeLists.txt as `.old` backup
- [ ] Run comprehensive parity validation:
  - [ ] Module loads correctly in Basecamp
  - [ ] All Q_INVOKABLE methods work as before
  - [ ] LGX packaging produces valid package
  - [ ] Installation paths correct
  - [ ] Hardware tests pass (reader/card detection)
  - [ ] No regressions in functionality
- [ ] Document any deviations from spike findings

**Exit criteria:**
- ✅ All parity checks pass
- ✅ No regressions in functionality
- ✅ Build times similar or better
- ✅ Ready for production use
- ✅ Rollback plan documented

**Estimated effort:** 6-8 hours
**Risk:** Higher (but bounded to one module + comprehensive parity checks)

---

### Phase 5: Migrate Second Module
**Goal:** Complete builder adoption with lessons learned from first module.

**Tasks:**
- [ ] Apply learnings from Phase 4 to second module
- [ ] Run same comprehensive parity validation suite
- [ ] Compare artifacts between both modules for consistency
- [ ] Ensure build patterns consistent across modules
- [ ] Update documentation with any new learnings

**Exit criteria:**
- ✅ Both modules use logos-module-builder
- ✅ All parity checks pass for second module
- ✅ Build system fully consistent
- ✅ No regressions across entire project

**Estimated effort:** 4-6 hours (faster with Phase 4 experience)
**Risk:** Medium (well-understood patterns from Phase 4)

---

### Phase 6: Package Management + CI Cleanup
**Goal:** Improve distribution workflows and automation.

**Tasks:**
- [ ] Document `lgpm` usage for module installation
- [ ] Update packaging scripts for builder-based workflow
- [ ] Add builder-based CI workflows
- [ ] Document improved LGX packaging process
- [ ] Clean up and consolidate documentation
- [ ] Add automated parity checks to CI

**Exit criteria:**
- ✅ lgpm workflow documented and tested
- ✅ CI runs with new build system
- ✅ Documentation reflects current state
- ✅ Packaging reproducible

**Estimated effort:** 4-6 hours
**Risk:** Low

---

### Phase 7: UI Refactor (Depends on #29 Completion) ⏸️ DEFERRED
**Goal:** Apply logos-tutorial QML patterns to production UI.

**Status:** Deferred until production UI design finalized (Issue #29)

**Tasks:**
- [ ] Split Main.qml into clean component hierarchy
- [ ] Use Logos.Theme and Logos.Controls throughout
- [ ] Implement production UI structure from Issue #29
- [ ] Move debug harness to DebugPanel.qml (Ctrl+D toggle)
- [ ] Validate all auth flows with new structure

**Estimated effort:** 8-10 hours (after UI design complete)
**Risk:** Medium (but isolated to UI, backend unchanged)

---

### Phase 8: Code Generation ⏸️ DEFERRED
**Goal:** Typed C++ bindings for improved IDE support (optional optimization).

**Status:** Deferred until API and UI architecture stabilize

**Rationale:**
- Current UI is QML-only (untyped anyway)
- API still evolving with production UI work
- Limited immediate payoff
- Adds churn while architecture in flux

**Tasks:** TBD after API stabilization
**Estimated effort:** TBD
**Risk:** TBD

---

## Compatibility Notes

**Breaking changes:**
- Migrating to logos-module-builder will change build commands
- metadata.json consolidation will change file locations
- Need migration guide for existing users

**Backwards compatibility:**
- Keep current build system working during migration
- Provide side-by-side comparison in docs
- Tag release before migration

---

## Questions for Discussion

1. Should we migrate incrementally (one phase at a time) or all at once?
2. Do we need C++ UI module or is QML-only sufficient?
3. Should code generator be used for QML → C++ calls?
4. Timeline for migration? (Before or after production UI implementation?)
5. Do we want to use logos-module-viewer for visual introspection?

---

## References

- [logos-tutorial](https://github.com/logos-co/logos-tutorial) - Official tutorial series
- [logos-module-builder](https://github.com/logos-co/logos-module-builder) - Build system
- [logos-cpp-sdk](https://github.com/logos-co/logos-cpp-sdk) - SDK and code generator
- [logos-logoscore-cli](https://github.com/logos-co/logos-logoscore-cli) - CLI runtime
- [logos-standalone-app](https://github.com/logos-co/logos-standalone-app) - UI testing shell
- [logos-module](https://github.com/logos-co/logos-module) - lm CLI tool
- [logos-package-manager-module](https://github.com/logos-co/logos-package-manager-module) - lgpm CLI

---

## Senty's Review Feedback (Incorporated)

**Review date:** 2026-03-26
**Issue:** #31

### Key Improvements from Senty's Review

**1. Pin Tools in flake.nix First** ✅
- **Problem:** Using `nix run github:...` floats tool versions, breaks reproducibility
- **Solution:** Pin specific revisions in flake.nix, scripts call pinned tools
- **Impact:** Phase 1 revised to focus on reproducibility

**2. Spike Before Metadata Consolidation** ✅
- **Problem:** Could invent metadata format that doesn't match builder expectations
- **Solution:** Phase 2 is throwaway spike to learn builder contract first
- **Impact:** Avoid creating temporary format that needs re-migration

**3. Migrate One Module at a Time** ✅
- **Problem:** Migrating core + UI together = too much risk, large blast radius
- **Solution:** Phases 4/5 migrate separately with validation between
- **Impact:** Smaller rollback surface, clearer validation

**4. Add Explicit Parity Gates** ✅
- **Problem:** Need concrete validation that new system produces equivalent results
- **Solution:** Comprehensive parity checks in each migration phase
- **Checks:**
  - Plugin loads same methods (`lm methods` comparison)
  - LGX contents materially identical
  - Install paths correct
  - Package validation passes
  - Manual test flows work

**5. Defer Code Generation** ✅
- **Problem:** API still evolving, codegen adds churn for limited payoff
- **Solution:** Move to Phase 8, post-stabilization
- **Impact:** Focus on foundation first, optimize later

**6. Define Exit Criteria for Each Phase** ✅
- **Problem:** Risk of all-or-nothing adoption
- **Solution:** Each phase independently valuable and mergeable
- **Impact:** Phase 1 can merge even if later phases delayed

### Revised Sequencing Rationale

**Old order:** Optimize for speed
- Phase 1: Testing scripts
- Phase 2: Migrate build system
- Phase 3: Consolidate metadata

**New order:** Optimize for reversibility and reproducibility
- Phase 1: Pin tools (reproducibility foundation)
- Phase 2: Spike builder (learn before committing)
- Phase 3: Metadata (apply learnings, not invent format)
- Phases 4-5: Migrate one at a time (validate between)

**Result:** Lower risk, better reproducibility, each phase stands alone

---

## Next Steps

### Immediate (Phase 1)
1. ✅ Update ADOPT_LOGOS_TUTORIAL.md with Senty's feedback
2. ⏳ Pin testing tools in flake.nix
3. ⏳ Create wrapper scripts
4. ⏳ Document usage
5. ⏳ Validate with current build
6. ⏳ Submit PR for Phase 1 (small, low-risk)

### Near-term (Phase 2)
- Create throwaway spike branch
- Learn logos-module-builder contract
- Document findings
- Discard spike code, retain knowledge

### Long-term (Phases 3+)
- Proceed only after Phase 2 learnings
- One module at a time
- Full parity validation at each step
- Deferred: UI refactor (after #29), code generation (after API stable)

---

## Status Update

**Current phase:** Phase 1 (Pin Tools + Wrapper Scripts)
**Branch:** `adopt-logos-tutorial-patterns` (all work stays here)
**Master:** Untouched (no breaking changes)
**Next PR:** Phase 1 only (when complete and validated)
