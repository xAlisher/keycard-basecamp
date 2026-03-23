# Development Workflow

## Issue Creation

When creating an issue, include:

1. **Problem statement** - What's broken or missing
2. **Phases** - Break work into logical chunks (if multi-part)
3. **Test plan** - Specific scenarios to verify
4. **Files** - Which files will likely change
5. **Dependencies** - Related issues or blocked work

Template:
```markdown
## Problem
[Description]

## Solution
### Phase 1: [Name]
- [ ] Task 1
- [ ] Task 2

## Test Plan
- [ ] Test scenario 1 (expected: X)
- [ ] Test scenario 2 (expected: Y)
- [ ] Edge case: Z

## Files
- path/to/file.cpp (reason)
```

## Development Cycle

### 1. Planning (5 min)
- Read issue carefully
- Identify test scenarios that aren't listed → add them to issue
- Check if we need debug infrastructure (conditional logging, not temp files)

### 2. Implementation
- **One phase at a time** - Don't mix phases in one commit
- **Debug smartly**:
  - Use `qDebug()` for temporary logging (easy to spot/remove)
  - For deep debugging: Add `#ifdef KEYCARD_DEBUG` blocks (never committed enabled)
  - Log to stderr, not temp files (unless testing file I/O itself)
- **Test early** - Build and basic test after each logical chunk

### 3. Testing
- Work through test plan systematically
- **If you find a bug not in the plan:**
  1. Document it in issue comments immediately
  2. Decide: Fix now (if blocking) or separate issue (if not)
  3. Update test plan in issue

### 4. Pre-Commit Checklist
```bash
# Remove debug code
git diff | grep -i "debug\|tmp\|test"

# Check for leftover temp files in code
rg "/tmp/" --type cpp

# Verify build clean
cmake --build build 2>&1 | grep -i "warning"

# Run through test plan one more time
```

### 5. Commit
- **One commit per phase** (unless phase is trivial)
- If you discover/fix a bug mid-work: separate commit with clear message
- Commit message format:
  ```
  <Type>: <Short summary>

  <Why this change was needed>
  <What was the root cause (if bug fix)>
  <Solution approach>

  Fixes #N (if closes issue)
  Part of #N (if partial work)

  Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
  ```

### 6. Fergie/Senty Protocol
**Fergie (me):** Posts completion comment with:
- Commit hash(es)
- What was implemented
- Test results (pass/fail for each scenario)
- Known limitations (if any)

**Senty (reviewer):** Reviews for:
- Issue scope completeness
- Code quality
- Test coverage
- Integration concerns

**LGTM → merge immediately** (per feedback memory)

## Debug Infrastructure

### Conditional Logging
Instead of temp files, use conditional logging:

```cpp
// In a header (e.g., debug.h)
#ifdef KEYCARD_DEBUG
#define KEYCARD_LOG(msg) qDebug() << "[KEYCARD]" << msg
#else
#define KEYCARD_LOG(msg) do {} while(0)
#endif

// In code
KEYCARD_LOG("UID:" << uid << "length:" << uid.length());
```

Enable in CMakeLists.txt only when needed:
```cmake
option(KEYCARD_DEBUG "Enable keycard debug logging" OFF)
if(KEYCARD_DEBUG)
    target_compile_definitions(keycard_plugin PRIVATE KEYCARD_DEBUG)
endif()
```

### Test Harness
For hardware testing, maintain a test checklist in each issue:
- [ ] Cold start (no card, no reader)
- [ ] Hot plug reader
- [ ] Insert card
- [ ] Remove card
- [ ] Reinsert same card
- [ ] Reader disconnect/reconnect
- [ ] App restart with card present
- [ ] (Add scenario-specific tests)

## Anti-Patterns to Avoid

❌ **Don't:**
- Add/remove debug code in same commit as feature
- Write to `/tmp/` files for debugging (use qDebug)
- Mix multiple phases in one commit
- Test only the happy path
- Discover a bug and silently fix it (document in issue)

✅ **Do:**
- One logical change per commit
- Document bugs found during testing
- Update issue if test plan incomplete
- Clean up before committing
- Test edge cases (reconnection, restart, etc.)

## When Things Go Wrong

**If you discover a critical bug mid-implementation:**
1. Comment on issue: "Found blocker: [description]"
2. Create new issue if it's out of scope
3. Fix if blocking current work, otherwise defer
4. Update test plan to prevent regression

**If testing reveals the approach is wrong:**
1. Comment on issue explaining why
2. Discuss alternative approach
3. Update issue phases if needed
4. Don't be afraid to rewrite

## Metrics (Self-Check)

After each issue, ask:
- How many rebuild cycles? (Target: <5 for small issues)
- How many commits? (Target: 1 per phase + 1 per bug fix)
- Did we catch bugs in testing or production? (Better: testing)
- Did Senty find issues we missed? (Improve pre-commit checks)

---

**Key principle:** A bit of upfront planning + systematic testing saves more time than it costs.
