# Your Crypto Keys Were Still in Memory After "Session Closed"

How a security audit of our smartcard module found keys persisting past session boundaries — and the Nix build system bug that hid the fix for days.

---

## The claim vs. the code

Our keycard module handles cryptographic key derivation from a hardware smartcard. Every document we ship — the spec, the API docs, the developer journey guide — makes the same promise:

> Keys live only in memory for a single approved session and are wiped on session close.

During a routine docs review, our auditor (an AI agent named Senty, running Codex) flagged a gap: the code didn't match the claim.

Here's what `closeSession()` actually did:

```cpp
QString KeycardPlugin::closeSession()
{
    m_sessionState = SessionState::NoSession;
    QJsonObject result;
    result["closed"] = true;
    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

It flipped a state flag. That's it. No zeroing. No cleanup. The derived key was still sitting in a `QString` on an `AuthRequest` struct, readable by any subsequent `checkAuthStatus()` call, for as long as the module stayed loaded.

`QString` uses reference-counted heap memory. Its destructor doesn't zero. Copy-on-write means the key bytes could be scattered across multiple allocations. This isn't a theoretical concern — it's the kind of thing memory forensics tools find trivially.

## The fix: one-read-and-drop

The core design decision was simple: **hand the key to the consumer exactly once, then destroy it.**

We ported `SecureBuffer` from our previous implementation — an RAII wrapper around `QByteArray` that calls `sodium_memzero` on destruction and enforces move-only semantics (no accidental copies):

```cpp
class SecureBuffer {
public:
    ~SecureBuffer() { wipe(); }

    // Move-only — copy deleted
    SecureBuffer(SecureBuffer &&other) noexcept;
    SecureBuffer(const SecureBuffer &) = delete;

    void wipe() {
        if (!m_data.isEmpty()) {
            sodium_memzero(m_data.data(), m_data.size());
            m_data.clear();
        }
    }
private:
    QByteArray m_data;
};
```

The `AuthRequest` struct switched from `QString key` to `SecureBuffer key`, which made the entire struct move-only (no more `QList`, switched to `std::vector`).

`checkAuthStatus()` became a one-shot:

```cpp
if (req.status == "complete") {
    // Convert to hex for JSON response
    QByteArray keyHex = req.key.ref().toHex();
    result["key"] = QString::fromUtf8(keyHex);

    // Wipe hex intermediate
    sodium_memzero(keyHex.data(), keyHex.size());

    // Wipe the SecureBuffer
    req.key.wipe();

    // Erase the entire request
    m_authRequests.erase(m_authRequests.begin() + i);

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}
```

First call returns the key. Second call returns `"Auth request not found"`. There is no third state.

We also added belt-and-braces cleanup: `closeSession()` now purges any completed-but-unread requests (consumer crashed before reading), card removal triggers the same purge, and the destructor wipes everything on module unload.

## The intermediate wipe problem

The on-card key derivation returns the key as hex in a JSON response. Between "card gives us bytes" and "bytes stored in SecureBuffer", there are intermediates — `QString`, `QByteArray`, the JSON document itself. Every one of them needs to be zeroed:

```cpp
QString deriveResponse = deriveKey(domain);
QByteArray deriveResponseUtf8 = deriveResponse.toUtf8();
QJsonObject keyResult = QJsonDocument::fromJson(deriveResponseUtf8).object();

// Wipe the raw JSON response (contains key hex)
sodium_memzero(deriveResponseUtf8.data(), deriveResponseUtf8.size());
sodium_memzero(deriveResponse.data(), deriveResponse.size() * sizeof(QChar));

// Extract key, store in SecureBuffer
QString hexKey = keyResult.value("key").toString();
QByteArray hexKeyUtf8 = hexKey.toUtf8();
QByteArray keyBytes = QByteArray::fromHex(hexKeyUtf8);
targetRequest->key = SecureBuffer(std::move(keyBytes));

