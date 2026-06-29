---
name: design-discovery
description: >
  PLAN→BUILD 사이의 빠진 페이즈 — 확정된 .omc/plans/*.md(+open-questions.md)를 받아
  근거 기반 디자인 방향을 확정하는 디스커버리 단계. 앱 코드는 건드리지 않고 탐색 아티팩트만
  생성한다. 산출물 design.md는 이후 BUILD에서 designer 에이전트 / insane-apply가 소비하는
  "계약"이다. UI 표면이 있는 플랜에만 작동(백엔드/CLI 전용은 skip).
  Manual: /design-discovery <plan-path>.
  Triggers: "기획서 디자인 뽑아줘", "플랜 기반 UI 탐색", "디자인 디스커버리",
  "design discovery", "plan to UI", "기획서로 디자인 방향".
triggers:
  - /design-discovery
  - 기획서 디자인 뽑아줘
  - 플랜 기반 UI 탐색
  - 디자인 디스커버리
  - design discovery from plan
  - plan to design
---

# Design Discovery (PLAN → design.md 계약 → BUILD)

## 무엇인가 / 왜 필요한가
OMC 흐름은 `planner/ralplan`(아키텍처·테스트) → `autopilot/executor/designer`(코드) 로 끊겨 있고,
**화면 디자인 방향을 근거로 확정하는 단계가 없다.** `designer` 에이전트는 방향이 정해졌다 가정하고
즉석에서 미감을 지어낸다(그래서 프롬프트 절반이 "Opus 에디토리얼 디폴트 조심" 경고다).
이 스킬이 그 공백을 채운다: **리서치 + 실측 토큰으로 design.md를 만들어 designer/insane-apply에 넘긴다.**

## 게이팅 (먼저 판정)
- 플랜에 **UI 표면**이 있나? (프레임워크 react/next/vue/svelte + 플랜에 화면/board/dashboard/page/UI 언급)
- 없으면(백엔드·CLI·라이브러리 전용) **즉시 skip**하고 그 사실을 보고. 노이즈 방지.

## 스코프 가드 (절대 규칙)
- **앱 코드를 수정하지 않는다.** 산출물은 `design-pipeline/` 하위 탐색 아티팩트뿐.
- open-question(특히 화면 디자인 범위)이 **사람에 의해 확정된 뒤**에야 insane-apply/designer가 코드에 토큰 주입.
- 플랜의 Non-goal 경계를 존중(예: "대규모 디자인 시스템 도입 = Non-goal"이면 design.md에 a/b 옵션만 제시).

## 입력
- `<plan-path>`: 확정된 메인 플랜(`.omc/plans/*.md`). 같은 폴더의 `*.readable.md`, `open-questions.md`도 읽는다.

## 파이프라인 (4단계 → `<plan-dir>/../design-pipeline/`)
서브폴더 `design-pipeline/{P1-brief,P2-research,P3-reference,P4-mockup}` 생성 후:

### P1 — brief.md (기획서 해석)
플랜 3종에서 추출: 제품 한 줄 · 핵심 화면 · **상태 모델**(각 상태의 시각 요구) · 슬롯/엔티티 필드 ·
**권한별 화면**(viewer/editor 등 affordance 차등) · 상호작용 디테일(충돌/링크/경고) · Non-goal · open-question 중 디자인이 답할 것.

### P2 — research.md (X/Reddit/HN UX 근거)
- 도메인에 맞는 경쟁/유사 제품의 **실제 UX 불만·선호 패턴**을 수집. 병렬 리서치 에이전트 2~3개(facet 분할).
- **소스 우선순위**: Reddit·X·HN. 일반 WebSearch/WebFetch 먼저, **403/차단되면 `insane-search` 스킬**(X syndication·Reddit .rss 우회), 개발 도메인이면 `dev-scan`(HN/Reddit/Dev.to/Lobsters).
- 산출: 인용 URL 붙은 pain points / praised patterns / 도메인 UI 패턴(상태 인코딩·밀도·충돌 UX) / **우리 제품 직접 시사점** 불릿.
- 한계 정직하게 명시(예: "Reddit 직접 fetch 차단 → 2차 인용"). 1차 인용 필요시 insane-search 보강 경로 안내.

### P3 — design.md (레퍼런스 실측 토큰, 계약 산출물)
- **`insane-design` 사전분석 100사 리포트를 먼저 재사용**(재fetch 0). 운영툴이면 linear/cal/notion/retool/supabase/railway/raycast/warp; 신규 URL만 실제 분석.
  경로: `~/.claude/plugins/marketplaces/gptaku-plugins/plugins/insane-design/docs/reports/<slug>/design.md`
- **도메인 오버라이드(핵심 휴리스틱)**: 데이터 밀집/운영 도구(dashboard·fintech·dev tool·healthcare)면 **OMC designer의 에디토리얼 디폴트(크림/세리프/테라코타)를 구체적 운영형 팔레트로 명시 오버라이드**. 막연한 부정("크림 빼") 금지 — hex+폰트로 대체 타겟 지정.
- **상태색은 CVD-safe**(red/green 페어 회피, Okabe-Ito 계열), 색만 인코딩 금지 → 색+패턴+아이콘 삼중(WCAG 1.4.1), 대비 텍스트 4.5:1·비텍스트 3:1.
- frontmatter에 구체적 토큰(colors hex / typography ladder / radius / elevation / spacing) + 본문에 상태 인코딩표·레이아웃·인터랙션·충돌 UX·**open-question a/b 시각안**.

### P4 — mockup (design.md 토큰 → HTML)
- design.md 토큰으로 self-contained `board.html`(또는 화면명) 시공. **insane-build 출력 계약 준수**(결정적 HTML+CSS, AI-slop 가드: 보라 그라데이션·제네릭 폰트 금지).
- 플랜 seed/상태/권한을 실제로 반영(예: viewer/editor 토글, 상태 시각 구분, 충돌 토스트).
- 비대화형으로 직접 시공 가능(designer 철학: execution-oriented, 런타임이 요청할 때만 사용자 확인).

## 피드백 루프
- `open-questions.md`의 UI 관련 질문에 **a/b 시각 옵션으로 회신**(design.md §open-question 절 참조 링크).
- `design-pipeline/README.md`에 단계·산출물·보는 법·다음 단계(insane-apply로 코드 주입) 인덱스.

## 다운스트림 계약
- BUILD 단계에서 **`designer` 에이전트 / `insane-apply`가 이 design.md를 입력**으로 받아 즉석 미감 대신 근거 기반 구현.
- 즉 이 스킬의 출력 = designer의 입력. 둘을 이 design.md로 연결한다.

## 성공 기준
- [ ] 게이팅 판정(UI 플랜만 진행) 명시
- [ ] P1~P4 4개 아티팩트 + README 생성, 앱 코드 무수정
- [ ] design.md에 구체적 hex 토큰 + 도메인 오버라이드 근거 + CVD-safe 상태색
- [ ] P2에 인용 URL, 수집 한계 정직 명시
- [ ] mockup 구조 검증(태그/괄호 밸런스, 화면 로직)
- [ ] open-questions UI 질문에 a/b 회신

## 함정
- 게이팅 생략 → 백엔드 플랜에 디자인 단계가 끼어 노이즈. 반드시 먼저 판정.
- 에디토리얼 디폴트 방치 → 운영 도구가 크림/세리프로 나옴. domain check 필수.
- insane-design 재fetch → 사전분석 리포트 먼저 확인(토큰 낭비 방지).
- 스코프 크립 → open-question 확정 전 코드 주입 금지.
- Reddit 직접 fetch 차단을 무시 → insane-search 폴백 명시.
