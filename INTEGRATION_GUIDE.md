# Keycard Integration Guide

Add hardware-backed signing or key derivation to your Basecamp module.

---

## Prerequisites

1. **Add keycard dependency** to your module's `manifest.json`:
```json
{
  "dependencies": ["keycard"],
  ...
}
```

2. **Install Keycard LGX packages** in Basecamp:
   - `keycard-core.lgx` — C++ backend, PC/SC integration
   - `keycard-ui.lgx` — Approval panel for PIN entry

   Download from [keycard-basecamp releases](https://github.com/xAlisher/keycard-basecamp/releases) and install both via Basecamp's module manager.

---

## Signing (primary use case)

Use signing when your module needs to commit to data — messages, transactions, votes — without managing keys. The private key never leaves the smartcard.

The flow: call `requestSign` with your payload hash, domain, caller, and scheme → poll `checkSignStatus` until the user approves in keycard-ui → receive the signature once.

No drop-in component yet — signing uses the manual flow. Signing showcase coming with [#98](https://github.com/xAlisher/keycard-basecamp/issues/98).

**`requestSign` takes a single JSON string argument:**
| Field | Type | Description |
|-------|------|-------------|
| `domain` | string | Determines the BIP32 derivation path — same domain, same signing key |
| `payloadHash` | string | Hex-encoded hash of your payload — the card signs this directly |
| `caller` | string | Your module name — shown to the user in the approval panel |
| `scheme` | string | `"ecdsa"` or `"schnorr"` (BIP340) |

```javascript
logos.callModule("keycard", "requestSign", [JSON.stringify({
    domain: "my_module_signing",
    payloadHash: hash,
    caller: "my_module",
    scheme: "ecdsa"
})])
```

**`checkSignStatus` response when complete:**
```json
{
  "signId": "...",
  "status": "complete",
  "signature": "a1b2c3...",
  "scheme": "ecdsa"
}
```

**Path note:** signing uses a non-EIP-1581 BIP32 path. This means the signing key can never be exported from the card — even by the keycard module itself. Keys that sign and keys that encrypt are derived at separate paths and cannot be confused.

---

## Key derivation (for encryption)

Use key derivation when your module needs to encrypt local data and needs a stable key it can reproduce later. The key is derived on-card, returned once, and must be wiped from memory when done.

The flow: call `requestAuth` with a domain and caller → poll `checkAuthStatus` → receive the derived key once → wipe it after use.

**See it in action:** [`auth_showcase-ui/qml/Main.qml`](auth_showcase-ui/qml/Main.qml) is a complete, running integration. The three functions to read:
- [`requestAuth()`](auth_showcase-ui/qml/Main.qml#L50) — queues the request
- [`checkAuthStatus()`](auth_showcase-ui/qml/Main.qml#L79) — polls for the result
- [`callModuleParse()`](auth_showcase-ui/qml/Main.qml#L30) — handles the double-JSON-wrap quirk ([#121](https://github.com/xAlisher/keycard-basecamp/issues/121))

### Drop-in component

For the common case, copy `KeycardAuth.qml` from keycard-basecamp into your module's QML directory:

```qml
KeycardAuth {
    domain: "my_module_encryption"   // Unique domain for your key
    caller: "my_module"              // Your module name

    onKeyReceived: function(hexKey) {
        myBackend.useKey(hexKey)     // Wipe after use — do not store
    }
    onError: function(message) { errorText.text = message }
}
```

The component handles the button, polling, status display, error handling, and auto-reset.

**`requestAuth` parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `domain` | string | Key derivation domain — same domain always produces the same key |
| `caller` | string | Your module name — shown to the user in the approval panel |

**`checkAuthStatus` response when complete:**
```json
{
  "authId": "...",
  "status": "complete",
  "key": "a1b2c3..."
}
```

**Path note:** `requestAuth` derives keys at EIP-1581 BIP32 paths — the only paths the Keycard applet allows for export. This is enforced on-card. The key exists in host memory for a single read, then the request is wiped. Your module is responsible for wiping it from application memory after use.

---

## What the user sees

When your module calls `requestSign` or `requestAuth`, a pending request appears in keycard-ui. The user:

1. Switches to the Keycard module (or keycard-ui surfaces it automatically)
2. Sees the request — domain name and your module as caller
3. Taps the card to the reader and enters their PIN
4. Approves or declines

On approval, your poller receives `status: "complete"` with the signature or key. On decline, it receives `status: "rejected"`. The session closes automatically — one approval, one result.

---

## Domain naming

```
"modulename_purpose"
```

Examples:
- `"notes_encryption"` — encrypting notes content
- `"wallet_signing"` — transaction signing
- `"governance_vote"` — voting commitments

**The domain is the identity of the key.** Use a stable, unique string — changing it produces a different key. Same domain + same card = same key, always. Different domains produce isolated keyspaces with no relation to each other.

---

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `callModule` returns a string | Always `JSON.parse()` — or use `callModuleParse()` from the showcase to handle the double-wrap quirk ([#121](https://github.com/xAlisher/keycard-basecamp/issues/121)) |
| Poller loops forever | Handle all terminal states: `complete`, `rejected`, AND `{error: ...}` for expired IDs. There is no `failed` status — wrong PINs stay `pending` so the user can retry |
| Key "changes" between sessions | It doesn't — same domain = same key. Session auto-closes, so each operation needs a new request |
| "Auth request not found" | The ID expired or was already consumed. Start a new request |
| `KeycardAuth.qml` doesn't render | Must be in the same directory as your `Main.qml` |
| Storing the derived key | Don't. Wipe after use. Request again next time — same domain reproduces it |

---

## Filing bugs

Found a problem with the keycard API? **File an issue on [keycard-basecamp](https://github.com/xAlisher/keycard-basecamp)**, not on your module's repo.

Include:
- The `callModule` call you made
- The response you received
- What you expected instead

---

## Full API reference

See [KEYCARD_API.md](KEYCARD_API.md) for the complete method reference with every response shape documented.
