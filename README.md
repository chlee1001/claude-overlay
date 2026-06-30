# claude-overlay

Keep your local edits to **oh-my-claudecode** plugin files alive across plugin updates.

한국어 안내: [README.ko.md](README.ko.md)

## The problem this solves

oh-my-claudecode installs each release into its own version folder
(`~/.claude/plugins/cache/omc/oh-my-claudecode/<version>/`). If you edit a file in
there directly, the next update writes a fresh version folder and your edit is gone.

claude-overlay stores each edit as a `(baseline, patched)` pair and re-applies it onto
whichever version is currently active, using a three-way merge (`git merge-file`).
Because it is a three-way merge, the plugin author's own changes to that file are
kept, and a real conflict is reported instead of being silently overwritten.

## Quick start

Run these from inside the `claude-overlay` folder:

```bash
./upstream-changes.sh                   # what the OMC update changed in files you patch (read-only)
./apply.sh                              # dry run: report only, writes nothing
./apply.sh --write                      # apply clean merges
./apply.sh --write --update-baseline    # apply, and move the baseline forward when upstream drifted
```

For the full step-by-step flow the assistant follows after an update, see the
"Guided update workflow" section of [SKILL.md](SKILL.md).

## How it works

Each patch lives in its own folder under `patches/` and is described by four files:

| file | meaning |
|------|---------|
| `target` | the file's path relative to a plugin root, e.g. `agents/git-master.md` |
| `marker` | a unique string that proves the patch is already present in a file |
| `baseline.md` | the pristine plugin file at the version you first patched against |
| `patched.md` | `baseline.md` plus your edits |

The three-way merge treats the live plugin file as the new version, `baseline.md` as
the common ancestor, and `patched.md` as your branch:

```
git merge-file -p --diff3 <live plugin file> baseline.md patched.md
```

- The merge succeeds cleanly when the plugin author did not touch the lines you edited.
- It reports a conflict when they did — that case needs a human decision, so the
  script writes the conflicted result next to the target and never applies it blindly.

### Two plugin roots

`apply.sh` applies every patch to two locations, so each patch shows two result lines:

1. **The active version folder** — what the assistant actually loads at run time.
2. **The marketplace source clone** (`~/.claude/plugins/marketplaces/omc/`) — the
   source the plugin is built and reinstalled from.

Patching both helps a patch survive longer: the active folder is used now, and the
source clone feeds future reinstalls. Some targets are build outputs that exist only
in the active folder (for example `skill-bodies/...`); the source clone has no such
file. A target absent on *some* roots is handled wherever it does exist and stays
silent — a patch only reports `MISSING` (and the run exits `4`) when its target is
absent on **every** root, which means upstream removed or renamed it.

### Owned skills (not merged)

A patch folder may also bundle skills you own, under
`patches/<name>/skill/<skillname>/`. These are not plugin files, so they are not
merged. `apply.sh` copies them as-is into your skills folder
(`${OMC_SKILLS_DIR:-$HOME/.claude/skills}/<skillname>/`). The bundled copy is the
source of truth: edit it there and re-run `./apply.sh --write` to redeploy. Because
the copy lives with the patch, a skill you delete by accident is restored by the same
run that re-applies the file patches.

### Owned rules (not merged)

A patch folder may also carry rule docs for `~/.claude/rules/`, under
`patches/<name>/rules/<file>`. Like owned skills, these are files you own, so `apply.sh`
mirrors them verbatim into `${OMC_RULES_DIR:-$HOME/.claude/rules}/`. The bundled copy is
the source of truth — edit it there and re-run `./apply.sh --write` to redeploy; a rule
you delete by accident is restored by the same run.

A patch folder may contain only assets (no `target`/`baseline`/`patched`); the file-patch
step is skipped for it and only its owned assets are deployed.

### Owned hooks + deploy steps (not merged)

A patch may also bundle hook scripts under `patches/<name>/hooks/<file>`, mirrored into
`${OMC_HOOKS_DIR:-$HOME/.claude/hooks}/` like owned skills and rules. When an asset needs more
than a verbatim copy — for example registering itself in the shared, user-owned `settings.json`
— the patch adds a `deploy.sh`. `apply.sh` runs each patch's `deploy.sh` on `--write` (after the
assets are mirrored), passing `OMC_HOOKS_DIR`; it must be idempotent so re-running is a safe
no-op. These targets (`~/.claude/{hooks,rules,skills}` and `settings.json`) are user-owned and
survive OMC updates — claude-overlay deploys them so a single `./apply.sh --write` restores your
whole customization layer, not because an update would clobber them.

