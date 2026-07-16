# Vercel Skills Routing (always-on pointer)

흡수한 vercel 스킬은 lazy 로드다 — 명시 호출해야만 발동한다. 사소하지 않은
React / Next.js / React Native 작업(컴포넌트·훅·페이지·데이터 패칭·리스트/
애니메이션 성능의 작성·리뷰·리팩토링)을 시작하기 전에, 아래 표에서 맞는
스킬을 Skill 툴로 먼저 부르고 그 규칙을 적용한다.

| 작업 | 스킬 |
|---|---|
| React/Next 작성·성능 리팩토링 | `vercel-react-best-practices` |
| 컴포넌트 API·중복 정리·prop 증식 해소 | `vercel-composition-patterns` |
| 라우트/뷰 전환·공유 요소·enter/exit 애니메이션 | `vercel-react-view-transitions` |
| 웹 UI 접근성·디자인 리뷰 | `vercel-web-design-guidelines` |
| React Native/Expo (컴포넌트·리스트 성능·네이티브 모듈·애니메이션) | `vercel-react-native-skills` |

한 줄 수정·rename·설정값 변경 같은 trivial 작업엔 생략한다(YAGNI).

이건 **포인터**일 뿐이다 — 스킬 본문은 호출 시 on-demand 로드되므로 항상-켜짐
컨텍스트는 이 표만큼만 늘어난다(lean 유지). 스폰되는 executor·code-reviewer·
architect·designer에는 각 에이전트 프롬프트에 별도 라우팅 패치가 이미 있고,
이 규칙은 그 패치가 닿지 않는 **메인 루프**(사용자와의 직접 대화)까지 덮는
보편 계층이다. 겹쳐도 무해하며 서로 보강한다.
