# career-ops — Fork Workflow Reference

> Personal use + open-source contribution strategy for `santifer/career-ops` Set up: June 2026 · Repo location: `/c/JobHunt/career-ops`

---

## 1. The Core Problem This Solves

`career-ops` is a tool you want to use **two different ways at the same time**:

1. **Personally** — customized with your own config, target companies, API keys, resume data. This needs to stay private and never get accidentally pushed anywhere public, and never get included in something you send upstream.
2. **As an open-source contributor** — if you find a bug or build something genuinely useful for everyone, you want to submit it back to the original project cleanly, with none of your personal data mixed in.

A single fork with a branching strategy handles both. You do **not** need two forks. The branches separate the concerns; the fork itself doesn't need to.

---

## 2. The Remote Setup

After forking `santifer/career-ops` to your own GitHub account (`Mohak-Tripathi/career-ops`), your local repo has two remotes:

|Remote|Points to|Purpose|
|---|---|---|
|`origin`|`https://github.com/Mohak-Tripathi/career-ops.git` (your fork)|Where you push everything — your `main` mirror and your `custom` work|
|`upstream`|`https://github.com/santifer/career-ops.git` (original project)|Read-only for you. You only ever **pull** from this, never push|

Verify anytime with:

```bash
git remote -v
```

Expected output:

```
origin    https://github.com/Mohak-Tripathi/career-ops.git (fetch)
origin    https://github.com/Mohak-Tripathi/career-ops.git (push)
upstream  https://github.com/santifer/career-ops.git (fetch)
upstream  https://github.com/santifer/career-ops.git (push)
```

### How this was set up from a non-standard starting point

If you accidentally clone the **original repo directly** (not your fork) — i.e. `origin` points at `santifer/career-ops` — here's the fix sequence used to recover into the correct setup without losing any local work:

```bash
# 1. Move any uncommitted personal changes onto a new branch first (safety net)
git checkout -b custom
git add <your-untracked-personal-files>
git commit -m "chore: add personal config and job-hunt customizations"

# 2. Rename the existing origin (which is actually the original repo) to upstream
git remote rename origin upstream

# 3. Add your actual fork as the new origin
git remote add origin https://github.com/<your-username>/career-ops.git

# 4. Push both branches to your fork
git push origin main
git push -u origin custom

# 5. Point local main at upstream so plain `git pull` on main always tracks the original repo
git checkout main
git branch --set-upstream-to=upstream/main main
```

This is a one-time recovery fix. If you fork correctly via GitHub's "Fork" button and clone your fork from the start, you'd set `upstream` via `git remote add upstream <original-url>` instead of the rename dance — same end state either way.

---

## 3. Branch Strategy

|Branch|What lives here|Tracks|Ever gets a PR?|
|---|---|---|---|
|`main`|Nothing of yours — kept as an exact mirror of upstream|`upstream/main`|No — never modified directly, never PR'd|
|`custom`|Your personal job-hunt setup: config, target companies, API keys, resume data, tweaks|`origin/custom`|No — this is your permanent personal working branch, never merged anywhere external|
|`feature/*` or `fix/*` (created as needed)|One specific, universal improvement — no personal data|`origin/<branch>`|**Yes** — this is the only branch type that goes into a PR against upstream|

**Why keep `main` untouched?** Because it needs to fast-forward cleanly every time you pull from upstream. The moment you commit your own changes onto `main`, future upstream pulls risk merge conflicts on a branch that's supposed to be a clean passthrough. Keeping `main` pristine means `git pull` on it is always a trivial fast-forward.

**Why `custom` and not just work on `main`?** Because `custom` is where your real day-to-day usage happens — personal YAML, sensitive config, job-hunt-specific tweaks. It's allowed to diverge from upstream permanently. You merge `main` _into_ `custom` repeatedly over time; you never merge `custom` _into_ `main`.

---

## 4. Use Case 1 — Personal Use (Day-to-Day)

You work on `custom`. That's it. All your job-hunt-specific changes, config edits, and personal files live and stay here.

```bash
git checkout custom
# ... do your work, edit files, run the tool ...
git add .
git commit -m "describe what changed"
git push origin custom
```

This branch will never be merged into `santifer/career-ops`. It's yours permanently.

---

## 5. Use Case 2 — Keeping Your Fork in Sync With Upstream

Run this periodically (e.g., weekly, or whenever you know upstream shipped something you want):

```bash
# Step 1 — update your local main from the real upstream
git checkout main
git pull
# (this works because main tracks upstream/main — see Section 2)

# Step 2 — push that update to your fork's main on GitHub (optional but keeps fork tidy)
git push origin main

# Step 3 — bring those upstream changes into your working branch
git checkout custom
git merge main

# Step 4 — push the updated custom branch
git push origin custom
```

