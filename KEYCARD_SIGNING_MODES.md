# Keycard Signing Modes

Reference document for the Keycard signing-modes work driven by the LEZ wallet integration conversation. This is the technical-source-of-truth: research, constraints, decisions, and open questions. Issues and epic link back here rather than duplicating the detail.

**Status:** Research complete, implementation not yet started. Tracked under epic _Keycard signing modes and Schnorr/BIP340 support for LEZ_ (issue link TBD — filled in once epic is created).

---

## 1. Context

The current `keycard-basecamp` module (as of 2026-04-09) exposes Keycard primarily as an **auth / key-derivation service**: consumers call `requestAuth(domain, caller)`, the user approves in `keycard-ui`, and the module derives a domain-scoped secp256k1 key on-card via BIP32 and returns the raw 32-byte private key to the consumer. The consumer is then responsible for whatever signing / encryption / identity operation it needs.

This shape makes sense for consumers doing bulk symmetric encryption (notes encryption, storage vaults) — they genuinely need the key bytes. It is the **wrong shape** for signing-oriented consumers, because:

- The private key leaves the card's security domain for no good reason.
- The consuming module's memory becomes part of the attack surface for the signing key.
- The user's approval moment is currently "let this module have this key for its session", not "let this module sign this specific payload". That is weaker than what users of hardware wallets (Ledger, Trezor, etc.) expect.
- It is orthogonal to the stated design principle of `keycard-basecamp` — *"single audited security surface for Keycard operations"* — since handing raw keys to consumers distributes the surface across every consumer module.