// Wipe all hex intermediates
sodium_memzero(hexKeyUtf8.data(), hexKeyUtf8.size());
sodium_memzero(hexKey.data(), hexKey.size() * sizeof(QChar));
keyResult.remove("key");
```

This is tedious. It's also necessary. If you're handling keys in C++ with Qt types, every buffer that touches key material is a liability.

## Then we couldn't test it

The code was clean. It compiled. The auditor gave LGTM after two review rounds. We installed the module, launched the app, and... the smartcard reader wasn't detected. The keycard module was loaded, the reader was plugged in, the card was inserted. Nothing.

`journalctl -u pcscd` told the story:

```
Communication protocol mismatch!
Client protocol is 4:5
Server protocol is 4:4
```

The system's PC/SC daemon (pcscd) speaks protocol 4:4 — it ships with Ubuntu's `libpcsclite 2.0.3`. But our plugin was speaking protocol 4:5. Where was the newer client library coming from?

```
$ readelf -d keycard_plugin.so | grep RUNPATH
RUNPATH: [$ORIGIN:/nix/store/.../pcsclite-2.3.0-lib/lib:...]
```

We build inside `nix develop`. Nix's compiler wrapper injects `-rpath /nix/store/...` for every dependency at link time. Our CMakeLists.txt said `INSTALL_RPATH "$ORIGIN"` — but Nix's wrapper overrode it, baking in a path to pcsclite 2.3.0 from the Nix store.

At runtime, the dynamic linker found Nix's pcsclite first (via RUNPATH), loaded it, and it tried to talk to the system pcscd using a protocol version the daemon didn't understand. Every smartcard operation silently failed.

We'd documented this pitfall before — "never bundle libpcsclite in the LGX package" — and our packaging script already deleted the `.so` file from the bundle. But the RUNPATH pointing to the Nix store is the same problem in a different form: you don't need to ship the wrong library if you tell the linker exactly where to find it.

## The one-line fix (and the automation)

```bash
patchelf --set-rpath '$ORIGIN' keycard_plugin.so
```

That's it. Strip the Nix store paths, keep only `$ORIGIN` (the plugin's own directory). The dynamic linker falls through to the system `libpcsclite.so.1`, which matches the system pcscd. Reader detected, card detected, PIN verified, key derived.

We automated it in two places:

**CMakeLists.txt** — runs after every `cmake --install`:
```cmake
find_program(PATCHELF_EXECUTABLE patchelf)
if(PATCHELF_EXECUTABLE)
    install(CODE "
        execute_process(
            COMMAND ${PATCHELF_EXECUTABLE} --set-rpath \"$ORIGIN\" \"${_plugin}\"
        )
    ")
endif()
```

**package-lgx.sh** — runs during LGX packaging:
```bash
PLUGIN_SO=$(find "$TEMP_DIR" -name "keycard_plugin.so" -print -quit)
if [ -n "$PLUGIN_SO" ] && command -v patchelf &>/dev/null; then
    patchelf --set-rpath '$ORIGIN' "$PLUGIN_SO"
fi
```

## Takeaways

**1. Audit your claims against the code, not the docs.** Our documentation consistently said "keys are wiped on session close." The code said otherwise. A fresh pair of eyes (even an AI auditor) reading the implementation — not the README — caught it.

**2. `QString` is not secure memory.** If you're handling cryptographic keys in Qt, use a dedicated buffer with `sodium_memzero` on destruction. Zero every intermediate. It's tedious, but `QString`'s reference counting and copy-on-write mean your key material has an undefined lifetime.

**3. Nix builds leak paths into your binaries.** `INSTALL_RPATH` in CMake means nothing when Nix's cc-wrapper injects its own `-rpath`. If your plugin needs to use system libraries at runtime (like pcsclite, which must match the system daemon), you need a post-install `patchelf` step. Check with `readelf -d your.so | grep RUNPATH`.

**4. "Don't bundle the library" is incomplete.** We had this documented. We had a script that deleted the bundled `.so`. But the RUNPATH was an equivalent path to the same problem. Security pitfalls have variants — document the principle ("plugin must use system pcsclite at runtime"), not just one manifestation ("delete the .so from the bundle").
