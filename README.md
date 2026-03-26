# keycard-basecamp

Standalone Keycard smartcard authentication module for Logos Basecamp.

## Overview

This module provides smartcard authentication primitives for the Logos Basecamp ecosystem. Any Basecamp app can consume Keycard functionality via `logos.callModule("keycard", ...)`.

**Status:** ✅ Core operations working, hardware tested

## Architecture

Built on **keycard-qt** (native C++/Qt library) for direct PC/SC smart card communication:

- **keycard-core**: C++ module with native keycard-qt integration, state machine, and on-card BIP32 key derivation
- **keycard-ui**: QML debug UI for testing state machine transitions

**Migration:** Migrated from libkeycard.so (CGO/14MB) to keycard-qt (native/~4-5MB) - 70% size reduction

## Features

**Core Operations:**
- ✅ Reader and card auto-detection
- ✅ Card pairing with pairing password (persistent storage)
- ✅ PIN verification with retry tracking
- ✅ On-card BIP32 key derivation (EIP-1581 standard)
- ✅ Domain-based key isolation (deterministic path mapping)
- ✅ Session management (authorize, derive, close)

**Security Properties:**
- ✅ PIN verification on-card (never leaves device)
- ✅ BIP32 key derivation on-card (EIP-1581 compliant)
- ✅ Domain separation via deterministic paths (no custom crypto)
- ✅ Secure memory wiping (sodium_memzero)
- ✅ Card UID verification (prevents card-swap attacks)
- ✅ Standards-compliant derivation (interoperable with Keycard ecosystem)

## Documentation

See [SPEC.md](SPEC.md) for complete implementation specification.

## Development

### Clone

```bash
# Simple clone (keycard-qt will be fetched automatically during build)
git clone https://github.com/xAlisher/keycard-basecamp.git

# Or with submodules for offline builds (optional)
git clone --recursive https://github.com/xAlisher/keycard-basecamp.git
```

### Build

**With Nix:**
```bash
nix build
```

**With CMake (manual):**
```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

**Note:** keycard-qt dependency is fetched automatically via CMake FetchContent if not present as a submodule.

### Package LGX

Create distributable LGX packages:

```bash
nix run .#package-lgx
```

Produces:
- `keycard-core.lgx` - Core module with dependencies (libpcsclite removed for system compatibility)
- `keycard-ui.lgx` - QML UI plugin

**Individual packages:**
```bash
nix build .#lib  # Build core module only
nix build .#ui   # Build UI plugin only
```

### Testing

**Headless backend testing (logoscore):**
```bash
# Test module without UI (fast iteration)
nix run .#test-with-logoscore
```

**Isolated UI testing (logos-standalone-app):**
```bash
# Test QML UI without full Basecamp shell
nix run .#test-ui-standalone
```

**Module introspection (lm CLI):**
```bash
# Inspect module structure, methods, and metadata
nix run .#inspect-module
```

All testing tools are pinned to specific versions in `flake.nix` for reproducibility.

### Install to Basecamp Dev

```bash
cmake --install build --prefix ~/.local/share/Logos/LogosBasecampDev
```

## Implementation

Initially based on KeycardBridge from [logos-notes](https://github.com/xAlisher/logos-notes), now fully migrated to native [keycard-qt](https://github.com/status-im/keycard-qt) library for better performance and smaller binary size.

## License

TBD
