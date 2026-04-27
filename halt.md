# Halt — 2026-04-25

## Where We Stopped

Completed: keycard PRs #151, #145, #153 merged to master. Beacon PR #2 (keycard integration) merged to main. Post-merge retros done for both. Testing plan written — not yet executed. `issue-155-headless-tests` branch has regression.sh + PROJECT_KNOWLEDGE updates, 8 commits ahead of origin, not yet pushed.

---

## Current State

- **Branch:** `issue-155-headless-tests`
- **Last commit:** `182eab7` — Merge remote-tracking branch 'origin/master' into issue-155-headless-tests
- **Build status:** passing (cmake --build build -j$(nproc) clean)
- **Open review:** none — waiting to push + open PR for issue-155

---

## Card Credentials

```
Dev card:        PIN 000440 / PUK 193258644395 / Pairing jyairW2naGbqtzDp
Regression card: PIN 111111
InstanceUID:     c5196e35721641a3902e8421c8fc0ba0
```

Pairing in `~/.local/share/Logos/LogosApp/keycard-pairings.json`

---

## Key Paths

```
AppImage:  ~/logos-basecamp-current.AppImage
logoscore: /nix/store/4yx67kjfwvfqx795ap20imgzds458x2g-logos-logoscore-cli-bin-0.1.0/bin/logoscore
Kill:      pkill -9 -f '\.LogosBasecamp\.elf'
```

---

## Next Steps (in order)

### 1. Push issue-155-headless-tests + open PR

```bash
cd /home/alisher/basecamp/modules/keycard-basecamp
git push -u origin issue-155-headless-tests
gh pr create --title "feat(#155): headless regression test suite" \
  --body "Regression tests for PRs #145, #151, #153. Requires card in reader, PIN 111111."
```

Then Senty review: `/codex:rescue Senty review of keycard-basecamp issue-155-headless-tests`

### 2. Run the full testing plan (see below)

Sections A–E are headless (logoscore). Sections F–G require AppImage + physical card.

### 3. Fix Senty 403 on GitHub comments

Settings → GitHub Apps → grant Claude/Codex App write access to `xAlisher/beacon-basecamp`

---

## Blockers

- **pcsclite nix/system version mismatch**: nix pcsclite 2.3.0 vs system pcscd 2.0.3. CMD_VERSION IPC change → SCARD_E_NO_SERVICE. Background detection thread never starts. Workaround: `export LD_LIBRARY_PATH=""` before logoscore commands. Skill: `pcsclite-nix-system-version-mismatch`.
- **Senty 403**: GitHub token lacks write access to xAlisher/beacon-basecamp — inline delivery only.

---

## What Was Completed (for context)

