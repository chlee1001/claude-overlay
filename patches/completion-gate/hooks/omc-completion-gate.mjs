#!/usr/bin/env node

/**
 * OMC Completion Hard Gate (Stop hook) — borrowed from Superpowers'
 * verification-before-completion discipline.
 *
 * Problem: OMC has NO main-loop gate that stops the assistant from ending a
 * turn with a "done / fixed / passing" claim that was never verified.
 * (`verify-deliverables.mjs` is advisory + SubagentStop-only; context-guard is
 * about context %.) This fills exactly that gap.
 *
 * Behavior: if the final assistant message claims completion AND this turn shows
 * no sign of a verification run (test/build/lint/typecheck command, or a
 * verifier/test/qa agent), block ONCE with a nudge to actually verify.
 *
 * Secondary (advisory, non-blocking): once a completion is claimed AND verified,
 * scan this turn's file edits for planning-artifact leakage in comments (plan
 * step IDs like "P2 fallback", "V1-V4", "Phase 0" that mean nothing to a
 * future reader) and surface a one-line comment-hygiene advisory. This never
 * blocks — it is the institutionalized "code-work-finished" comment nudge. It is
 * intentionally scoped to plan-ID leakage only (not mere Korean presence, which
 * is normal for Korean-writing users, and not abbreviations, which are noisy).
 *
 * Safety rails (bias toward NOT annoying the user):
 *   - Fires at most ONCE per stop chain (honors `stop_hook_active`).
 *   - Never blocks user-abort or context-limit stops.
 *   - Never blocks when a persistent mode (ralph/ultrawork/autopilot/team) is
 *     active — those own their own loop.
 *   - Disabled by OMC_SKIP_COMPLETION_GATE=1 or DISABLE_OMC containing
 *     'completion-gate'.
 *   - Any error → allow (never break the session).
 *
 * Output: { decision: "block", reason } to nudge, else { continue: true,
 *          suppressOutput: true }.
 */

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

function allow() {
  process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true }));
  process.exit(0);
}
function block(reason) {
  process.stdout.write(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
}
// Non-blocking: let the turn end but surface a one-line advisory to the user.
function allowWithMessage(systemMessage) {
  process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true, systemMessage }));
  process.exit(0);
}

async function readStdin() {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks).toString('utf-8');
}

// --- Detection vocab -------------------------------------------------------

// Strong completion claims (English + Korean). Word-boundary where it helps.
const CLAIM_RE = new RegExp(
  [
    '\\b(done|complete|completed|finished|fixed|resolved|passing|implemented)\\b',
    '\\ball (tests?|checks?) (pass|passed|passing|green)\\b',
    '\\b(works now|good to go|ready to (merge|ship|go)|successfully (added|created|fixed|implemented|updated))\\b',
    '✅',
    '(완료(했|됐|입니다|\\b)|끝났|끝냈|마쳤|마무리(했|됐)|구현(완료|했)|수정(했|완료)|고쳤|통과(했|입니다|됐)|작동(합니다|해요|함)|성공적으로)',
  ].join('|'),
  'i'
);

// Verification evidence: a command or agent that actually checks the work.
const EVIDENCE_CMD_RE = new RegExp(
  [
    '\\b(npm|pnpm|yarn|bun)\\s+(run\\s+)?(test|build|lint|typecheck|check|tsc)\\b',
    '\\b(jest|vitest|mocha|pytest|tox|nox|rspec|phpunit)\\b',
    '\\bgo\\s+(test|build|vet)\\b',
    '\\bcargo\\s+(test|build|check|clippy)\\b',
    '\\b(make|gradle|mvn)\\s+\\w*(test|check|build|verify)\\w*\\b',
    '\\b(tsc|eslint|ruff|mypy|flake8|playwright|cypress|dotnet\\s+test)\\b',
    '\\bpython\\s+-m\\s+(pytest|unittest)\\b',
    '\\bbash\\s+-n\\b',
    '\\b(apply\\.sh|verify)\\b',
  ].join('|'),
  'i'
);

// Agents that constitute verification when dispatched via the Task tool.
const EVIDENCE_AGENT_RE = /verifier|test-engineer|qa-tester|security-reviewer|code-reviewer|critic/i;

