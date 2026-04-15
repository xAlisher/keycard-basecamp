# Try the Keycard Showcase

The quickest way to see Keycard working in Basecamp is to install the pre-built LGX packages and run the included showcase module.

## Requirements

- [Logos Basecamp](https://github.com/logos-co/logos-basecamp) (pre-release)
- PC/SC smart card reader
- [Keycard](https://keycard.tech/) smartcard (initialized and paired)

## Install

1. **Download the latest release** from [keycard-basecamp releases](https://github.com/xAlisher/keycard-basecamp/releases/latest):
   - `keycard-core.lgx`
   - `keycard-ui.lgx`

2. **Install both LGX files** via Basecamp's module manager (Settings → Modules → Install from file).

3. **Restart Basecamp.** Both modules should appear in the module list.

## Try it

With both modules installed you can exercise the full approval flow:

1. Open the **Keycard** module — it will detect your reader and card.
2. Pair your card if not already paired (Pair tab → enter pairing password + PIN).
3. From any module's QML, call `logos.callModule("keycard", "requestAuth", ["test_domain", "my_module"])` and poll `checkAuthStatus` — or drop in `KeycardAuth.qml` (see the [Integration Guide](../INTEGRATION_GUIDE.md#private-key-generation-for-encryption)).
4. The pending request will appear in the Keycard UI. Enter your PIN and approve.
5. The derived key is returned to the calling module.

## Build the showcase from source

`auth_showcase` is not included in the current release. To run the full showcase demo, build from source:

See the [README](../README.md#build) for build instructions, then install `auth_showcase` alongside `keycard-core` and `keycard-ui`.

## Next step

Ready to integrate Keycard into your own module? See the [Integration Guide](../INTEGRATION_GUIDE.md).