### Reading the output

Per file: `OK` (already patched) · `CLEAN` / `APPLY` (merged) · `CONFLICT` ·
`MISSING` (target absent on every root) · `ERROR`.
Per owned skill / rule / hook: `OK` (up to date) · `INSTALL` (was missing) · `UPDATE` (differed).
Per deploy step: `RUN` (on `--write`) · `PLAN` (dry-run would run).
Exit code: `0` all good · `2` at least one conflict · `3` a merge error ·
`4` a patch's target is gone from every root.

The baseline only moves forward when you pass `--update-baseline`, and only for a
patch whose upstream actually drifted. A plain `--write` applies the merged result to
the live file but leaves `baseline.md` and `patched.md` pinned to the original
version; when that happens the run prints a `REMINDER:` line naming the drifted
patches. Re-run with `--update-baseline` so the next update merges against the current
version — a stale baseline invites needless conflicts over time.

## Layout

```
claude-overlay/
  apply.sh                       # the three-way re-apply script
  upstream-changes.sh            # shows what the OMC update changed in patched files (read-only)
  SKILL.md                       # usage doc for the assistant (incl. guided update workflow)
  README.md / README.ko.md
  patches/
    git-master/                  # target: agents/git-master.md
      target / marker / baseline.md / patched.md / baseline-version
    planner-readable/            # target: agents/planner.md
      target / marker / baseline.md / patched.md / baseline-version
      skill/plan-readable/       # owned skill, copied to ~/.claude/skills/
    team-review/                 # target: skill-bodies/team/SKILL.md
      target / marker / baseline.md / patched.md / baseline-version
    executor-tdd/                # target: agents/executor.md
      target / marker / baseline.md / patched.md / baseline-version
      skill/strict-tdd/          # owned skill, copied to ~/.claude/skills/
    korean-writing/              # assets only (no file patch)
      rules/                     # owned rule docs, copied to ~/.claude/rules/
        korean-writing.md
        writing-tropes.md
    completion-gate/             # assets only (no file patch)
      hooks/                     # owned hook, copied to ~/.claude/hooks/
        omc-completion-gate.mjs
      deploy.sh                  # registers the Stop hook in settings.json (idempotent)
    design-discovery/            # assets only (no file patch)
      skill/design-discovery/    # owned skill, copied to ~/.claude/skills/
      deploy.sh                  # registers the PostToolUse plan-save suggestion hook (idempotent)
```

## Current patches

### git-master

Makes the global `git-master` agent defer to a repository's own `.claude/skills/git/`
rules when they exist (for commit, create-pull-request, summarize-pull-request),
falling back to its generic behavior otherwise. The safety rails always remain: atomic
commits, `--force-with-lease` instead of a plain force push, no rebasing the main
branch, and verifying history with `git log`.

### planner-readable

Right after the global `planner` agent saves a machine-oriented plan to
`.omc/plans/<name>.md`, this patch also has it produce a human-review companion at
`.omc/plans/<name>.readable.md` — plain Korean prose with no unexplained abbreviations.
The machine plan is never changed. The companion is written by the bundled
`plan-readable` skill (with an inline fallback when the skill cannot be called).

### team-review

Makes `code-reviewer` mandatory in the `team` skill's verify stage, where it was
previously optional and only triggered on large changes. Every verify pass now runs
`code-reviewer`, which checks specification compliance first and code quality second,
scoped to the files that pass changed so it stays cheap. The target file
(`skill-bodies/team/SKILL.md`) is a build output present only in the active version
folder; the marketplace clone has no such file, so the patch is applied on the active
root and the missing marketplace copy is passed over silently.

### executor-tdd

Teaches the `executor` agent to honor strict Test-Driven Development when a task asks
for it. oh-my-claudecode's `tdd` keyword injects the strict rule — no production code
without a failing test first, and delete any code written before its test — into the
main session, but that text does not reach an `executor` subagent, so delegated
implementation could quietly skip it. This patch adds a block that makes `executor`
follow the write-failing-test-first cycle (or hand the test work to `test-engineer`)
when its task signals Test-Driven Development, and ignore it otherwise.

