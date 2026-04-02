# keycard-basecamp

Hardware deterministic key generator for Logos Basecamp.

Think of it like a password manager — but there's no vault, no master password, no cloud. One smartcard derives infinite unique keys, one per domain, always reproducible, never stored anywhere. It's sovereign — you hold the card, you hold the keys. And it's crypto-ready — BIP32 derivation, the same standard used by hardware wallets.

**Status:** ✅ v1.0.0 released — [Download LGX packages](https://github.com/xAlisher/keycard-basecamp/releases/tag/v1.0.0)

## How It Works

Any Basecamp module can request a key:

```
Module calls requestAuth("notes_private", "notes")
  → User sees request in keycard-ui
  → User enters PIN on physical smartcard
  → Card derives unique key for that domain (on-chip BIP32)
  → Key returned to requesting module
  → Session closes automatically
```

One card, infinite keys. Each derived deterministically from the domain — same domain always produces the same key.

## Architecture

- **keycard-core** — C++ plugin with native [keycard-qt](https://github.com/status-im/keycard-qt) integration, on-card BIP32 key derivation, encrypted pairing storage
- **keycard-ui** — Single-screen QML UI: "No pending requests" or request card + PIN + approve/decline
- **auth_showcase** — Demo module showing how to integrate with keycard

## Security

- PIN verified on-card (never leaves device)
- BIP32 key derivation on-card (EIP-1581 compliant)
- Domain separation via deterministic paths (no custom crypto)
- Pairing keys encrypted on disk (Argon2id + XSalsa20-Poly1305)
- Secure memory wiping (sodium_memzero)
- Card UID verification (prevents card-swap attacks)
- No persistent sessions — one approval, one key, session closes

## Development

### Prerequisites

- [Nix](https://nixos.org/download.html) (for reproducible builds)
- PC/SC smart card reader + [Keycard](https://keycard.tech/)

### Build

```bash
nix develop
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

### Install & Run

```bash
cmake --install build --prefix ~/.local/share/Logos/LogosApp
```

### Package LGX

```bash
mkdir -p dist && nix run .#package-lgx -- dist/
```

Produces:
- `keycard-core.lgx` — Core module (no bundled libpcsclite)
- `keycard-ui.lgx` — All QML files, icons, metadata

### Testing Tools

```bash
nix run .#test-with-logoscore   # Headless backend testing
nix run .#test-ui-standalone    # Isolated UI testing
nix run .#inspect-module        # Module introspection (lm CLI)
```

## Integration

Any Basecamp module can use keycard for key derivation:

```javascript
// 1. Request authorization
var result = logos.callModule("keycard", "requestAuth", ["my_domain", "my_module"])
var authId = JSON.parse(result).authId

// 2. Poll for completion (user approves in keycard-ui)
var status = logos.callModule("keycard", "checkAuthStatus", [authId])
var obj = JSON.parse(status)
if (obj.status === "complete") {
    var key = obj.key  // Hardware-derived key for "my_domain"
}
```

## Documentation

- [SPEC.md](SPEC.md) — Complete specification
- [PROJECT_KNOWLEDGE.md](PROJECT_KNOWLEDGE.md) — Lessons learned
- [WORKFLOW.md](WORKFLOW.md) — Fergie/Senty collaboration workflow

## License

MIT
