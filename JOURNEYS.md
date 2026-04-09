# Keycard Journeys

Product-level framing of what `keycard-basecamp` enables for Basecamp users, developers, and node operators. For the technical contract see [KEYCARD_API.md](KEYCARD_API.md); for the state machine and security properties see [SPEC.md](SPEC.md); for step-by-step integration see [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md).

---

## What this module is

`keycard-basecamp` is a **Basecamp module that exposes Keycard smartcard primitives** (card discovery, PIN verification, on-card BIP32 key derivation, session lifecycle) via `logos.callModule("keycard", ...)`.

It is **not** a wallet, not an identity product, not an end-user application. It is an auth and key-derivation service that any Basecamp module can consume. The only UI it ships is `keycard-ui` — a single-screen approval panel where the user enters their PIN and approves incoming requests from other modules.

---

## For designers / product

If you are reading this to understand what Keycard *feels like* rather than how it is wired, start here. The rest of the document is for engineers.

### The mental model: hardware SSO

Think of Keycard as **single sign-on, but for hardware**. Any Basecamp module that needs a cryptographic key can ask the Keycard module for one. The user approves the request by entering their PIN on a physical smartcard. One module, one approval UI, many consumers.

It is **not** a wallet. It has no product screens of its own besides a small approval panel. The wallet, notes, LEZ — those are separate apps that *consume* Keycard for their auth needs.

### The UX principle: one approval surface

Imagine if every iOS app built its own Face ID prompt, with its own look, its own error states, its own "try again" copy. That would be chaos. iOS has **one** Face ID sheet, and every app triggers it the same way.

That is what Keycard does in Basecamp. There is **one approval panel** (`keycard-ui`). When any module — notes, wallet, LEZ, anything — needs hardware-backed auth, the user sees the same panel. Same visual language, same PIN field, same "X attempts remaining" copy. **The user learns Keycard once, and it works the same everywhere.**

