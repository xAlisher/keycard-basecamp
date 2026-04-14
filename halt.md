# Halt — 2026-04-14 (#98 merged, waiting on bitgamma review of epic #95)

## Where we stopped

#98 (requestSign API) merged to master. LGTM from Senty. Epic #95 is pending
bitgamma review before the whole epic merges.

---

## Completed this session

- `#96` — LEE/Schnorr signing modes: keycard-qt patches + detectMode + setKeyMode.
  LGTM from Senty. Waiting on bitgamma review before epic merge.
- `#98` — requestSign API (on-card signing, ECDSA + Schnorr). Merged to master.
  Schnorr verified end-to-end. ECDSA gap: needs BIP39 card (noted on issue).
- `#110` — Pairing PBKDF2 bug issue filed.
- `#111` — Automated headless integration tests issue filed.
- basecamp-skills — major housekeeping: 5 new/updated skills migrated from
  keycard-basecamp (logoscore-headless-testing, keycard-qt-api, platform-state-machine,
  logos-tutorial-adoption, qml-patterns, basecamp-security-patterns, platform-lessons).

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

Card currently has **LEE key loaded** (from #96 testing).

---

## Next steps (in order)

1. **bitgamma review of epic #95** — ping if no response in 48h
2. **#97** — mode-aware pairing
3. **#109** — mock state bar
4. **#111** — automated headless tests
5. **#110** — pairing PBKDF2 bug
6. **ECDSA sign path** — verify on BIP39 card when #97 lands (easy: removeKey + loadKey BIP39)

---

## Logoscore test sequence (for next session)

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
