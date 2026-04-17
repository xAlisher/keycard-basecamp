# Keycard Is Now a Basecamp Module

People are already extending Basecamp.

A new module by [@alisher](https://github.com/xAlisher) brings [Keycard](https://keycard.tech) into the ecosystem — a hardware wallet in smartcard form, now usable by any Basecamp module.

Keycard is a smartcard with a secure element onboard. Private keys live on the card. They never leave it. Signing happens on-chip.

> **Experimental.** This module is in active development — for testing and development use only. Not ready for production.

---

## Signing from any module

The primary thing the Keycard module unlocks is **hardware-backed signing** — available to any module in the stack, without that module having to manage keys.

Here is what happens when a module requests a signature:

1. The module hashes its payload and calls `requestSign` with a domain, the hash, and a scheme (Schnorr or ECDSA)
2. A pending request surfaces in keycard-ui
3. The user taps the card and enters their PIN
4. The card derives the signing key on-chip at a domain-specific BIP32 path and signs — with ECDSA or Schnorr, whichever the module requested. The private key never leaves the card
5. The signature is returned to the requesting module exactly once, then wiped from host memory

Each signing request is discrete. It requires the card and the PIN. Nothing in the Basecamp app layer can sign on a module's behalf, or sign twice from a single approval.

---

## How the key stays on the card

BIP32 derivation runs on the card's secure element. The module supplies a domain string — `requestSign` maps it to a deterministic BIP32 path. The card derives the key at that path on-chip and signs with it, using either ECDSA or Schnorr (BIP340). Both schemes are supported; the requesting module specifies which. No private key material is ever exported to the host.

Same card, same domain, same key every time. Different domains produce different keys. A messaging module and a governance module each sign with their own isolated keyspace, derived from the same card.

---

## Private key generation is also available

Beyond signing, modules can request a derived private key directly — for local encryption. The flow is the same: `requestAuth` queues a request, the user approves in keycard-ui, and the derived private key is exported from the card, returned to the module once, and wiped immediately after the caller reads it.

These keys come from EIP-1581 paths — and that matters: the Keycard applet only allows export of keys derived at EIP-1581 paths. This is enforced card-side. Signing deliberately uses a different path, so the key used to sign can never be exported, even if a module tried.

This is useful when a module needs to encrypt local data without storing any key material. The key exists in host memory for the duration of a single read, then it's gone.

---

## What changes for the rest of the stack

Modules stay lightweight. No module has to implement key management. No module stores key material. None of them can reuse a key without going back through the user — card in hand.

The Keycard module behaves like any other Basecamp module: it can be combined, extended, or swapped out. It makes no assumptions about what else is running.

---

## Where control lives

Keys managed in software can be copied, leaked, or held hostage by the app that manages them.

Keys that live on a dedicated hardware device — derived on-chip, signed on-chip, never exported — remove that class of risk from the application layer entirely. Modules stay small. Users stay in control. The card is the authority.

---

The greatest expeditions start at Basecamp.

If you want something that doesn't exist yet, you don't wait.

**[Build it → build.logos.co](https://build.logos.co)**

---

| [Try the showcase →](https://github.com/xAlisher/keycard-basecamp/blob/master/docs/INSTALL.md) | [Integration guide →](https://github.com/xAlisher/keycard-basecamp/blob/master/INTEGRATION_GUIDE.md) |
|---|---|
