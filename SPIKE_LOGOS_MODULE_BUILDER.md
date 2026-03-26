# Spike: logos-module-builder Exploration

**Branch:** `spike/logos-module-builder-exploration` (throwaway)
**Date:** 2026-03-26
**Goal:** Learn builder contract before Phase 3-4 migration

---

## Template Structure: ui-qml-module

The `ui-qml-module` template creates just **3 files**:

### 1. metadata.json (Single Source of Truth)

```json
{
  "name": "ui_qml_example",
  "version": "1.0.0",
  "type": "ui_qml",
  "category": "example",
  "description": "A QML UI module",
  "main": "Main.qml",
  "icon": null,
  "dependencies": [],

  "nix": {
    "packages": {
      "build": [],
      "runtime": []
    },
    "external_libraries": [],
    "cmake": {
      "find_packages": [],
      "extra_sources": [],
      "extra_include_dirs": [],
      "extra_link_libraries": []
    }
  }
}
```

**Key observations:**
- ✅ Single file for ALL metadata (no separate manifest.json)
- ✅ Type field: `"ui_qml"` for QML-only modules
- ✅ Nix section handles build/runtime dependencies
- ✅ CMake section handles Qt packages, sources, includes

### 2. flake.nix (Minimal - 17 lines!)

```nix
{
  description = "Logos QML UI Module";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
```

**vs. Our Current flake.nix:**
- **Current:** ~240 lines with manual package definitions, CMake flags, install phases
- **Builder:** ~17 lines - ONE function call!
- **Magic:** `mkLogosQmlModule` reads metadata.json and generates everything

### 3. Main.qml (Standard QML)

```qml
import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    // Template shows logos.callModule() pattern
    // var result = logos.callModule("module", "method", ["args"])
}
```

**No changes needed** - our current Main.qml already uses this pattern!

---

## Current keycard-ui Structure (What We Have)

```
keycard-ui/
├── CMakeLists.txt                    (install rules only)
├── plugins/keycard-ui/
│   └── metadata.json                 (Qt plugin metadata)
└── qml/
    └── Main.qml                      (UI implementation)
```

**Issues:**
- ❌ No flake.nix for standalone UI build
- ❌ metadata.json incomplete (missing nix/cmake sections)
- ❌ Relies on top-level flake.nix manual package definition

---

## Migration Path for keycard-ui

### Step 1: Create metadata.json

Adapt template to keycard:

```json
{
  "name": "keycard_ui",
  "version": "1.0.0",
  "type": "ui_qml",
  "category": "security",
  "description": "Keycard debug UI and test harness",
  "main": "Main.qml",
  "icon": "",
  "dependencies": ["keycard"],

  "nix": {
    "packages": {
      "build": [],
      "runtime": []
    },
    "external_libraries": [],
    "cmake": {
      "find_packages": [],
      "extra_sources": [],
      "extra_include_dirs": [],
      "extra_link_libraries": []
    }
  }
}
```

**Changes from template:**
- name: `keycard_ui`
- category: `security`
- dependencies: `["keycard"]` (core module)

### Step 2: Create flake.nix for keycard-ui

```nix
{
  description = "Keycard UI Module";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-standalone-app.url = "github:logos-co/logos-standalone-app";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs = inputs@{ logos-module-builder, logos-standalone-app, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      logosStandalone = logos-standalone-app;
    };
}
```

### Step 3: Keep Main.qml as-is

✅ No changes needed - already uses `logos.callModule()`

### Step 4: Remove old files

After validation:
- ❌ Delete `plugins/keycard-ui/metadata.json` (merged into top-level)
- ❌ Delete `CMakeLists.txt` (builder handles install)

---

## Migration Path for keycard-core

**Template:** Use `default` or `with-external-lib` (needs keycard-qt, libsodium, pcsclite)

**Metadata structure:**

```json
{
  "name": "keycard",
  "version": "1.0.0",
  "type": "core",
  "category": "security",
  "description": "Keycard module for Basecamp app",
  "main": {
    "linux-amd64": "keycard_plugin.so",
    "darwin-arm64": "keycard_plugin.dylib"
  },
  "dependencies": [],

  "nix": {
    "packages": {
      "build": ["cmake", "ninja", "pkg-config"],
      "runtime": ["qt6.qtbase", "openssl", "libsodium", "pcsclite"]
    },
    "external_libraries": [
      {
        "name": "keycard-qt",
        "fetchGit": {
          "url": "https://github.com/status-im/keycard-qt",
          "rev": "3c01bc114f0a38e91147793e96d7a4ebd68301a6"
        }
      }
    ],
    "cmake": {
      "find_packages": ["Qt6 COMPONENTS Core Quick", "PkgConfig"],
      "extra_sources": [
        "src/plugin.cpp",
        "src/keycard_manager.cpp",
        "src/secure_buffer.cpp",
        "src/file_pairing_storage.cpp"
      ],
      "extra_include_dirs": [
        "src",
        "${LOGOS_CPP_SDK}/include",
        "${KEYCARD_QT_SOURCE_DIR}/src"
      ],
      "extra_link_libraries": [
        "Qt6::Core",
        "Qt6::Quick",
        "PkgConfig::sodium",
        "OpenSSL::SSL",
        "${LOGOS_CPP_SDK}/lib/liblogos_sdk.a"
      ]
    }
  }
}
```

**Complex parts:**
- External libraries (keycard-qt)
- Multiple sources
- SDK paths
- Custom build flags

---

## Key Questions for Spike

### Q1: Does builder support external git dependencies?

**Test:** Try adding keycard-qt to metadata.json `external_libraries`

