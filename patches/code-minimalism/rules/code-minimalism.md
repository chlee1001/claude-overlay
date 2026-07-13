---
alwaysApply: true
---

# Code Minimalism Rules

Applies to **code work only** — writing, adding, refactoring, fixing, reviewing code,
and choosing libraries/dependencies. Not for prose, docs, translation, or summaries
(those under-build if you apply this). The mindset (think-before-coding, simplicity,
surgical changes) lives in `karpathy-guidelines.md`; this file adds the *procedure* and
the *safety floor* that make minimalism safe. Absorbed from the ponytail "lazy senior
dev" discipline — see the overlay's `sources/ponytail/`.

## The ladder — stop at the first rung that holds

Run this **after** you understand the problem, never instead of it: read the task and
the code it touches, trace the real flow end to end, then climb.

1. **Does this need to exist at all?** Speculative need → skip it, say so in one line. (YAGNI)
2. **Already in this codebase?** A helper, util, type, or pattern already here → reuse it. Re-implementing what's a few files over is the most common slop.
3. **Stdlib does it?** Use it.
4. **Native platform feature covers it?** `<input type="date">` over a picker lib, CSS over JS, a DB constraint over app code.
5. **Already-installed dependency solves it?** Use it. Never add a new dependency for what a few lines can do.
6. **Can it be one line?** One line.
7. **Only then:** write the minimum code that works.

Two rungs work → take the higher one and move on. The first lazy solution that works is
the right one — once you actually know what the change has to touch.

## Bug fix = root cause, not symptom

A report names a symptom. Before editing, grep every caller of the function you're about
to touch. One guard in the shared function is a smaller diff than a guard per caller —
and patching only the path the ticket names leaves every sibling caller still broken.
Fix it once, where all callers route through.

## Rules

- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes.
- No boilerplate or scaffolding "for later" — later can scaffold for itself.
- Deletion over addition. Boring over clever (clever is what someone decodes at 3am). Fewest files possible.
- Shortest working diff wins — but only once you understand the problem. The smallest change in the wrong place isn't lazy, it's a second bug.
- Complex request? Ship the lazy version and question it in the same response ("Did X; Y covers it. Need full X? Say so."). Never stall.
- Two stdlib options, same size? Take the one that's correct on edge cases. Lazy means less code, not the flimsier algorithm.
- Mark a deliberate simplification with a `simplification:` comment so it reads as intent, not ignorance. If the shortcut has a known ceiling (global lock, O(n²) scan, naive heuristic), the comment names the ceiling and the upgrade path: `# simplification: global lock; per-account locks if throughput matters`.

## When NOT to be lazy (the safety floor — non-negotiable)

Never simplify away:

- **Understanding the problem.** The ladder shortens the solution, never the reading. A small diff you don't understand is laziness dressed up as efficiency — it ships a confident wrong fix.
- **Input validation at trust boundaries.**
- **Error handling that prevents data loss.**
- **Security measures.**
- **Accessibility basics.**
- **Hardware calibration.** The platform is never the spec ideal — a clock drifts, a sensor reads off. Leave the calibration knob, not just less code.
- **Anything the user explicitly asked to keep.** They insist on the full version → build it, no re-arguing.

**Lazy code without its check is unfinished.** Non-trivial logic (a branch, loop, parser,
money/security path) leaves ONE runnable check behind — the smallest thing that fails if
the logic breaks: an `assert`-based self-check or one small test file. No frameworks, no
fixtures. Trivial one-liners need no test (YAGNI applies to tests too).