(Target state note: the shipped approval panel covers PIN entry, wrong-PIN retry, and approve / decline. Pairing and blocked-card recovery flows currently live in the debug UI rather than the production approval panel, and are planned to graduate into the unified approval surface as the product hardens. This doc describes where we're going; implementation is still catching up in those specific corners.)

If every Basecamp module shipped its own Keycard integration, users would see a different PIN prompt in every app. Same hardware, inconsistent experience. We do not want that.

### The handoff pattern

The consuming app is responsible for *asking* ("please approve") and *showing the result* ("encrypted ✓"). The Keycard panel is responsible for *the PIN moment*. Clean handoff, clean handback.

```
Consuming app          Keycard approval panel          Consuming app
   "sign this"    →       "enter your PIN"       →       "signed ✓"
```

The consuming app never sees the PIN. The Keycard panel never knows what the user is signing or encrypting — it only knows "notes is asking for a key scoped to notes_encryption" and shows that to the user before asking for PIN approval.

### The three journeys, in product language

**1. User journey** — "I want to do a thing in a Basecamp app, and that thing needs my Keycard."
The user is inside an app. They hit a button that needs hardware auth — encrypt this note, sign this LEZ transaction. The app tells them "approve on Keycard". They glance at the approval panel, enter their PIN, approve. Key flows back to the original app, which uses it and forgets it.

**2. Developer journey** — "I am building a Basecamp module and I need hardware keys."
Not a user journey, but a developer one. The module author adds one dependency, makes one API call, polls for the result. They get a key that is deterministic (same request always produces the same key) and isolated (other modules get different keys from the same card). They never have to think about PINs, readers, lockout, recovery, or any of it. **This matters for UX because it means hardware auth becomes a default option for every Basecamp module, not a heroic integration that only one or two apps can afford to build.**

**3. Node operator journey** — "I run a Logos node and I want its identity bound to a physical card."
Rare but important. A node has an identity key. Normally that sits on disk; anyone who steals the disk steals the identity. With Keycard, the key is derived on-card every time the node needs it. Lose the card, lose access. Keep the card, keep the identity. Same primitives as the user journey, different consumer.

### LEZ, disambiguated

"LEZ" — **Logos Execution Zone** — means two different things depending on who says it, and the user-facing story is different for each. This matters for the journeys doc because if we conflate them we confuse the reader.

**Layer 1: the LEZ wallet** — a Basecamp app that users actually touch. Shows LEZ accounts, balances, lets them send transfers. This is a normal Basecamp app, and it is the natural Keycard consumer. **This is what the Logos journeys doc should describe under "LEZ".** When a user signs a LEZ transaction with their Keycard, the flow is identical to signing anything else with their Keycard. Same panel, same PIN moment, same mental model.

**Layer 2: the LEZ programs themselves** — zero-knowledge smart contracts running inside a zkVM. RLN, multisig, atomic swaps. These live on-chain and **cannot talk to a physical card at all** — no USB inside a zkVM. They only see what the wallet hands them: signatures, commitments, proofs.

Subtle but important: the zkVM programs can still *benefit* from Keycard, just indirectly. The wallet uses Keycard to derive a key, uses that key to produce a signature or an identity commitment, and hands it to the on-chain program. The program verifies it — it has no idea a Keycard was involved. Same way Ethereum contracts don't know what a Ledger is.

Concrete example, because it is a great story: a user's RLN membership (think "anti-spam quota for a decentralized service") can be tied to a secret that only their Keycard can reproduce. Lose the card → can't post. Have the card → can post. The zkVM program sees none of this; it just checks a commitment. From a user perspective this is an extraordinary property — **your ability to participate in a Logos service is physically gated on a piece of hardware in your pocket** — but it all happens through the wallet UX, not through any new Keycard surface.

### Why "don't fork Keycard in LEZ" is a UX decision, not just a security one

This was raised in a Discord thread as an architectural / security ask. It is those things, but it is also fundamentally a UX decision:

- **Mental model consistency.** If the LEZ wallet had its own Keycard prompt and the notes app had a different one, users would have to learn Keycard twice. They wouldn't — they'd just be confused, and some would decide Keycard is broken.
- **Error recovery consistency.** What happens when the PIN is wrong? When the card is removed mid-transaction? When the card is blocked? These are high-stakes, high-anxiety moments. They should look and feel the same everywhere.
- **Trust consistency.** Users should know there is exactly **one place** where their PIN is typed. If there are multiple Keycard integrations, the user can't be sure which one is legitimate. One approval panel is a security property *and* a trust-UX property.

In product terms: **there is exactly one Keycard experience in Basecamp, and LEZ participates in it rather than inventing a parallel one.**

### What this means for a Logos-wide journeys doc

If you are writing the Logos-wide journeys document and you need the Keycard section:

- **Do** describe Keycard as a cross-cutting capability that appears inside specific consuming apps (LEZ wallet, notes, node tooling), not as its own user destination.
- **Do** describe the approval moment as a consistent, shared UI that users learn once.
- **Do** call out the "hardware-gated participation" story for LEZ + RLN — it is genuinely distinctive.
- **Don't** describe Keycard as an app users "use" directly. They use it inside other apps.
- **Don't** conflate the LEZ wallet with LEZ on-chain programs. The Keycard story is about the wallet.
- **Don't** imply LEZ-wallet + Keycard integration is shipped today. It is an architectural direction; scheduling is a roadmap conversation.

---

## Architectural principle: one module, many consumers

**Domain separation happens on the host, not in firmware.**

Each consuming module passes a domain string (e.g. `"notes_encryption"`, `"wallet_signing"`, `"lez_identity"`). The Keycard module maps that domain deterministically to an EIP-1581 BIP32 path and derives the key on-card. Same card + same domain always produces the same key; different domains produce different keys.

This is the load-bearing design decision: **no consumer ever needs its own Keycard integration**. One audited PC/SC surface, one PIN-lockout state machine, one place to patch security issues. Forking per consumer would break all three.

**Implication for LEZ and any future Keycard consumer:** consume this module via `callModule`. Do not reimplement.

---

## Journey 1 — User: "Authorize an action in a Basecamp module with my Keycard"

**Who:** A Basecamp user who owns a Keycard and wants to use a Basecamp module (wallet, notes, LEZ client, etc.) that supports hardware-backed keys.

**Flow:**
1. User plugs in a USB smartcard reader and inserts their Keycard.
2. User performs an action in a consuming app (e.g. "encrypt this note", "sign this transaction", "unlock this identity").
3. The consuming app calls `requestAuth` on the Keycard module with its own domain tag.
4. User sees the pending request appear in `keycard-ui` — the Keycard module's approval panel — showing which module is asking and for what domain.
5. User enters their PIN on the approval panel and approves (or declines).
6. On approval: the card verifies the PIN on-chip, derives the domain-specific key via BIP32, and returns it to the requesting module. The session is marked closed so a subsequent operation requires a new `requestAuth`.
7. The consuming app uses the key for its operation and wipes its own copy. (The Keycard module itself currently still holds the derived key in its auth-request table until module unload — see [#94](https://github.com/xAlisher/keycard-basecamp/issues/94). Tightening this to a one-read-and-drop semantics is a known follow-up.)

**What the user sees:** the consuming app's normal UI, plus a brief excursion to `keycard-ui` to approve the request. The PIN is entered in `keycard-ui` and never reaches the consuming app.

**Failure modes the user may encounter:**
- **No reader / no card** → consuming app shows "connect your Keycard".
- **Wrong PIN** → `keycard-ui` shows remaining attempts in the activity log; card is not blocked until the third failure. The request stays in `pending` on the consumer API side so the consumer keeps waiting rather than being handed a terminal failure.
- **Card blocked** (3 wrong PINs) → the card enters PIN-lockout. Recovery via PUK is the standard Keycard path and currently sits in the debug UI rather than the production approval panel (see the target-state note under "one approval surface").
- **Card removed mid-session** → the session is marked closed and a fresh `requestAuth` is required on the next operation. The consuming app should also wipe any key copy it took. Module-side key cleanup is tracked in [#94](https://github.com/xAlisher/keycard-basecamp/issues/94).
- **Declined** → consumer API sees `status: "rejected"`; consuming app shows "authorization declined".

**Where the UI lives:** in each consuming app, plus the shared `keycard-ui` approval panel. `keycard-basecamp` itself does not ship any product UI beyond that panel.

---

## Journey 2 — Developer: "Add hardware key derivation to my Basecamp module"

**Who:** A module developer building any Basecamp module that needs domain-scoped, hardware-backed keys — encryption, signing, identity, session tokens, etc.

**Flow:**
1. Declare `"keycard"` in the module's `manifest.json` dependencies.
2. Pick a domain string unique to the module's purpose (convention: `"modulename_purpose"`, e.g. `"notes_encryption"`).
3. Call `logos.callModule("keycard", "requestAuth", [domain, callerName])` → receive an `authId`.
4. Poll `checkAuthStatus(authId)`. The consumer API exposes three terminal-ish states: `pending` (keep polling), `complete` (key is in the response), and `rejected` (user declined). Wrong-PIN and internal derivation errors are intentionally kept as `pending` so the user can retry in the approval panel — consumers should not treat them as terminal. Also handle the `{error: "Auth request not found"}` shape for expired or invalid `authId`s so the poller does not loop forever. Note that PIN-lockout on the card does not currently resolve the request on the consumer side either — the request stays `pending` even after the card is blocked — so consuming modules that care about giving up gracefully should apply their own request-level timeout on top of polling.
5. On `complete`, receive a hex-encoded 32-byte key. Use it, then wipe it on the consumer side.
6. Next operation → repeat. Sessions are marked closed after each approval from the consumer's perspective; module-side key retention is tracked in [#94](https://github.com/xAlisher/keycard-basecamp/issues/94).

**Minimal example:**
```javascript
var result = logos.callModule("keycard", "requestAuth",
                              ["my_module_encryption", "my_module"])
var authId = JSON.parse(result).authId
// poll checkAuthStatus until complete, then use response.key
```

For a drop-in QML component and full polling example, see [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md). For the complete API including every response shape, see [KEYCARD_API.md](KEYCARD_API.md).

**Guarantees the developer gets for free:**
- PIN verification on-card (never handled by the consuming module)
- BIP32 derivation on-card (no host-side crypto)
- Deterministic keys (same domain + same card = same key, always)
- Domain isolation (different domains produce different keys)
- Session lifecycle (session marked closed after each approval; see [#94](https://github.com/xAlisher/keycard-basecamp/issues/94) for the in-progress key-cleanup work)
- Card UID verification (prevents mid-session card-swap)
- Single audited security surface (bugs fixed in one place)

**What the developer does not need to handle:** PC/SC, pairing, PIN entry UI, PIN lockout state, libpcsclite packaging, card presence polling, or any cryptographic primitive. All of that is owned by `keycard-basecamp`.

---

## Journey 3 — Node operator: "Protect a node identity key with hardware"

**Who:** A Logos node operator who wants a node's long-lived identity or signing key to be bound to a physical smartcard rather than stored on disk.

**Flow:** identical to the developer journey, from the perspective of whatever node-management module holds the identity. The node-management module requests a key from Keycard with a node-scoped domain (e.g. `"node_identity"`), uses it for signing or unsealing, and wipes it. The card must be present for the node to (re-)derive the key; the key is never persisted.

**What this unlocks:**
- Node identity that cannot be exfiltrated from disk because it is not on disk.
- Operator-controlled recovery — lose the card, lose access; retain the card, retain the identity.
- Same primitives, same audited module — no separate Keycard integration for node tooling.

**What this does not do:** this module does not manage the node, does not define what the key is used for, and does not ship any node-operator UI. Those belong in node-management tooling that consumes `keycard-basecamp`.

---

## LEZ integration note

"LEZ" — **Logos Execution Zone** — refers to two distinct layers, and the Keycard story is different for each. Disambiguating up front, because the Discord thread's "how does Keycard support for LEZ get exposed to users and devs?" can land on either.

### Layer 1 — The LEZ wallet (Basecamp consumer)

The user-facing entry point to LEZ is the **LEZ wallet** — a Basecamp core module + UI plugin pair that initializes private/public LEZ accounts, inspects balances, and performs transfers. (The exact public identifiers for that module pair are internal to the LEZ wallet repo and are not reproduced here; any integration work would target whichever identifiers that repo ships.) This is where the user actually interacts with LEZ, and this is where Keycard support is naturally exposed.

**Architectural ask:** the LEZ wallet should consume `keycard-basecamp` via `callModule` with its own domain tag(s) — e.g. `"lez_account_signing"` for transaction signing, `"lez_account_identity"` for account derivation, or whatever scoping the wallet needs. It should **not** ship its own Keycard integration.

**Why this is the right architecture and not just convenience:**
- **Single audited PC/SC surface.** PC/SC is finicky, and libpcsclite packaging has known footguns (see `PROJECT_KNOWLEDGE.md` lesson #36). One module, one place to get right.
- **Single PIN-lockout state machine.** Three wrong PINs bricks the card until PUK recovery. Two independent implementations would be two independent risks of getting the state machine wrong.
- **Single place to patch security issues.** When a Keycard or PC/SC issue lands, it gets fixed once and every consumer benefits.
- **Consistent UX.** The user sees one approval panel regardless of whether they are encrypting notes, signing an LEZ transaction, or unlocking a node identity. The mental model is "I approve Keycard requests in `keycard-ui`".
- **Domain separation already solves the isolation concern.** LEZ gets its own keys via its own domain tag. There is no cryptographic reason for the LEZ wallet to own the integration.

If the LEZ wallet needs a primitive that Keycard does not yet expose (e.g. a specific signing scheme, a different derivation path, attestation over an account), the correct path is to add it to `keycard-basecamp` and let every consumer benefit, not to fork the integration.

### Layer 2 — LEZ on-chain programs (the zone itself)

LEZ also refers to the on-chain execution environment: RISC Zero zkVM guest programs using PDA-style accounts, chained calls, and token primitives. See `logos-co/lez-framework`, `logos-co/logos-lez-rln`, `logos-co/lez-multisig`, `logos-co/eth-lez-atomic-swaps`.

**This layer is out of scope for `keycard-basecamp` in a direct sense.** LEZ programs run inside a zkVM, not inside Basecamp. They have no access to `logos.callModule`, no PC/SC, no USB, no live card. The Keycard module cannot reach into a zkVM guest and derive keys for it.

**What LEZ programs *can* consume from Keycard, indirectly:**
- **Keycard-signed transactions.** The LEZ wallet (layer 1) uses Keycard to sign a transaction off-chain; the LEZ program verifies the signature on-chain. The on-chain program does not need to know Keycard exists — it just verifies secp256k1 signatures against a public key. This is the normal hardware-wallet → on-chain pattern.
- **Identity commitments derived via Keycard.** A Keycard-derived key can be used as the preimage for an identity commitment (RLN-style), with the commitment registered on-chain. The card-derived key stays off-chain; only the commitment lives on-chain. `logos-lez-rln` is the obvious fit here — a user could register an RLN membership whose identity secret is derived from their Keycard via a domain tag like `"lez_rln_identity"`, meaning the membership can only be used when the physical card is present.
- **Multisig signers backed by Keycard.** `lez-multisig` signers can be Keycard-held keys. Each signer's wallet-side integration goes through `keycard-basecamp`; the multisig program just verifies signatures.

**What does not belong in `keycard-basecamp`:**
- RLN-specific logic, multisig-specific logic, atomic-swap-specific logic, or anything about LEZ programs. Those are consumer concerns. Keycard provides the domain-scoped key; consumers decide what to do with it.
- Any zkVM guest code. The module is host-side C++/Qt.

### Summary for the Discord thread

- **"How does Keycard get exposed to LEZ users and devs?"** → through the LEZ wallet (a Basecamp module), which consumes `keycard-basecamp` via `callModule` with LEZ-specific domain tags. The user sees the same approval panel as for any other Keycard-backed module.
- **"Should LEZ have a separate Keycard integration?"** → no. The LEZ wallet consumes this module. The zone itself (on-chain programs) does not integrate with Keycard at all in the PC/SC sense — it only ever sees signatures and public commitments that the wallet produced using Keycard-derived keys.
- **"What is planned?"** → this is an architectural statement, not a delivery commitment. The LEZ wallet does not currently consume `keycard-basecamp`. Making it do so is a concrete, bounded piece of work on the LEZ wallet side (add dependency, add `requestAuth` call, pick domain tags, wire into account flow). Scheduling is a roadmap conversation, not a Keycard-module conversation.

---

## Non-goals

To keep the module focused and the security surface small, `keycard-basecamp` deliberately does **not**:

- Ship any product UI beyond the `keycard-ui` approval panel. Wallet, notes, LEZ, node tooling all own their own UIs.
- Persist keys to disk. Derived keys are not written to storage. (The in-memory cleanup of completed auth requests on session close is an in-progress security hardening — see [#94](https://github.com/xAlisher/keycard-basecamp/issues/94) — and is called out wherever this doc discusses session close.)
- Persist PINs or cache them across requests. Every approval requires a fresh PIN entry.
- Implement business logic (signing protocols, encryption schemes, identity semantics). Consumers do that with the keys they receive.
- Require firmware changes per consumer. Domain separation is host-side.
- Manage PUK recovery. A blocked card must be recovered through the standard Keycard tooling.
- Bundle `libpcsclite`. The system library is used at runtime (see `PROJECT_KNOWLEDGE.md` lesson #36).

---

## Summary for the Logos journeys doc

If you are the person maintaining the Logos-wide journeys document and you need a short section for Keycard:

> **Keycard** is a Basecamp module that gives any other Basecamp module hardware-backed, domain-scoped key derivation via a single shared approval UI. Users authorize requests by entering their PIN on their Keycard; developers call `requestAuth` with a domain tag and receive a deterministic key; node operators can bind node identities to a physical card. One module, many consumers — the LEZ wallet, notes, and node tooling all consume the same integration rather than reimplementing it. The on-chain LEZ programs themselves (RLN, multisig, atomic swaps) do not integrate with Keycard directly — they consume the signatures and commitments that Keycard-backed wallets produce off-chain, which is the standard hardware-wallet-to-on-chain pattern.

For details, link to this file.
