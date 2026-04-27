#!/usr/bin/env bash
# Keycard headless regression suite
# Tests PRs #145 (XPUB bip32_path), #151 (format-only validation), #153 (eventResponse)
# Requires: real card in reader, PIN 111111
# Usage: bash tests/headless/regression.sh

set -euo pipefail

# Nix shell sets LD_LIBRARY_PATH to nix store paths which pulls in pcsclite 2.3.0.
# System pcscd is 2.0.3 — the CMD_VERSION IPC protocol changed between versions.
# Clearing LD_LIBRARY_PATH forces the plugin to use system libpcsclite.so.1 (2.0.3).
export LD_LIBRARY_PATH=""

LOGOSCORE=/nix/store/4yx67kjfwvfqx795ap20imgzds458x2g-logos-logoscore-cli-bin-0.1.0/bin/logoscore
PIN="111111"
PASS=0
FAIL=0
SKIP=0

# ── helpers ──────────────────────────────────────────────────────────────────

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

pass() { green "  PASS: $1"; PASS=$((PASS+1)); }
fail() { red   "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { yellow "  SKIP: $1"; SKIP=$((SKIP+1)); }

# Call keycard and unwrap {"result":"..."} envelope (same as run-software-tests.sh call())
kc() {
    $LOGOSCORE call keycard "$@" 2>/dev/null \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result','{}'))"
}

# Assert result contains a key with given value substring
assert_has() {
    local desc="$1" key="$2" want="$3" got="$4"
    if echo "$got" | python3 -c "import sys,json; d=json.load(sys.stdin); v=str(d.get('$key','')); exit(0 if '$want' in v else 1)" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc  [got: $got]"
    fi
}

# Assert result has an "error" field
assert_error() {
    local desc="$1" got="$2"
    if echo "$got" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'error' in d else 1)" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc — expected error, got: $got"
    fi
}

# Assert result contains a non-empty value for the given key
assert_key_exists() {
    local desc="$1" key="$2" got="$3"
    if echo "$got" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d.get('$key',''); exit(0 if v != '' else 1)" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc  [got: $got]"
    fi
}

# Assert result has NO "error" field
assert_ok() {
    local desc="$1" got="$2"
    if echo "$got" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(1 if 'error' in d else 0)" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc — unexpected error: $got"
    fi
}

PAYLOAD32="a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1c2d3e4f5a0b1"

# ── setup ────────────────────────────────────────────────────────────────────

bold "=== Keycard Regression Suite ==="
echo "Card PIN: $PIN"
echo ""

# Build and install current branch to ensure we test the branch, not a stale install
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -d "$REPO_ROOT/build" ]; then
    if cmake --build "$REPO_ROOT/build" -j"$(nproc)" 2>/dev/null \
        && cmake --install "$REPO_ROOT/build" > /dev/null 2>&1; then
        echo "Build+install: ok (testing current branch)"
    else
        yellow "WARNING: build/install failed — testing currently installed module (may not reflect branch)"
    fi
else
    yellow "WARNING: no build/ dir found — testing whatever is currently installed"
fi

# Kill stale daemon
pkill -9 -f "logoscore" 2>/dev/null || true
sleep 1
rm -f ~/.logoscore/daemon.json

mkdir -p /tmp/test-modules-kc
cp -r ~/.local/share/Logos/LogosBasecamp/modules/keycard /tmp/test-modules-kc/

$LOGOSCORE -D --modules-dir /tmp/test-modules-kc > /tmp/logoscore-kc.log 2>&1 &
sleep 5

LOAD=$($LOGOSCORE load-module keycard 2>/dev/null)
if ! echo "$LOAD" | grep -q '"ok"'; then
    red "ERROR: could not load keycard module — aborting"
    cat /tmp/logoscore-kc.log | tail -20
    exit 1
fi

echo "Module loaded. Discovering hardware..."
kc discoverReader > /dev/null
# Skip discoverCard: its isCardPresent() calls SCardGetStatusChange(2000ms) on the
# main Qt thread, stalling the QRemoteObjects heartbeat and dropping the connection.
# The background detection thread started by discoverReader finds the card on its own.
sleep 3

# ── Section 1: requestSign format-only validation (PR #151) ──────────────────

bold ""
bold "=== 1. requestSign bip32_path format validation (PR #151) ==="

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m\"}")
assert_key_exists "bare 'm' is valid" "signId" "$R"

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m/43'/60'/1582'\"}")
assert_key_exists "standard signing path" "signId" "$R"

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"ecdsa\",\"bip32_path\":\"m/44'/0'/0'/0/0\"}")
assert_key_exists "wallet path mixed hardened/normal" "signId" "$R"

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m/43'/60'/1581'\"}")
assert_key_exists "1581' path no longer blocked host-side" "signId" "$R"

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m/abc\"}")
assert_error "non-decimal segment rejected" "$R"

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"44'/0'\"}")
assert_error "path without leading m/ rejected" "$R"

