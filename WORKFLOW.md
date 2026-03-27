# Fergie/Senty Collaboration Workflow

Multi-agent development workflow for keycard-basecamp using two AI agents:
- **Fergie (Claude):** Implementation agent - builds features
- **Senty (Codex):** Review agent - catches issues, validates quality
- **User:** Product owner - orchestrates, makes final decisions

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

### 3. Handoff to Senty (Event-Driven Cron Start)

**Fergie posts handoff comment:**
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

Branch: issue-XX-feature-name
Ready for review! 🚀"
```

**Fergie starts polling for Senty's review:**
```
CronCreate(
    cron="*/2 * * * *",
    prompt="Check for Senty comments on issue #XX",
    recurring=true
)
# Save job ID for later deletion
```

---

### 4. Review (Senty)

**Senty reviews code:**
- Validates against requirements
- Checks security, correctness, quality

**Senty posts review:**
```
Senty:

Findings:
1. [SEVERITY] - Issue description
2. [SEVERITY] - Another issue

Result: [LGTM / not LGTM yet]
```

---

### 5. Fixes (If Needed)

**Fergie gets auto-notified via cron** → Makes fixes → Posts update

**Repeat until LGTM**

---

### 6. Merge (After LGTM)

**Fergie auto-merges:**
```bash
gh pr create --title "Issue #XX: Feature" --base master
gh pr merge XX --squash --delete-branch
```

**Stop cron:**
```bash
CronDelete(job_id)
```

**Document lessons in LESSONS.md**

---

## Cron Polling Protocol

### When to Start
- ✅ After "Ready for review" handoff
- ✅ During active review cycles

### When to Stop
- ✅ After PR merged to master
- ✅ After issue closed

### Job Details
- **Schedule:** `*/2 * * * *` (every 2 minutes)
- **Filters:** Comments starting with "Senty:" (for Fergie) or "Fergie:" (for Senty)
- **Session-only:** Dies when terminal exits
- **Auto-expires:** 3 days

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
- [ ] Handoff comment posted
- [ ] Cron started

**Before merge:**
- [ ] Senty LGTM received
- [ ] PR created
- [ ] PR merged
- [ ] Cron stopped
- [ ] Lessons documented
