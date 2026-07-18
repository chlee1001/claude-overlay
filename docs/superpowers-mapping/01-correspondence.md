# Superpowers ↔ OMC 대응표

출처: [obra/Superpowers](https://github.com/obra/Superpowers) v6.0.3 (Jesse Vincent)
작성일: 2026-06-28

## 한눈에 보는 차이

| | Superpowers | OMC (oh-my-claudecode) |
|---|---|---|
| 구성 | 스킬 라이브러리 14개만 (슬래시 명령·named agent 없음) | named agent + tier-0 워크플로우 + 스킬 다수 |
| 실행 방식 | description 조건으로 **자동 강제 발동** | 대부분 **명시 호출/opt-in** + 일부 키워드 트리거 |
| 강제력 | `using-superpowers` 부트스트랩이 세션 시작·compaction마다 주입 → "제안 아닌 필수 워크플로우" | CLAUDE.md operating_principles + 일부 hook (magic keyword) |
| 철학 | 4기둥: TDD / 체계 > 임기응변 / 단순성 / 증거 > 주장 | 위임 우선 / 증거 기반 / 저비용 경로 / 작성·리뷰 분리 |
| 단위 | 7단계 고정 파이프라인 | 작업 성격별 워크플로우 선택 후 에이전트 오케스트레이션 |

핵심: Superpowers는 **한 줄 컨베이어 벨트를 강제로** 태우고, OMC는 **작업에 맞는 워크플로우를 골라** 에이전트를 배치한다.

---

## 7단계 캐노니컬 워크플로우 대응

| # | Superpowers 단계 (스킬) | OMC 대응 | 비고 |
|---|---|---|---|
| 1 | **brainstorming** — 소크라테스식 질문으로 설계 도출, 설계문서 저장 | `/brainstorm`, `/deep-interview`, `/ralplan`(합의 게이트), clarify:vague/unknown/metamedium | OMC는 brainstorm/interview가 분리돼 더 다양. ralplan은 모호 요청 자동 차단 게이트 |
| 2 | **using-git-worktrees** — 격리 브랜치 워크트리, 클린 테스트 베이스라인 확인 | `EnterWorktree`/`ExitWorktree` 툴, `project-session-manager`(워크트리 우선) | OMC는 워크트리가 "필수 단계"가 아니라 옵션 |
| 3 | **writing-plans** — 2~5분 단위 태스크, 정확한 파일경로·완성 코드·검증스텝 | `/plan`, `planner`/`architect` 에이전트, `.omc/plans/` | Superpowers는 "판단력 없는 주니어용"으로 완성 코드까지 박는 게 특징 |
| 4 | **subagent-driven-development** / **executing-plans** — 태스크당 fresh 서브에이전트 + 2단계 리뷰 | `team`, `ultrawork`, `executor`(opus), `autopilot` | OMC의 team/ultrawork가 대응. 단 "태스크당 2단계 리뷰" 패턴은 OMC에 자동 내장 아님 |
| 5 | **test-driven-development** — RED-GREEN-REFACTOR 강제, 테스트 전 코드 삭제 | "tdd" 모드, `test-engineer`, `tdd-guide`(rules) | OMC TDD는 존재하나 "테스트 전 코드 삭제"만큼 엄격하진 않음 |
| 6 | **requesting-code-review** — 계획 대비 리뷰, 심각도별 보고, critical 차단 | `code-reviewer`, `critic`, `security-reviewer`, `/code-review` | 대응 풍부 |
| 7 | **finishing-a-development-branch** — 테스트 확인 후 merge/PR/keep/discard | `git-master`, `/release`, `project-session-manager` | 대응 있음 |

---

## 보조 스킬 대응

| Superpowers 보조 스킬 | OMC 대응 | 갭 여부 |
|---|---|---|
| **systematic-debugging** — 4단계 근본원인 프로세스 | `debugger`, `tracer`, `/trace`, `/deep-dive` | OMC가 오히려 더 풍부 |
| **verification-before-completion** — 완료 주장 전 검증 명령 실행 강제 | `verifier`, `/verify` | 에이전트는 있으나 "하드 게이트" 강제는 약함 |
| **dispatching-parallel-agents** — 독립 2+ 태스크 병렬 | `ultrawork`, `/team` | 대응 |
| **receiving-code-review** — 리뷰 피드백을 맹종 말고 기술적으로 검증 | (직접 대응 없음) | **갭** — OMC에 명시적 스킬 없음 |
| **writing-skills** — 스킬 작성/검증 메타 | `/skillify`, `/learner`, `skill-creator`, `/skill`, `harness` | 대응 풍부 |
| **using-superpowers** — 부트스트랩(스킬 강제) | CLAUDE.md + hooks (magic keyword, ralph "boulder") | **부분 갭** — OMC는 강제력이 약함 |

---

## Superpowers에만 있는 차별 패턴 (OMC 기본엔 약하거나 없음)

1. **강제 자동 발동** — 부트스트랩이 매 응답 전 스킬 체크를 강제. OMC는 대체로 사용자가 불러야 함.
2. **태스크당 2단계 리뷰** — 스펙 준수 → 코드 품질 순서로 매 태스크마다. (OMC는 리뷰어가 따로 있지만 태스크 단위 자동 2패스는 아님)
3. **엄격 TDD** — 테스트보다 먼저 쓴 코드는 삭제.
4. **완성 코드까지 박는 계획** — "판단력 없는 주니어"가 그대로 실행 가능하도록.
5. **완료 주장 하드 게이트** — 검증 명령 출력 확인 전 "됐다" 금지.
6. **receiving-code-review 규율** — 리뷰 수용 시 performative 동의 금지.

이 6개가 "OMC 사용자가 Superpowers에서 빌려올 만한" 후보다. (적용 판단은 02-adoption.md 참고)
