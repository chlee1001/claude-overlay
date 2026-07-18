---
name: claude-overlay
description: Re-apply and maintain local OMC (oh-my-claudecode) plugin customizations after an update — a guided, step-by-step workflow that first detects what changed upstream (via the marketplace git clone of Yeachan-Heo/oh-my-claudecode), then 3-way merges each patch onto the new version, preserving upstream changes and surfacing conflicts. Make sure to use this skill whenever OMC was updated, upgraded, or reinstalled; when a patched OMC agent or skill (git-master, planner, executor, team, etc.) looks reverted or behaves like the stock version; when you want to know what an OMC update changed in files you have customized; or to verify your local OMC patches are still applied. Run it from the claude-overlay folder after any oh-my-claudecode version bump.
---

# OMC Patch Maintainer

OMC plugin files live in a **versioned cache** that is regenerated on every update
(`~/.claude/plugins/cache/omc/oh-my-claudecode/<version>/...`). Any local edit we
make to those files (e.g. the `git-master` Project_Skill_Routing block) is **lost
when OMC updates** to a new version folder. This skill re-applies our patches onto
whatever version is currently active, via a 3-way merge so upstream's own changes
to the file are preserved and any real conflict is surfaced — never silently
clobbered.

## When to use

- After updating OMC (`/oh-my-claudecode:omc-setup`, plugin update, version bump).
- A previously-patched OMC file (e.g. `git-master.md`) appears reverted.
- To verify our local OMC patches are present on the active version.

## Health check (one verdict across both flows)

`./doctor.sh` is the single read-only health entry point. It runs `apply.sh` (dry-run) +
`reabsorb.sh` (detect) + a version-skew breadcrumb, and prints ONE combined verdict + exit
code (`3` error · `2` hard action · `5` soft drift · `4` informational · `0` healthy). It
never writes anything (there is no `--write` path — that is the point). `./doctor.sh --quiet`
prints a single line and passes `--local-only` to reabsorb (skips git-repo network probes),
for a fast offline-safe SessionStart nudge (phase 2). Use `doctor.sh` first after an update to
see whether anything needs attention; then follow the guided workflow below for what it flags.

## Fossilize regressions

When you resolve a real drift / CONFLICT / BREAKING / tooling bug, add BOTH: (a) a permanent
fixture in `tests/run.sh` that fails if it returns, and (b) a dated one-liner in
`REGRESSIONS.md`. A ledger line without a fixture rots silently; a fixture without a line
loses its story. The insane-design 3.1→3.2 case is the model fossil.

## Guided update workflow (step by step)

When this skill triggers after an OMC update, walk the user through these steps. The scripts
are read-only unless given `--write`. **Pause for the user's confirmation before any step that
writes to the global plugin files** — those affect every project, so don't apply silently.

**0. Locate.** When this skill loads, its directory is shown as "Base directory for this skill"
(typically `~/.claude/skills/claude-overlay`, a symlink to the project copy). `cd` into that
directory first — every command below uses `./` to mean it, and the relative `patches/...` paths
resolve from there.

**1. Did anything change?** Compare the active version with what each patch was built against:
- active version = `basename` of the install path in `~/.claude/plugins/installed_plugins.json`
- baseline version = `cat patches/<name>/baseline-version`

If they match and the step-3 dry-run is all `OK`, the patches survived the update — you're done.
If they differ, an update landed; continue.

**2. Understand what upstream changed — before touching anything.**
```bash
./upstream-changes.sh
```
This reads the marketplace git clone of Yeachan-Heo/oh-my-claudecode and prints, per patched
file, the upstream commits + diffstat since that patch's baseline version. Summarize for the
user which files drifted and why. This predicts which patches will merge cleanly versus
`CONFLICT`. Cache-only files (no git history, e.g. `skill-bodies/`) are flagged — their changes
surface in the merge instead. If the git clone is missing, it prints a GitHub compare URL.

