# Ecosystem — keycard-basecamp

## Cross-Project References

### logos-notes
- **Repo:** https://github.com/xAlisher/logos-notes
- **Relationship:** Original Keycard implementation. keycard-basecamp was extracted from logos-notes `KeycardBridge`.
- **Porting source:** `src/core/KeycardBridge.{h,cpp}` -> `keycard_manager.{h,cpp}`, `src/core/SecureBuffer.h` -> `secure_buffer.{h,cpp}`
- **Integration:** logos-notes calls `logos.callModule("keycard", "requestAuth", ...)` for key derivation. Mnemonic/PIN path remains alongside keycard. `key_source` meta field tracks which path is active.
- **Install path note:** logos-notes installs to `LogosBasecampDev/`, keycard-basecamp to `LogosBasecamp/`. Basecamp loads from `LogosBasecamp/`. Must copy or adjust paths.

### keycard-qt Upstream
- **Purpose:** Native C++/Qt smartcard library replacing CGO/JSON-RPC libkeycard.so
- **Integration:** Statically linked via CMake. Fetched via `FetchContent` (dev) or `-DKEYCARD_QT_SOURCE_DIR` (Nix).
- **Benefits:** 54% binary size reduction (14MB -> 6.4MB), real EIP-1581 support, direct C++ API
- **API surface:** `CommandSet::verifyPIN()`, `CommandSet::exportKey()`, `IPairingStorage`, `PairingInfo`

### logos-cpp-sdk
- **Repo:** https://github.com/logos-innovation-lab/logos-cpp-sdk
- **Purpose:** Basecamp plugin SDK. Provides `PluginInterface`, `LogosAPI`, build infrastructure.
- **Usage:** Linked as static library (`liblogos_sdk.a`).

### logos-module-builder
- **Repo:** https://github.com/logos-innovation-lab/logos-module-builder
- **Purpose:** Standardized Nix flakes and CMake templates for Basecamp modules.
- **Status:** Experimental (official warning: "do not use"). Has basic bugs (cp without -r flag).
- **Findings (Phase 2 spike):** Monorepo + dual-builder = architecturally viable. No hard "one module per repo" constraint. Don't block on builder stabilization.
- **Spike documented:** `SPIKE_LOGOS_MODULE_BUILDER.md`

### logos-tutorial
- **Repo:** https://github.com/logos-co/logos-tutorial
- **Purpose:** Best practices reference for Basecamp module development.
- **Adoption:** See Logos Tutorial Adoption section below.

### logos-module (logos-co)
- **Relationship:** `PluginInterface` in `module_lib/interface.h` is byte-for-byte identical to `core/interface.h` (logos-liblogos). Migration is just an include path change.

### LEZ Wallet / keycard-tech Repos
- **Context:** Keycard ecosystem repos (Status project). keycard-qt originated from this ecosystem.
- **Relevant for:** Understanding card firmware constraints, EIP-1581 path conventions, TLV encoding formats.

---

## External Dependencies

### libpcsclite
- **Purpose:** PC/SC middleware for smartcard communication.
- **CRITICAL:** Must use system library, NEVER bundle in LGX packages. Bundled version has wrong socket paths and version mismatches with system pcscd.
- **Dev package:** `sudo apt-get install libpcsclite-dev` (required for keycard-qt PC/SC backend)
- **Protocol compatibility:** After `nix flake update`, nix pcsclite (2.3.0, protocol 4:5) may not match system pcscd (2.0.3, protocol 4:4). Fix: patch RPATH to use system libpcsclite. Tracked in #67.
- **Reference:** https://pcsclite.apdu.fr/

### libsodium
- **Version:** 1.0.18
- **Purpose:** `sodium_memzero` for secure key wiping, `crypto_hash_sha256` for domain separation.
- **Linked via:** `PkgConfig::sodium`

### pcscd
- **Purpose:** PC/SC daemon. libpcsclite communicates with this daemon via IPC (Unix socket).
- **Why system library matters:** Bundled libpcsclite can't find system pcscd socket. Must use system's libpcsclite.

### OpenSSL
- **Purpose:** secp256k1 ECDH for keycard-qt pairing.
- **Linked via:** `find_package(OpenSSL REQUIRED)`, `OpenSSL::Crypto`

---

## Logos Tutorial Adoption

**Tracking Issue:** #31
**Strategy:** 8-phase approach with parity gates, throwaway spikes, one module at a time.

### Phase Status

