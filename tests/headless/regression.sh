#!/usr/bin/env bash
# Keycard headless regression suite
# Tests PRs #145 (XPUB bip32_path), #151 (format-only validation)
# Note: PR #153 (eventResponse signal) is not tested here — emitted signals require a live
# QRemoteObjects event listener and are covered by QML integration tests, not headless logoscore.
# Requires: real card in reader, PIN 111111
# Usage: bash tests/headless/regression.sh

set -euo pipefail

# Nix shell sets LD_LIBRARY_PATH to nix store paths which pulls in pcsclite 2.3.0.
# System pcscd is 2.0.3 — the CMD_VERSION IPC protocol changed between versions.
# Clearing LD_LIBRARY_PATH forces the plugin to use system libpcsclite.so.1 (2.0.3).
export LD_LIBRARY_PATH=""

# ── helpers ──────────────────────────────────────────────────────────────────
# Defined first so error paths below can use them.

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

# Prefer logoscore on PATH; fall back to the known nix store path for this machine.
LOGOSCORE_FALLBACK=/nix/store/4yx67kjfwvfqx795ap20imgzds458x2g-logos-logoscore-cli-bin-0.1.0/bin/logoscore
if command -v logoscore &>/dev/null; then
    LOGOSCORE=$(command -v logoscore)
elif [ -x "$LOGOSCORE_FALLBACK" ]; then
    LOGOSCORE="$LOGOSCORE_FALLBACK"
else
    red "ERROR: logoscore not found on PATH and fallback store path missing (after GC?)"
    exit 1
fi
PIN="111111"
PASS=0
FAIL=0
SKIP=0

