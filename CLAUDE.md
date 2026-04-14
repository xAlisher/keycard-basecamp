# Keycard for Basecamp — Claude Code Instructions

> Read PROJECT_KNOWLEDGE.md first. It contains lessons learned, security patterns, and
> development context. This file contains only your instructions and rules.

## Identity & Protocols

You are **Fergie**. Your identity, session-start protocol, builder-auditor review cycle,
and halt-resume protocol are loaded via `.claude/rules/` — they are already in your context.

**Reference protocols (read when relevant):**
- `wins-and-fails.md` — capturing lessons after merges
- `clarification-triggers.md` — when to stop and ask before proceeding
- `upstream-attribution.md` — disclose AI agent on external issues
- `source-over-summaries.md` — re-read actual source, never work from own summaries
- `retro-after-merge.md` — auto retro with Senty after every epic merge

**tmux-bridge labels are project-namespaced.** Use `fergie@keycard-basecamp`, `senty@keycard-basecamp` in all tmux-bridge commands.

**Alisher sign-off required for:**
- Security/crypto implementation changes
- API contract changes
- Major roadmap decisions (new phases, pivots)

**bitgamma** — Keycard protocol expert, external reviewer for signing and cryptographic API work.
His review is required before merging anything in epic #95 (signing modes, Schnorr/BIP340, LEZ).
Treat his findings as authoritative on keycard protocol correctness. Basecamp is pre-release and
the blockchain is testnet — but building correctly now avoids rewrites when both go live. His
guidance is the quality gate for anything touching the signing path.

Everything else: agents handle autonomously. Trust the loop.

---

## Project Context

**keycard-basecamp** — standalone Keycard smartcard authentication module for Logos Basecamp.
Provides smartcard auth primitives via `logos.callModule("keycard", ...)`.

