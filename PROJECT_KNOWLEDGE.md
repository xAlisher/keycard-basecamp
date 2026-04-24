# Project Knowledge: keycard-basecamp
*Last updated: 2026-04-14 (epic #127 retro)*

> **Architecture change (2026-04-02):** KeycardBridge, libkeycard.so, and direct PC/SC code
> have been removed from logos-notes. Keycard support now uses the external keycard-basecamp
> module via `logos.callModule("keycard", "requestAuth", ...)` for key derivation.

> **This file is the project's shared memory.**
> It lives in the repo root and is committed like any other file.
> GitHub issues are ephemeral. This file is not.

---

## Completed Phases

| Phase | Issue/PR | What shipped | Date |
|-------|----------|-------------|------|
| 1 — Scaffolding | #1 | Core module + pure-QML debug UI, eventResponse signal, manifest+metadata | 2026-03 |
| 2 — PC/SC Integration | #2 / PR merged | KeycardBridge (keycard-qt native), 7-state session contract, all API methods | 2026-03 |
| 3 — Debug UI | #3 / 04e472e | 7 action rows, live state indicator, prerequisites gating, hardware-verified | 2026-03 |
| X — keycard-qt Migration | #10 / bf24f68 | CGO->native C++ (54% size reduction), real EIP-1581, FetchContent builds | 2026-03-23 |
| 5 — Nix/LGX Packaging | #5 / PR #17 | Nix packages, `nix run .#package-lgx`, libpcsclite removal, LGX tested | 2026-03-23 |
| Security Fixes | #14,#15,#16 / PR #20 | Debug log gating (KEYCARD_LOG), UID sanitization, session enforcement | 2026-03-23 |
| Tutorial Adoption Ph1 | #32 / PR #40 | Pinned testing tools (logoscore, standalone-app, lm CLI) | 2026-03-26 |
| Tutorial Adoption Ph2 | #33 | Builder spike: monorepo viable, builder experimental | 2026-03-26 |
| Tutorial Adoption Ph3 | #34 | Metadata consolidation (preparatory, builder-aligned) | 2026-03-26 |
| Production UI | #29 / PR #46 | Button hovers, signal-based lock, focus timer, SVG colors, clip patterns | 2026-03-26 |
| Auth Screen UI | #42 / PR #47 | Authorization modal (UI shell), scope management pattern established | 2026-03-26 |
| Request Binding | #48 / PR #51 | Auth request data flow, signal parameters, Ctrl+A test trigger | 2026-03-26 |
| Backend API | #49 / PR #52 | authorizeRequest + rejectRequest wired, hardware vs software testing | 2026-03 |
| ActivityLog | #41 / PR #53 | Reusable ActivityLog.qml, clipboard, selectable text, copy button | 2026-03 |
| Upstream Compat | Epic #56 | logos-module migration, relative install paths, dual build surface | 2026-03 |
| Single-Screen | Epic #55 | UI cutover, enum cleanup, DesignTokens fixes, pcsclite RPATH | 2026-03 |
| Auto-close Session | #70 | Session auto-close, demo/code sync | 2026-04 |
| Encrypted Pairing | #43 | Encrypted pairing storage, migration-after-verify, fail-closed corruption | 2026-04 |
| Dev Integration Kit | Epic #82 | Full API docs, install manifest sync | 2026-04 |
| Key Persistence Fix | #94 / be284f0 | One-read-and-drop keys, SecureBuffer for AuthRequest, pcscd RUNPATH fix | 2026-04-10 |
| Dev Card Setup | #107 / ff95f6f | LEE applet (v3.2) installed, card initialized, ISD key identified | 2026-04-14 |
| Pending Requests Gate | #125 / PR #126 / cf62780 | Qt.callLater deferral + checkPairingBusy guard, gate fix root.cardDetected | 2026-04-14 |
| Pairing Flow UI | Epic #127 / PR #130 / bdd943c | Inline pairing form, QML auto-mirror to LogosBasecamp, declineRequest reset | 2026-04-14 |

---

## Current Status

- **Test release:** v1.0.0-test.2 (keycard-core.lgx 3.3MB, keycard-ui.lgx 5.3KB)
- **Tutorial adoption:** Phases 1-3 complete, Phase 4+ planned
- **Parked:** AppImage packaging (Qt 6.9 AOT conflict, upstream logos-co/logos-app#60)
- **logoscore test path confirmed:** Module loads and responds via logoscore after: (1) adding `-dev` manifest variants, (2) patchelf RUNPATH to include Nix lib paths (dev workaround only)
- **#108 / logos-basecamp #141:** AppImage does NOT auto-load user-installed core modules. Reported upstream. logoscore is the recommended dev test path.

---

## Open Security Findings

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| #10 | Low | PIN lockout counter in same DB as wrapped key (logos-notes). Keycard eliminates this. | Accepted |
| #8 | Low | AAD domain separation not implemented in AEAD calls. | Future hardening |

---

## Open Questions

1. ~~**pcsclite protocol compatibility (#67):**~~ **Resolved in #94.** CMake install and package-lgx.sh now auto-patch RUNPATH to `$ORIGIN`, ensuring system libpcsclite is used at runtime. Nix pcsclite (protocol 4:5) no longer leaks into installed plugins.
2. **Logos Storage built-in encryption:** May be built-in eventually. Worth watching.
3. **LEE mode probe (SW=0x6A86):** Requires Keycard secure channel wrapping. `keycard-cli` v0.7.0 has no LEE/P2=0x01 support. Deferred to #96 (`detectMode()`). Raw APDU outside SC returns SW=6D00.
4. **logos-basecamp #141 (user core module discovery):** AppImage never spawns user-installed core modules from `dependencies[]` in UI manifests. Upstream fix pending. Dev workaround: use logoscore CLI (see lessons.md "Issue #108").

---

## QML / Install Pitfalls (Epic #127, 2026-04-14)

- **QML does not auto-mirror to LogosBasecamp.** `cmake --install --prefix LogosApp` installs QML to `LogosApp/plugins/` only. The `.so` mirror in `keycard-core/CMakeLists.txt` does not cover QML. Fixed: `install(CODE)` mirror step in `keycard-ui/CMakeLists.txt`. Verify with `md5sum` on both paths after every install.
- **Launch the canonical AppImage path, not an ad-hoc shortcut.** Use `~/.local/share/Logos/appimages/current.AppImage`. Launching a different copy/symlink can leave multiple Basecamp instances alive with different mount roots, which makes module/QML verification misleading.
- **Always clear `LogosBasecamp` cache, not `LogosApp`.** AppImage reads from `~/.cache/Logos/LogosBasecamp/qmlcache/`. Clearing `LogosApp/qmlcache` has no effect on the running app.
- **Gate pairing UI on `!root.paired`, not `cardDetected`.** `cardDetected` can be false at the moment a pending request surfaces (timing race between `checkHardware` and deferred `checkPairing`). `paired` is the authoritative state.
- **`Qt.callLater` changes property ordering.** Deferring `checkPairing()` means `currentRequest` can be populated before `paired` becomes true. Any focus or UI state depending on both must handle both orderings (`onCurrentRequestChanged` + `onPairedChanged`).
- **`declineRequest()` must reset all request-scoped form state.** Fields introduced for a request flow (`pairingPassword`, `pairingError`, etc.) must be cleared in `declineRequest()` — not only on card removal or success path.

---

## Reference Files

| What | Where |
|------|-------|
| Architecture, state machine, QML patterns, security checklist | `docs/skills/architecture.md` |
| All lessons (numbered + phase/issue) | `docs/skills/lessons.md` |
| Ecosystem, cross-project refs, dependencies, tutorial adoption | `docs/skills/ecosystem.md` |
| Security audit history | `SECURITY_REVIEW.md` |
| Complete specification | `SPEC.md` |

---

## XPUB Export — Firmware Constraints (Discovered 2026-04-24)

Hardware-proven on Status Keycard firmware v3.1 (caps=0x1f).

### Root Cause: Two separate bugs fixed during proof

**Bug 1 — Wrong TLV tags in plugin.cpp:**
`EXPORT_KEY` response uses tags `0x80` (pubkey, 65B) and `0x82` (chain code, 32B) inside the `0xA1` template. Plugin was using `0x81` and `0x83` — found nothing, silently failed.

**Bug 2 — Two-step derive+export doesn't preserve chain code:**
`DERIVE_KEY` followed by `EXPORT_KEY P1=0x00 P2=0x02` returns `0x6985`. The firmware stores the derived private key but NOT the chain code in the "current key" state. Fix: use one-step `EXPORT_KEY P1=0x01 (derive+from_master)` for public-key-only exports.

### Firmware chain code export restriction

| Path | `P2=0x02` (extended, +chain code) | `P2=0x01` (pubkey only) |
|------|-----------------------------------|------------------------|
| master (`m/`) | SW=0x9000, **but chain code = all zeros** | SW=0x9000 ✓ |
| `m/43'/60'/1581'` (EIP-1581 root, 3 levels) | SW=0x9000 ✓ **real chain code** | SW=0x9000 ✓ |
| `m/43'/60'/1581'/A'/B'/C'/D'` (7 levels hardened) | SW=0x6985 ✗ | SW=0x9000 ✓ |

**Firmware only allows chain code export at the EIP-1581 root depth (3 levels).**

### Correct XPUB Export Architecture

**For domain-specific public key** (signing verification, key lookup):
- Use `EXPORT_KEY P1=derive P2=0x01 (PUBLIC_ONLY)` at the domain path `m/43'/60'/1581'/<A>'/<B>'/<C>'/<D>'`
- Returns 65-byte uncompressed public key, no chain code
- This is what `approveXPUB` and `testXPUBExport` now do

**For watch-only XPUB** (offline child key derivation, full BIP32 xpub):
- Export at `m/43'/60'/1581'` (EIP-1581 root) → real pubkey + real chain code
- `testEip1581Export(pin)` demonstrates this
- Use `testEip1581Export` or implement `requestXPUBRoot` for this use case
- Client can then derive child public keys offline using UNHARDENED BIP32 derivation

**For domain-path derivation from the EIP-1581 XPUB:**
- Change `domainToPath()` to return UNHARDENED indices (no `'`) for the 4 domain-specific components
- Then client-side BIP32 public child derivation works
- This is a future improvement; current API uses hardened (more secure, but no offline derivation)

### Proof Binary

`tests/xpub_proof.cpp` — full end-to-end hardware proof:
1. `discoverReader` → `discoverCard` → `checkPairing` → `authorize`
2. `removeKey` (clears old key) → `loadKey(bip39_seed)` (stores master + chain code)
3. `testMasterExport` → proves BIP39 load works, chain code exported as zeros at master level
4. `testEip1581Export` → proves real chain code `8d8a4740...` available at `m/43'/60'/1581'`
5. `testXPUBExport("test-domain")` → proves domain pubkey export works at 7-level hardened path