// Test-output-shaped strings pasted into the transcript also count as evidence.
const EVIDENCE_OUTPUT_RE = /(\bPASS\b|passed|✓|0 failed|all tests pass|build succeeded|tests? (passed|ok))/i;

// --- Comment-hygiene advisory vocab (planning-artifact leakage, #2 only) ----

// A line that reads as a code comment (leading marker for common languages).
const COMMENT_LINE_RE = /^\s*(\/\/|#|\/\*|\*|--|;|<!--)/;

// High-precision plan-ID leakage. Deliberately COMPOUND, language-agnostic
// phrasings only — bare tokens like "G1"/"S3" are too ambiguous (hardware pins,
// bucket names) for an auto-advisory. Matches: "P2 fallback", "V1-V4",
// "Phase 0", "G1 validator". Korean stage-leak (e.g. "3단계") is intentionally
// NOT auto-triggered: it collides with legit domain terms like "2단계 인증"
// (2FA), so it is left to the on-demand Pass 5 with its repo-resolvability grep.
const PLAN_ID_RE =
  /\bPhase\s?\d+\b|\bV\d\s*-\s*V\d\b|\b[GPVST]\d\s+(fallback|path|case|branch|validator|probe|step)\b/i;

// Extract the added/authored text from an Edit/Write/MultiEdit tool_use input.
function editedText(name, input) {
  if (name === 'Write') return String(input?.content || '');
  if (name === 'Edit') return String(input?.new_string || '');
  if (name === 'MultiEdit' && Array.isArray(input?.edits)) {
    return input.edits.map((e) => String(e?.new_string || '')).join('\n');
  }
  return '';
}

function baseName(p) {
  return String(p || '').split('/').filter(Boolean).pop() || String(p || '');
}

// --- Helpers ---------------------------------------------------------------

function isUserAbort(d) {
  if (d.user_requested || d.userRequested) return true;
  const r = String(d.stop_reason || d.stopReason || d.reason || '').toLowerCase();
  return ['aborted', 'abort', 'cancel', 'interrupt'].some((p) => r === p) ||
    ['user_cancel', 'user_interrupt', 'ctrl_c', 'manual_stop'].some((p) => r.includes(p));
}
function isContextLimit(d) {
  const r = String(d.stop_reason || d.stopReason || d.reason || '').toLowerCase().replace(/[\s-]+/g, '_');
  return ['context_limit', 'context_window', 'context_exceeded', 'context_full',
    'max_context', 'token_limit', 'max_tokens', 'conversation_too_long', 'input_too_long']
    .some((p) => r.includes(p));
}

// A persistent OMC mode owns its own continuation loop — don't interfere.
function persistentModeActive() {
  try {
    const stateDir = join(process.cwd(), '.omc', 'state');
    if (!existsSync(stateDir)) return false;
    const names = readdirSync(stateDir).join(' ').toLowerCase();
    return /(ralph|ultrawork|autopilot|ultraqa|team|swarm|pipeline)/.test(names) &&
      /active|mode|running/.test(names);
  } catch { return false; }
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((b) => (typeof b === 'string' ? b : b?.text || '')).join('\n');
}

/**
 * Parse the transcript tail. Returns { lastAssistantText, hasEvidence }.
 * Evidence is searched only within the CURRENT turn — i.e. transcript events
 * after the last user (human) message — so stale verification from earlier
 * doesn't excuse an unverified new claim.
 */
function analyzeTranscript(transcriptPath) {
  const out = { lastAssistantText: '', hasEvidence: false, commentLeakFiles: [] };
  if (!transcriptPath || !existsSync(transcriptPath)) return out;
  const leakSet = new Set();

  let lines;
  try {
    lines = readFileSync(transcriptPath, 'utf-8').split('\n').filter(Boolean);
  } catch { return out; }

  // Walk from the end; collect events back to (and excluding) the last real
  // user message. Cap the scan so a huge transcript stays within the 5s budget.
  const scan = lines.slice(-200);
  const events = [];
  for (let i = scan.length - 1; i >= 0; i--) {
    let ev;
    try { ev = JSON.parse(scan[i]); } catch { continue; }
    const role = ev?.message?.role || ev?.role || ev?.type;
    // Stop at the human turn boundary (a genuine user message, not a tool_result).
    if (role === 'user') {
      const c = ev?.message?.content;
      const isToolResult = Array.isArray(c) && c.some((b) => b?.type === 'tool_result');
      if (!isToolResult) break;
    }
    events.push(ev);
  }
  events.reverse();

  let lastAssistantText = '';
  for (const ev of events) {
    const msg = ev?.message || ev;
    const role = msg?.role || ev?.type;
    const content = msg?.content;

    if (role === 'assistant') {
      const t = textOf(content);
      if (t.trim()) lastAssistantText = t;
      if (Array.isArray(content)) {
        for (const b of content) {
          if (b?.type !== 'tool_use') continue;
          const name = String(b?.name || '');
          const input = b?.input || {};
          if (name === 'Bash' && EVIDENCE_CMD_RE.test(String(input.command || ''))) out.hasEvidence = true;
          if ((name === 'Task' || name === 'Agent') &&
              EVIDENCE_AGENT_RE.test(JSON.stringify(input))) out.hasEvidence = true;
          if (name === 'Write' || name === 'Edit' || name === 'MultiEdit') {
            const leaked = editedText(name, input)
              .split('\n')
              .some((ln) => COMMENT_LINE_RE.test(ln) && PLAN_ID_RE.test(ln));
            if (leaked && input?.file_path) leakSet.add(baseName(input.file_path));
          }
        }
      }
    }
    // tool_result blocks (carried on user-role events) may contain test output.
    const blocks = Array.isArray(content) ? content : [];
    for (const b of blocks) {
      if (b?.type === 'tool_result' && EVIDENCE_OUTPUT_RE.test(textOf(b?.content))) out.hasEvidence = true;
    }
  }
  out.lastAssistantText = lastAssistantText;
  out.commentLeakFiles = [...leakSet];
  return out;
}

const NUDGE = [
  '완료를 주장했지만 이번 턴에서 테스트/빌드/검증 실행 흔적이 보이지 않습니다.',
  '마무리 전에 둘 중 하나를 하세요:',
  '  1) 실제 검증을 돌려 출력을 확인하거나(verifier/test-engineer 에이전트 또는 테스트·빌드 명령), 또는',
  '  2) 이 작업에 검증이 불필요하면 왜 불필요한지 한 줄로 명시하세요.',
  '그런 다음 마무리하세요. (이 게이트는 한 번만 작동합니다.)',
].join('\n');

function commentAdvisory(files) {
  const list = files.slice(0, 5).join(', ') + (files.length > 5 ? ', …' : '');
  return [
    `주석 위생 권고: 이번 턴에 편집한 주석에 계획-단계 표기(plan-ID)가 남아 있습니다 — ${list}.`,
    '미래 개발자에겐 뜻이 통하지 않으니 ai-slop-cleaner의 Pass 5(주석 위생)로 정리를 고려하세요. (차단 아님, 권고)',
  ].join('\n');
}

// --- Main ------------------------------------------------------------------

(async () => {
  try {
    if (process.env.OMC_SKIP_COMPLETION_GATE === '1') return allow();
    if (String(process.env.DISABLE_OMC || '').includes('completion-gate')) return allow();

    const raw = await readStdin();
    let data = {};
    try { data = JSON.parse(raw || '{}'); } catch { return allow(); }

    // Already nudged once in this stop chain → let it stop (no loops, one nudge).
    if (data.stop_hook_active === true) return allow();
    if (isUserAbort(data) || isContextLimit(data)) return allow();
    if (persistentModeActive()) return allow();

    const { lastAssistantText, hasEvidence, commentLeakFiles } =
      analyzeTranscript(data.transcript_path || data.transcriptPath);
    if (!lastAssistantText) return allow();
    if (!CLAIM_RE.test(lastAssistantText)) return allow();
    if (!hasEvidence) return block(NUDGE);

    // Finished AND verified: surface the comment-hygiene advisory (non-blocking)
    // if this turn's edits left plan-ID leakage in comments.
    const skipHygiene = process.env.OMC_SKIP_COMMENT_HYGIENE === '1' ||
      String(process.env.DISABLE_OMC || '').includes('comment-hygiene');
    if (!skipHygiene && commentLeakFiles.length) {
      return allowWithMessage(commentAdvisory(commentLeakFiles));
    }
    return allow();
  } catch {
    return allow();
  }
})();
