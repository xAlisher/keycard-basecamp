# Doc-Packet Draft — Keycard for Basecamp

Prepared for submission to [logos-co/logos-docs](https://github.com/logos-co/logos-docs/issues/new?template=doc-packet.yml).

Tracking issue: [#104](https://github.com/xAlisher/keycard-basecamp/issues/104)

---

## 1. Outcome and Purpose

**What the user achieves (one sentence):**
Add hardware-backed key derivation to any Basecamp module using a single API call and a shared approval UI.

**Why it matters:**
Keycard gives every Basecamp module access to on-card BIP32 key derivation and PIN verification through one audited integration — no module needs its own PC/SC stack, PIN-lockout state machine, or smartcard UI. One module, many consumers.

**Key components (2–5):**
- `keycard-core` — Basecamp core module: PC/SC bridge, state machine, `requestAuth`/`checkAuthStatus` consumer API
- `keycard-ui` — Basecamp UI plugin: shared approval panel (PIN entry, request approval/decline, activity log)
- `KeycardAuth.qml` — drop-in QML component for consuming modules (handles polling, status, key delivery)
- `keycard-qt` (vendored) — Qt wrapper around the Keycard applet APDU protocol

---

## 2. Scope

**Repository:**
https://github.com/xAlisher/keycard-basecamp — branch `master`

**Runtime target:**
Local (desktop Basecamp — Linux x86_64, AppImage distribution)

**Prerequisites:**
- Linux x86_64
- Nix package manager (for build environment)
- Logos Basecamp AppImage (`logos-app.AppImage`)
- USB smartcard reader (tested with ACS ACR122U, Identiv uTrust)
- Keycard smartcard (Status Keycard or compatible JavaCard applet)
- `pcscd` service running (`sudo systemctl start pcscd`)

---

## 3. Happy Path

```sh
# 1. Clone and build
git clone https://github.com/xAlisher/keycard-basecamp.git
cd keycard-basecamp
nix develop --command bash -c "cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build"

# 2. Install to Basecamp
cmake --install build --prefix ~/.local/share/Logos/LogosApp

# 3. Clear cache and launch
rm -rf ~/.cache/Logos/LogosApp/qmlcache/*
~/logos-app/logos-app.AppImage

# 4. In Basecamp:
#    - Open the Keycard debug panel (keycard-ui)
#    - Insert smartcard into reader
#    - Click "Discover Reader" → state changes to CARD_NOT_PRESENT
#    - Click "Discover Card" → state changes to CARD_PRESENT
#    - Enter PIN, click "Authorize" → state changes to AUTHORIZED
#    - Enter a domain (e.g. "notes_encryption"), click "Derive Key" → key appears (hex)
#    - Click "Close Session" → state changes to SESSION_CLOSED, key is wiped

# 5. Consumer integration (from another module's QML):
#    var result = logos.callModule("keycard", "requestAuth", ["my_domain", "my_module"])
#    var authId = JSON.parse(result).authId
#    // poll checkAuthStatus(authId) until status == "complete", then use response.key
```

---

## 4. Verification

**Success command:**
```sh
# After building + installing, verify the plugin is discovered by Basecamp
ls ~/.local/share/Logos/LogosApp/plugins/keycard-core/plugin_metadata.json
```

**Expected result:**
```sh
# File exists and contains valid metadata:
# {"name":"keycard-core","version":"0.1.0", ...}
# AND in Basecamp, the Keycard debug panel loads and shows "READER_NOT_FOUND" initial state
```

---

## 5. Configuration (optional)

- `pcscd` must be running as a system service — Keycard uses the system's PC/SC daemon, not a bundled one
- No environment variables or custom ports required
- The LGX package must NOT bundle `libpcsclite.so` (breaks `pcscd` communication)

---

## 6. Known Issues / Failure Modes (optional)

1. **Card blocked after 3 wrong PINs** — card enters permanent lockout until PUK recovery. No automated recovery in `keycard-basecamp`; standard Keycard tooling required.
2. **`libpcsclite` accidentally bundled in LGX** — if the packaged plugin includes `libpcsclite.so`, `pcscd` communication breaks silently. Verify with `tar -tzf keycard-core.lgx | grep -i pcsclite` (must return nothing).
3. **Derived keys persist in memory after read ([#94](https://github.com/xAlisher/keycard-basecamp/issues/94))** — `checkAuthStatus()` returns the same key on repeat calls; `closeSession()` does not wipe completed auth requests. Fix in progress.

---

## 7. Point of Contact

<!-- TODO: fill with Alisher's handles -->
- **GitHub:** @xAlisher
- **Discord:** (TODO)

---

## 8. Additional Context (optional)

**Existing docs:**
- [JOURNEYS.md](../JOURNEYS.md) — product-level framing (user, developer, node operator journeys)
- [KEYCARD_API.md](../KEYCARD_API.md) — complete API reference for consumers
- [INTEGRATION_GUIDE.md](../INTEGRATION_GUIDE.md) — 5-minute developer quickstart
- [SPEC.md](../SPEC.md) — state machine, security properties, method specifications

**Security notes:**
- PIN never leaves the card — verified on-chip
- Key material derived on-card via BIP32, returned to host only after PIN verification
- No persistent key storage — card must be present for every derivation
- In-memory key cleanup after read is a known gap ([#94](https://github.com/xAlisher/keycard-basecamp/issues/94))
- `sodium_memzero` used for key wiping; `SecureBuffer` RAII pattern for key material
