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

**Response — Failed (PIN wrong or derivation error):**
```json
{
  "authId": "...",
  "status": "failed",
  "domain": "notes_encryption",
  "caller": "notes",
  "error": "Failed to open secure channel: ..."
}
```

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

**Important:** Handle ALL five cases. If you only check `complete`/`failed`/`rejected`, your poller will loop forever on expired requests.

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
        } else if (response.status === "failed" || response.status === "rejected" || response.error) {
            statusPoller.stop()
            onError(response.error || "Authorization " + response.status)
        }
        // "pending" → keep polling
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

| Method | Purpose |
|--------|---------|
| `getPendingAuths()` | List pending auth requests |
| `authorizeRequest(authId, pin)` | Approve request with PIN |
| `rejectRequest(authId)` | Decline request |
| `getState()` | Poll card/reader state |
| `discoverReader()` | Initialize PC/SC reader |
| `discoverCard()` | Detect card and check pairing |
| `checkPairing()` | Check pairing status |
| `authorize(pin)` | Direct PIN verify (used internally) |
| `deriveKey(domain)` | Direct key derivation (used internally) |
| `closeSession()` | Close active session |
| `pairCard(password, pin)` | Create new card pairing |
| `unpairCard()` | Remove card pairing |
