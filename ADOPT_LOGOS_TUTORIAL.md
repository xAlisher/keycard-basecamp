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

## Implementation Roadmap

### Phase 1: Analyze (Current)
- ✅ Review logos-tutorial patterns
- ✅ Document learnings in ADOPT_LOGOS_TUTORIAL.md
- ⏳ Create GitHub issue

### Phase 2: Migrate Build System
- [ ] Migrate keycard-core to logos-module-builder template
- [ ] Consolidate metadata.json
- [ ] Update CMakeLists.txt to use `logos_module()` macro
- [ ] Test build with new system

### Phase 3: Improve Testing
- [ ] Add logoscore test scripts
- [ ] Document logos-standalone-app usage
- [ ] Add lm CLI examples to README

### Phase 4: Refactor UI
- [ ] Split Main.qml into components
- [ ] Adopt Logos.Theme and Logos.Controls
- [ ] Implement production UI from Issue #29 mockups

### Phase 5: Improve Distribution
- [ ] Use lgpm for installation
- [ ] Update packaging scripts
- [ ] Document LGX workflow

### Phase 6: Documentation
- [ ] Restructure docs into focused files
- [ ] Add tutorials
- [ ] Improve API reference

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

## Next Steps

1. **Create GitHub issue** for tracking adoption work
2. **Get team feedback** on roadmap and timeline
3. **Prioritize phases** based on current needs (production UI vs build system)
4. **Start with Phase 2** (build system migration) as foundation

**Do not implement yet** - this is a planning document for discussion.