| Item | Status |
|------|--------|
| PR #151 — arbitrary BIP32 paths + 1582' signing subtree | Merged |
| PR #145 — XPUB EIP-1581 root path, correct TLV tags | Merged |
| eventResponse (#153) — keycardAuthComplete/Rejected after authorize/reject | Merged |
| Beacon PR #2 — keycard auth integration (keycardConnected guard, clearSigningKey, cardCheckTimer) | Merged |
| Post-merge retros — 4 new skills extracted | Done |
| regression.sh — headless test suite for PRs above | Written, not run |

---

## Testing Plan

Full plan for everything visible to the user from recent work (keycard PRs #145, #151, #153 + beacon PR #2).

### A — Headless Regression (keycard, no UI)

```bash
cd /home/alisher/basecamp/modules/keycard-basecamp

# Kill any stale logoscore daemon
pkill -9 -f logoscore 2>/dev/null; sleep 1

# Build fresh module dir (keycard only — full dir crashes on capability_module)
MDIR=$(mktemp -d) && mkdir -p "$MDIR/keycard"
cp -r ~/.local/share/Logos/LogosApp/modules/keycard/. "$MDIR/keycard/"

# Start daemon
LOGOSCORE=/nix/store/4yx67kjfwvfqx795ap20imgzds458x2g-logos-logoscore-cli-bin-0.1.0/bin/logoscore
$LOGOSCORE -D --modules-dir "$MDIR" &
sleep 5

# Load module
$LOGOSCORE load-module keycard

# Run full regression
bash tests/headless/regression.sh
```

Expected: all sections PASS (or SKIP if card absent).

**pcsclite workaround if SCARD_E_NO_SERVICE:**
```bash
export LD_LIBRARY_PATH=""
# then re-run logoscore commands
```

### B — BIP32 Path Validation (PR #151)

```bash
# Valid path — must queue
$LOGOSCORE call keycard requestSign \
  '{"bip32_path":"m/44'"'"'/60'"'"'/0'"'"'/0/0","payload":"deadbeef"}'
# Expected: ok, pending sign queued

# Invalid — no m/ prefix
$LOGOSCORE call keycard requestSign \
  '{"bip32_path":"44/60/0/0","payload":"deadbeef"}'
# Expected: error — path must start with m/
```

### C — Domain Path Routing (1581' vs 1582')

```bash
# Auth path — must route to m/43'/60'/1581'/<domain-hash>
$LOGOSCORE call keycard requestAuth \
  '{"domain":"logos_beacon","caller":"logos_beacon"}'
$LOGOSCORE call keycard getPendingAuths '{}'
# Expected: effective_path starts 43'/60'/1581'

# Signing path — must route to m/43'/60'/1582'/<domain-hash>
$LOGOSCORE call keycard requestSign \
  '{"bip32_path":"m/43'"'"'/60'"'"'/1582'"'"'/0/0","payload":"cafebabe"}'
$LOGOSCORE call keycard getPendingSigns '{}'
# Expected: effective_path starts 43'/60'/1582'
```

### D — XPUB Export (PR #145)

```bash
# Request XPUB for EIP-1581 root path
$LOGOSCORE call keycard requestXPUB \
  '{"bip32_path":"m/43'"'"'/60'"'"'/1581'"'"'"}'

# Get pending XPUB request ID
XPUB_ID=$($LOGOSCORE call keycard getPendingXPUBRequests '{}' \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(json.loads(r['result'])[0]['id'])")

# Approve (requires card + PIN)
$LOGOSCORE call keycard approveXPUB "{\"id\":\"$XPUB_ID\",\"pin\":\"111111\"}"

# Check result — one-read-and-drop
$LOGOSCORE call keycard checkXPUBStatus "{\"id\":\"$XPUB_ID\"}"
# Expected: xpub field present

# Second call should return not_found or empty (one-read-and-drop)
$LOGOSCORE call keycard checkXPUBStatus "{\"id\":\"$XPUB_ID\"}"
```

### E — Auth + eventResponse Flow (PR #153)

```bash
# 1. Request auth
$LOGOSCORE call keycard requestAuth \
  '{"domain":"logos_beacon","caller":"logos_beacon"}'

# 2. Get pending auth ID
AUTH_ID=$($LOGOSCORE call keycard getPendingAuths '{}' \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(json.loads(r['result'])[0]['id'])")

# 3. Authorize (approve path) — PIN in JSON object, not bare string
$LOGOSCORE call keycard authorizeRequest \
  "{\"id\":\"$AUTH_ID\",\"pin\":\"111111\"}"

# 4. Check status — one-read-and-drop
$LOGOSCORE call keycard checkAuthStatus "{\"id\":\"$AUTH_ID\"}"
# Expected: status=complete, key present

# 5. Reject path
$LOGOSCORE call keycard requestAuth \
  '{"domain":"logos_beacon","caller":"logos_beacon"}'
AUTH_ID2=$($LOGOSCORE call keycard getPendingAuths '{}' \
  | python3 -c "import sys,json; r=json.load(sys.stdin); print(json.loads(r['result'])[0]['id'])")
$LOGOSCORE call keycard rejectRequest "{\"id\":\"$AUTH_ID2\"}"
$LOGOSCORE call keycard checkAuthStatus "{\"id\":\"$AUTH_ID2\"}"
# Expected: status=rejected
```

### F — Beacon Integration Lifecycle (manual, AppImage)

```bash
pkill -9 -f '\.LogosBasecamp\.elf' 2>/dev/null; sleep 1
~/logos-basecamp-current.AppImage &
sleep 5
```

Steps:
1. **Open Beacon tab** → UI shows "Connect your Keycard" or "Waiting for Keycard approval"
2. **Open Keycard tab** → pending auth from `logos_beacon` visible
3. **Enter PIN → approve** → switch to Beacon tab: channel ID appears, stash polling active
4. **Enable Watch Stash toggle** → no error spinner
5. **Upload a note** → within ~10s Beacon shows new inscription row
6. **Remove card physically** → Beacon stops, re-requests auth (8s cardCheckTimer)
7. **Re-insert card** → Keycard tab shows new pending auth from `logos_beacon`
8. **Re-approve** → Beacon resumes, same channel ID shown

Verify:
- Channel ID identical before/after card removal
- `keycardConnected` UI: false → true → false → true
- Inscription log shows rows with status dots

### G — XPUB UI Smoke (AppImage, if XPUB panel exists)

1. Open Keycard tab → XPUB section
2. Request XPUB for default path
3. Approve with PIN
4. Verify XPUB string appears (not empty, starts with `xpub`)
5. Close and reopen tab — XPUB should not persist (one-read-and-drop)
