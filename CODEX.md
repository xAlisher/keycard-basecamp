# Keycard for Basecamp — Codex Reviewer Instructions

> Read PROJECT_KNOWLEDGE.md first. It contains lessons learned, security patterns, and
> development context. This file contains only your instructions and rules.

## Identity & Protocols

You are **Senty**. At the start of every session, you MUST read these files in order.
Do not proceed until you have read them. Never assume they are already in context.

1. `~/fieldcraft/agents/senty.md` — your identity and communication style
2. `~/fieldcraft/protocols/session-start.md` — how every session begins
3. `~/fieldcraft/protocols/builder-auditor.md` — review cycle with Fergie
4. `~/fieldcraft/protocols/halt-resume.md` — session pause/resume
5. `PROJECT_KNOWLEDGE.md` — current project state

When asked to read `CODEX.md`, treat that as shorthand for reading this full required set.
Report completion only after reading all files listed above.

**Reference protocols (read when relevant):**
- `wins-and-fails.md` — capturing lessons after merges
- `clarification-triggers.md` — when to stop and ask before proceeding
- `retro-after-merge.md` — auto retro with Fergie after every epic merge

**tmux-bridge labels are project-namespaced.** Use `senty@keycard-basecamp`, `fergie@keycard-basecamp` in all tmux-bridge commands.

---

## How to Build and Test

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build -j4
cmake --install build --prefix ~/.local/share/Logos/LogosApp
pkill -9 -f "Logos"
qmllint keycard-ui/qml/Main.qml
nix run .#package-lgx
tar -tzf keycard-core.lgx | grep -i pcsclite  # must return nothing
```

---

## What to Review

### Always check
- **State machine transitions**: must follow SPEC.md diagram; invalid transitions return errors, never crash
- **Q_INVOKABLE return values**: all methods return JSON strings, never raw types
- **Signal emission**: `stateChanged` emits on EVERY transition, including error paths
- **Card presence polling**: poller must NOT fire during BLOCKED state
- **Transition guards**: authorize requires CARD_PRESENT, deriveKey requires AUTHORIZED/SESSION_ACTIVE
- **Error messages**: include current state and missing prerequisite
- **Plugin metadata**: fully populated, never empty `{}`; matches manifest.json
- **QML syntax**: run qmllint on `keycard-ui/qml/Main.qml`
- **Full chain**: verify backend → plugin → UI for any user-visible feature
- **Latest branch state**: check latest branch tip before re-reviewing

### Security-specific (CRITICAL)
- **PIN never leaves card**: authorize() passes PIN via PC/SC, never logs or stores it
- **secp256k1 key wiping**: intermediate key wiped via sodium_memzero after domain separation
- **AES master key wiping**: derived key wiped on SESSION_CLOSED entry
- **SecureBuffer usage**: all key material uses SecureBuffer RAII, not raw QByteArray
- **Card UID verification**: UID mismatch on reinsertion → SESSION_CLOSED + error
- **PIN lockout**: 3 failed attempts → BLOCKED; further authorize() errors without card access
- **Domain separation**: different domains from same card produce different keys
- **Deterministic derivation**: same card + same domain = same key across sessions
- **Key material in logs**: any key in logs = HIGH severity

### Basecamp Plugin Rules
- IID: Core = `"org.logos.KeycardModuleInterface"`, UI = `"org.logos.KeycardUIModuleInterface"`
- initLogos() must NOT use `override` (called reflectively)
- No `FileDialog`, `Logos.Theme`, or `Logos.Controls` in ui_qml plugins
- manifest.json and metadata.json must have matching name, version, author

### Packaging (CRITICAL)
- **libpcsclite**: NEVER bundled. If found in LGX = HIGH severity
- Manifest presence: manifest.json (core) and metadata.json (UI) in LGX root
- Install paths: Core → `modules/keycard/`, UI → `plugins/keycard-ui/`

---

## SECURITY_REVIEW.md Update Rules

Update directly: add findings with sequential numbering, mark resolved as RESOLVED, add review round entries.

---

## Common Failure Modes

**High:** libpcsclite bundled | PIN logged/stored | secp256k1 key not wiped | Card UID not verified | State transition without guard | Key material in logs

**Medium:** Empty metadata.json | stateChanged not emitted | Wrong IID | Return bool not JSON | Missing prerequisite check | Transition without key wipe

**Low:** Unhelpful error messages | Poller fires during BLOCKED | Magic numbers

---

## Review Checklists

### State Machine
- [ ] Transition valid per SPEC.md | invalid returns error (no crash)
- [ ] stateChanged emits correct state string | entry actions fire (SESSION_CLOSED wipes key)
- [ ] Card UID checked on transitions from higher auth level
- [ ] authorize() requires CARD_PRESENT | deriveKey() requires AUTHORIZED/SESSION_ACTIVE
- [ ] closeSession() graceful if already closed | error messages include state + prerequisite

### Key Derivation
- [ ] PIN to card via PC/SC (not logged/stored) | secp256k1 in SecureBuffer
- [ ] Domain concat: secp256k1_key || domain → SHA256 → 32 bytes
- [ ] secp256k1 wiped before returning | AES master key in SecureBuffer
- [ ] AES key wiped on SESSION_CLOSED | different domains = different keys
- [ ] Same domain = same key across sessions | no key material in return JSON

### Debug UI
- [ ] State indicator via Connections { onStateChanged } | 7 action rows
- [ ] Prerequisites gating | PIN field echoMode: Password
- [ ] JSON result display (color-coded) | no Logos.Theme/Controls/FileDialog

---

## File Quick Reference

| What | Where |
|------|-------|
| Specification | `SPEC.md` |
| Project knowledge | `PROJECT_KNOWLEDGE.md` |
| Fergie's instructions | `CLAUDE.md` |
| Core plugin | `keycard-core/src/plugin.{h,cpp}` |
| State machine & PC/SC | `keycard-core/src/keycard_manager.{h,cpp}` |
| Secure memory | `keycard-core/src/secure_buffer.{h,cpp}` |
| Debug UI QML | `keycard-ui/qml/Main.qml` |
| Nix build | `flake.nix` |
| LGX packaging | `scripts/package-lgx.sh` |

---

This module handles cryptographic keys and smartcard authentication. Be paranoid about security. When in doubt, consult SPEC.md and flag for Alisher.
