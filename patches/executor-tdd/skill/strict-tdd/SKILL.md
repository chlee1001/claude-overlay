---
name: strict-tdd
description: "Strict TDD (the IRON LAW) for the current task. Use ONLY when the user explicitly asks for rigorous/strict TDD — triggers: '엄격 tdd', '엄격한 tdd', 'strict tdd', 'rigorous tdd', 'IRON LAW', or /strict-tdd. Establishes no-production-code-without-a-failing-test discipline directly in this session, superseding the softer default 'tdd' reminder. Do NOT trigger on a bare 'tdd' mention (that stays soft)."
trigger: /strict-tdd
---

# /strict-tdd

이 세션의 작업을 **엄격 TDD(IRON LAW)**로 진행한다. 평소의 부드러운 `tdd` 모드("가능하면 테스트
먼저")와 달리, 여기서는 규율을 **메인 세션에 직접** 세운다 — test-engineer나 executor로 위임됐는지
여부에 의존하지 않는다. 위임 경로가 모호해서 엄격함이 새는 일을 막는 게 목적이다.

## 언제 켜지나

사용자가 **명시적으로** 엄격 TDD를 요청할 때만: "엄격 tdd", "엄격한 tdd", "strict tdd",
"rigorous tdd", "IRON LAW", 또는 `/strict-tdd`. 그냥 "tdd"만 언급한 경우는 켜지지 않는다(그건
부드러운 기본 모드로 둔다).

## THE IRON LAW

**실패하는 테스트 없이는 production 코드를 한 줄도 쓰지 않는다.**

RED → GREEN → REFACTOR, 한 사이클에 하나의 동작만:

1. **RED** — 다음 동작에 대한 테스트를 먼저 쓴다. 실행해서 **실패를 눈으로 확인하고 그 출력을
   보여준다**. (실패 안 하면 테스트가 틀린 것 — 실패하도록 고친다.)
2. **GREEN** — 통과시킬 **최소한의** production 코드만 쓴다. 실행해서 통과를 보여준다. 군더더기 금지.
3. **REFACTOR** — 정리하되 테스트는 계속 초록으로 유지한다.
4. 다음 실패 테스트로 반복.

## 강제 규칙

- **테스트보다 먼저 쓴 코드는 삭제한다.** 멈추고, 그 코드를 지우고, 테스트부터 다시 쓴다. 예외 없음.
- 한 사이클에 여러 기능 금지. 하나의 테스트, 하나의 동작.
- "됐다"고 말하기 전에 RED와 GREEN 출력을 모두 보여준다(가정 금지).
- 부드러운 `tdd` 안내("가능하면 테스트 먼저")가 함께 떴다면 **무시한다 — 이 세션은 IRON LAW가
   지배한다.**

## 위임할 때 (선택)

테스트 전략이 복잡하면 `test-engineer` 에이전트에 위임해도 된다
(`Task(subagent_type="oh-my-claudecode:test-engineer", ...)`). 단 **위임은 선택이지 전제가
아니다** — 위임하지 않아도 위 사이클을 직접 지킨다. 구현을 `executor`로 위임하는 경우, task 설명에
"strict TDD / IRON LAW"를 명시해 executor의 TDD 모드(Executor_TDD_Mode 패치)가 켜지게 한다.

## 범위

- 이 작업/세션에만 적용한다. 사용자가 요청하지 않은 다른 작업에까지 TDD를 강요하지 않는다.
- 기존 코드의 대규모 리팩터를 핑계로 스코프를 넓히지 않는다. IRON LAW는 "지금 만드는 동작"에 대한 것이다.
