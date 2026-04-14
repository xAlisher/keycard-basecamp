# X Thread Draft: Basecamp Unblock + Headless Logos Core Testing

1. We finally unblocked `keycard-basecamp` on the latest Basecamp commit.

The key shift was not "more app logic", it was getting the module/runtime boundary understood correctly:
- where Basecamp actually loads plugins from
- how QML updates propagate
- how core modules behave in AppImage vs dev flows
- what `logos.callModule(...)` actually does under failure

2. One of the biggest unlocks was separating "UI looks alive" from "module is actually working".

We hit several false positives early:
- stale QML loaded from the wrong runtime dir
- wrong cache being cleared
- user-installed core modules not auto-loading in AppImage
- synchronous `callModule` timeouts looking like benign idle UI

Once we treated those as runtime-contract problems instead of random bugs, progress got much faster.

3. Latest Basecamp work also made a practical difference for us in headless flows.

The important part: we can exercise the Logos core/module boundary without always driving the full UI manually.
That changed debugging from:
- "click around, guess from the screen"
to:
- "call the module directly, inspect exact responses, narrow the failing layer"

4. That headless path turned out to be a big deal for keycard work.

With headless Logos core, we can test things like:
- module loadability
- request creation / pending auth flow
- pairing-state transitions
- signing API behavior
- exact JSON responses and error paths

That’s much better than trying to infer everything from UI state.

5. It also lets us write real automated tests around the module contract.

Not full hardware coverage yet, but enough to catch a large class of regressions:
- wrong-mode handling
- malformed request validation
- stale cached state
- response shape mismatches
- request lifecycle bugs

That’s already paying off.

6. A concrete example: some of our recent bugs were not crypto bugs at all.

They were:
- cached state not cleared on card loss/stop
- pending requests gated behind the wrong UI condition
- form state surviving request dismissal
- TLV response parsing returning the wrong bytes

Headless core testing is exactly what makes those easier to reproduce and lock down.

7. Another useful lesson: AppImage/runtime issues and protocol issues need different test surfaces.

UI + hardware is still necessary for final confirmation.
But headless Logos core gives us a stable place to verify:
- "does the module answer?"
- "is the state machine correct?"
- "does this method return the contract we think it does?"

That reduces a lot of wasted hardware-debug time.

8. We’re not done yet, but the path is much clearer now:

- Basecamp latest commit unblocked the integration work
- headless Logos core made the module testable in a disciplined way
- that, in turn, makes automated regression coverage realistic for keycard flows

This is the kind of infrastructure improvement that quietly speeds up everything after it.

9. Next step for us: keep hardware-in-the-loop for final verification, but move as much state-machine / API / response-contract coverage as possible into headless tests.

That’s the only scalable way to work on secure-card integrations without drowning in manual retesting.