R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\"}")
assert_error "missing domain and bip32_path rejected" "$R"

R=$(kc requestSign "{\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m/44'\"}")
assert_error "missing payloadHash rejected" "$R"

R=$(kc requestSign "{\"payloadHash\":\"tooshort\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m/44'\"}")
assert_error "wrong-length payloadHash rejected" "$R"

R=$(kc requestSign "{\"domain\":\"bc:test\",\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\"}")
assert_key_exists "domain-only (no bip32_path) still accepted" "signId" "$R"

# ── Section 2: getPendingSigns effective_path ─────────────────────────────────

bold ""
bold "=== 2. getPendingSigns effective_path field ==="

# Queue a domain-based sign request
R=$(kc requestSign "{\"domain\":\"bc:beacon\",\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\"}")
SIGN_ID=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('signId',''))" 2>/dev/null)

if [ -n "$SIGN_ID" ]; then
    PEND=$(kc getPendingSigns)
    if echo "$PEND" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reqs=d.get('pending',[])
found=[r for r in reqs if r.get('effective_path','').startswith(\"m/43'/60'/1582'\")]
exit(0 if found else 1)
" 2>/dev/null; then
        pass "domain-based sign uses 1582' signing subtree in effective_path"
    else
        fail "effective_path not starting with m/43'/60'/1582' — got: $PEND"
    fi
else
    skip "could not queue domain sign request"
fi

# Queue an explicit-path sign request
R=$(kc requestSign "{\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\",\"bip32_path\":\"m/44'/0'/0'\"}")
SIGN_ID2=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('signId',''))" 2>/dev/null)

if [ -n "$SIGN_ID2" ]; then
    PEND=$(kc getPendingSigns)
    if echo "$PEND" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reqs=d.get('pending',[])
found=[r for r in reqs if r.get('effective_path','')==\"m/44'/0'/0'\"]
exit(0 if found else 1)
" 2>/dev/null; then
        pass "explicit bip32_path shown as effective_path"
    else
        fail "explicit bip32_path not in effective_path — got: $PEND"
    fi
else
    skip "could not queue explicit-path sign request"
fi

# ── Section 3: requestXPUB mandatory bip32_path (PR #145) ────────────────────

bold ""
bold "=== 3. requestXPUB / approveXPUB (PR #145) ==="

R=$(kc requestXPUB "{\"caller\":\"test\"}")
assert_error "requestXPUB missing bip32_path rejected" "$R"

R=$(kc requestXPUB "{\"domain\":\"test\",\"caller\":\"test\"}")
assert_error "requestXPUB with old domain param rejected" "$R"

R=$(kc requestXPUB "{\"bip32_path\":\"m/abc\",\"caller\":\"test\"}")
assert_error "requestXPUB invalid path format rejected" "$R"

R=$(kc requestXPUB "{\"bip32_path\":\"m/43'/60'/1581'\",\"caller\":\"test\"}")
assert_ok "requestXPUB with valid bip32_path accepted" "$R"
XPUB_ID=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('xpubId',''))" 2>/dev/null)

bold ""
bold "--- XPUB approval (real card) ---"

if [ -n "$XPUB_ID" ]; then
    echo "  Approving xpubId: ${XPUB_ID:0:8}... with PIN $PIN"
    R=$(kc approveXPUB "{\"xpubId\":\"$XPUB_ID\",\"pin\":\"$PIN\"}")
    if echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='complete' else 1)" 2>/dev/null; then
        pass "approveXPUB returns status:complete"

        # Retrieve XPUB — one-read-and-drop
        STATUS=$(kc checkXPUBStatus "{\"xpubId\":\"$XPUB_ID\"}")
        if echo "$STATUS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
xpub=d.get('xpub','')
path=d.get('bip32_path','')
exit(0 if len(xpub)==194 and path==\"m/43'/60'/1581'\" else 1)
" 2>/dev/null; then
            pass "checkXPUBStatus returns 97-byte xpub (194 hex chars) and correct bip32_path"
        else
            fail "checkXPUBStatus unexpected response: $STATUS"
        fi

        # Second read must be gone (one-read-and-drop)
        STATUS2=$(kc checkXPUBStatus "{\"xpubId\":\"$XPUB_ID\"}")
        assert_error "checkXPUBStatus second read returns not-found (one-read-and-drop)" "$STATUS2"

    else
        fail "approveXPUB failed — got: $R"
        skip "checkXPUBStatus one-read-and-drop (skipped: approval failed)"
        skip "checkXPUBStatus second-read gone (skipped: approval failed)"
    fi
else
    skip "approveXPUB — could not get xpubId"
    skip "checkXPUBStatus one-read-and-drop — skipped"
    skip "checkXPUBStatus second-read gone — skipped"
fi

# ── Section 4: auth request flow + one-read-and-drop (PR #153 context) ───────

bold ""
bold "=== 4. Auth flow: requestAuth → authorizeRequest → checkAuthStatus ==="

R=$(kc requestAuth "bc:beacon" "logos_beacon")
AUTH_ID=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('authId',''))" 2>/dev/null)

