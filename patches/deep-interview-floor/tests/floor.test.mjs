#!/usr/bin/env node
// Regression test for the deep-interview dimension-floor hook (omc-di-floor.mjs).
// Hermetic: builds synthetic OMC-shape state (flattened top-level + _meta, the
// shape state_write actually writes to disk) in a fresh temp cwd, pipes
// {cwd, session_id} to the hook, asserts on the parsed JSON. No real-state
// fixtures. Run: node floor.test.mjs
import { writeFileSync, mkdtempSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const HOOK = join(HERE, '..', 'hooks', 'omc-di-floor.mjs');
let pass = 0, fail = 0;

// Build a fresh cwd with the state file at the legacy path, plus a deterministic
// project settings.json pinning maxRounds (so the escape hatch is predictable
// regardless of the user's real ~/.claude/settings.json).
function scenario(state, { maxRounds = 20 } = {}) {
  const cwd = mkdtempSync(join(tmpdir(), 'di-floor-'));
  mkdirSync(join(cwd, '.omc', 'state'), { recursive: true });
  writeFileSync(join(cwd, '.omc', 'state', 'deep-interview-state.json'), JSON.stringify(state));
  mkdirSync(join(cwd, '.claude'), { recursive: true });
  writeFileSync(join(cwd, '.claude', 'settings.json'),
    JSON.stringify({ omc: { deepInterview: { maxRounds } } }));
  return cwd;
}
function run(cwd, env = {}) {
  const out = execFileSync('node', [HOOK], {
    input: JSON.stringify({ cwd, session_id: 'test-sid' }),
    env: { ...process.env, ...env },
  }).toString();
  return JSON.parse(out || '{}');
}
function assert(name, cond) {
  if (cond) { pass++; console.log('  PASS', name); }
  else { fail++; console.log('  FAIL', name); }
}
const isBlock = (r) => !!r.hookSpecificOutput?.additionalContext;
const ctx = (r) => r.hookSpecificOutput?.additionalContext || '';

// OMC-shape state defaults (flattened top-level + _meta).
function omcState(overrides = {}) {
  return {
    _meta: { mode: 'deep-interview' },
    active: true,
    type: 'greenfield',
    current_ambiguity: 0.18,
    threshold: 0.2,
    rounds: [{}],
    topology: { components: [] },
    ...overrides,
  };
}
const comp = (clarity_scores, status = 'active') => ({ status, clarity_scores });
const topo = (...components) => ({ components });

// 1. Populated topology, one dim below floor → block, names criteria.
let r = run(scenario(omcState({
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.5, context: null })),
})));
assert('1 below-floor dim → blocks', isBlock(r));
assert('1 names criteria + value', ctx(r).includes('criteria') && ctx(r).includes('0.50 < 0.70'));

// 2. All-null clarity_scores (Round 0 init) → nulls skipped, allow.
r = run(scenario(omcState({
  topology: topo(comp({ goal: null, constraints: null, criteria: null, context: null })),
})));
assert('2 all-null → allow (nulls not compared)', !isBlock(r) && r.continue === true);

// 3. Multi-component MIN trips: criteria {0.9, 0.55} → min 0.55 < 0.70.
r = run(scenario(omcState({
  topology: topo(
    comp({ goal: 0.9, constraints: 0.9, criteria: 0.9, context: null }),
    comp({ goal: 0.9, constraints: 0.9, criteria: 0.55, context: null }),
  ),
})));
assert('3 multi-component min trips → names criteria', isBlock(r) && ctx(r).includes('criteria'));

// 4. All dims above floor → silent allow.
r = run(scenario(omcState({
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.9, context: null })),
})));
assert('4 all above floor → allow', !isBlock(r) && r.continue === true);

// 5. Empty topology AND no scores_after → fail-safe allow.
r = run(scenario(omcState({ topology: topo(), rounds: [{}] })));
assert('5 unresolvable → allow', !isBlock(r) && r.continue === true);

// 6. Fallback alias path (OMX-shape scores_after): success → criteria.
r = run(scenario(omcState({
  topology: topo(),
  rounds: [{ scores_after: { intent: 0.9, constraints: 0.9, success: 0.5, context: 0.9 } }],
})));
assert('6 fallback alias → names criteria via success', isBlock(r) && ctx(r).includes('criteria'));

// 7. Fail-safe threshold: ambiguity > threshold → allow even with a low dim.
r = run(scenario(omcState({
  current_ambiguity: 0.5,
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.5, context: null })),
})));
assert('7 ambiguity > threshold → allow', !isBlock(r) && r.continue === true);

// 8. Escape hatch: rounds.length >= maxRounds → allow despite low dim.
r = run(scenario(omcState({
  rounds: [{}, {}, {}],
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.5, context: null })),
}), { maxRounds: 3 }));
assert('8 maxRounds reached → allow', !isBlock(r) && r.continue === true);

// 9. Kill-switch → allow.
r = run(scenario(omcState({
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.5, context: null })),
})), { OMC_SKIP_DI_FLOOR: '1' });
assert('9 kill-switch → allow', !isBlock(r) && r.continue === true);

// 10. Identity gate: top-level mode present but _meta.mode absent → allow.
r = run(scenario({
  mode: 'deep-interview', // top-level only; hook must NOT gate on this
  _meta: { mode: 'something-else' },
  active: true, type: 'greenfield', current_ambiguity: 0.18, threshold: 0.2,
  rounds: [{}],
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.5, context: null })),
}));
assert('10 gates on _meta.mode not top-level mode → allow', !isBlock(r) && r.continue === true);

// 10b. active:false → allow.
r = run(scenario(omcState({
  active: false,
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.5, context: null })),
})));
assert('10b active:false → allow', !isBlock(r) && r.continue === true);

// 11. Brownfield context floor: context 0.5 < 0.60 → block, names context.
r = run(scenario(omcState({
  type: 'brownfield',
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.9, context: 0.5 })),
})));
assert('11 brownfield context below floor → names context', isBlock(r) && ctx(r).includes('context'));

// 11b. Greenfield: low context is NOT gated (context floor is brownfield-only).
r = run(scenario(omcState({
  type: 'greenfield',
  topology: topo(comp({ goal: 0.9, constraints: 0.9, criteria: 0.9, context: 0.3 })),
})));
assert('11b greenfield low context → allow (floor brownfield-only)', !isBlock(r) && r.continue === true);

// 12. Fail-safe: empty/malformed state → allow.
r = run(scenario({}));
assert('12 empty state → allow', !isBlock(r) && r.continue === true);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