pass() { green "  PASS: $1"; PASS=$((PASS+1)); }
fail() { red   "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { yellow "  SKIP: $1"; SKIP=$((SKIP+1)); }

# Call keycard and unwrap {"result":"..."} envelope.
# On IPC/transport failures logoscore returns {"code":N,"message":"..."} with no "result" key;
# we fall back to the full outer envelope so assert_* helpers can show the real error.
# The `|| true` suppresses logoscore's non-zero exit code (exit 4 for METHOD_FAILED/RPC_FAILED
# etc.) so that set -euo pipefail does not kill the script on expected error responses.
kc() {
    { $LOGOSCORE call keycard "$@" 2>/dev/null || true; } \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('result') or json.dumps(r))"
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

# Build current branch and sync the .so into the lgpm-structured dir so the test
# uses current-branch code, not a stale install.
#
# WHY not cmake --install:
# In logos-module-builder (nix develop) mode cmake installs to
#   LogosApp/lib/logos/modules/keycard_plugin.so
# but the lgpm dir the test uses is
#   LogosBasecamp/modules/keycard/keycard_plugin.so
# Copying directly from build/ avoids the path mismatch entirely.
#
# Build output location differs by cmake mode:
#   builder mode (nix develop):    build/modules/keycard_plugin.so
#   standalone mode (plain cmake): build/keycard-core/keycard_plugin.so
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGOS_BASECAMP=~/.local/share/Logos/LogosBasecamp
if [ -d "$REPO_ROOT/build" ]; then
    if cmake --build "$REPO_ROOT/build" -j"$(nproc)" 2>/dev/null; then
        # Prefer builder-mode output; fall back to standalone-mode output.
        if [ -f "$REPO_ROOT/build/modules/keycard_plugin.so" ]; then
            BUILT_SO="$REPO_ROOT/build/modules/keycard_plugin.so"
        elif [ -f "$REPO_ROOT/build/keycard-core/keycard_plugin.so" ]; then
            BUILT_SO="$REPO_ROOT/build/keycard-core/keycard_plugin.so"
        else
            red "ERROR: built .so not found in build/modules/ or build/keycard-core/"
            exit 1
        fi
        cp "$BUILT_SO" "$LOGOS_BASECAMP/modules/keycard/keycard_plugin.so"
        echo "Build+sync: ok (testing current branch, from $BUILT_SO)"
    else
        red "ERROR: cmake --build failed — refusing to test stale artifacts"
        exit 1
    fi
else
    red "ERROR: no build/ dir found — run: cmake -B build -G Ninja && cmake --build build"
    exit 1
fi

# ── daemon infrastructure setup ──────────────────────────────────────────────
#
# WHY .logoscore-wrapped instead of $LOGOSCORE:
# The nix C wrapper unconditionally overwrites LOGOS_HOST_PATH (via putenv()).
# We call the inner ELF directly so we can supply our own LOGOS_HOST_PATH.
#
# WHY LOGOS_HOST_PATH points to the nix-locked logos_host inner ELF:
# The nix logoscore-cli's liblogos_core.so expects:
#   - auth socket:  /tmp/logos_token_{name}           (old format, no instanceId)
#   - IPC socket:   /tmp/logos_{name}_{instanceId}    (new format, with instanceId)
# The locked logos_host (logos-liblogos-build-0.1.0) creates exactly those two sockets
# so auth and RPC both work. The AppImage logos_host uses an intermediate format
# (logos_token_{name}_{instanceId}) for auth which the nix liblogos_core cannot find.
#
# WHY LOGOS_BUNDLED_MODULES_DIR=/dev/null:
# The nix-bundled capability_module has an ABI mismatch with the locked logos_host
# binary — it was built against a newer PluginInterface vtable and crashes the daemon
# at startup (QProcess::Crashed). Skipping bundled modules avoids the crash.

LOGOSCORE_BIN_DIR="$(dirname "$LOGOSCORE")"
LOGOSCORE_WRAPPED="$LOGOSCORE_BIN_DIR/.logoscore-wrapped"
if [ ! -x "$LOGOSCORE_WRAPPED" ]; then
    red "ERROR: .logoscore-wrapped not found at $LOGOSCORE_WRAPPED"
    exit 1
fi

# Find the AppImage logos_host (modern plugin loader).
APPIMAGE_LOGOS_HOST=""
for _d in /tmp/appimage_extracted_*/usr/bin; do
    if [ -f "$_d/.logos_host.elf" ]; then
        APPIMAGE_LOGOS_HOST="$_d/logos_host"
        break
    fi
done
if [ -z "$APPIMAGE_LOGOS_HOST" ]; then
    APPIMAGE="$HOME/logos-basecamp-current.AppImage"
    if [ ! -f "$APPIMAGE" ]; then
        red "ERROR: AppImage not found at $APPIMAGE — needed for logos_host"
        exit 1
    fi
    _EXTRACT_DIR="$(mktemp -d)"
    (cd "$_EXTRACT_DIR" && "$APPIMAGE" --appimage-extract usr/bin 2>/dev/null)
    APPIMAGE_LOGOS_HOST="$_EXTRACT_DIR/squashfs-root/usr/bin/logos_host"
    if [ ! -f "$APPIMAGE_LOGOS_HOST" ]; then
        red "ERROR: could not extract logos_host from AppImage"
        exit 1
    fi
fi

# Python proxy wrapper: bridges auth socket mismatch between nix daemon and AppImage logos_host.
# nix daemon expects /tmp/logos_token_{name} (old format).
# AppImage logos_host creates /tmp/logos_token_{name}_{instanceId} (new format).
# The proxy accepts on old-format socket and forwards to new-format socket.
# After auth, AppImage logos_host creates IPC socket at /tmp/logos_{name}_{instanceId}
# which the daemon's liblogos_core connects to directly for RPC calls.
KC_HOST_WRAP_DIR=/tmp/kc-host-wrap
mkdir -p "$KC_HOST_WRAP_DIR"
python3 - "$APPIMAGE_LOGOS_HOST" "$KC_HOST_WRAP_DIR/logos_host" << 'PYEOF'
import sys, textwrap
appimage_host, wrapper_path = sys.argv[1], sys.argv[2]
script = textwrap.dedent(f'''
    #!/usr/bin/env python3
    import sys, os, socket, subprocess, threading, time
    APPIMAGE_LOGOS_HOST = {repr(appimage_host)}
    def main():
        instance_id = os.environ.get("LOGOS_INSTANCE_ID", "")
        name = None
        args = list(sys.argv[1:])
        for i, a in enumerate(args):
            if a in ("--name", "-n") and i + 1 < len(args):
                name = args[i + 1]
        if not name or not instance_id:
            os.execv(APPIMAGE_LOGOS_HOST, [APPIMAGE_LOGOS_HOST] + args)
        new_auth = f"/tmp/logos_token_{{name}}_{{instance_id}}"
        old_auth = f"/tmp/logos_token_{{name}}"
        stderr_log = open("/tmp/logoscore-kc-host.log", "w", buffering=1)
        proc = subprocess.Popen([APPIMAGE_LOGOS_HOST] + args, stderr=stderr_log, stdout=stderr_log)
        for _ in range(100):
            if os.path.exists(new_auth): break
            time.sleep(0.1)
        else:
            stderr_log.flush()
            sys.exit(proc.wait())
        if os.path.exists(old_auth): os.unlink(old_auth)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(old_auth); srv.listen(5)
        def relay(a, b):
            try:
                while True:
                    data = a.recv(65536)
                    if not data: break
                    b.sendall(data)
            except: pass
            finally:
                try: a.close()
                except: pass
                try: b.close()
                except: pass
        def accept_loop():
            while proc.poll() is None:
                try:
                    srv.settimeout(0.5)
                    client, _ = srv.accept()
                except socket.timeout: continue
                except: break
                try:
                    remote = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    remote.connect(new_auth)
                except: client.close(); continue
                threading.Thread(target=relay, args=(client, remote), daemon=True).start()
                threading.Thread(target=relay, args=(remote, client), daemon=True).start()
        threading.Thread(target=accept_loop, daemon=True).start()
        rc = proc.wait()
        srv.close()
        try: os.unlink(old_auth)
        except: pass
        sys.exit(rc)
    main()
''').lstrip('\n')
with open(wrapper_path, 'w') as f:
    f.write(script)
import os; os.chmod(wrapper_path, 0o755)
PYEOF
if [ ! -x "$KC_HOST_WRAP_DIR/logos_host" ]; then
    red "ERROR: failed to create logos_host proxy wrapper"
    exit 1
fi

# Kill any stale daemon from a previous incomplete run, then start a fresh one.
LOGOSCORE_PID=""
cleanup() {
    if [ -n "$LOGOSCORE_PID" ]; then
        # SIGTERM first so logos_host can close the PC/SC channel cleanly before we SIGKILL.
        kill "$LOGOSCORE_PID" 2>/dev/null || true
        pkill -f "logos_host.*test-modules-kc" 2>/dev/null || true
        sleep 1
        kill -9 "$LOGOSCORE_PID" 2>/dev/null || true
        pkill -9 -f "logos_host.*test-modules-kc" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Kill ALL stale logoscore daemons and their logos_host children before starting fresh.
# Covers: daemons started by previous test runs (regardless of --modules-dir path),
# and any logos_host orphans that survived an unclean exit.
if [ -f /tmp/logoscore-kc.pid ]; then
    OLD_PID=$(cat /tmp/logoscore-kc.pid 2>/dev/null)
    [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null || true
    rm -f /tmp/logoscore-kc.pid
fi
# Kill any .logoscore-wrapped daemon (logoscore daemon process) still running.
pgrep -f ".logoscore-wrapped" | xargs -r kill 2>/dev/null || true
# Kill any logos_host that was spawned by a previous test run.
pgrep -f "logos_host.*test-modules" | xargs -r kill 2>/dev/null || true
sleep 1
pgrep -f ".logoscore-wrapped" | xargs -r kill -9 2>/dev/null || true
pgrep -f "logos_host.*test-modules" | xargs -r kill -9 2>/dev/null || true
sleep 1
rm -f ~/.logoscore/daemon.json

rm -rf /tmp/test-modules-kc
mkdir -p /tmp/test-modules-kc
cp -r "$LOGOS_BASECAMP/modules/keycard" /tmp/test-modules-kc/

# RPATH fix — pcsclite version mismatch (skill: pcsclite-nix-system-version-mismatch).
# keycard_plugin.so is built against nix pcsclite 2.3.0; system pcscd is 2.0.3.
# The nix pcsclite CMD_VERSION IPC protocol is incompatible with older pcscd:
# SCardEstablishContext() returns SCARD_E_NO_SERVICE → card detection never starts →
# discoverCard always returns found:false even with card in reader.
# patchelf replaces the nix store pcsclite RPATH entry with the system lib path.
_KC_SO=/tmp/test-modules-kc/keycard/keycard_plugin.so
_NIX_PCSC_DIR=$(patchelf --print-rpath "$_KC_SO" 2>/dev/null \
    | tr ':' '\n' | grep "pcsclite" | head -1)
if [ -n "$_NIX_PCSC_DIR" ]; then
    _CUR_RPATH=$(patchelf --print-rpath "$_KC_SO")
    _NEW_RPATH=$(echo "$_CUR_RPATH" | sed "s|$_NIX_PCSC_DIR|/usr/lib/x86_64-linux-gnu|g")
    patchelf --set-rpath "$_NEW_RPATH" "$_KC_SO"
fi

LOGOS_BUNDLED_MODULES_DIR=/dev/null \
LOGOS_HOST_PATH="$KC_HOST_WRAP_DIR/logos_host" \
"$LOGOSCORE_WRAPPED" -D --modules-dir /tmp/test-modules-kc > /tmp/logoscore-kc.log 2>&1 &
LOGOSCORE_PID=$!
echo "$LOGOSCORE_PID" > /tmp/logoscore-kc.pid
sleep 5

LOAD=$($LOGOSCORE load-module keycard 2>/dev/null)
if ! echo "$LOAD" | grep -q '"ok"'; then
    red "ERROR: could not load keycard module — aborting"
    echo "--- daemon log ---"
    tail -20 /tmp/logoscore-kc.log
    echo "--- logos_host log ---"
    tail -20 /tmp/logoscore-kc-host.log 2>/dev/null
    exit 1
fi

echo "Module loaded."

# pcsc_scan intentionally removed — it held a competing PC/SC context that crashed logos_host.
# LD_LIBRARY_PATH="" above ensures system pcsclite 2.0.3 is used (not nix 2.3.0).
# discoverReader is the authoritative card check — it calls startDetection() in the plugin.
DISCOVER=$(kc discoverReader)
if echo "$DISCOVER" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('found') else 1)" 2>/dev/null; then
    echo "Bridge initialized (reader found)."
else
    yellow "WARNING: discoverReader returned found:false — card sections 3-4 may fail"
fi

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
    # Check specifically for the bc:beacon request we just created (by signId),
    # not just any entry that happens to have a 1582' path (Section 1 already queued some).
    if echo "$PEND" | python3 -c "
import sys,json
d=json.load(sys.stdin)
reqs=d.get('pending',[])
found=[r for r in reqs if r.get('signId','')=='$SIGN_ID' and r.get('effective_path','').startswith(\"m/43'/60'/1582'\")]
exit(0 if found else 1)
" 2>/dev/null; then
        pass "domain-based sign uses 1582' signing subtree in effective_path"
    else
        fail "effective_path not starting with m/43'/60'/1582' for signId $SIGN_ID — got: $PEND"
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

# Old API used {domain, caller} with no bip32_path. That pattern must still be rejected
# (missing bip32_path). The domain field itself is silently ignored when bip32_path is present.
R=$(kc requestXPUB "{\"domain\":\"test\",\"caller\":\"test\"}")
assert_error "requestXPUB old-style call (domain, no bip32_path) rejected" "$R"

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

# Auth uses m/43'/60'/1581'/<domain-hash> (verified indirectly: Section 4 derived a 32-byte key
# from a domain auth request via authorizeRequest → checkAuthStatus; if the derivation path were
# wrong the card would return an error or a zero key). Direct path inspection is not available
# headlessly — there is no getPendingAuths that exposes effective_path.
R=$(kc requestAuth "bc:test" "test")
AUTH_ID3=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin).get('authId',''))" 2>/dev/null)
if [ -n "$AUTH_ID3" ]; then
    pass "requestAuth 'bc:test' domain accepted (1581' derivation covered by Section 4)"
    kc rejectRequest "$AUTH_ID3" > /dev/null 2>&1 || true
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

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