if [ -n "$AUTH_ID" ]; then
    pass "requestAuth returns authId"

    echo "  Authorizing authId: ${AUTH_ID:0:8}... with PIN $PIN"
    R=$(kc authorizeRequest "$AUTH_ID" "{\"pin\":\"$PIN\"}")
    if echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='complete' else 1)" 2>/dev/null; then
        pass "authorizeRequest returns status:complete"

        # Read key once
        R=$(kc checkAuthStatus "$AUTH_ID")
        if echo "$R" | python3 -c "
import sys,json
d=json.load(sys.stdin)
key=d.get('key','')
exit(0 if len(key)==64 and d.get('status')=='complete' else 1)
" 2>/dev/null; then
            pass "checkAuthStatus returns 32-byte key (64 hex chars)"
        else
            fail "checkAuthStatus bad response: $R"
        fi

        # Second read must be gone
        R2=$(kc checkAuthStatus "$AUTH_ID")
        assert_error "checkAuthStatus second read returns not-found (one-read-and-drop)" "$R2"
    else
        fail "authorizeRequest failed — got: $R"
        skip "checkAuthStatus one-read-and-drop (skipped)"
    fi
else
    fail "requestAuth did not return authId — got: $R"
    skip "authorizeRequest (skipped)"
    skip "checkAuthStatus (skipped)"
fi

# ── Section 5: rejectRequest flow ────────────────────────────────────────────

bold ""
bold "=== 5. Reject auth request ==="

R=$(kc requestAuth "bc:notes" "logos_notes")
AUTH_ID2=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('authId',''))" 2>/dev/null)

if [ -n "$AUTH_ID2" ]; then
    pass "requestAuth (second) returns authId"

    R=$(kc rejectRequest "$AUTH_ID2")
    assert_has "rejectRequest returns status:rejected" "status" "rejected" "$R"

    R=$(kc checkAuthStatus "$AUTH_ID2")
    assert_has "checkAuthStatus after reject shows rejected" "status" "rejected" "$R"
else
    fail "requestAuth (second) failed"
    skip "rejectRequest (skipped)"
    skip "checkAuthStatus after reject (skipped)"
fi

# ── Section 6: domainToPath vs domainToSignPath different roots ───────────────

bold ""
bold "=== 6. Domain path routing: 1581' for auth, 1582' for sign ==="

R=$(kc requestAuth "bc:test" "test")
AUTH_ID3=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('authId',''))" 2>/dev/null)
if [ -n "$AUTH_ID3" ]; then
    pass "requestAuth 'bc:test' domain accepted"
    kc rejectRequest "$AUTH_ID3" > /dev/null 2>&1
else
    fail "requestAuth 'bc:test' failed: $R"
fi

R=$(kc requestSign "{\"domain\":\"bc:test\",\"payloadHash\":\"$PAYLOAD32\",\"caller\":\"test\",\"scheme\":\"schnorr\"}")
if echo "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'signId' in d else 1)" 2>/dev/null; then
    SIGN_ID3=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin)['signId'])")
    PEND=$(kc getPendingSigns)
    if echo "$PEND" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reqs=d.get('pending',[])
s=[r for r in reqs if r.get('signId','')==open('/dev/stdin').read().strip()]
" 2>/dev/null <<< "$SIGN_ID3" || true; then : ; fi

    if echo "$PEND" | python3 -c "
import sys,json,os
d=json.load(sys.stdin)
sid='$SIGN_ID3'
for r in d.get('pending',[]):
    if r.get('signId','') == sid:
        ep=r.get('effective_path','')
        exit(0 if ep.startswith(\"m/43'/60'/1582'\") else 1)
exit(1)
" 2>/dev/null; then
        pass "bc:test sign uses 1582' subtree (non-exportable signing key)"
    else
        fail "bc:test sign effective_path not under 1582': $PEND"
    fi
else
    fail "requestSign for bc:test failed: $R"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

bold ""
bold "=== Results ==="
green "  PASS: $PASS"
if [ "$FAIL" -gt 0 ]; then
    red "  FAIL: $FAIL"
else
    echo "  FAIL: $FAIL"
fi
yellow "  SKIP: $SKIP"
echo ""

pkill -9 -f "logoscore" 2>/dev/null || true

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
