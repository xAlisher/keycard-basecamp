# Halt — 2026-04-14 (epic #95 waiting on bitgamma review before any merges)

## Where we stopped

#96 and #98 both have Senty LGTM. All branches are sitting open, waiting on
bitgamma review of epic #95 before anything merges to master.

---

## Branch state

| Branch | Issue | Senty | bitgamma | Notes |
|--------|-------|-------|----------|-------|
| `master` | — | — | — | Clean, no #96/#98 code yet |
| `issue-98-request-sign` | #98 | LGTM Round 2 | pending | requestSign API |
| keycard-qt submodule | #96 | LGTM | pending | signWithPath scheme + loadKey type |

All #96 commits are on master (they landed before the epic-merge rule was set).
#98 is on its branch, not yet merged.

---

## Card credentials

```
PIN: 000440
PUK: 193258644395
Pairing password: jyairW2naGbqtzDp
InstanceUID: c5196e35721641a3902e8421c8fc0ba0
```

Pairing in `~/.local/share/Logos/LogosBasecamp/keycard-pairings.json` and
`~/.local/share/Logos/LogosApp/keycard-pairings.json`.

```
PAIRING KEY (b64): TtowilnWIJYvyZ0aCINvThI4HINpEI+L0zrr7E62KlY=
PAIRING INDEX: 0
```

Card currently has **LEE key loaded** (from #96 testing).

---

## Next steps (in order)

1. **Wait for bitgamma review of epic #95** — then merge #96 + #98 together
2. **#97** — mode-aware pairing
3. **#109** — mock state bar
4. **#111** — automated headless tests
5. **#110** — pairing PBKDF2 bug
6. **ECDSA sign path** — verify on BIP39 card when #97 lands

---

## Logoscore test sequence

```bash
LOGOSCORE=/nix/store/4v00839956lahxv54hf581x58z32nj4r-logos-logoscore-cli/bin/logoscore
kill -9 $(cat ~/.logoscore/daemon.json | python3 -c "import sys,json; print(json.load(sys.stdin)['pid'])") 2>/dev/null
rm -f ~/.logoscore/daemon.json
mkdir -p /tmp/test-modules && cp -r ~/.local/share/Logos/LogosApp/modules/keycard /tmp/test-modules/
$LOGOSCORE -D --modules-dir /tmp/test-modules &
sleep 5
$LOGOSCORE load-module keycard
$LOGOSCORE call keycard discoverReader
$LOGOSCORE call keycard discoverCard
$LOGOSCORE call keycard authorize '{"pin":"000440"}'
$LOGOSCORE call keycard detectMode
```

Note: use `/tmp/test-modules` with keycard only — full modules dir crashes on
capability_module.
