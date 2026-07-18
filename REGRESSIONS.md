# Overlay regressions ledger

Fossilized bugs — each has a permanent test fixture in `tests/run.sh` that fails if the
bug returns. The convention (see SKILL.md "Fossilize regressions"): when you resolve a
real drift / CONFLICT / BREAKING / tooling bug, add (a) a permanent fixture that pins it
and (b) a dated one-liner here. A ledger without a fixture rots silently; a fixture
without a ledger line loses its story.

Format: `YYYY-MM-DD — <what broke / what the guard is> — <fixture / guard location>`

- 2026-06-15 — insane-design `schema_version` moved 3.1→3.2 while `plugin_version` stayed
  0.5.3, i.e. contract drift the version axis alone can't see. The two-axis probe exists
  because of this. — `tests/run.sh` "REGRESSION: insane-design 3.1->3.2 schema drift".

- 2026-07-19 — `apply.sh` dry-run wrote `<target>.merge-conflict` into the live cache on a
  CONFLICT (the `cp` was outside the `WRITE` gate), contradicting its own "report only,
  write nothing" contract. doctor.sh (read-only) would have inherited the leak. Fix gated
  the write behind `--write`. — `tests/run.sh` "apply.sh dry-run CONFLICT writes nothing".

- 2026-07-19 — `apply.sh` exited `0` on a clean-but-drifted run (the rc cascade never read
  `drift_names`; drift was prose `REMINDER:` only). Any caller checking apply's exit code
  (doctor, a SessionStart hook) saw "healthy" despite pending drift. Fix added drift → rc 5.
  — `tests/run.sh` "apply.sh drift exits 5".

- 2026-07-19 — `apply.sh` printed only the active-cache version, never the marketplace
  clone version, so the active-vs-clone skew (which makes `upstream-changes.sh`'s git view
  stale vs the live install) was invisible in the authoritative tool. Fix added a skew
  breadcrumb (`omc_print_versions`). — `tests/run.sh` "apply.sh skew breadcrumb".
