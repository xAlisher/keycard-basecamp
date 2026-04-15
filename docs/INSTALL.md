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
   - `auth_showcase.lgx`

2. **Install all three LGX files** via Basecamp's module manager (Settings → Modules → Install from file).

3. **Restart Basecamp.** All three modules should appear in the module list.

## Run

1. Open the **Keycard** module — it will detect your reader and card.
2. Pair your card if not already paired (Pair tab → enter pairing password + PIN).
3. Open the **Auth Showcase** module.
4. Click **Request Auth** — a pending request will appear in the Keycard module.
5. Switch back to Keycard, enter your PIN, and approve.
6. The showcase module receives the derived key and displays confirmation.

## Build from source

See the [README](../README.md#build) for build instructions.

## Next step

Ready to integrate Keycard into your own module? See the [Integration Guide](../INTEGRATION_GUIDE.md).
