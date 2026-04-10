# Keycard Module API Reference

Complete reference for integrating with the Keycard module via `logos.callModule("keycard", ...)`.

**For module developers:** If you find a bug in this API, file an issue on [keycard-basecamp](https://github.com/xAlisher/keycard-basecamp), not on your module's repo.

---

## Consumer API (for other modules)

These are the methods your module needs to request and receive keys from Keycard.

### requestAuth

Request a hardware-derived key for a specific domain.

```javascript
var result = logos.callModule("keycard", "requestAuth", [domain, caller])
```

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `domain` | string | Key derivation domain (e.g., `"notes_encryption"`) — same domain always produces same key |
| `caller` | string | Your module name (e.g., `"notes"`) — shown to user in keycard-ui |

**Response:**
```json
{
  "authId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "message": "Authorization request created. Open Keycard UI to complete."
}
```

**Notes:**
- Always returns `status: "pending"` — the user must approve in keycard-ui
- Store the `authId` and poll with `checkAuthStatus`
- The request stays pending until the user approves, declines, or it fails

---

### checkAuthStatus

Poll for the result of a previously created auth request.

```javascript
var result = logos.callModule("keycard", "checkAuthStatus", [authId])
```

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `authId` | string | The auth request ID from `requestAuth` |

**Response — Pending (still waiting for user):**
```json
{
  "authId": "...",
  "status": "pending",
  "domain": "notes_encryption",
  "caller": "notes"
}
```

**Response — Complete (key derived successfully):**
```json
{
  "authId": "...",
  "status": "complete",
  "domain": "notes_encryption",
  "caller": "notes",
  "key": "a1b2c3d4e5f6..."
}
```
The `key` is a hex-encoded 32-byte key derived via BIP32 on the smartcard. Same domain always produces the same key from the same card.

**Response — Rejected (user declined):**
```json
{
  "authId": "...",
  "status": "rejected",
  "domain": "notes_encryption",
  "caller": "notes"
}
```

**Response — Not found (invalid or expired authId):**
```json
{
  "error": "Auth request not found"
}
```

**Important:** the consumer API intentionally exposes only three statuses — `pending`, `complete`, `rejected` — plus the `{error: ...}` shape for not-found. **Wrong PINs and internal derivation errors do not surface as a terminal `failed` state.** They are intentionally held at `pending` so the user can retry in the approval panel; the request resolves only when the user either succeeds (→ `complete`) or explicitly declines in the approval panel (→ `rejected`). **Exhausting PIN attempts does not currently resolve the request on the consumer side** — the request stays `pending` even after the card enters PIN-lockout; the consuming module has to decide for itself when to give up (e.g. via its own timeout) or wait for the user to decline. Your poller must therefore handle: `pending` (keep polling, subject to your own timeout), `complete` (use the key), `rejected` (stop and show declined), and the `{error: "Auth request not found"}` shape (stop and show expired). Do not wait for a `failed` status — it does not arrive.

---

## Integration Pattern

### QML (recommended)

```qml
property string authId: ""

// 1. Request auth
function connectKeycard() {
    var result = logos.callModule("keycard", "requestAuth", ["my_domain", "my_module"])
    var response = JSON.parse(result)
    if (response.authId) {
        authId = response.authId
        statusPoller.start()
    }
}

// 2. Poll for result
Timer {
    id: statusPoller
    interval: 1000
    repeat: true
    onTriggered: {
        var result = logos.callModule("keycard", "checkAuthStatus", [authId])
        var response = JSON.parse(result)
        if (response.status === "complete" && response.key) {
            statusPoller.stop()
            onKeyReceived(response.key)
        } else if (response.status === "rejected" || response.error) {
            statusPoller.stop()
            onError(response.error || "Authorization rejected")
        }
        // "pending" → keep polling (wrong PINs are retried in the approval panel and stay pending)
    }
}
```

### C++ Plugin

```cpp
// Via LogosAPI (if available)
QString result = logosAPI->callModule("keycard", "requestAuth",
                                       QVariantList{"my_domain", "my_module"});
```

---

## Key Properties

| Property | Value |
|----------|-------|
| Key size | 32 bytes (256-bit), hex-encoded in response |
| Derivation | BIP32 on-card at EIP-1581 path |
| Domain separation | Deterministic — same domain + same card = same key, always |
| Session | Auto-closes after each approval — request again for next operation |
| PIN | Entered by user in keycard-ui, never exposed to your module |

---

## State Values

The `getState()` method returns the current card/reader state. Useful for status indicators but **not required for basic integration**.

| State | Meaning |
|-------|---------|
| `READER_NOT_FOUND` | No USB smart card reader connected |
| `CARD_NOT_PRESENT` | Reader connected but no card inserted |
| `CARD_PRESENT` | Card detected, ready for PIN |
| `AUTHORIZED` | PIN verified, card unlocked |
| `SESSION_ACTIVE` | Active key derivation session |
| `BLOCKED` | PIN blocked (too many wrong attempts) |

---

## Common Pitfalls

1. **Always `JSON.parse()` before accessing fields** — `callModule` returns a string, not an object

2. **Handle the `error` field** — some responses have `{error: "..."}` instead of `{status: "..."}`. Check for both.

3. **Session auto-closes** — after each approval, the session closes. Your next operation needs a new `requestAuth`.

4. **Don't skip `rejected` handling** — if the user clicks Decline in keycard-ui, your poller needs to stop and show an appropriate message.

5. **Expired auth IDs** — if too much time passes, `checkAuthStatus` returns `{error: "Auth request not found"}`. Your poller must handle this or it loops forever.

6. **Domain naming** — use a descriptive, unique domain string. Different domains produce different keys from the same card. Convention: `"modulename_purpose"` (e.g., `"notes_encryption"`, `"wallet_signing"`).

---

## Internal API (keycard-ui only)

These methods are used by keycard-ui to manage the approval flow. Other modules should NOT call these directly.

### getPendingAuths()

Returns all pending authorization requests.

```json
{ "pending": [{ "authId": "...", "domain": "...", "caller": "...", "timestamp": 1234567890 }], "count": 0 }
```

### authorizeRequest(authId, pin)

Approve a pending request with the card PIN. Derives key on-card and auto-closes session.

**Success:** `{ "authId": "...", "status": "complete", "key": "hex...", "message": "..." }`
**Wrong PIN:** `{ "authId": "...", "status": "retry", "remainingAttempts": N }` — no `error` field. The underlying `AuthRequest` stays `pending` on the consumer side.
**Derivation error (after PIN verified):** `{ "authId": "...", "status": "retry" }` — no `error` field, no `remainingAttempts`. The underlying `AuthRequest` also stays `pending` on the consumer side.
**Not found:** `{ "error": "Auth request not found or already completed" }`

Note: neither retry response currently terminates the auth request. Even on the third wrong PIN (where `remainingAttempts: 0` and the card is about to enter PIN-lockout), `authorizeRequest()` still returns `status: "retry"` and the request remains `pending`. Consumer-side resolution on exhausted attempts is a known gap; see also the discussion in [#93](https://github.com/xAlisher/keycard-basecamp/issues/93).

### rejectRequest(authId)

Decline a pending request.

**Success:** `{ "authId": "...", "status": "rejected", "message": "..." }`
**Not found:** `{ "error": "Auth request not found or already completed" }`

### getState()

Poll current card/reader state. Returns `{ "state": "<STATE>" }` — see State Values table above.

### discoverReader()

Initialize PC/SC reader monitoring.

**Found:** `{ "found": true, "name": "Smart card reader" }`
**Not found:** `{ "found": false }`

### discoverCard()

Detect card and check pairing status.

**Found:** `{ "found": true, "uid": "card-uid-hex" }`
**Not found:** `{ "found": false }`
**No bridge:** `{ "found": false, "error": "Bridge not initialized - call discoverReader first" }`

### checkPairing()

Check pairing file status without decrypting.

**Cached:** `{ "paired": true, "pairingIndex": 1, "status": "decrypted" }`
**Locked:** `{ "paired": true, "status": "locked" }`
**Legacy:** `{ "paired": true, "status": "legacy" }`
**Not paired:** `{ "paired": false, "status": "not_paired" }`
**Corrupted:** `{ "paired": false, "status": "corrupted" }`

### authorize(pin)

Direct PIN verification against the card. Decrypts pairing file, opens secure channel, verifies PIN.

**Success:** `{ "authorized": true }`
**Wrong PIN:** `{ "authorized": false, "error": "...", "remainingAttempts": 2 }`
**Not paired:** `{ "authorized": false, "error": "Card not paired - pair first" }`
**Corrupted:** `{ "authorized": false, "error": "Pairing file corrupted" }`

### deriveKey(domain)

Derive key at EIP-1581 BIP32 path for the given domain. Requires active session.

**Success:** `{ "key": "hex-64-chars", "path": "m/43'/60'/1581'/..." }`
**No session:** `{ "error": "No active session - authorize to derive keys" }`

### closeSession()

Close active session and clear pairing cache.

**Always:** `{ "closed": true }`

### pairCard(password, pin)

Create new card pairing. PIN required for encryption-first persistence.

**Success:** `{ "paired": true, "pairingIndex": 1 }`
**Failed:** `{ "paired": false, "error": "..." }`

### unpairCard()

Remove card pairing from storage and card.

**Success:** `{ "unpaired": true }`
**Failed:** `{ "unpaired": false, "error": "..." }`
