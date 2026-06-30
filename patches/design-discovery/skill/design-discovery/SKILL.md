---
name: design-discovery
description: >
  PLAN→BUILD 사이의 빠진 페이즈 — 확정된 .omc/plans/*.md(+open-questions.md)를 받아
  근거 기반 디자인 방향을 확정하는 디스커버리 단계. 앱 코드는 건드리지 않고 탐색 아티팩트만
  생성한다. 타깃 프로젝트에 디자인 가이드가 있으면(brownfield) 구조·인터랙션·느낌만 가져오고
  값(hex/폰트/spacing/컴포넌트)은 기존 시스템에서 와야 하므로 reconciliation으로 매핑하고
  plan delta를 뱉는다. 없으면(greenfield) 레퍼런스 값을 그대로 써서 design.md를 만든다.
  UI 표면이 있는 플랜에만 작동(백엔드/CLI 전용은 skip). Manual: /design-discovery <plan-path>.
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
OMC 흐름은 `planner/ralplan`(아키텍처·테스트) → `autopilot/executor/designer`(코드)로 끊겨 있고,
**화면 디자인 방향을 근거로 확정하는 단계가 없다.** `designer`는 방향이 정해졌다 가정하고 즉석에서
미감을 지어낸다. 이 스킬이 그 공백을 채워 design.md를 만들어 designer/insane-apply에 넘긴다.

## 핵심 원칙 — 의도(intent)와 값(values)을 분리한다
디자인 산출물은 두 층이다. 이 분리가 이 스킬의 중심이다.
- **의도(intent) = 이식 가능**: 화면 구조, 정보 위계, 밀도, **상태 인코딩 전략**(색+패턴+아이콘),
  인터랙션 패턴(인라인 vs 사이드패널, viewer/editor affordance), 충돌 UX, 모션 성격, "느낌".
- **값(values) = 브라운필드에선 이식 불가**: 구체적 hex, 폰트 스택, spacing 스케일, radius/elevation,
  컴포넌트 API·네이밍.

레퍼런스(Linear/Cal/Notion 등)에서는 **항상 의도를 가져온다.** 값은 모드에 따라 출처가 다르다:
- **greenfield(디자인 가이드 없음)**: 값도 레퍼런스에서 가져와 design.md에 박는다 = 새 디자인 언어.
- **brownfield(디자인 가이드 있음)**: 값은 **기존 프로젝트 시스템**에서만 온다. 레퍼런스 값은 버린다.

## 게이팅 (먼저 판정)
1. **UI 표면이 있나?** (프레임워크 react/next/vue/svelte + 플랜에 화면/board/dashboard/page/UI 언급)
   없으면(백엔드·CLI·라이브러리) **즉시 skip**하고 그 사실을 보고.
2. **(P0) 디자인 가이드가 있나? → 모드 결정.** 아래 신호로 brownfield/greenfield 판정:
   - tokens 파일(`tokens.json`/DTCG/Style Dictionary), tailwind `theme.extend` 커스텀,
     `globals.css`의 `:root` 디자인 변수 다수, 컴포넌트 라이브러리/Storybook,
     `design/`·`ui/`·`components/ui` 폴더, Figma Code Connect(`*.figma.tsx`),
     CLAUDE.md/AGENTS.md의 디자인 섹션, 디자인 시스템 의존성(MUI/Chakra/shadcn 등).
   - 하나라도 뚜렷하면 **brownfield**, 전무하면 **greenfield**. 애매하면 brownfield로 안전하게 가고 근거를 적는다.

## 스코프 가드 (절대 규칙)
- **앱 코드를 수정하지 않는다.** 산출물은 `design-pipeline/` 하위 탐색 아티팩트뿐.
- open-question(화면 디자인 범위)이 **사람에 의해 확정된 뒤**에야 insane-apply/designer가 코드에 반영.
- 플랜의 Non-goal 경계 존중.

## 입력
- `<plan-path>`: 확정 메인 플랜. 같은 폴더의 `*.readable.md`, `open-questions.md`도 읽는다.

## 파이프라인 (→ `<plan-dir>/../design-pipeline/`)
서브폴더 `design-pipeline/{P1-brief,P2-research,P3-reference,P4-mockup}` 생성 후:

### P1 — brief.md (기획서 해석)
제품 한 줄 · 핵심 화면 · **상태 모델**(시각 요구) · 엔티티 필드 · **권한별 화면**(affordance 차등) ·
상호작용 디테일(충돌/링크/경고) · Non-goal · 디자인이 답할 open-question.

### P2 — research.md (X/Reddit/HN UX 근거)
도메인 경쟁/유사 제품의 실제 UX 불만·선호 패턴. 병렬 리서치 에이전트 2~3개(facet 분할).
소스 우선순위 Reddit·X·HN; WebSearch/WebFetch 먼저, **403/차단 시 `insane-search`**, 개발 도메인이면 `dev-scan`.
인용 URL + 우리 제품 직접 시사점. 수집 한계 정직 명시.

### P3 — design.md (계약 산출물) — 모드 분기
**공통**: 레퍼런스(insane-design 사전분석 100사 먼저 재사용; 운영툴이면 linear/cal/notion/retool/supabase/railway/raycast/warp)에서 **의도**(구조·위계·상태 인코딩·인터랙션·모션 성격)를 추출.
경로: `~/.claude/plugins/marketplaces/gptaku-plugins/plugins/insane-design/docs/reports/<slug>/design.md`
상태색은 CVD-safe(red/green 페어 회피, Okabe-Ito 계열), 색만 인코딩 금지 → 색+패턴+아이콘 삼중(WCAG 1.4.1), 대비 텍스트 4.5:1·비텍스트 3:1.

- **greenfield**: 레퍼런스 **값**(hex/폰트/spacing/radius)을 design.md frontmatter에 박는다.
  운영/데이터밀집 도메인이면 OMC designer의 에디토리얼 디폴트를 구체 운영형 팔레트로 명시 오버라이드(막연한 부정 금지 — hex+폰트로 대체 타겟).
- **brownfield**: 레퍼런스 값은 **버린다**. 값은 **기존 프로젝트 시스템에서 추출**:
  insane-design을 자사 URL/스토리북에 돌리거나 tokens/tailwind/`:root`를 직접 읽어 `existing-tokens.md`로 정리.
  design.md frontmatter의 값 = **기존 시스템 토큰**. 본문 의도 절은 레퍼런스에서.

### P3.5 — integration.md (brownfield 전용, reconciliation)
**디자인 의도 → 기존 시스템 실현** 매핑 표를 만든다. 이게 "plan에 녹이는 다리"다.
- 표 컬럼: `의도 항목 | 기존 시스템 실현(어느 컴포넌트/토큰) | gap? | 비고`
- **충돌 우선순위(고정)**: **값(hex/폰트/spacing/컴포넌트 API)은 기존 시스템이 이긴다.
  화면 구조·상태 인코딩·인터랙션 패턴·느낌은 design-discovery가 이긴다.** 충돌 시 이 규칙으로 자동 판정.
- **gap 목록**: 기존 시스템이 표현 못 하는 의도 → **최소 추가 제안**(예: "기존 스케일에 hatch 패턴 토큰 1개 추가", "기존 `<Cell>`에 `status` variant 추가"). 새 컴포넌트/팔레트 신설은 최후수단.

### P4 — mockup
design.md 토큰으로 self-contained 목업 시공(insane-build 계약: 결정적 HTML+CSS, AI-slop 가드).
- **greenfield**: design.md(레퍼런스 값) 토큰 사용.
- **brownfield**: **기존 시스템 토큰**으로 시공(레퍼런스 hex 금지). 의도는 살리되 값은 기존 것.
플랜 seed/상태/권한 실제 반영(viewer/editor 토글, 상태 시각 구분, 충돌 토스트).

## 피드백 루프 — plan delta (핵심: 떠다니지 않게)
design.md를 독립 산출물로 두지 말고 **plan에 붙는 작업 항목으로 환원**한다. `design-pipeline/plan-delta.md`:
- **open-question 회신**: UI 관련 질문에 a/b 시각 옵션으로 답.
- **brownfield 구현 태스크**(integration.md에서 도출): "기존 `<X>`에 variant 추가", "토큰 1개 추가" 등 — 기존 플랜 마일스톤에 끼울 수 있는 단위.
- **gap 결정 필요 항목**: 사람이 판단할 충돌/추가는 open-questions로 에스컬레이트.
- `design-pipeline/README.md`에 모드·산출물·보는 법·다음 단계(insane-apply/designer로 반영) 인덱스.

## 다운스트림 계약
BUILD에서 **designer / insane-apply가 이 design.md(+brownfield면 integration.md)를 입력**으로 받아
즉석 미감 대신 근거 기반 구현. brownfield면 **기존 시스템 토큰·컴포넌트만** 쓰고 의도만 design-discovery에서.

## 성공 기준
- [ ] 게이팅(UI 플랜만) + **모드 판정(greenfield/brownfield) 근거** 명시
- [ ] P1~P4 + README 생성, 앱 코드 무수정
- [ ] 의도/값 분리 준수 — brownfield면 design.md 값=기존 시스템(레퍼런스 hex 미사용)
- [ ] brownfield면 integration.md(매핑+gap+충돌 우선순위) + plan-delta.md 생성
- [ ] P2 인용 URL·수집 한계 명시, 상태색 CVD-safe, mockup 구조 검증
- [ ] open-question UI 질문에 a/b 회신

## 함정
- 모드 판정 생략 → brownfield에 레퍼런스 hex를 박아 기존 시스템과 충돌. **P0 감지 필수.**
- 의도/값 혼동 → "느낌만 가져온다"를 어기고 값까지 이식. brownfield면 값은 무조건 기존 시스템.
- reconciliation 생략 → design.md가 떠다니고 plan에 안 닿음. integration.md + plan-delta가 다리.
- 게이팅 생략 → 백엔드 플랜에 디자인 단계 끼어 노이즈.
- insane-design 재fetch → 사전분석 리포트 먼저. 스코프 크립 → open-question 확정 전 코드 반영 금지.
- Reddit 직접 fetch 차단 무시 → insane-search 폴백.
