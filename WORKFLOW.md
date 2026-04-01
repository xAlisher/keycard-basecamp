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

tmux-bridge is a lightweight pointer only. All content lives on GitHub.

**Format:** `/btw check [issue|pr] #XX`

| Direction | When |
|-----------|------|
| Fergie → Senty | Implementation ready for review |
| Senty → Fergie | Review complete (LGTM or findings posted) |
| Fergie → Senty | Fixes applied, ready for re-review |

GitHub is the record. tmux-bridge is the nudge. No polling, no cron.

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
- [ ] Code builds
- [ ] Tests pass
- [ ] Branch pushed
- [ ] Handoff comment posted on GitHub
- [ ] Senty notified via tmux-bridge

**Before merge:**
- [ ] Senty LGTM received
- [ ] PR created
- [ ] PR merged
- [ ] Lessons documented
