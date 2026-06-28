---
name: plan-readable
description: "Generate a human-review companion for a finalized work plan. Use right after a work plan is saved (e.g. to .omc/plans/*.md by planner/ralplan/plan), or when the user wants a jargon-free, no-abbreviation prose version of a plan for human review. Produces <plan>.readable.md next to the machine plan without modifying the original."
trigger: /plan-readable
---

# /plan-readable

기계용 작업 계획(`.omc/plans/{name}.md`)을 **사람이 5분 안에 검토할 수 있는 산문 윤문본**으로 바꾼다.
원본 계획은 executor가 실행하기 위한 것이라 약어와 전문용어가 많고 체크리스트형이다. 이 스킬은 그 옆에 `{name}.readable.md`를 따로 만든다. **원본은 절대 수정하지 않는다.**

## 언제 동작하나

- planner/ralplan/`/plan`이 계획을 `.omc/plans/`에 막 저장한 직후 (자동 트리거 — planner 패치가 호출)
- 사용자가 "이 계획 사람이 보게 윤문해줘", "약어 풀어서 읽기 좋게", "/plan-readable" 요청 시

## 입력

- 인자로 계획 파일 경로가 주어지면 그것을 사용.
- 없으면 `.omc/plans/`에서 가장 최근 수정된 `*.md`를 대상으로 한다 (단 `*.readable.md`, `open-questions.md` 제외).
- `.omc/plans/open-questions.md`가 있으면 함께 읽어 "결정해야 할 것"에 반영한다.

## 작성 규칙 (엄수)

1. **약어 금지 — 첫 등장 시 풀어쓰기.** 예: `ADR` → "아키텍처 결정 기록(Architecture Decision Record, ADR)". 같은 문서 안에서 두 번째부터는 약어만 써도 된다.
2. **전문용어엔 괄호 한 줄 설명.** 예: "멱등성(같은 요청을 여러 번 보내도 결과가 같은 성질)".
3. **산문 중심.** 원본의 TODO 체크리스트를 "무엇을, 왜, 어떤 순서로" 흐르는 글로 다시 쓴다. 단계 구분은 유지하되 기계적 번호 나열 강박은 버린다.
4. **핵심을 맨 위로.** 한 문단 요약 → 사람이 결정할 것 → 위험/되돌리기 어려운 것 순서로 배치한다. 검토자는 위에서부터 읽다 멈춰도 판단할 수 있어야 한다.
5. **왜 이 순서인지 포함.** task flow를 그냥 나열하지 말고 "왜 A를 B보다 먼저 하는지"를 한 줄이라도 붙인다.
6. **AI 글쓰기 트로프 회피.** `~/.claude/rules/writing-tropes.md`를 따른다. "다양한/~적/활용/중요합니다 인플레/이를 통해/~라는 점에서 의미가 있습니다/지금까지 ~알아보았습니다" 같은 빈 표현을 쓰지 않는다. 볼드 키워드로 모든 불릿을 시작하지 않는다.
7. **언어는 한국어.** 원본 계획이 영어라도 사람 검토용은 한국어로 쓴다 (사용자 기본 언어).
8. **짧게.** 원본보다 길어지면 안 된다. 검토 5분이 목표다.
9. **원본 불변.** `{name}.md`는 읽기만 한다. 출력은 `{name}.readable.md`에만 쓴다.

## 출력 형식

`.omc/plans/{name}.readable.md`에 아래 골격으로 쓴다:

```markdown
# {계획 이름} — 사람용 검토본

> 원본(실행용): `.omc/plans/{name}.md` · 이 파일은 검토용 요약본이라 실행에 쓰지 않는다.

## 한 문단 요약
이 작업이 무엇을 하고, 끝나면 무엇이 달라지는지 한 문단으로.

## 지금 결정해야 할 것
- 사용자가 골라야 하는 선택지나 열린 질문. (open-questions.md 반영)
- 없으면 "현재 열린 결정 없음"이라고 쓴다.

## 되돌리기 어렵거나 위험한 부분
- 데이터 마이그레이션, 외부 전송, 삭제 등 신중해야 할 지점. 없으면 생략 가능.

## 무엇을, 어떤 순서로
원본의 단계들을 산문으로. 각 단계가 왜 그 자리에 오는지 한 줄씩.

## 완료를 어떻게 확인하나
원본의 acceptance criteria를 사람 말로 풀어서.
```

## 절차

1. 대상 계획 파일을 읽는다 (인자 우선, 없으면 최신).
2. `open-questions.md`가 있으면 읽는다.
3. 위 규칙대로 윤문본을 작성해 `{name}.readable.md`에 Write.
4. 윤문본은 한글 문서이므로 `korean-writing` 규칙에 따라 humanize 패스를 한 번 적용한다
   (`/humanize {name}.readable.md`, 또는 호출이 어려우면 자체검증 6항 직접 점검). 의미는 그대로 두고 표현만 다듬는다.
5. 사용자에게 생성 경로를 한 줄로 알린다: "사람용 검토본: `.omc/plans/{name}.readable.md`".

## 하지 말 것

- 원본 계획 파일 수정 (절대).
- 새 작업 항목 추가/삭제 — 윤문은 표현만 바꾸지 내용을 바꾸지 않는다.
- 실행 시작 — 이 스킬은 글만 쓴다.
