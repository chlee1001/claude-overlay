#!/usr/bin/env node

/**
 * OMC Deep-Interview Dimension Floor (PostToolUse hook) — ports the Ouroboros
 * per-dimension clarity floor that OMC lost when the gate was prompt-ized.
 *
 * Problem: OMC deep-interview crystallizes once the LLM's self-reported weighted
 * `current_ambiguity` drops <= threshold, with NO code check that any single
 * clarity dimension is actually strong. Ouroboros enforced per-dimension floors
 * in code (ambiguity.py: get_completion_floor_failures). This restores that as an
 * owned overlay hook, sibling to completion-gate.
 *
 * Behavior: after each deep-interview `state_write`, re-read the persisted state,
 * resolve the per-dimension clarity vector, and — only when the weighted
 * ambiguity is already at/below threshold (the skill is about to treat the
 * interview as done) AND a resolved numeric dimension is below its floor — inject
 * an advisory `<system-reminder>` that NAMES the failing dimension(s) and tells
 * the skill not to crystallize yet.
 *
 * Enforcement ceiling: a PostToolUse hook can only inject `additionalContext`, it
 * cannot clamp state — this is advisory, the model can still rationalize past it.
 *
 * Fail-safe over false-block (the state schema is model-authored and drifts):
 *   - Any absent/`null`/non-numeric/malformed signal → allow (skip that floor).
 *   - `null` clarity (Round 0 init) is ABSENT, never compared (no `null < floor`).
 *   - Escape hatch: rounds.length >= maxRounds (skill's own hard cap) → allow.
 *   - Kill-switch: OMC_SKIP_DI_FLOOR=1 or DISABLE_OMC contains 'deep-interview-floor'.
 *   - Any error → allow (never break the session).
 *
 * OMC-only: reads `.omc/state`. OMX (`.omx/state`) traffic is a deliberate no-op
 * in Phase 1 (see the plan's "OMX widening" one-liner to opt in).
 *
 * Output: { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext } }
 *         to nudge, else { continue: true, suppressOutput: true }.
 */

import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// Ouroboros floor constants (ambiguity.py) — kept as-is: OMC and Ouroboros share
// the same threshold (0.2), weights, and formula, so the math environment is
// identical and no recalibration is warranted.
const FLOORS = { goal: 0.75, constraints: 0.65, criteria: 0.70, context: 0.60 };
const DIMS = ['goal', 'constraints', 'criteria', 'context'];

// Defensive fallback for the OMX-shape `rounds[].scores_after` object — maps its
// keys onto the OMC-native canonical dimensions. Weakest sub-signal governs (min).
const ALIASES = {
  goal: ['goal', 'goal_clarity', 'intent'],
  constraints: ['constraints', 'constraint', 'constraint_clarity'],
  criteria: ['criteria', 'success', 'success_criteria', 'success_criteria_clarity'],
  context: ['context', 'context_clarity'],
};

function allow() {
  process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true }));
  process.exit(0);
}
function block(additionalContext) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext },
  }));
  process.exit(0);
}

async function readStdin() {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks).toString('utf-8');
}

// A clarity value counts only if it is a real number (Round 0 `null`, strings, or
// NaN are ABSENT — never compared to a floor).
function numOrNull(v) {
  return typeof v === 'number' && !Number.isNaN(v) ? v : null;
}

// Primary (OMC contract, SKILL.md:364): per-dimension min of numeric
// clarity_scores across active (status !== 'deferred') topology components.
function resolvePrimary(topology) {
  const comps = Array.isArray(topology?.components) ? topology.components : [];
  const out = { goal: null, constraints: null, criteria: null, context: null };
  for (const dim of DIMS) {
    const vals = [];
    for (const c of comps) {
      if (!c || c.status === 'deferred') continue;
      const n = numOrNull(c.clarity_scores?.[dim]);
      if (n !== null) vals.push(n);
    }
    if (vals.length) out[dim] = Math.min(...vals);
  }
  return out;
}

// Fallback (defensive): newest rounds[] entry carrying a scores_after object,
// resolved through the alias map. Harmless when absent.
function resolveFallback(rounds) {
  const arr = Array.isArray(rounds) ? rounds : [];
  let sa = null;
  for (let i = arr.length - 1; i >= 0; i--) {
    const s = arr[i]?.scores_after;
    if (s && typeof s === 'object') { sa = s; break; }
  }
  const out = { goal: null, constraints: null, criteria: null, context: null };
  if (!sa) return out;
  for (const dim of DIMS) {
    const vals = [];
    for (const key of ALIASES[dim]) {
      const n = numOrNull(sa[key]);
      if (n !== null) vals.push(n);
    }
    if (vals.length) out[dim] = Math.min(...vals);
  }
  return out;
}