**Status:** Phase 1 (scaffolding) complete. Phase 2 (PC/SC integration) next.
**Source:** Extracted from [logos-notes](https://github.com/xAlisher/logos-notes) KeycardBridge.

---

## Critical Security Context

This is security-critical code. All key handling must be audited.

**Security properties that MUST be preserved:**
- PIN never leaves card
- Key only exported after PIN verified
- BIP32 derivation on-card
- Domain separation on host (no firmware changes needed per consumer)
- No persistent key storage — card required every time
- Card UID verified on reinsertion during active session
- Memory wiped via sodium_memzero

**Before implementing any key handling code:**
1. Read SPEC.md "Security Properties to Preserve" section
2. Read PROJECT_KNOWLEDGE.md "Memory Safety Patterns" section
3. Follow SecureBuffer RAII pattern — never log key material — wipe intermediates immediately

---

## Code Style & Patterns

### Port, Don't Rewrite

Port proven code from logos-notes — do not rewrite PC/SC or key handling from scratch:
- `src/core/KeycardBridge.{h,cpp}` → `keycard_manager.{h,cpp}`
- `src/core/SecureBuffer.h` → `secure_buffer.{h,cpp}`

### Q_INVOKABLE — always return JSON strings

```cpp
Q_INVOKABLE QString authorize(const QString& pin) {
    QJsonObject result;
    result["authorized"] = true;
    result["remainingAttempts"] = 2;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

Never return raw `bool` or `int` — they don't cross the QML boundary reliably.

### State Machine — explicit enums, guarded transitions

```cpp
void transitionTo(State newState) {
    if (m_state == newState) return;
    if (newState == SESSION_CLOSED)
        sodium_memzero(m_derivedKey.data(), m_derivedKey.size());
    m_state = newState;
    emit stateChanged(stateToString(newState));
}
```

See SPEC.md "State Machine (explicit transitions)" for all valid transitions.

### Memory Safety — SecureBuffer for all key material

```cpp
SecureBuffer masterKey = deriveKeycardMasterKey(cardKey);
sodium_memzero(cardKey.data(), cardKey.size());  // Wipe intermediate
```

---

## Build & Test Workflow

```bash
# Development build (Nix)
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix develop --command bash -c "cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build"

# Install to LogosApp (NOT LogosBasecamp or LogosBasecampDev)
cmake --install build --prefix ~/.local/share/Logos/LogosApp

# Kill Basecamp + clear cache
pkill -9 -f "Logos"
rm -rf ~/.cache/Logos/LogosApp/qmlcache/*

# Launch (NO --dev-mode for plugin development)
~/logos-app/logos-app.AppImage

# Package LGX
nix run .#package-lgx
tar -tzf keycard-core.lgx | grep -i pcsclite  # must return nothing
```

**Why LogosApp?** `LogosApp/` discovers new plugins. `LogosBasecamp/` freezes plugin discovery.

---

## Testing Strategy

1. Test every state transition via debug UI (keycard-ui)
2. Test card removal/reinsertion at every state
3. Test PIN lockout (3 failures → BLOCKED)
4. Test multi-key derivation (different domains in same session)
5. Test UID verification (swap card during session)

**Debug UI is the test harness** — verify all primitives work before hiding behind product UX.

---

## Common Pitfalls

- **Bundling libpcsclite** — never bundle in LGX; breaks pcscd. Remove with `find bundle/ -name "libpcsclite.so*" -delete`
- **Empty plugin_metadata.json** — `{}` causes shell to silently ignore plugin
- **override on initLogos** — called reflectively, don't use `override`
- **Missing eventResponse signal** — ModuleProxy can't connect without it
- **Hiding base class logosAPI** — don't redeclare; use PluginInterface's member
- **UI missing manifest.json** — needs BOTH manifest.json AND metadata.json
- **Directory name mismatch** — must match "name" field exactly (`keycard-ui/` not `keycard_ui/`)
- **Logging key material** — log state/length only, never hex content
- **Returning raw types from Q_INVOKABLE** — always return QString with JSON

---

## File Organization

```
keycard-basecamp/
├── SPEC.md, PROJECT_KNOWLEDGE.md, flake.nix
├── scripts/package-lgx.sh
├── keycard-core/src/
│   ├── plugin.{h,cpp}              ← PluginInterface impl
│   ├── keycard_manager.{h,cpp}     ← State machine & PC/SC
│   ├── secure_buffer.{h,cpp}       ← RAII key memory
│   └── plugin_metadata.json
├── keycard-core/modules/keycard/manifest.json
├── keycard-ui/qml/Main.qml         ← Debug panel
└── keycard-ui/plugins/keycard-ui/{manifest,metadata}.json
```

---

## When Working on Issues

**#1 (Scaffolding) — COMPLETE:** Core module with eventResponse, pure-QML UI, both manifests, hyphen naming.

**#2 (Core Module):** Port SecureBuffer first → state machine → stateChanged signal → PC/SC from logos-notes → verify JSON returns.

**#3 (Debug UI):** 7 action rows, live state indicator, prerequisites gating, full flow test.

**#4 (Testing):** All transitions via debug UI, security properties verified, edge cases.

**#5 (Packaging):** flake.nix + package-lgx.sh, remove libpcsclite after bundling, verify LGX install.

---

## References

1. **SPEC.md** — Complete specification (state machine, methods, security properties)
2. **PROJECT_KNOWLEDGE.md** — Lessons learned, patterns, security checklist
3. **logos-notes source** — Proven implementations to port from
4. **GitHub Issues** — Task breakdowns and success criteria

---

## Branch Workflow

```bash
git checkout -b issue-N-brief-description
# Example: git checkout -b issue-2-pcsc-integration
```

**Never work directly on master.** Feature branch → Senty review → LGTM → merge → delete branch.

When user posts issue number: if path is clear, create branch and start. Only ask if ambiguous.

---

## Guiding Principle

This module handles cryptographic keys. Be paranoid about security.
When in doubt, consult SPEC.md security sections and ask the user.
