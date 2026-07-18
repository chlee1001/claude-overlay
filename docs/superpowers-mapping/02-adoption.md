# 적용 판단: Superpowers → 내 OMC 환경

작성일: 2026-06-28 · 인터뷰 기반

## 내 프로필 (인터뷰 요약)

- 주력 작업: 다양하게 섞임 (기능 구현·디버깅·리서치)
- 약점: **계획이 부실함** + **품질/리뷰 게이트 부족**
- 강제력 선호: **중요 게이트만 강제** (부트스트랩 풀강제 X)
- 빌리고 싶은 패턴: 태스크당 2단계 리뷰 / 엄격 TDD / 완료 하드게이트 / 계획 규율
- 추가 요청: 계획이 나오면 **사람 검토용 윤문본**(약어 없고 이해 잘 되는 글 형태)을 따로 생성

이 프로필이면 "풀 파이프라인 강제"는 과하고, **두 개의 게이트(계획 승인 / 완료 검증)** 와 **계획 품질**에 집중하는 게 정답이다.

## 적용 권장 (우선순위)

### P1 — 계획 품질 + 사람용 윤문본 (가장 큰 약점, 가장 큰 효과)

**문제:** OMC `planner`/`ralplan`은 계획을 내지만 (a) 실행이 흔들릴 만큼 두루뭉술하고 (b) 약어·전문용어 범벅이라 사람이 검토하기 불편하다.

**적용:**
1. Superpowers `writing-plans` 규율 이식 — 계획에 **정확한 파일경로 + 검증 스텝**을 의무화. (완성 코드까지는 선택. 다양한 작업엔 과할 수 있어 "검증 가능한 단위"까지만 권장)
2. **신규 스킬: 계획 윤문본 생성기** — 계획이 확정되면 별도 파일로 사람용 산문 버전을 생성. 규칙: 약어 금지(첫 등장 시 풀어쓰기), 전문용어엔 한 줄 설명, AI 글쓰기 트로프 회피(`~/.claude/rules/writing-tropes.md` 준수), "왜 이 순서인지"를 포함. 기계용 plan(`.omc/plans/`)과 사람용 윤문본을 분리 저장.

→ 이게 P1이자 인터뷰에서 직접 요청한 **신규 자산**. 가장 먼저 만들 가치 있음.

### P2 — 태스크당 2단계 리뷰

**적용:** OMC에 `code-reviewer`·`critic`·`verifier`가 이미 있으니, 빠진 건 "매 태스크마다 자동 2패스(스펙 준수 → 코드 품질)"라는 **규율/순서**다. `team`/`ultrawork`로 실행할 때 각 태스크 완료 직후 `code-reviewer`(스펙) → `code-simplifier` 또는 `critic`(품질) 순으로 도는 컨벤션을 CLAUDE.md 또는 전용 스킬에 박는다. CLAUDE.md의 "작성·리뷰 분리" 원칙과 정확히 일치 → 마찰 적음.

### P3 — 완료 하드게이트

**적용:** Stop hook으로 구현. "완료/수정됨/통과" 주장 전 `verifier` 증거(테스트 출력 등)가 없으면 차단/재촉. OMC `verifier`+`/verify`가 이미 있어 hook 한 줄로 게이트화 가능. "중요 게이트만 강제" 선호와 정확히 부합.

### P4 — 엄격 TDD

**적용:** 다양한 작업엔 풀강제가 거추장스러울 수 있으니 **선택적 모드**로. "tdd" 키워드 → test-engineer + RED-GREEN-REFACTOR. Superpowers의 `testing-anti-patterns.md`는 참고자료로 가져올 만함. "테스트 전 코드 삭제"까지는 본인 작업 성격 보고 결정.

## 적용하지 말 것 (또는 보류)

| 항목 | 이유 |
|---|---|
| 부트스트랩 풀강제(using-superpowers식) | 본인이 "중요 게이트만 강제" 선택. 매 응답 강제는 다양한 작업엔 마찰만 큼 |
| 워크트리 필수화 | OMC는 옵션으로 충분. 단일 기능엔 과함 |
| receiving-code-review 스킬 | 갭이긴 하나 우선순위 낮음. 필요 시 나중 |

## 진행 현황

1. ✅ **P1 계획 윤문본** — `plan-readable` 스킬 + `claude-overlay/patches/planner-readable/` (planner 자동 트리거). 검증 완료.
2. ✅ **P2 태스크당 2단계 리뷰** — `claude-overlay/patches/team-review/` (team-verify에서 code-reviewer 필수화, Stage1 스펙→Stage2 품질). 오케스트레이션 경로(team)만 적용 — 사용자 선택. 적용·검증 완료.
3. ✅ **P3 완료 하드게이트** — `claude-overlay/patches/completion-gate/` (Stop hook + settings.json 등록). 6개 시나리오 + 배포본 검증 완료.
4. ✅ **P4 엄격 TDD** — 두 단계 명시 분리로 확정:
   - `"tdd"` → **부드러운** test-first (OMC 기본 내장, keyword-detector 자동 주입)
   - `"엄격 tdd"`/`"strict tdd"`/`/strict-tdd` → **IRON LAW** (신규 `strict-tdd` 스킬). 위임에 의존하지 않고 메인 세션에 규율을 직접 세움.
   - 백업: `claude-overlay/patches/executor-tdd/`가 executor 위임 경로에서도 IRON LAW를 honor. strict-tdd 스킬은 이 패치에 동봉되어 apply.sh로 배포됨.
   적용·검증 완료.

→ 다음 메시지에서 P1부터 실제로 만들지 결정.