This came up in a Logos Discord thread with `@fryorcraken` and `@guylouis` after `JOURNEYS.md` was first drafted (see issue #93). Guylouis's push-back was direct: *"keycard-basecamp needs to be more than an auth/key-derivation service — it also needs to sign request for signature coming from LEZ wallet (or other modules)"*. He was right, and the research below is the work to make the architectural ask concrete.

**The question:** can `keycard-basecamp` expose an on-card signing API, and if so, what are the constraints?

---

## 2. LEZ signing scheme — confirmed Schnorr BIP340

The first blocker was confirming what signature scheme LEZ uses. Early assumptions were wrong in both directions: it is neither plain secp256k1 ECDSA (which Keycard already supports) nor Ed25519 (which would have ruled out on-card signing entirely given current Keycard applet capabilities).

**Confirmed by `@guylouis` in the Discord thread:**

> LEZ (public state) is using schnorr (BIP340) which is supported since a couple of weeks by keycard

Key implications:
- **BIP340 Schnorr over secp256k1.** Same elliptic curve as Bitcoin / Ethereum ECDSA. Different signature scheme (Schnorr, not ECDSA), different hashing (tagged hashes per BIP340), different output layout (no recovery byte).
- **"Public state" qualifier.** LEZ has both public-state accounts and private-state accounts; guylouis specified *public state*. Private-state accounts (inside the zkVM, RLN-style, shielded transfers) use ZK-friendly primitives that are outside the scope of this module regardless. When this doc says "LEZ signing", it means public-state account signing — the thing the LEZ wallet does when a user sends a public transfer or similar.

**Supporting evidence from `logos-blockchain/logos-execution-zone` (public):**
- `wallet-ffi/src/keys.rs` — references `nssa::PublicKey`, `secp256k1`
- `wallet-ffi/src/types.rs` — `secp256k1`
- `nssa/core/src/encoding.rs` — account encoding references `secp256k1`
- `nssa/core/src/encryption/shared_key_derivation.rs` — shared-key derivation references `secp256k1`
- `sequencer/core/src/block_settlement_client.rs` — this is where `ed25519` appears, but it's the block-production layer, not the wallet or account layer

Ed25519 is confined to sequencer / block-production infrastructure. Wallet-side account signing is secp256k1, with BIP340 Schnorr as the actual signature algorithm.

---

## 3. Keycard applet support — confirmed, via temporary branch

Also confirmed in the Discord thread, this time by `@mikkoph` (Keycard core developer):

- BIP340 Schnorr signing is **supported by the Keycard applet as of a recent branch**, currently in a temporary build mikkoph distributes by hand.
- The branch is not yet merged upstream. Documentation will be updated when it merges.
- OP24 has already walked one other developer (Marvin) through installing the temporary applet; same procedure applies to our dev card.

### 3.1 APDU-level specifics

From mikkoph's answers:

| Operation | APDU | P2 Value | Meaning |
|-----------|------|----------|---------|
| LOAD KEY  | 0x... | **0x00** | Standard BIP39 / BIP32 derivation constants (current behavior) |
| LOAD KEY  | 0x... | **0x01** | LEE (Logos Execution Environment) public-state derivation constants |
| SIGN      | 0xC0  | **0x00** | ECDSA (current behavior) — also includes P2=0x01 and P2=0x02 variants for derive-and-sign |
| SIGN      | 0xC0  | **0x03** | BIP340 Schnorr (new) |

(P2 values for `SIGN` other than 0x00/0x01/0x02/0x03 are not currently supported.)

**Input format:** same for both ECDSA and Schnorr sign paths. A **32-byte pre-hashed digest**. The host is responsible for computing the digest in whatever form the consumer's verification layer expects (for LEZ: whatever hash the LEZ transaction signing scheme prescribes).

**Output format:** both return **TLV-wrapped** bytes. mikkoph flagged that he wasn't sure whether the current keycard-qt SDK parses the TLV or returns it raw. From reading `external/keycard-qt/src/command_set.cpp` (local vendored copy), we can confirm the SDK **does** parse the TLV:

- `signWithPath()` returns 65 bytes: R(32) ‖ S(32) ‖ V(1) — Ethereum-compatible ECDSA shape
- `signWithPathFullResponse()` returns the full TLV including the public key prefix (65 bytes) and the signature

For Schnorr, the expected output shape is **64 bytes: R(32) ‖ s(32)** — no recovery byte (Schnorr public keys are derivable from signatures differently, and recovery is not part of the BIP340 signature itself). The exact TLV layout of `SIGN P2=3` is not yet documented; will be confirmed empirically once the applet is installed, or by reading mikkoph's branch before merge.

### 3.2 Key-hierarchy constraint — one card, one mode

This is the part that actually shapes the product model, not the APDU details. From mikkoph:

> P2=0 is standard BIP39/BIP32 while P2=1 uses different constants defined for the LEE public state. Note that ECDSA and Schnorr signing is supported in both cases, although ECDSA is not used when doing LEE

And after a direct clarification question:

> You can only have either one or the other active at the same time

Meaning:
- **The same binary seed format** is accepted by both `LOAD KEY P2=0` and `LOAD KEY P2=1`.
- **The key hierarchy that the card derives** from that seed is different in each mode. `P2=0` uses standard BIP39 / BIP32 constants; `P2=1` uses LEE-specific constants. Keys at the same derivation path will be different across modes.
- **Only one mode can be loaded at a time.** Switching modes requires reloading the seed, which replaces the previous mode's derived-key state.
- **Both signing algorithms (ECDSA and Schnorr) work in both modes**, but LEZ-verified signatures require a card loaded in `P2=1` mode because otherwise the signed key will not match the account's expected public key at the LEE-derivation path.

**Therefore:**
- A card configured for standard Logos use (notes encryption, EIP-1581 domains, Ethereum-style signing, node identity) cannot also produce LEZ-valid signatures.
- A card configured for LEZ signing cannot produce the keys needed for notes encryption or Ethereum-style signing.
- A user who wants both needs **two physical Keycards**.

This is a property of the applet, not a design choice in `keycard-basecamp`. The module must honestly surface it.

### 3.3 Mode detection — probe today, proper self-report later

After confirming the one-mode-at-a-time constraint, the next question was whether the card self-reports its mode so the host can detect it without asking the user. mikkoph's answer came in two parts.

**First answer — no dedicated flag yet:**

> no, there currently isn't but it would make sense to add

So there is no clean status bit in `SELECT` or an equivalent "what mode am I?" query in the current applet or the temporary Schnorr branch. mikkoph agreed adding one makes sense but made no commitment on when.

**Second answer — an immediate workaround via `EXPORT LEE`:**

> In the meantime a workaround would be to call EXPORT LEE (INS=C3) with P1=F0. If the card was loaded with normal keys, you'll get 0x6985, otherwise 0x6a86

So we have a functional detection mechanism **today**, before any applet changes:

| Probe | Command | Response status word | Meaning |
|-------|---------|----------------------|---------|
| EXPORT LEE | `INS=0xC3, P1=0xF0` | `0x6985` (conditions not satisfied) | Card loaded with standard BIP32 keys → **standard mode** |
| EXPORT LEE | `INS=0xC3, P1=0xF0` | `0x6a86` (incorrect P1/P2) | Card loaded with LEE keys → **LEZ mode** |

The probe is cheap (single APDU, no side effects, no key material extracted — we're only reading the status word, not the response body) and deterministic. It fits naturally into the existing discovery flow: after a successful `SELECT` and secure-channel establishment, send the probe, read the mode, store it in the pairing record on first pair, return it via `getCardMode()` on subsequent discoveries.

**Implication for the product model:** the user-prompt-at-pairing path described in earlier drafts of this doc becomes a **fallback** rather than the primary mechanism. Primary path is automatic detection via the probe. User prompt only appears if the probe returns an unexpected status word (card firmware unknown, probe returns `0x9000` unexpectedly, etc.) or if the stored mode in the pairing record disagrees with the probe result (indicates the card was re-loaded in a different mode since last pairing — keycard-basecamp should refuse to proceed in that case and prompt the user to re-pair, because the stored mode is stale).

**Forward compatibility:** when mikkoph ships a dedicated self-report flag, the probe becomes a legacy fallback for older applet versions. The detection code gains one layer: try self-report first, fall back to the EXPORT LEE probe, fall back to user prompt as a last resort.

---

## 4. `keycard-qt` delta

Our vendored copy of keycard-qt lives at `external/keycard-qt/`. Based on reading `external/keycard-qt/src/command_set.cpp` around `signWithPath` / `signWithPathFullResponse` (see research trail in #93 and the `SignCommand` wrapper in `external/keycard-qt/include/keycard-qt/card_command.h` around lines 232–242), the delta for Schnorr support is small:

**New sign path:**
- Add `signWithPathSchnorr(data, path, makeCurrent)` or extend the existing method with a `scheme` parameter. Implementation is almost identical to `signWithPath`; the only change in the APDU command is `P1` remaining 0x01 / 0x02 (derive flavor) but the new **P2 = 0x03** instead of the current 0x00. (Clarify: mikkoph described the algorithm selector as P2; confirm against the APDU format when reading the branch, because the existing keycard-qt uses P1 for derive flavors — the exact byte position of the algorithm selector needs to match mikkoph's branch.)
- New TLV parser for the Schnorr output. Returns 64 bytes `R ‖ s`. No recovery-byte synthesis. No public-key stripping (or: strip the same pubkey prefix that `signWithPathFullResponse` handles, but return a 64-byte signature instead of the 65-byte ECDSA shape).

**New load-key path:**
- Either a new `loadKeyForLee(seed)` method or an overload of the existing `loadKey` that takes a `forLee: bool` parameter. One-line P2 change (`0x00` → `0x01`). Everything else about the command is unchanged.

**New mode-detection probe:**
- Add a `detectMode()` or `probeLeeMode()` method that sends `EXPORT LEE` (`INS=0xC3, P1=0xF0`) and returns `Standard` / `Lee` / `Unknown` based on the status word (`0x6985` → standard, `0x6a86` → LEE, anything else → unknown). Does not parse any response body — only the status word matters. Does not require a live signing session or PIN verification beyond whatever the existing secure-channel setup already ensures.
- Alternatively, if we don't want to add this to `keycard-qt` itself, expose raw APDU passthrough from `keycard-basecamp` and implement the probe in `keycard_manager.cpp`. The probe is a single-APDU, status-word-only call, so it doesn't particularly need to live inside keycard-qt unless we want a clean test seam.

**Scope:** probably 60–100 lines of C++ in `external/keycard-qt/src/command_set.cpp` plus matching header declarations and possibly test stubs. Carried as a vendored patch in our tree until mikkoph's branch merges upstream and we can drop the patch cleanly.

**Risks:**
- The Schnorr output TLV layout may have additional fields we are not expecting. Empirically verify against the installed applet before finalizing the parser.
- If the upstream status-im/keycard-qt develops its own Schnorr API that differs from our patch, we will need to reconcile. Not a blocker but worth mentioning in the patch commit so it is findable later.

---

## 5. `keycard-basecamp` design implications

This section is the product-model delta.

### 5.1 Pairing record gains a `mode` field

Today the pairing record holds the pairing key, card UID, and whatever metadata we track. It needs one more field:

```json
{
  "pairingKey": "...",
  "cardUID": "...",
  "mode": "standard" | "lez"
}
```

**Populated automatically via the `EXPORT LEE` probe** (section 3.3) on first pair, then cached in the pairing file so subsequent discoveries don't re-probe. Flow:

1. User pairs a new card (PIN, pairing password, etc. — existing flow).
2. Once the secure channel is established, `keycard-basecamp` sends the mode-detection probe.
3. Probe returns `0x6985` → mode = `standard`. Probe returns `0x6a86` → mode = `lez`. Anything else → mode = `unknown`, ask the user explicitly as a fallback.
4. Mode is written to the pairing record alongside the pairing key and UID.
5. Subsequent `discoverCard()` calls read the cached mode from the pairing record. The probe does not need to run on every discovery — only at initial pair, and optionally on demand if we want to catch the "user re-loaded the card seed with a different mode between sessions" edge case.

**Consistency check on re-pair or mode-change detection.** If a paired card is re-inserted and the stored mode in the pairing record disagrees with what the probe now returns (user reloaded the seed with the other P2 outside of `keycard-basecamp`), the module should refuse to proceed, log a clear message, and prompt the user to unpair and re-pair. This is the right failure mode: we never want a consumer to call `requestSign(scheme: "schnorr")` against what we think is a LEZ card but has secretly become a standard card, and vice versa.

**User prompt as fallback.** If the probe returns an unexpected status word (card firmware unknown, probe behavior differs from mikkoph's spec, etc.), fall back to asking the user directly:

> How is this Keycard configured?
> (a) Standard — notes, wallets, Ethereum-style signing, node identity
> (b) LEZ — for signing LEZ transactions

Only used as a last resort. Primary path is automatic.

**Forward compatibility.** When the applet ships a dedicated mode self-report flag, detection gains a layer: try the self-report first, fall back to the probe, fall back to user prompt. Nothing else about the design changes.

### 5.2 Public API additions

**`getCardMode()`** — new `Q_INVOKABLE` returning `{"mode": "standard" | "lez" | "unpaired"}`. Consumers can query upfront and show appropriate UX without waiting for a failed request.

**`requestSign(domain, payloadHash, caller, scheme)`** — new `Q_INVOKABLE` paralleling `requestAuth`. Parameters:
- `domain` — same meaning as `requestAuth`: a scoping string that maps to a BIP32 path
- `payloadHash` — **hex-encoded 32-byte digest** that the consumer has already computed in whatever form their verification layer expects
- `caller` — consumer module name, shown in the approval panel
- `scheme` — `"ecdsa"` or `"schnorr"`

Returns the same `{"authId": "...", "status": "pending"}` shape as `requestAuth` (rename to `signId` if preferred for clarity). Consumer polls `checkAuthStatus` (or a parallel `checkSignStatus`) until terminal state.

On completion, the response includes the signature as hex:
- `scheme: "ecdsa"` → 65 bytes (R‖S‖v), Ethereum-compatible
- `scheme: "schnorr"` → 64 bytes (R‖s), BIP340-compatible

**Mode-mismatch error:**
```json
{
  "error": "Paired card is in LEZ mode; this operation requires a standard-mode Keycard",
  "cardMode": "lez",
  "requiredMode": "standard"
}
```

Returned immediately from `requestAuth` (if card is LEZ) or `requestSign(scheme: "ecdsa")` (if card is LEZ) or `requestSign(scheme: "schnorr")` when LEZ wallet calls it on a standard card. Consumers can distinguish this from other errors and prompt the user to insert a different card.

### 5.3 Approval panel surfaces mode

`keycard-ui`'s approval panel currently shows the requesting module and the domain. It should also show:

- **Card mode label** — "Standard Keycard" / "LEZ Keycard" — as a persistent indicator whenever a card is inserted and paired.
- **Mode-mismatch copy** — when a request comes in that requires a different mode, the panel shows a clear message explaining the mismatch instead of just "error".
- **Pairing flow mode picker** — new screen during initial pairing asking the user which mode the card is in.

No new PC/SC or security logic here — this is pure QML / UX work on top of the mode-aware API in 5.2.

### 5.4 Multi-card support (out of scope for this epic)

The cleanest long-term answer to "I want both a standard card and a LEZ card" is to let `keycard-basecamp` pair with multiple cards at once and auto-route consumer requests based on the required mode. This is a bigger refactor — the current pairing storage and discovery code assume a single card — and is intentionally **out of scope** for this epic.

Filed as a separate follow-up issue. Linked from the epic but not required for epic completion. Until then, users with both needs swap cards and re-pair when they want to switch contexts.

---

## 6. `JOURNEYS.md`, `KEYCARD_API.md`, `SPEC.md` updates

All three docs need updates. Short sketch here; full content lives in the dedicated docs-update sub-issue.

**`JOURNEYS.md`** gains a "Card Modes" section surfacing the per-card mode constraint honestly. The "one module, many consumers" architectural principle gets qualified: *true per mode*, not *true across modes*. LEZ integration note expands to cover the signing-mode question and the two-cards-for-both-use-cases reality.

**`KEYCARD_API.md`** documents:
- `requestSign(domain, payloadHash, caller, scheme)` with all response shapes
- `getCardMode()` with its response shape
- The mode-mismatch error shape and when it is returned
- A note on `requestAuth` requiring a standard-mode card

**`SPEC.md`** adds mode as a first-class concept in the security properties section and in the card-state model. The "Security Properties to Preserve" checklist gains a line: *Card mode is stored at pairing time and routed per consumer request; mode mismatch produces a clean error, never a garbage signature.*

---

## 7. Forward compatibility

Things that will change when dependencies land:

- **When mikkoph merges the Schnorr branch upstream in `status-im/status-keycard`** → drop the "temporary applet" footnote, document the stable applet version, keep our vendored keycard-qt patch until upstream keycard-qt also supports it.
- **When upstream `status-im/keycard-qt` adds Schnorr support** → drop our vendored patch, bump the submodule, keep the `keycard-basecamp`-side API.
- **When the applet adds mode self-report** → add detection code in `keycard-basecamp`, prefer self-report over stored user claim, use stored claim as a fallback / cross-check, ask mikkoph for the detection APDU or status bit details at that time.
- **When multi-card support lands** (separate future epic) → the single-card assumption in the pairing storage goes away; consumers gain ability to target a specific card or let the module auto-route; mode routing becomes automatic.

---

## 8. Open questions

Things we don't currently know and should track:

1. **Exact Schnorr output TLV layout.** We know it's `{R, s}` with "more data in it" (mikkoph). Need to either read mikkoph's branch or verify empirically once the applet is installed. Blocks finalizing the keycard-qt output parser.
2. **Is the algorithm selector really P2 for `SIGN`?** mikkoph consistently referred to P2, but the existing keycard-qt uses P1 for sign-flavor variants (derive, derive-and-make-current, etc.). Cross-check once we have the APDU spec from mikkoph's branch or the applet documentation update.
3. **Is there any secure-channel / PIN-verify state difference between the modes?** Current assumption is no — secure channel and PIN verification are below the mode/scheme layer and unchanged. Confirm empirically during integration.
4. **What specific hash function does the LEZ wallet use when computing the 32-byte digest to sign?** Plain SHA-256? A BIP340-tagged hash? Something LEZ-specific? Not a Keycard-side concern (we take any 32-byte input), but the LEZ wallet integration will need this and the answer should be captured somewhere.
5. **Recovery semantics for Schnorr.** ECDSA has recoverable signatures (v byte); Schnorr does not. Consumers that currently rely on pubkey recovery from an ECDSA signature will need a different flow if they move to Schnorr. Not a `keycard-basecamp` concern directly, but worth flagging for any consumer considering both schemes.
6. **User-initiated mode switch flow.** If a user wants to convert a standard card to a LEZ card (or vice versa), what's the UX? Today: unpair, reload seed via some external tool, re-pair with new mode. Is that acceptable, or does `keycard-basecamp` need a "convert card mode" flow? Probably the former for now; revisit if user pain becomes evident.
7. **Does the `EXPORT LEE` probe require an established secure channel?** Probably yes (most Keycard commands do), but worth confirming — determines whether the probe runs post-`SELECT` or post-secure-channel in the pairing flow.
8. **Does the probe behavior survive applet upgrades?** mikkoph's workaround is for the current temporary Schnorr branch. When the branch merges, the `INS=0xC3, P1=0xF0` behavior may change. Treat the probe as "stable for now but re-verify on every applet version bump" until the proper self-report flag lands.

---

## 9. Related issues

- **#93** — `JOURNEYS.md`: where this conversation started. The original draft framed Keycard as auth/key-derivation only, which is what surfaced the signing gap.
- **#94** — Key-persistence cleanup in `m_authRequests`. Orthogonal but related: `requestSign` should inherit whatever tightened key-handling comes out of #94, since signatures (and possibly intermediate signing state) should get the same one-read-and-drop treatment as derived keys.
- **(TBD)** — Epic: Keycard signing modes and Schnorr/BIP340 support for LEZ — to be filed, will list this doc as its technical reference.
- **(TBD)** — Sub-issues for: vendored keycard-qt patch, `keycard-basecamp` mode-aware pairing, `requestSign` API, approval-panel UX, docs updates, forward-compat self-report detection, multi-card support follow-up.

Issue numbers and cross-links get filled in after the epic and sub-issues are created.
