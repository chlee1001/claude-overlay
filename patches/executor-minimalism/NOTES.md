# executor-minimalism — maintenance note

This patch stacks on the SAME target (`agents/executor.md`) as `executor-tdd`.
Because the live target always carries the tdd block, apply.sh will ALWAYS report
this patch as "upstream drifted, merged cleanly" and suggest `--update-baseline`.

DO NOT run `--update-baseline` on this patch. Its `baseline.md` is the TRUE pristine
upstream executor.md (from `git show HEAD:agents/executor.md`). Updating the baseline
would copy the tdd-applied target into it and corrupt this patch's single-purpose diff.

Only advance the baseline when UPSTREAM itself changes executor.md, and then only by
re-extracting pristine via git — never from the working (patched) target.