// maxRounds escape hatch: reuse the skill's own hard round-cap (Phase 2f).
// Project settings override user settings; default 20.
function readMaxRounds(cwd) {
  for (const p of [join(cwd, '.claude', 'settings.json'), join(homedir(), '.claude', 'settings.json')]) {
    try {
      if (!existsSync(p)) continue;
      const mr = JSON.parse(readFileSync(p, 'utf-8'))?.omc?.deepInterview?.maxRounds;
      if (typeof mr === 'number' && mr > 0) return mr;
    } catch { /* ignore malformed settings */ }
  }
  return 20;
}

function loadState(cwd, sessionId) {
  const probes = [];
  if (sessionId) probes.push(join(cwd, '.omc', 'state', 'sessions', sessionId, 'deep-interview-state.json'));
  probes.push(join(cwd, '.omc', 'state', 'deep-interview-state.json'));
  // OMX widening (NOT enabled in Phase 1): add `.omx/state/...` probes here to
  // also cover OMX traffic; the fallback resolver already handles its shape.
  for (const p of probes) {
    try {
      if (existsSync(p)) return JSON.parse(readFileSync(p, 'utf-8'));
    } catch { /* malformed → try next, else fail-safe allow */ }
  }
  return null;
}

// --- Main ------------------------------------------------------------------

(async () => {
  try {
    if (process.env.OMC_SKIP_DI_FLOOR === '1') return allow();
    if (String(process.env.DISABLE_OMC || '').includes('deep-interview-floor')) return allow();

    const raw = await readStdin();
    let data = {};
    try { data = JSON.parse(raw || '{}'); } catch { return allow(); }

    const cwd = data.cwd || process.cwd();
    const parsed = loadState(cwd, data.session_id);
    if (!parsed || typeof parsed !== 'object') return allow();

    // Identity gate: state_write flattens the payload to top level + `_meta`, and
    // mode lives ONLY at `_meta.mode` (top-level `mode` is absent on disk; do not
    // gate on it or on `current_phase`).
    if (parsed._meta?.mode !== 'deep-interview') return allow();
    if (parsed.active === false) return allow();

    const { topology, rounds, current_ambiguity: reported, type } = parsed;

    // Escape hatch: at/over the skill's own hard round-cap, it owns the release valve.
    if (Array.isArray(rounds) && rounds.length >= readMaxRounds(cwd)) return allow();

    // simplification: 2-round streak dormant — OMC persists no per-round ambiguity
    // history (ambiguity_after / consecutive_below_threshold are OMX-only). Upgrade:
    // when a per-round ambiguity history exists, count trailing rounds <= threshold
    // and require >= 2 consecutive before allowing crystallize.

    const primary = resolvePrimary(topology);
    const fallback = resolveFallback(rounds);
    const isBrownfield = type === 'brownfield';

    const failures = [];
    for (const dim of DIMS) {
      if (dim === 'context' && !isBrownfield) continue; // context floor is brownfield-only
      const v = primary[dim] !== null ? primary[dim] : fallback[dim];
      if (v === null) continue;              // absent/null → skip this floor
      if (v < FLOORS[dim]) failures.push({ dim, score: v, floor: FLOORS[dim] });
    }

    // Only gate when the skill is about to treat the interview as done.
    const threshold = numOrNull(parsed.threshold) !== null ? parsed.threshold : 0.2;
    if (numOrNull(reported) === null) return allow();
    if (reported > threshold || failures.length === 0) return allow();

    const lines = failures.map((f) => `  - ${f.dim}: ${f.score.toFixed(2)} < ${f.floor.toFixed(2)}`);
    const weakest = failures.reduce((a, b) => (a.score - a.floor <= b.score - b.floor ? a : b)).dim;
    const reminder = [
      '<system-reminder>',
      'di-floor: weighted ambiguity is at/below threshold, but these scored clarity dimension(s) are below their per-dimension floor:',
      ...lines,
      `Do NOT crystallize the spec yet. Aim the next question at the weakest failing dimension (${weakest}) and re-score before proceeding.`,
      '(Ouroboros per-dimension floor, advisory; fail-safe — unscored/null dimensions are skipped.)',
      '</system-reminder>',
    ].join('\n');
    return block(reminder);
  } catch {
    return allow();
  }
})();
