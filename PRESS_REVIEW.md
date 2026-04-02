# Keycard Module for Logos Basecamp — Press Review

People and agents are already extending Logos Basecamp.

A new module lead by @alisher brings @Keycard_ into the ecosystem.

Keycard is a hardware smartcard for cryptographic key management and hardware wallet:
- Private keys stored on a secure element
- Key derivation happens on-chip via BIP32
- Your master key never leaves the card — only the specific derived key you approve is returned to the requesting module

Keycard module shifting key management from software to hardware, while staying within Logos:

It's simpler and safer.

Keys stay on a dedicated secure device.

Current version built for one purpose: deterministic key derivation.

You can use your Keycard to derive unique encryption keys for any module in the ecosystem.

No module gets key access unless you explicitly approve the request, and even then it receives only the derived key you approved, not your master key.

## How it works

The Keycard module acts as a hardware deterministic key generator for Logos.

Any module can request a key for a specific domain.

- A request is surfaced in keycard-ui
- User inserts the card and enters their PIN
- The card derives a unique key on-chip using BIP32 (EIP-1581 standard)
- The derived key is returned to the requesting module
- Session closes immediately

Each request is one-time and requires explicit user approval. Same domain always produces the same key — deterministic and reproducible.

## Why this matters

In most ecosystems, keys are tied to a wallet, and the wallet becomes the gateway to everything.

With the Keycard module, keys sit outside the entire Logos app layer.

Any Logos module can request a key, but none of them own it. The key lives in memory only for the active session — never written to disk. To use it again, the module must go back through the user.

That keeps modules lightweight and removes the need to build key management into every app.

Because keys are derived per domain, each module operates with its own isolated keyspace:

A notes app, a storage module, or a governance tool — each gets a separate key, derived from the same card, reproducible when needed.

The Keycard module behaves like any other Logos module:

- It can be combined with other modules
- It can be extended
- It can be swapped out

Where keys live defines who's in control. Keep them external, portable, and only usable with your approval — the rest of the system can evolve freely without sacrificing user control.

## Current Status

This is an experimental project in active development, built as part of the Basecamp ecosystem which is itself evolving. The module demonstrates hardware key derivation for the Logos modular architecture and is being used to explore integration patterns for other module developers.

**What's working today:**
- Hardware key derivation via USB smartcard reader
- Cross-module authorization flow (notes module integration live)
- Drop-in QML component for module developers
- API documentation and integration guide

**What's next:**
- Card removal detection and session management
- Testing against latest Basecamp releases
- Event-based cross-module notifications

## The Frontier is Yours

The greatest expeditions start at Basecamp. It's your staging ground for everything that follows.

Modules like this expand what's possible.

And that's the point.

If you want something different, you don't wait.
You build it: [Build.logos.co](https://build.logos.co)

