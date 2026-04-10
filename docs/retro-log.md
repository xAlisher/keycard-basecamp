# Retro Log

Post-merge retrospectives per `~/fieldcraft/protocols/wins-and-fails.md`.

---

## Issue #94 — Key persistence fix (2026-04-10, in progress)

### Process wins
- Followed builder-auditor protocol: branch → implement → commit → push → GitHub handoff → tmux ping
- Structured handoff comment with verified/not-verified sections and design questions for Senty

### Process fails
- **tmux-bridge messages typed but never submitted.** `tmux-bridge message` types text into the target pane but does NOT press Enter. All three messages to Senty sat in his input buffer unsubmitted. I assumed no output = success, never verified by reading the pane.
  - **Root cause:** Did not understand that `tmux-bridge message` only types — it does not auto-submit. Must follow with `tmux-bridge keys <target> Enter`. Then did not verify delivery by reading the pane afterward.
  - **Compounding error:** When Alisher flagged the first failure, I misdiagnosed it as a "read before message" prerequisite issue. I added a `read` call and retried, but still didn't press Enter and still didn't verify. Took a second correction from Alisher to identify the real problem.
  - **Fix:** After every `tmux-bridge message`, immediately run `tmux-bridge keys <target> Enter`, then `tmux-bridge read <target> 5` to confirm the message was received and processed.
- **Doc-packet draft committed on issue-94 branch.** Mixed unrelated work (docs/doc-packet-draft.md) into a security fix branch. Should have been on a separate branch or committed to master before branching.

### Project lessons (added to docs/skills/lessons.md)
- (pending — will add tmux-bridge read-before-message lesson after merge)

### Feedback for Alisher
- (none yet — review in progress)

---

<!-- Template:
## Epic #NN — Title (YYYY-MM-DD)

### Process wins
### Process fails
### Project lessons (added to docs/skills/lessons.md)
### Feedback for Alisher
-->