This step explains *intent* — it is not authoritative for what's on disk. It reads the
marketplace clone, which can lag the active install (the cache may be on v4.15.0 while the clone
is still v4.14.7). The **step-3 dry-run is authoritative** for the active version. If the two
disagree — `upstream-changes.sh` says "no changes" but the dry-run reports drift — trust the
dry-run, and `diff patches/<name>/baseline.md` against the live target to see the real change.

**3. Dry-run to see the plan.**
```bash
./apply.sh
```
Read each status line: `OK` (already applied) · `CLEAN` (will apply; drift noted) · `CONFLICT`
(upstream touched our lines — needs you) · `MISSING` (file gone/renamed). The final `REMINDER`/
`WARNING` lines summarize drift and missing targets.

**4. Apply.** Confirm with the user, then pick by what the dry-run showed:
- only `OK` → nothing to do.
- `CLEAN`, no drift → `./apply.sh --write`.
- `CLEAN` with drift → `./apply.sh --write --update-baseline` (advances `baseline.md`,
  `patched.md`, and `baseline-version` to the new version so future merges stay trivial).

**5. Resolve each CONFLICT.** Open `<target>.merge-conflict`. Use the upstream diff from step 2
to understand the *intent* of upstream's change, combine it with our edit, write the result onto
the target, then re-baseline that patch (see "Resolving a CONFLICT"). Re-run step 3 to confirm
it now reads `OK`.

**6. Investigate each MISSING.** The agent/file was removed or renamed upstream. Find where it
went using the marketplace git history:
```bash
git -C ~/.claude/plugins/marketplaces/omc log --oneline --name-status \
    "$(cat patches/<name>/baseline-version)"..HEAD -- <old-target-dir>/
```
A rename shows as `R`, a deletion as `D`. If renamed → update `patches/<name>/target` to the new
path and rebuild `baseline.md`/`patched.md`/`baseline-version` against it. If the feature was
removed → retire the patch (delete its folder) and tell the user.

**7. Verify.** Re-run `./apply.sh`. Success is all `OK` with exit `0`, and owned skills
`up-to-date`.

## Mechanism (verified)

Per patch in `patches/<name>/`:

| file | meaning |
|------|---------|
| `baseline.md` | pristine upstream file at the version we patched against |
| `patched.md`  | `baseline.md` + our local edits |
| `target`      | relative path under each OMC root (e.g. `agents/git-master.md`) |
| `marker`      | unique string proving our patch is already present |
| `baseline-version` | OMC version/git-ref the baseline was captured at (e.g. `v4.14.7`); used by `upstream-changes.sh` |

Core merge — `current = NEW upstream (pristine)`, `base = baseline.md`, `other = patched.md`:

```
git merge-file -p --diff3 <new-upstream> baseline.md patched.md
# exit 0       = clean   -> safe to apply
# exit 1..127  = N conflicts -> upstream touched our patched lines; DO NOT auto-apply
# exit >=128   = error
```

No git repo is needed (operates on three on-disk files). Roots targeted: the active
cache install (from `~/.claude/plugins/installed_plugins.json`) **and** the
marketplace source.

한글 실행 가이드(업데이트 후 직접 실행): [업데이트-후-실행-가이드.md](업데이트-후-실행-가이드.md)

## Owned skills (not 3-way merged)

A patch may also bundle skills WE own under `patches/<name>/skill/<skillname>/`. These are
not upstream files, so they are not merged — `apply.sh` mirrors them verbatim into the skills
dir (`${OMC_SKILLS_DIR:-$HOME/.claude/skills}/<skillname>/`). This means a lost skill is
restored by the same `apply.sh` run that re-applies plugin patches. The bundled copy is the
**canonical source**; edit it there and re-run `apply.sh --write` to deploy. Status lines:
`OK (skill up-to-date)` · `INSTALL` (was missing) · `UPDATE` (differed).

Likewise, rule docs WE own go under `patches/<name>/rules/<file>` and are mirrored into
`${OMC_RULES_DIR:-$HOME/.claude/rules}/`. Same model: the bundled copy is canonical, so edit it
there (not the deployed `~/.claude/rules/` copy, which the next `--write` would overwrite) and
re-run. A patch folder may be **asset-only** — no `target`/`baseline.md`/`patched.md`, just
`skill/` and/or `rules/`; the 3-way file-patch step is skipped for it and only its owned assets
deploy (e.g. the `korean-writing` patch ships writing-style rules and patches no plugin file).