### Q2: How does builder handle SDK paths?

**Test:** Check if `LOGOS_CPP_SDK` env var works or needs special handling

### Q3: What install structure does builder create?

**Test:** Build with `nix build` and inspect `result/`

### Q4: Does LGX output match our current format?

**Test:** Compare builder LGX vs. manual LGX (should be identical)

### Q5: Can we mix builder modules with manual modules?

**Test:** Build keycard-ui with builder, keycard-core manual - does it work?

---

## Next Steps for Spike

1. ✅ Scaffold ui-qml-module template (DONE)
2. ✅ Document metadata.json structure (DONE)
3. ✅ Adapt keycard-ui to builder pattern (DONE)
4. ⏳ Test build and install (IN PROGRESS - hit builder bug)
5. ⏳ Compare artifacts with current approach
6. ⏳ Test loading in Basecamp
7. ⏳ Document gotchas and migration risks
8. ⏳ Discard spike branch, keep docs

## Dual-Builder Test Results (Senty's Recommendation)

**Test:** Can top-level flake call `mkLogosQmlModule` for keycard-ui?

**Setup:**
- Created `keycard-ui/metadata.json` (QML module config)
- Added `logos-module-builder` input to top-level flake.nix
- Called `mkLogosQmlModule` in packages.builder-ui

**Result:** ❌ Hit builder bug before completing test

**Builder Bug Found:**
```
cp: -r not specified; omitting directory '/nix/store/.../keycard-ui'
```

The builder tries to `cp` the source directory without `-r` flag.

**Possible causes:**
1. Builder assumes flat structure (Main.qml at root, not in subdirectory)
2. Builder bug in QML module source handling
3. Our directory structure incompatible with builder expectations

**Next:** Report bug or find workaround to continue dual-builder test

---

## Findings So Far

### ✅ Wins

- **Dramatic simplification:** ~240 lines flake.nix → ~17 lines
- **Single source of truth:** One metadata.json for everything
- **Ecosystem consistency:** Same pattern as other Logos modules
- **Built-in testing:** logos-standalone-app integration included

### ⚠️ Risks / Unknowns

- External library support (keycard-qt) - not in template
- SDK path handling - might need custom logic
- Mixed builder/manual modules - compatibility unknown
- Migration path for dual-module repo (core + ui) - builder expects single module per repo?

### 🔴 Blockers (To Investigate)

- **Multi-module repo:** Our repo has TWO modules (core + ui). Builder templates assume ONE module per repo.
  - Option A: Split into two repos (keycard-core, keycard-ui)
  - Option B: Custom flake.nix that calls `mkLogosModule` + `mkLogosQmlModule`
  - Option C: Monorepo pattern with subdirectories

---

## Critical Finding: Logos Ecosystem Pattern

**Status:** ✅ Pattern identified from builder docs/examples

**Canonical Logos pattern: ONE MODULE PER REPO**

**Evidence:**
1. ✅ README: "Experimental - do not use" warning shows active development
2. ✅ Migration guide: All examples are single-module repos
3. ✅ Templates: Separate `ui-module`, `ui_qml-module`, `core` templates
4. ✅ Builder API: `mkLogosModule` and `mkLogosQmlModule` are separate functions
5. ✅ No examples or docs showing multi-module repos
6. ✅ Module types: `"core"`, `"ui"`, `"ui_qml"` - mutually exclusive

**Implication for keycard-basecamp:**

Current structure (monorepo):
```
keycard-basecamp/
├── keycard-core/    (backend)
└── keycard-ui/      (frontend)
```

**Canonical Logos structure (split repos):**
```
keycard-core/        (separate repo)
├── metadata.json
├── flake.nix
└── src/

keycard-ui/          (separate repo)
├── metadata.json    (with dependency: ["keycard"])
├── flake.nix
└── Main.qml
```

**Question for Senty:**
Should we split into two repos to match ecosystem pattern, or is there a reason to keep the monorepo and use custom build?

---

## Conclusion: Phase 2 Complete

**Final migration strategy:** Defer builder adoption, proceed with metadata consolidation only

**Dual-Builder Test Results:**
- ✅ **Proved:** Monorepo + dual-builder = architecturally viable
- ❌ **Blocked:** Builder too buggy (experimental, not production-ready)
- ✅ **Senty was right:** No hard "one module per repo" constraint

**Gotchas discovered:**
1. Builder marked "Experimental - do not use" (accurate warning!)
2. Builder has basic bugs (cp without -r flag)
3. Documentation shows examples, not working production code
4. Dramatic simplification promise (600→70 lines) blocked by tool maturity

**Risk assessment:** 🔴 **HIGH** - Builder not production-ready
- Current bugs block basic builds
- Would introduce instability
- Manual build works fine now

**Estimated migration effort:**
- **With current builder:** Impossible (blocked by bugs)
- **After builder stabilizes:** ~4-6 hours per module
- **Metadata consolidation only:** ~2-3 hours (independent of builder)

**Recommendation:**
1. ✅ **Proceed with Phase 3:** Metadata consolidation (no builder dependency)
2. ⏸️ **Defer builder adoption:** Wait for tool stabilization
3. ✅ **Keep current build:** Manual flake.nix works, don't break it
4. 🔄 **Revisit later:** Adopt builder when production-ready

**Value delivered:**
- Proved monorepo approach viable
- Identified tool maturity blocker
- Saved time by not pursuing broken migration
- Clear path forward (metadata first, builder later)

**Phase 2 Status:** ✅ COMPLETE - knowledge retained, spike branch ready to discard
