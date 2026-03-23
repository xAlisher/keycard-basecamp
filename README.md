# keycard-basecamp

Standalone Keycard smartcard authentication module for Logos Basecamp.

## Overview

This module provides smartcard authentication primitives for the Logos Basecamp ecosystem. Any Basecamp app can consume Keycard functionality via `logos.callModule("keycard", ...)`.

**Status:** 🚧 In development

## Architecture

- **keycard-core**: C++ module with PC/SC smartcard integration, state machine, and key derivation
- **keycard-ui**: QML debug UI for testing state machine transitions

## Security Properties

✅ PIN verification on-card
✅ BIP32 key derivation on-card
✅ Domain separation for multi-app support
✅ Secure memory wiping (sodium_memzero)
✅ Card UID verification (prevents card-swap attacks)

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

```bash
nix run .#package-lgx
```

### Install to Basecamp Dev

```bash
cmake --install build --prefix ~/.local/share/Logos/LogosBasecampDev
```

## Source

Keycard logic ported from [logos-notes](https://github.com/xAlisher/logos-notes) KeycardBridge implementation.

## License

TBD