Hook scripts WE own go under `patches/<name>/hooks/<file>` and mirror into
`${OMC_HOOKS_DIR:-$HOME/.claude/hooks}/` the same way. When an asset needs more than a verbatim
copy — e.g. registering itself in the shared, user-owned `settings.json` — the patch adds a
`deploy.sh` that does it idempotently. `apply.sh` runs each patch's `deploy.sh` on `--write`
(after assets are mirrored), passing `OMC_HOOKS_DIR`; a re-run must be a safe no-op. The
`completion-gate` patch is asset-only this way: it ships the hook and a `deploy.sh` that
registers the Stop hook in `settings.json`. Note these targets (`~/.claude/{hooks,rules,skills}`,
`settings.json`) are user-owned and survive OMC updates — claude-overlay deploys them so one
`apply.sh --write` restores your whole customization layer (handy on a new machine or after an
accidental delete), not because an update would clobber them.

## How to run

```bash
# 1. Dry-run first — report only, writes nothing (DEFAULT)
./apply.sh

# 2. Apply clean merges
./apply.sh --write

# 3. Apply AND advance baseline when upstream drifted but merged cleanly
#    (baseline := new pristine, patched := merged result — keeps the pair consistent)
./apply.sh --write --update-baseline
```

Status lines: `OK` (already patched) · `CLEAN`/`APPLY` (merged) · `CONFLICT` · `MISSING` · `ERROR`.
Script exit: `0` all good · `2` ≥1 conflict · `3` a merge error · `4` a patch's target is gone from every root.

**MISSING** means a defined patch's target file is absent on **every** root — the upstream
agent/file was removed or renamed, so our customization is no longer applied anywhere. The run
prints a `WARNING:` line and exits `4`; retarget the patch to the new path or retire it. A target
absent on only *some* roots (e.g. the marketplace has no `skill-bodies/`) is normal and stays
silent — a patch is handled wherever its target exists.

**Baseline only advances with `--update-baseline` (and only when that patch drifted).**
Plain `--write` applies the merge to the live file but leaves `baseline.md`/`patched.md`
pinned to the original version. When a drift is applied without advancing, the run prints
a `REMINDER:` line naming the drifted patches — that is the cue to re-run with
`--update-baseline` so the next update merges against the current version (a stale baseline
invites needless conflicts over time). No drift → nothing to advance.

## Resolving a CONFLICT

A conflict means upstream changed the same lines our patch edits — this needs human/agent judgment, by design.

1. Open `<target>.merge-conflict` (written next to the target). It has `<<<<<<< upstream-new / ||||||| baseline / ======= / >>>>>>> my-patch` markers.
2. Decide how to combine upstream's change with our routing edit.
3. Write the resolved content onto the target file.
4. **Re-baseline**: copy the new pristine upstream to `patches/<name>/baseline.md` and the resolved file to `patches/<name>/patched.md`, so the next update merges against the reconciled version. (See README for the exact reverse-derivation trick if you need to rebuild baseline.)

## Adding a new patch

Create `patches/<name>/` with `target`, `marker`, `baseline.md` (pristine upstream),
`patched.md` (pristine + your edits), and `baseline-version` (the OMC version/git-ref the
baseline came from, e.g. `v4.14.7`). For an owned skill, add `skill/<skillname>/`; for owned
rule docs, add `rules/<file>`. A folder may be asset-only (just `skill/` and/or `rules/`, no
`target`) — then only those assets deploy. The scripts pick it up automatically.

## Caveats

- Targets the **active** version + marketplace only (not stale cache versions). That is intentional — only the active version is loaded.
- `OMC_PATCH_ROOTS=<dir1:dir2>` overrides root discovery (used for testing).
- This does not survive an OMC reinstall on its own — re-run after updates. Wire to a SessionStart hook later if you want it automatic.
