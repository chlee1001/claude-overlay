#!/usr/bin/env node
// Regression test for the completion-gate comment-hygiene advisory.
// Hermetic: builds synthetic transcripts in a temp dir, pipes them to the hook,
// asserts on the parsed JSON decision. Run: node comment-hygiene.test.mjs
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const HOOK = join(HERE, '..', 'hooks', 'omc-completion-gate.mjs');
const dir = mkdtempSync(join(tmpdir(), 'cg-hooktest-'));
let pass = 0, fail = 0, seq = 0;

function tx(events) {
  const p = join(dir, `t${seq++}.jsonl`);
  writeFileSync(p, events.map((e) => JSON.stringify(e)).join('\n'));
  return p;
}
function run(transcriptPath, env = {}) {
  const out = execFileSync('node', [HOOK], {
    input: JSON.stringify({ transcript_path: transcriptPath }),
    env: { ...process.env, ...env },
  }).toString();
  return JSON.parse(out || '{}');
}
function assert(name, cond) {
  if (cond) { pass++; console.log('  PASS', name); }
  else { fail++; console.log('  FAIL', name); }
}

const userMsg = { type: 'user', message: { role: 'user', content: 'go implement it' } };
const asst = (blocks) => ({ type: 'assistant', message: { role: 'assistant', content: blocks } });
const bashEvidence = { type: 'tool_use', name: 'Bash', input: { command: 'python -m pytest' } };
const claim = { type: 'text', text: '완료했습니다. 모든 테스트 통과.' };
const editLeak = { type: 'tool_use', name: 'Edit', input: { file_path: 'src/foo.py', new_string: '# P2 fallback: handle blocked fetch\nx = 1' } };
const editClean = { type: 'tool_use', name: 'Edit', input: { file_path: 'src/foo.py', new_string: '# retry with backoff when the upstream 403s\nx = 1' } };
const editLegitRef = { type: 'tool_use', name: 'Edit', input: { file_path: 'src/bar.py', new_string: '# see JIRA-1234 and #45 for context\ny = 2' } };
const editPlanIdInCode = { type: 'tool_use', name: 'Edit', input: { file_path: 'src/baz.py', new_string: 'phase0 = compute()\ns = "Phase 0"' } };
const writeLeak = { type: 'tool_use', name: 'Write', input: { file_path: 'a/plan.ts', content: '// V1-V4 validator lockstep\nexport const x = 1;' } };

let r = run(tx([userMsg, asst([bashEvidence, editLeak, claim])]));
assert('leak → systemMessage present', typeof r.systemMessage === 'string' && r.systemMessage.includes('plan-ID'));
assert('leak → non-blocking', r.decision !== 'block' && r.continue === true);
assert('leak → names the file', r.systemMessage.includes('foo.py'));

r = run(tx([userMsg, asst([bashEvidence, editClean, claim])]));
assert('clean comment → silent allow', !r.systemMessage && r.continue === true && r.decision !== 'block');

r = run(tx([userMsg, asst([editLeak, claim])]));
assert('claim + no evidence → block (gate primary)', r.decision === 'block');

r = run(tx([userMsg, asst([bashEvidence, editLeak, { type: 'text', text: '작업 중입니다.' }])]));
assert('no completion claim → allow, no nag', r.continue === true && r.decision !== 'block' && !r.systemMessage);

r = run(tx([userMsg, asst([bashEvidence, editLeak, claim])]), { OMC_SKIP_COMMENT_HYGIENE: '1' });
assert('killswitch → no advisory', !r.systemMessage && r.continue === true);

r = run(tx([userMsg, asst([bashEvidence, editLegitRef, claim])]));
assert('legit ref (JIRA/#45) → no advisory', !r.systemMessage);

r = run(tx([userMsg, asst([bashEvidence, editPlanIdInCode, claim])]));
assert('plan-ID in code/string only → no advisory', !r.systemMessage);

r = run(tx([userMsg, asst([bashEvidence, writeLeak, claim])]));
assert('Write V1-V4 → advisory names plan.ts', !!r.systemMessage && r.systemMessage.includes('plan.ts'));

// MultiEdit: leak in one of several edits → advisory names the file
const multiLeak = { type: 'tool_use', name: 'MultiEdit', input: { file_path: 'm/x.ts', edits: [{ new_string: 'const a = 1;' }, { new_string: '// P2 fallback path when blocked\nconst b = 2;' }] } };
r = run(tx([userMsg, asst([bashEvidence, multiLeak, claim])]));
assert('MultiEdit leak → advisory names x.ts', !!r.systemMessage && r.systemMessage.includes('x.ts'));

// Korean stage-leak ("2단계 인증") is intentionally NOT auto-triggered (deferred
// to the manual Pass 5 grep) — it collides with legit domain terms.
const editKoreanStage = { type: 'tool_use', name: 'Edit', input: { file_path: 'k/auth.ts', new_string: '// 2단계 인증을 3단계로 확장한다\nconst c = 3;' } };
r = run(tx([userMsg, asst([bashEvidence, editKoreanStage, claim])]));
assert('Korean N단계 → no advisory (deferred to Pass 5)', !r.systemMessage);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