| Phase | Issue | Status | Description |
|-------|-------|--------|-------------|
| 1 | #32 | Merged (PR #40) | Pin testing tools (logoscore, standalone-app, lm CLI) |
| 2 | #33 | Complete | Builder spike (monorepo viable, builder experimental) |
| 3 | #34 | Merged | Metadata consolidation (preparatory, builder-aligned) |
| 4 | #35 | Planned | Migrate first module (keycard-core with parity gate) |
| 5 | #36 | Planned | Migrate second module (keycard-ui with parity gate) |
| 6 | #37 | Planned | Package management + CI workflows |
| 7 | #38 | Deferred | UI refactor (depends on #29 - production UI/UX design) |
| 8 | #39 | Deferred | Code generation patterns (evaluate after Phases 1-6) |

### Phase 1: Reproducible Tool Pinning
- Pinned testing tool versions in `flake.nix`: `logos-logoscore-cli`, `logos-standalone-app`, `logos-module`
- Thin wrapper entrypoints: `test-with-logoscore`, `test-ui-standalone`, `inspect-module`
- Scope narrowed per Senty Option A: reproducible pinning + starter wrappers only
- Full operational workflows deferred to Phase 4 (after module layout migration)
- Merged PR #40, 2026-03-26

### Phase 2: Builder Spike
- Tested dual-builder invocation from monorepo
- Findings: monorepo + dual-builder architecturally viable, but builder is experimental with basic bugs
- Keep monorepo (don't split repos), don't block on builder stabilization
- Spike branch discarded per plan

### Phase 3: Metadata Consolidation
- Created builder-aligned `metadata.json` for keycard-core and keycard-ui
- Preparatory only (CMakeLists.txt remains operational source of truth)
- Must match current reality — no drift from actual files
- Merged to master, Issue #34 closed

---

## Test Release v1.0.0-test.2

**Released:** 2026-03-23
**URL:** https://github.com/xAlisher/keycard-basecamp/releases/tag/v1.0.0-test.2

**Contents:**
- `keycard-core.lgx` (3.3 MB) — Core module with keycard-qt, pcscd-compatible
- `keycard-ui.lgx` (5.3 KB) — QML debug UI

**Purpose:** Testing LGX distribution, security hardening, reader/card discovery, on-card BIP32 key derivation, session management. Not for production.

---

## Nix Package Structure

```nix
packages.lib        # Core module: keycard_plugin.so + manifest.json + metadata.json
packages.ui         # UI plugin: Main.qml + metadata.json
packages.default    # Defaults to lib
apps.package-lgx    # LGX packaging: nix run .#package-lgx
```

**LGX packaging:**
```bash
nix run .#package-lgx [output-dir]
```
Produces `keycard-core.lgx` and `keycard-ui.lgx`. Automatically removes libpcsclite from bundle.

**Verification:** `tar -tzf keycard-core.lgx | grep -i pcsclite` should return nothing.

---

## Reference Links

| What | Where |
|------|-------|
| logos-notes | https://github.com/xAlisher/logos-notes |
| logos-cpp-sdk | https://github.com/logos-innovation-lab/logos-cpp-sdk |
| logos-module-builder | https://github.com/logos-innovation-lab/logos-module-builder |
| logos-tutorial | https://github.com/logos-co/logos-tutorial |
| PC/SC Lite | https://pcsclite.apdu.fr/ |
| Logos Basecamp upstream | https://github.com/logos-co/logos-app |
| AppImage AOT issue | https://github.com/logos-co/logos-app/issues/60 |
| keycard-basecamp releases | https://github.com/xAlisher/keycard-basecamp/releases |

---

## Open Questions (from logos-notes, relevant context)

1. **Social backup CID discovery:** Permissioned trust groups via Waku messaging. Request/response CID exchange on group join. One encrypted blob per backup. (Giuliano guidance, 2026-03-17)
2. **Logos Storage built-in encryption:** bkomuves mentioned automatic encryption may be built-in. Not yet implemented.
3. **AppImage unblock:** Three options: `QT_QML_NO_CACHEGEN=1`, `qt_deploy_qml_imports()`, or Nix bundle (recommended). Blocked on Qt 6.9 AOT conflict. Upstream: logos-co/logos-app#60.

## Parked Tasks

### AppImage packaging
Blocked on Qt 6.9 AOT-compiled QML type registration conflict.
Unblock options: (1) `nix bundle` (recommended), (2) `qt_deploy_qml_imports()`, (3) `QT_QML_NO_CACHEGEN=1`.
