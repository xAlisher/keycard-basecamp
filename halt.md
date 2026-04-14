# Halt — 2026-04-14 (#96 LEE bit-flip VERIFIED, ready for Senty review)

## Where we stopped

#96 all code committed and end-to-end verified. LEE bit-flip test passed.
Senty has been notified via halt.md (handoff on GitHub issue #96 was posted in previous session).

---

## Verified end-to-end (2026-04-14, session 2)

```
discoverReader  → {"found": true}
discoverCard    → {"found": true, "uid": "c5196e35721641a3902e8421c8fc0ba0"}
authorize       → {"authorized": true}        (using {"pin":"000440"} JSON format)
detectMode      → {"mode": "LEE"}             ← LEE key loaded (from prev session)
removeKey       → {"ok": true}
detectMode      → {"mode": "none"}            ← none after key removed
loadKey(LEE)    → {"keyUID": "3a9311e3..."}   ← LEE seed loaded
detectMode      → {"mode": "LEE"}             ← LEE bit confirmed 0x3F
```

All three detectMode states verified: `"LEE"`, `"none"`, and BIP39 (`"BIP39"` from session 1).

---

## Card credentials

```
PIN: 000440
PUK: 193258644395
Pairing password: jyairW2naGbqtzDp
InstanceUID: c5196e35721641a3902e8421c8fc0ba0
```

Pairing injected in `/home/alisher/.local/share/Logos/LogosBasecamp/keycard-pairings.json`
and `/home/alisher/.local/share/Logos/LogosApp/keycard-pairings.json`.

```
PAIRING KEY (b64): TtowilnWIJYvyZ0aCINvThI4HINpEI+L0zrr7E62KlY=
PAIRING INDEX: 0
```

---

## #96 commits (all on master)

- `bc09f36` keycard-qt: signWithPath scheme param + loadKey type param
- `b998951` keycard-qt: Capability::LEEKey + isLEEKey()
- `cbc289e` basecamp: submodule bump (signing modes)
- `1cea9ee` basecamp: KeycardBridge KeyMode + detectMode() API
- `d3c5d76` basecamp: submodule bump (LEEKey)
- `3d13250` feat(#96): expose loadKey/removeKey for testing; update halt
- `ea2d6c9` fix(#96): authorize JSON arg parsing, loadKey/removeKey setKeyMode, detectMode refresh

---

## Key findings from this session

1. **logoscore arg passing**: Unquoted string args (e.g., `abcdef`) are passed raw. JSON-quoted
   strings (`'"000440"'`) are passed WITH the surrounding quote chars. Numbers with leading
   zeros (`000440`) fail JSON parsing → METHOD_FAILED. Use `'{"pin":"000440"}'` format.

2. **LEE capability bit persists after removeKey**: Tag 0x8D bit 5 stays set after removing a
   LEE key. Use `appInfo.keyUID.isEmpty()` as the authoritative "key loaded" indicator.

3. **CommandSet::select() is cached**: `select()` returns cached `m_appInfo` if already parsed.
   Use `select(true)` to force a fresh SELECT — BUT this breaks any existing SC. Better: track
   key mode manually via setKeyMode() after loadKey/removeKey.

4. **Pairing storage injection**: keycard-pairings.json key must be base64-encoded raw pairing
   key. Our slot 0 key: `TtowilnWIJYvyZ0aCINvThI4HINpEI+L0zrr7E62KlY=` (index 0).

---

## Next steps

1. **Senty review of #96** — handoff posted on GitHub, ping Senty to review
2. **Pairing bug** — pairCard() has PBKDF2 mismatch vs keycard-go. File as separate issue.
3. **#98** — requestSign API (Schnorr signing from the module)
4. **#97** — mode-aware pairing
5. **#109** — mock state bar

---

## Logoscore test sequence (for next session)

```bash
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
$LOGOSCORE -D --modules-dir ~/.local/share/Logos/LogosApp/modules &
sleep 5
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader
$LOGOSCORE call keycard discoverCard
$LOGOSCORE call keycard authorize '{"pin":"000440"}'
$LOGOSCORE call keycard detectMode
```