**No GitHub UI step is involved in this sync. No pull request is created or needed.** This is purely local Git operations — `git pull`, `git merge`, `git push`. PRs only matter for the contribution flow below.

If `git merge main` produces a conflict, it means upstream changed a file you've also personally modified on `custom`. Git will mark the conflicting sections in the file; resolve them manually, keeping your personal customization where it matters, then:

```bash
git add <resolved-file>
git commit
git push origin custom
```

This is normal and expected occasionally — not a sign anything is broken.

---

## 6. Use Case 3 — Contributing Back to the Open-Source Project

This is the only scenario where a Pull Request comes into play.

### Step-by-step

```bash
# 1. Make sure main is fully up to date with upstream first
git checkout main
git pull

# 2. Branch off the CLEAN main — not off custom, so no personal data comes along
git checkout -b fix/some-bug-description

# 3. Make ONLY the universal fix — no personal config, no API keys, no resume data
#    ... edit code ...
git add <only the relevant files>
git commit -m "fix: clear description of the universal fix"

# 4. Push this branch to YOUR fork (origin) — not upstream, you don't have push access there
git push origin fix/some-bug-description
```

### Raising the actual PR

**Can you raise a PR against the original repo directly from GitHub?** Yes — and this is the standard way it's done. You do not push anything to `santifer/career-ops` directly (you don't have write access to it anyway). Instead:

1. Go to your fork on GitHub: `https://github.com/Mohak-Tripathi/career-ops`
2. After pushing a branch, GitHub shows a banner: _"Compare & pull request"_ for that branch — click it. (Or go to the **Pull Requests** tab → **New Pull Request**.)
3. Set:
    - **Base repository:** `santifer/career-ops`, base branch `main` ← this is the original project, the target of your contribution
    - **Head repository:** `Mohak-Tripathi/career-ops` (your fork), compare branch `fix/some-bug-description` ← this is your branch with the fix
4. Write a clear PR description: what the bug/feature was, what you changed, how you tested it.
5. Submit. The PR now lives on the original repo's GitHub page, even though the code physically sits on your fork until merged.
6. Maintainers review. If they request changes, just commit more to the same local branch and `git push origin fix/some-bug-description` again — the PR updates automatically, no new PR needed.
7. Once merged, the fix is in `santifer/career-ops:main`. Your local `fix/some-bug-description` branch has served its purpose — you can delete it locally and on your fork:
    
    ```bash
    git branch -d fix/some-bug-descriptiongit push origin --delete fix/some-bug-description
    ```
    
8. Next time you sync (`git checkout main && git pull`), your own fix comes back to you as part of upstream — full circle.

### The one rule that matters most here

> **Never branch a contribution off `custom`.** Always branch fresh off an up-to-date `main`. This is what guarantees your PR contains only the universal fix and zero personal data — no resume content, no API keys, no target-company lists, nothing fork-specific.

---

## 7. Keeping Sensitive Data Out of Contributions Entirely

Beyond branch discipline, add a second layer of protection: make sure personal files are **gitignored** so they can never accidentally get staged into a contribution branch in the first place.

In `.gitignore` (on `custom`, and ideally this pattern stays consistent if it ever touches `main`):

```
.env
config.local.yml
private/
.claude/settings.json
data/target-companies.md
```

Anything containing API keys, personal resume data, or job-hunt-specific config should live in files matched by these patterns. This way, even if you slip and run `git add .` on the wrong branch, these files won't get staged.

---

## 8. Quick Reference — Command Cheat Sheet

**Daily personal work:**

```bash
git checkout custom
# ... work ...
git add . && git commit -m "..." && git push origin custom
```

**Sync fork with upstream (weekly-ish):**

```bash
git checkout main && git pull
git push origin main
git checkout custom && git merge main
git push origin custom
```

**Contribute a fix upstream:**

```bash
git checkout main && git pull
git checkout -b fix/descriptive-name
# ... make ONLY the universal change ...
git add <specific files> && git commit -m "fix: ..."
git push origin fix/descriptive-name
# → go to GitHub → fork → "Compare & pull request" → base: santifer/career-ops:main
```

---

## 9. Mental Model Summary

```
santifer/career-ops (upstream)
        │
        │  git pull (one-way, read-only for you)
        ▼
   main  ──────────────────────────────────►  stays a clean mirror, forever
        │
        │  git merge main → custom (one-way, local only, no PR)
        ▼
   custom ─────────────────────────────────►  your permanent personal branch
        │
        │  branch off main (NOT custom) when contributing
        ▼
   fix/* or feature/*  ──── PR ────────────►  back to santifer/career-ops:main
```

- `origin` = your fork. Everything you push goes here.
- `upstream` = the real project. You only ever pull from it.
- `main` = clean passthrough. Never edited directly.
- `custom` = your real working branch. Never PR'd.
- `fix/*` / `feature/*` = short-lived, clean, PR-bound branches cut from `main`.