This pairs with a two-level design: a bare `tdd` keyword stays gentle (the built-in
test-first reminder), while `엄격 tdd` / `strict tdd` / `/strict-tdd` invokes the
bundled `strict-tdd` skill, which establishes the strict rule directly in the main
session without relying on delegation. This patch is the safety net for the delegated
path.

### korean-writing

Assets only — no plugin file is patched. Bundles two rule docs and deploys them to
`~/.claude/rules/`: `writing-tropes.md` (the Korean AI-writing tropes to avoid, the
prevention rule) and `korean-writing.md` (the convention that Korean documents follow
those tropes and then get a humanize pass for polish and meaning-preservation). Keeping
them here means they are restorable with the same `apply.sh` run as everything else.

### completion-gate

Assets only — no plugin file is patched. A **completion hard-gate**: a Stop hook that blocks a
"done / fixed / passing / 완료 / 통과" claim made without verification evidence *in the same turn*
(a test/build/lint command, a verifier/qa subagent, or test output like `PASS` / `0 failed`), and
nudges one verification pass before finishing. It fires at most once per stop, stays out of
ralph/ultrawork/autopilot/team loops, and is disabled by `OMC_SKIP_COMPLETION_GATE=1`. The patch
bundles the hook (`hooks/omc-completion-gate.mjs`) and a `deploy.sh` that registers it in
`~/.claude/settings.json` idempotently. Adapted from Superpowers' verification-before-completion
discipline; OMC had no main-loop gate for this. (Previously a standalone `completion-gate/` folder;
folded in here so one tool deploys and restores it with everything else.)

### design-discovery

Assets only — no plugin file is patched. Fills the missing **PLAN→BUILD** phase: OMC plans
(`ralplan`/`planner`) stop at architecture and defer UI direction to open-questions, while the
`designer` agent improvises aesthetics at build time. This patch deploys a `design-discovery` skill
that, given a finalized `.omc/plans/*.md`, produces research-grounded design artifacts (a brief,
cited X/Reddit/HN UX research, an `insane-design`-token `design.md`, and an HTML mockup) **without
touching app code** — a `design.md` "contract" the `designer` agent / `insane-apply` then consume.
It separates **intent** (structure, interaction, status-encoding, feel — always portable) from
**values** (hex/fonts/spacing/components) and gates on a design-system check: in *greenfield*
projects it bakes reference values into `design.md`; in *brownfield* projects (existing tokens,
tailwind theme, component library, design-system dep) it takes only the intent and reconciles it
onto the project's **own** tokens/components (`integration.md` mapping + gap list with a fixed
priority — existing system wins on values, design-discovery wins on structure/interaction), then
emits a `plan-delta.md` of concrete tasks so the design actually weaves into the implementation
plan instead of floating beside it.
The bundled `deploy.sh` registers a `PostToolUse` (Write|Edit) hook in `~/.claude/settings.json`
idempotently: when a finalized plan is written (not `*.readable.md` / `open-questions.md`), it
injects a one-line nudge to consider `/design-discovery <plan-path>`, and stays silent for every
other write. Gated to UI-bearing plans; backend/CLI-only plans are skipped.

## Rebuilding a baseline (if one is lost)

A `baseline.md` is just the pristine plugin file at the version you patched against.
To rebuild one, take the current `patched.md` and reverse each of your edits out of it
until you are back to the original plugin file, then confirm it matches the pristine
file (for example with an `md5` checksum). Once `baseline.md` is correct again, the
`(baseline, patched)` pair is consistent and merges work normally.

## Notes

- Targets the active version (read from `~/.claude/plugins/installed_plugins.json`)
  plus the marketplace source clone.
- `OMC_PATCH_ROOTS=<dir1>:<dir2>` overrides where roots are discovered (used for testing).
- `OMC_SKILLS_DIR=<dir>` overrides where owned skills are deployed (used for testing).
- This is not automatic. Re-run it after each oh-my-claudecode update. You could wire
  it to a session-start hook if you want it to run on its own.
