# vercel-skills-executor — maintenance note

Stacks on agents/executor.md alongside executor-minimalism + executor-tdd. apply.sh will therefore
ALWAYS report this patch as "upstream drifted, merged cleanly" (the live target carries the other two
blocks). This is EXPECTED and benign — do NOT run --update-baseline on it.

baseline.md is the TRUE pristine executor.md (copied from executor-minimalism/baseline.md, itself
extracted via `git show HEAD:agents/executor.md`). Advancing the baseline would fold the other patches'
blocks into it and corrupt this patch's single-purpose diff. Only re-extract pristine via git when
UPSTREAM itself changes executor.md.

Our block is appended after </Agent_Prompt> (disjoint from minimalism@~L20 and tdd@Final_Checklist) so
the 3-way merge stays clean.
