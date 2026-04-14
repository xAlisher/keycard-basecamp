#!/usr/bin/env bash
# Headless integration tests for keycard-basecamp.
#
# Two sections:
#   1. Pure input-validation tests — return before any card/bridge interaction
#   2. Mode-mismatch tests — require card present (uses live bridge state)
#
# No PIN entry required. Exits non-zero on any failure.
#
# Usage:
#   ./tests/run-software-tests.sh
#   LOGOSCORE=/path/to/logoscore ./tests/run-software-tests.sh

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

LOGOSCORE="${LOGOSCORE:-}"
MODULES_DIR="${MODULES_DIR:-}"

if [[ "${1:-}" == "--logoscore" ]]; then
    LOGOSCORE="$2"; shift 2
fi

if [[ -z "$LOGOSCORE" ]]; then
    LOGOSCORE=$(find /nix/store -maxdepth 3 -name "logoscore" \
        -path "*/logos-logoscore-cli/bin/*" 2>/dev/null | head -1)
fi

if [[ -z "$LOGOSCORE" || ! -x "$LOGOSCORE" ]]; then
    echo "ERROR: logoscore not found. Set LOGOSCORE env var." >&2; exit 1
fi

KEYCARD_SO="$HOME/.local/share/Logos/LogosApp/modules/keycard/keycard_plugin.so"
if [[ ! -f "$KEYCARD_SO" ]]; then
    echo "ERROR: keycard_plugin.so not found. Run: cmake --install build --prefix ~/.local/share/Logos/LogosApp" >&2
    exit 1
fi

if [[ -z "$MODULES_DIR" ]]; then
    MODULES_DIR=$(mktemp -d)
    mkdir -p "$MODULES_DIR/keycard"
    cp -r "$HOME/.local/share/Logos/LogosApp/modules/keycard/." "$MODULES_DIR/keycard/"
    CLEANUP_MODULES=1
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

PASS=0; FAIL=0
DAEMON_PID=""

log_pass() { echo "  ✓ $1"; ((PASS++)) || true; }
log_fail() { echo "  ✗ $1"; ((FAIL++)) || true; }

call() {
    "$LOGOSCORE" call keycard "$@" 2>/dev/null \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result','{}'))"
}

assert_field() {
    local desc="$1" json="$2" field="$3" expected="$4"
    local actual
    actual=$(echo "$json" | python3 -c \
        "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('$field',''))" 2>/dev/null)
    if [[ "$actual" == "$expected" ]]; then log_pass "$desc"
    else log_fail "$desc (expected $field='$expected', got $field='$actual')"; fi
}

assert_has_field() {
    local desc="$1" json="$2" field="$3"
    local actual
    actual=$(echo "$json" | python3 -c \
        "import sys,json; d=json.loads(sys.stdin.read()); print('yes' if '$field' in d else 'no')" 2>/dev/null)
    if [[ "$actual" == "yes" ]]; then log_pass "$desc"
    else log_fail "$desc (field '$field' missing in: $json)"; fi
}

assert_not_field() {
    local desc="$1" json="$2" field="$3"
    local actual
    actual=$(echo "$json" | python3 -c \
        "import sys,json; d=json.loads(sys.stdin.read()); print('yes' if '$field' in d else 'no')" 2>/dev/null)
    if [[ "$actual" == "no" ]]; then log_pass "$desc"
    else log_fail "$desc (field '$field' should be absent in: $json)"; fi
}

extract_field() {
    local json="$1" field="$2"
    echo "$json" | python3 -c \
        "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('$field',''))" 2>/dev/null
}

start_daemon() {
    local pid_file="$HOME/.logoscore/daemon.json"
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid=$(python3 -c "import json; print(json.load(open('$pid_file'))['pid'])" 2>/dev/null || true)
        [[ -n "$old_pid" ]] && kill -9 "$old_pid" 2>/dev/null || true
        rm -f "$pid_file"
    fi
    "$LOGOSCORE" -D --modules-dir "$MODULES_DIR" >/tmp/logoscore-test.log 2>&1 &
    DAEMON_PID=$!
    sleep 5
    "$LOGOSCORE" load-module keycard >/dev/null 2>&1
}

stop_daemon() {
    [[ -n "$DAEMON_PID" ]] && kill "$DAEMON_PID" 2>/dev/null || true
    [[ -n "${CLEANUP_MODULES:-}" ]] && rm -rf "$MODULES_DIR"
}

# Restart daemon if it died (e.g. plugin crash during card discovery)
ensure_daemon() {
    if ! "$LOGOSCORE" call keycard getPendingSigns >/dev/null 2>&1; then
        DAEMON_PID=""
        start_daemon
    fi
}

trap stop_daemon EXIT

VALID_HASH="0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"

# ── Start ─────────────────────────────────────────────────────────────────────

echo ""
echo "keycard-basecamp headless integration tests"
echo "============================================"
echo "logoscore: $LOGOSCORE"
echo "module:    $KEYCARD_SO"
echo ""

start_daemon

# ── 1. Empty state checks (before anything is enqueued) ───────────────────────
echo "Empty state"

R=$(call getPendingSigns)
assert_field "getPendingSigns count=0 on fresh start" "$R" "count" "0"

R=$(call getPendingAuths)
assert_field "getPendingAuths count=0 on fresh start" "$R" "count" "0"

echo ""

# ── 2. requestSign: input validation (returns before bridge interaction) ───────
echo "requestSign — input validation"

R=$(call requestSign '{}')
assert_has_field "missing all fields → error" "$R" "error"

