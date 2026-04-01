# Fergie/Senty Collaboration Workflow

Multi-agent development workflow for keycard-basecamp using two AI agents:
- **Fergie (Claude):** Implementation agent - builds features
- **Senty (Codex):** Review agent - catches issues, validates quality
- **User:** Product owner - orchestrates, makes final decisions

---

## Session Setup (one-time per work session)

Label panes so agents can find each other by name:

```bash
# Run in Fergie's pane
tmux-bridge name "$(tmux-bridge id)" fergie

# Run in Senty's pane
tmux-bridge name "$(tmux-bridge id)" senty

# Verify both are visible
tmux-bridge list
```

---

## Standard Issue Workflow

### 1. Issue Creation & Planning

**User creates issue** (or selects from backlog)

**Fergie checks issue:**
```bash
gh issue view XX
```

**Fergie confirms understanding:**
- Read issue body, requirements, success criteria
- Check dependencies and blockers
- Ask clarifying questions if needed

---

### 2. Implementation (Fergie)

**Create feature branch:**
```bash
git checkout master
git pull origin master
git checkout -b issue-XX-feature-name
```

**Implement changes:**
- Write code following PROJECT_KNOWLEDGE.md lessons
- Test locally (build, install, run)
- Fix issues as they arise

**Commit changes:**
```bash
git add <files>
git commit -m "Brief description

Detailed explanation of changes...

Related to Issue #XX

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

**Push to remote:**
```bash
git push origin issue-XX-feature-name
```

---

### 3. Handoff to Senty

**Fergie posts handoff comment (permanent record):**
```bash
gh issue comment XX --body "Fergie: Ready for review! 🎯

## What's Implemented
- Feature 1
- Feature 2

## Testing
✅ Build succeeds
✅ Tests pass

## Files Changed
- path/to/file.cpp

Branch: issue-XX-feature-name"
```

**Fergie notifies Senty via tmux-bridge:**
```bash
tmux-bridge read senty 20
tmux-bridge message senty '/btw check issue #XX'
tmux-bridge read senty 20
tmux-bridge keys senty Enter
```

---

### 4. Review (Senty)

**Senty reads the issue:**
```bash
gh issue view XX
```

**Senty reviews code:**
- Validates against requirements
- Checks security, correctness, quality

**Senty posts review comment (permanent record):**
```bash
gh issue comment XX --body "Senty:

Findings:
1. [SEVERITY] - Issue description
2. [SEVERITY] - Another issue

Result: [LGTM / not LGTM yet]"
```

**Senty notifies Fergie via tmux-bridge:**
```bash
tmux-bridge read fergie 20
tmux-bridge message fergie '/btw check issue #XX'
tmux-bridge read fergie 20
tmux-bridge keys fergie Enter
```

---

### 5. Fixes (If Needed)

**Fergie reads Senty's findings:**
```bash
gh issue view XX
```

**Fergie makes fixes → posts update comment → notifies Senty:**
```bash
gh issue comment XX --body "Fergie: Fixed P1 (bounds check in keycard_auth.cpp:142). Ready for re-review."

tmux-bridge read senty 20
tmux-bridge message senty '/btw check issue #XX'
tmux-bridge read senty 20
tmux-bridge keys senty Enter
```

**Repeat until LGTM.**

---

### 6. Merge (After LGTM)

**Fergie merges:**
```bash
gh pr create --title "Issue #XX: Feature" --base master
gh pr merge XX --squash --delete-branch
```

**Document lessons in LESSONS.md**

---

## Notification Protocol

- **GitHub is the system of record.** Every substantive review result, finding, fix handoff, and final LGTM must be posted on the relevant issue/PR.
- **tmux-bridge is interrupt + routing only.** Use it to notify the other agent that attention is needed; do not treat tmux as the durable record.
- **Do not poll GitHub comment counts or sleep-wait for responses.** After sending a tmux ping, continue useful work. The receiving agent will reply via tmux-bridge when ready.

### Handoff Status Tags

| Tag | Meaning |
|-----|---------|
| `READY` | All issue success criteria for the current scope are complete and ready for review |
| `PARTIAL` | Code or validation is incomplete; review requested only on the completed subset. State what is still pending |
| `FIX` | Prior review findings have been addressed and the issue is ready for re-review |
| `RECHECK` | No code change expected; reviewer should verify updated evidence, runtime result, or issue-thread clarification |
| `BLOCKED` | Cannot proceed without input, permission, missing dependency, or failed prerequisite |

### Handoff Message Format

Use tmux pings in this shape: `/btw [TAG] check issue #NN — one-line scope summary`

Examples:
```
/btw READY check issue #57 — PluginInterface migration complete
/btw PARTIAL check issue #61 — build verified, runtime host test pending
/btw FIX check issue #59 — removed speculative manifest fields
/btw RECHECK check issue #61 — manual Basecamp smoke test evidence posted
/btw BLOCKED issue #60 — install path conflict between docs and build flow
```

### Required Handoff Checklist

- Every `READY`, `PARTIAL`, or `FIX` handoff must include the issue success criteria as a short checklist in the GitHub comment, with each item marked done or not done.
- If any criterion is still open, the handoff must be `PARTIAL`, not `READY`.
- If the issue has a repo-default verification matrix, the handoff comment must explicitly state each verified surface.

### Default Verification Matrix

Unless the issue says otherwise, verify:
1. `nix develop` dev build
2. `nix build .#lib`
3. install-to-prefix (`cmake --install --prefix <path>`)

Host runtime validation in Basecamp is required **only** when the issue explicitly calls for real host-app behavior.

### Batching Rules

- If multiple issues are independently reviewable at once, batch them into one tmux ping instead of sending multiple separate nudges.
- The reviewer may still post separate GitHub comments per issue if the findings differ by scope or severity.

### Reviewer Response Protocol

- Reviewer posts findings or LGTM on GitHub first, then sends a tmux ping back referencing the issue(s).
- Implementer treats the tmux ping as the callback signal and should not poll GitHub while waiting.

---

## Communication Protocol

- **Fergie comments:** Start with `Fergie:`
- **Senty comments:** Start with `Senty:`
- **User comments:** No prefix

---

## Branch Workflow

- **master:** Stable, production-ready
- **issue-XX-feature:** Active development
- **Never commit directly to master** (except docs after merge)
- **Squash merge** to master, delete branch after

---

## Success Checklist

**Before handoff:**
- [ ] Code builds (dev build + nix build .#lib)
- [ ] Install-to-prefix verified
- [ ] Branch pushed
- [ ] Handoff comment posted on GitHub with success criteria checklist
- [ ] Agent notified via tmux-bridge with correct status tag

**Before merge:**
- [ ] Senty LGTM received
- [ ] PR created
- [ ] PR merged
- [ ] Lessons documented