R=$(call requestSign "{\"domain\":\"x\",\"payloadHash\":\"aabb\",\"caller\":\"test\",\"scheme\":\"ecdsa\"}")
assert_has_field "payloadHash not 32 bytes → error" "$R" "error"

R=$(call requestSign "{\"domain\":\"x\",\"payloadHash\":\"$VALID_HASH\",\"caller\":\"test\",\"scheme\":\"bad\"}")
assert_has_field "unknown scheme → error" "$R" "error"

R=$(call requestSign "{\"domain\":\"\",\"payloadHash\":\"$VALID_HASH\",\"caller\":\"test\",\"scheme\":\"ecdsa\"}")
assert_has_field "empty domain → error" "$R" "error"

R=$(call requestSign "{\"domain\":\"x\",\"payloadHash\":\"$VALID_HASH\",\"caller\":\"\",\"scheme\":\"ecdsa\"}")
assert_has_field "empty caller → error" "$R" "error"

echo ""

# ── 3. requestSign: both schemes valid on any key type (live card required) ────
# Per bitgamma review: both Schnorr and ECDSA are valid on either key type.
# The P2 byte selects the scheme on-card; mode only gates "no key loaded".
echo "requestSign — both schemes accepted on any key type (live card)"

DETECT_R=$(call detectMode) || DETECT_R='{}'
CARD_MODE=$(extract_field "$DETECT_R" "mode") || CARD_MODE=""

if [[ "$CARD_MODE" == "none" || "$CARD_MODE" == "" ]]; then
    echo "  (skipped — no key loaded on card)"
elif [[ "$CARD_MODE" == "LEE" || "$CARD_MODE" == "BIP39" ]]; then
    # Schnorr should be accepted on either key type
    R=$(call requestSign "{\"domain\":\"test\",\"payloadHash\":\"$VALID_HASH\",\"caller\":\"test\",\"scheme\":\"schnorr\"}")
    assert_not_field "schnorr on $CARD_MODE card → no error" "$R" "error"
    assert_field     "schnorr on $CARD_MODE card → status pending" "$R" "status" "pending"
    PENDING_SCHNORR=$(extract_field "$R" "signId") || PENDING_SCHNORR=""

    # ECDSA should also be accepted on either key type
    R=$(call requestSign "{\"domain\":\"test\",\"payloadHash\":\"$VALID_HASH\",\"caller\":\"test\",\"scheme\":\"ecdsa\"}")
    assert_not_field "ecdsa on $CARD_MODE card → no error" "$R" "error"
    assert_field     "ecdsa on $CARD_MODE card → status pending" "$R" "status" "pending"
    PENDING_ECDSA=$(extract_field "$R" "signId") || PENDING_ECDSA=""

    # Clean up
    [[ -n "$PENDING_SCHNORR" ]] && "$LOGOSCORE" call keycard rejectSign "{\"signId\":\"$PENDING_SCHNORR\"}" >/dev/null 2>&1 || true
    [[ -n "$PENDING_ECDSA"   ]] && "$LOGOSCORE" call keycard rejectSign "{\"signId\":\"$PENDING_ECDSA\"}"   >/dev/null 2>&1 || true
fi

echo ""

# ── 4. approveSign: input validation ──────────────────────────────────────────
# Restart daemon if the plugin crashed during card discovery above.
ensure_daemon
echo "approveSign — input validation"

R=$(call approveSign '{}')
assert_has_field "empty json → error" "$R" "error"

R=$(call approveSign '{"signId":"","pin":"000440"}')
assert_has_field "empty signId → error" "$R" "error"

R=$(call approveSign '{"signId":"some-id","pin":""}')
assert_has_field "empty pin → error (no card touch)" "$R" "error"

R=$(call approveSign '{"signId":"00000000-0000-0000-0000-000000000000","pin":"000440"}')
assert_has_field "unknown signId → error" "$R" "error"

echo ""

# ── 5. checkSignStatus / rejectSign ───────────────────────────────────────────
echo "checkSignStatus / rejectSign — unknown ids"

R=$(call checkSignStatus '{"signId":"00000000-0000-0000-0000-000000000000"}')
assert_has_field "checkSignStatus unknown id → error" "$R" "error"

R=$(call rejectSign '{"signId":"00000000-0000-0000-0000-000000000000"}')
assert_has_field "rejectSign unknown id → error" "$R" "error"

echo ""

# ── 6. rejectSign lifecycle ────────────────────────────────────────────────────
echo "rejectSign — full lifecycle (requires card for requestSign)"

if [[ "$CARD_MODE" == "LEE" || "$CARD_MODE" == "BIP39" ]]; then
    SCHEME=$([[ "$CARD_MODE" == "LEE" ]] && echo "schnorr" || echo "ecdsa")
    R=$(call requestSign "{\"domain\":\"reject-test\",\"payloadHash\":\"$VALID_HASH\",\"caller\":\"test\",\"scheme\":\"$SCHEME\"}")
    REJ_ID=$(extract_field "$R" "signId")

    if [[ -n "$REJ_ID" ]]; then
        R=$(call getPendingSigns)
        assert_has_field "getPendingSigns shows request" "$R" "pending"

        R=$(call rejectSign "{\"signId\":\"$REJ_ID\"}")
        assert_field "rejectSign → status rejected" "$R" "status" "rejected"

        R=$(call checkSignStatus "{\"signId\":\"$REJ_ID\"}")
        # Rejected requests are removed; status returns error or rejected
        assert_has_field "checkSignStatus after reject → not found or rejected" "$R" "status"
    fi
else
    echo "  (skipped — no key on card)"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then echo "FAIL"; exit 1
else echo "PASS"; exit 0; fi
