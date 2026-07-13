# claude-overlay

oh-my-claudecode 플러그인 파일에 직접 넣은 수정을, 플러그인이 업데이트돼도 살려두는 도구다.

English: [README.md](README.md)

## 무엇을 푸는가

oh-my-claudecode는 버전마다 별도 폴더에 설치된다
(`~/.claude/plugins/cache/omc/oh-my-claudecode/<버전>/`). 이 안의 파일을 직접 고치면,
다음 업데이트가 새 버전 폴더를 만들면서 수정이 사라진다.

claude-overlay는 각 수정을 `(원본, 수정본)` 한 쌍으로 저장해 두었다가, 지금 활성화된 버전 위에
다시 얹는다. 이때 3방향 병합(`git merge-file`)을 쓴다. 3방향 병합이라서 플러그인 제작자가
같은 파일에 넣은 변경은 그대로 보존되고, 진짜 충돌이 나면 말없이 덮어쓰는 대신 알려준다.

## 빠른 시작

`claude-overlay` 폴더 안에서 실행한다:

```bash
./apply.sh                              # 모의 실행: 보고만 하고 아무것도 안 씀
./apply.sh --write                      # 깨끗하게 병합되는 것만 적용
./apply.sh --write --update-baseline    # 적용하고, upstream이 바뀐 경우 원본 기준을 앞으로 옮김

./reabsorb.sh                           # 흡수한 외부 원본의 드리프트 감지 (사이드 플로우, 읽기전용)
./tests/run.sh                          # reabsorb 테스트 하네스 (격리)
```

## 동작 방식

패치 하나는 `patches/` 아래 자기 폴더를 가지며, 네 파일로 기술된다:

| 파일 | 뜻 |
|------|----|
| `target` | 플러그인 루트 기준 파일 경로. 예: `agents/git-master.md` |
| `marker` | 그 파일에 패치가 이미 들어 있는지 증명하는 고유 문자열 |
| `baseline.md` | 처음 패치를 만들 때 기준이 된 손대지 않은 플러그인 원본 |
| `patched.md` | `baseline.md`에 내 수정을 더한 것 |

3방향 병합은 현재 플러그인 파일을 새 버전으로, `baseline.md`를 공통 조상으로,
`patched.md`를 내 갈래로 본다:

```
git merge-file -p --diff3 <현재 플러그인 파일> baseline.md patched.md
```

- 제작자가 내가 고친 줄을 건드리지 않았으면 깨끗하게 병합된다.
- 같은 줄을 건드렸으면 충돌로 보고한다. 이 경우는 사람 판단이 필요하므로, 스크립트는
  충돌 결과를 대상 파일 옆에 적어두고 절대 그대로 적용하지 않는다.

### 두 개의 플러그인 루트

`apply.sh`는 모든 패치를 두 곳에 적용한다. 그래서 패치마다 결과 줄이 두 개씩 나온다:

1. **활성 버전 폴더** — 어시스턴트가 실행 시점에 실제로 읽는 파일.
2. **마켓플레이스 소스 클론**(`~/.claude/plugins/marketplaces/omc/`) — 플러그인을 빌드하고
   재설치할 때 쓰는 원본.

두 곳에 다 박아두면 패치가 더 오래 버틴다. 활성 폴더는 지금 쓰이고, 소스 클론은 이후 재설치의
바탕이 되기 때문이다. 일부 대상은 활성 폴더에만 생기는 빌드 산출물이다(예: `skill-bodies/...`).
그런 파일은 소스 클론 쪽에 아예 없으므로 그 줄이 `SKIP`으로 나온다. 실패가 아니라 정상이다.

### 직접 소유한 스킬 (병합하지 않음)

패치 폴더는 직접 만든 스킬을 함께 담을 수 있다. 위치는 `patches/<패치>/skill/<스킬이름>/`.
이건 플러그인 파일이 아니라서 병합하지 않고, `apply.sh`가 그대로 스킬 폴더로 복사한다
(`${OMC_SKILLS_DIR:-$HOME/.claude/skills}/<스킬이름>/`). 동봉한 사본이 원본이다. 거기서
고치고 `./apply.sh --write`를 다시 돌리면 배포된다. 사본이 패치와 함께 있으니, 실수로 스킬을
지워도 파일 패치를 다시 적용하는 바로 그 실행이 스킬도 복구한다.

### 직접 소유한 규칙 (병합하지 않음)

패치 폴더는 `~/.claude/rules/`에 둘 규칙 문서도 담을 수 있다. 위치는
`patches/<패치>/rules/<파일>`. 소유 스킬과 같은 방식으로, `apply.sh`가 규칙 폴더
(`${OMC_RULES_DIR:-$HOME/.claude/rules}/`)로 그대로 복사한다. 동봉한 사본이 원본이니, 거기서
고치고 `./apply.sh --write`를 다시 돌려 배포한다. 실수로 지운 규칙도 같은 실행이 복구한다.

패치 폴더는 자산만 담을 수도 있다(`target`/`baseline`/`patched` 없이). 그 경우 파일 패치 단계는
건너뛰고 스킬과 규칙만 배포된다.

### 출력 읽는 법

파일별: `OK`(이미 패치됨) · `CLEAN` / `APPLY`(병합됨) · `CONFLICT` ·
`SKIP`(대상 파일 없음) · `ERROR`.
스킬·규칙별: `OK`(최신) · `INSTALL`(없어서 새로 설치) · `UPDATE`(달라서 갱신).
종료 코드: `0` 정상 · `2` 충돌 하나 이상 · `3` 병합 오류.

원본 기준(baseline)은 `--update-baseline`을 줄 때만, 그리고 실제로 upstream이 바뀐 패치에
대해서만 앞으로 옮겨진다. 그냥 `--write`는 병합 결과를 실제 파일엔 적용하지만 `baseline.md`와
`patched.md`는 원래 버전에 그대로 둔다. 그럴 때는 실행 끝에 바뀐 패치 이름을 담은 `REMINDER:`
줄이 찍힌다. `--update-baseline`으로 다시 돌려, 다음 업데이트가 현재 버전과 병합되게 해두자.
원본 기준이 오래된 채로 남으면 시간이 갈수록 쓸데없는 충돌을 부른다.

## 폴더 구조

```
claude-overlay/
  apply.sh                       # 3방향 재적용 스크립트
  reabsorb.sh                    # 흡수한 외부 원본 드리프트 감지 (사이드 플로우)
  .reabsorb_core.py              # reabsorb detect/triage/bump/validate 코어 (순수 stdlib)
  verdict.schema.json            # architect triage verdict 계약 (고무도장 방지)
  sources/<id>/provenance.json   # 무엇을·어디서@버전·어느 자산이 무엇에 의존하는지 기록
  tests/run.sh                   # reabsorb 테스트 하네스 (env override fixture)
  docs/reabsorb-design.md        # 재흡수 플로우 설계 (결정 8개 락인)
  SKILL.md                       # 어시스턴트용 사용 문서
  README.md / README.ko.md
  patches/
    git-master/                  # 대상: agents/git-master.md
      target / marker / baseline.md / patched.md
    planner-readable/            # 대상: agents/planner.md
      target / marker / baseline.md / patched.md
      skill/plan-readable/       # 소유 스킬, ~/.claude/skills/ 로 복사됨
    team-review/                 # 대상: skill-bodies/team/SKILL.md
      target / marker / baseline.md / patched.md
    executor-tdd/                # 대상: agents/executor.md
      target / marker / baseline.md / patched.md
      skill/strict-tdd/          # 소유 스킬, ~/.claude/skills/ 로 복사됨
    korean-writing/              # 자산만 (파일 패치 없음)
      rules/                     # 소유 규칙 문서, ~/.claude/rules/ 로 복사됨
        korean-writing.md
        writing-tropes.md
    design-discovery/            # 자산만 (파일 패치 없음)
      skill/design-discovery/    # 소유 스킬, ~/.claude/skills/ 로 복사됨
      deploy.sh                  # 플랜 저장 제안 PostToolUse 훅을 settings.json에 멱등 등록
    ai-slop-cleaner/             # 대상: skill-bodies/ai-slop-cleaner/SKILL.md
      target / marker / baseline.md / patched.md
    completion-gate/             # 자산만 (파일 패치 없음)
      hooks/                     # 소유 훅, ~/.claude/hooks/ 로 복사됨
        omc-completion-gate.mjs
      deploy.sh                  # Stop 훅을 settings.json에 멱등 등록
    code-minimalism/             # 자산만 (파일 패치 없음)
      rules/                     # 소유 규칙 문서, ~/.claude/rules/ 로 복사됨
        code-minimalism.md
    executor-minimalism/         # 대상: agents/executor.md (executor-tdd와 스택)
      target / marker / baseline.md / patched.md / NOTES.md
    reabsorb/                    # 자산만 (파일 패치 없음)
      skill/reabsorb/            # 소유 /reabsorb 스킬, ~/.claude/skills/ 로 복사됨
```

## 재흡수 (`reabsorb.sh`) — 흡수한 외부 원본을 위한 사이드 플로우

`apply.sh`는 **OMC 자체 파일**에 건 우리 패치를 OMC 업데이트에도 살려둔다. 그런데 우리는 **다른** 프로젝트에서도
흡수했다: `design-discovery`는 런타임에 `insane-design`의 리포트 형식을 소비하고, `completion-gate`는
**Superpowers**의 규율을 적응했고, `korean-writing`은 **humanize-korean**의 분류체계에서 파생됐다. *그* 원본들이
움직이면 3방향 머지가 못 돕는다 — 우리 자산은 원본의 줄-포크가 아니라 인터페이스나 개념의 *파생물*이라서.
`reabsorb.sh`가 그 공백을 메우며, 외부 원본의 자체 주기(OMC 업데이트와 독립)로 돈다.

각 흡수 원본은 `sources/<id>/provenance.json`에 기록한다: 타입(`installed-plugin`/`git-repo`/`concept-source`),
흡수 당시 버전/커밋 + **계약**, 그리고 어느 소유 자산이 무엇에 의존하는지(`depends_on`/`break_if`).
새 흡수 등록 = `provenance.json` 하나 추가(필수 6필드) — 중앙 파일 편집 없음.

흐름(`/reabsorb` 스킬이 판단, `reabsorb.sh`가 기계):

1. **`./reabsorb.sh`** — 전 소스 상태표(dry-run). **2축 감지**: 플러그인 버전 *그리고* 계약(리포트
   `schema_version` 또는 파일 해시). 버전만 보면 실제 드리프트를 놓친다 — 예: `insane-design` 스키마
   `3.1→3.2`인데 플러그인은 `0.5.3` 그대로. 상태 어휘는 `apply.sh`와 동형: `CURRENT`/`DRIFTED`/`UNKNOWN`/`ERROR`,
   exit `0/5/4/3`(`2`=breaking).
2. **`./reabsorb.sh --triage <id>`** — 분석 패킷 조립(dry-run, 무쓰기).
3. **OMC `architect`(read-only)** 가 드리프트 소스마다 triage → `irrelevant`/`compatible`(구체 `proposed_delta` 포함)/`breaking`.
4. **`./reabsorb.sh --validate-verdict <파일>`** — `verdict.schema.json` 스키마 검증으로 고무도장 방지 강제:
   `compatible`은 구체 델타 없이 무효, non-`irrelevant` 저신뢰는 에스컬레이트 필수.
5. **사람 게이트 → 재흡수**: `irrelevant`→`./reabsorb.sh --bump <id>`; `compatible`→사람이 **번들** 자산을
   델타대로 편집→`./apply.sh --write` 재배포→`--bump`; `breaking`→에스컬레이트, 자동편집 없음. 롤백=overlay git 이력.

설계부터 테스트 가능: `reabsorb.sh`는 `OMC_SOURCES_DIR`/`OMC_INSTALLED_PLUGINS`/`OMC_MARKETPLACES_DIR`를 받아
`tests/run.sh`가 fixture를 가리키고 실제 `~/.claude`를 절대 안 건드린다. 전체 설계: `docs/reabsorb-design.md`.

## 현재 패치들

### git-master

전역 `git-master` 에이전트가, 저장소에 자체 규칙(`.claude/skills/git/`)이 있으면 그것을 따르게
한다(커밋, 풀 리퀘스트 생성, 풀 리퀘스트 요약). 규칙이 없으면 원래 기본 동작으로 돌아간다.
안전장치는 늘 유지된다 — 원자적 커밋, 강제 푸시 대신 `--force-with-lease`, 메인 브랜치 리베이스
금지, `git log`로 이력 확인.

### planner-readable

전역 `planner` 에이전트가 기계용 계획을 `.omc/plans/<이름>.md`에 저장한 직후, 사람 검토용
사본도 `.omc/plans/<이름>.readable.md`에 만들게 한다. 사본은 약어를 풀어 쓴 한국어 산문이다.
기계용 계획은 절대 바꾸지 않는다. 사본은 동봉한 `plan-readable` 스킬이 작성한다(스킬을 부를 수
없을 때를 위한 대체 동작도 있다).

### team-review

`team` 스킬의 검증 단계에서 `code-reviewer`를 필수로 만든다. 예전에는 선택이었고 큰 변경에만
돌았다. 이제 검증 패스마다 `code-reviewer`가 돌며, 명세 충족을 먼저 보고 코드 품질을 그다음에
본다. 그 패스에서 바뀐 파일로 범위를 좁혀 비용을 아낀다. 대상 파일(`skill-bodies/team/SKILL.md`)은
활성 버전 폴더에만 있는 빌드 산출물이라, 소스 클론 줄은 `SKIP`으로 나온다.

### executor-tdd

작업이 요구할 때 `executor` 에이전트가 엄격한 테스트 주도 개발(Test-Driven Development)을
지키게 한다. oh-my-claudecode의 `tdd` 키워드는 엄격 규칙(실패하는 테스트 없이 production 코드
금지, 테스트보다 먼저 쓴 코드는 삭제)을 메인 세션에 주입하지만, 그 문구가 `executor` 서브에이전트
까지는 닿지 않는다. 그래서 위임된 구현이 규칙을 슬쩍 건너뛸 수 있다. 이 패치는, 작업이 테스트 주도
개발을 가리키면 `executor`가 "실패 테스트 먼저" 사이클을 따르게(또는 테스트 작업을
`test-engineer`에 넘기게) 하고, 그렇지 않으면 무시하게 만든다.

이건 2단계 설계와 짝을 이룬다. 그냥 `tdd` 키워드는 부드럽게 둔다(기본 제공되는 테스트 먼저
권고). 반면 `엄격 tdd` / `strict tdd` / `/strict-tdd`는 동봉한 `strict-tdd` 스킬을 부른다.
이 스킬은 위임에 기대지 않고 엄격 규칙을 메인 세션에 직접 세운다. 이 패치는 위임 경로를 위한
안전망이다.

### korean-writing

자산만 담는다 — 플러그인 파일은 건드리지 않는다. 규칙 문서 두 개를 `~/.claude/rules/`로
배포한다: `writing-tropes.md`(피해야 할 한국어 AI 글쓰기 트로프 — 예방 규칙)와
`korean-writing.md`(한글 문서는 그 트로프를 따르고, 그다음 윤문·의미보존을 위해 humanize 패스를
거친다는 컨벤션). 여기 두면 나머지 자산과 같은 `apply.sh` 실행으로 함께 복구된다.

### design-discovery

자산만 담는다 — 플러그인 파일은 건드리지 않는다. 비어 있던 **PLAN→BUILD** 단계를 채운다. OMC
플랜(`ralplan`/`planner`)은 아키텍처까지만 정하고 UI 방향은 open-questions로 미루며, `designer`
에이전트는 빌드 시점에 미감을 즉흥으로 짠다. 이 패치는 `design-discovery` 스킬을 배포한다 — 확정된
`.omc/plans/*.md`를 받아 **앱 코드를 건드리지 않고** 근거 기반 디자인 아티팩트(brief, 인용 붙은
X/Reddit/HN UX 리서치, `insane-design` 토큰 기반 `design.md`, HTML 목업)를 만든다. 이 `design.md`는
이후 `designer`/`insane-apply`가 소비하는 "계약"이다. **의도**(구조·인터랙션·상태 인코딩·느낌 — 항상
이식 가능)와 **값**(hex/폰트/spacing/컴포넌트)을 분리하고 디자인 가이드 유무로 분기한다: *greenfield*
는 레퍼런스 값을 `design.md`에 박고, *brownfield*(기존 토큰·tailwind theme·컴포넌트 라이브러리)는 의도만
가져와 프로젝트 **자체** 토큰/컴포넌트에 매핑한다(`integration.md` 매핑+gap, 고정 우선순위 — 값은 기존
시스템이, 구조/인터랙션은 design-discovery가 이김). 그 뒤 `plan-delta.md`에 구체 태스크를 뽑아 디자인이
구현계획에 **떠다니지 않고 녹아들게** 한다. 동봉한 `deploy.sh`는 `PostToolUse`(Write|Edit)
훅을 `~/.claude/settings.json`에 멱등 등록한다: 확정 플랜이 저장되면(`*.readable.md`/`open-questions.md`
제외) `/design-discovery <plan-path>`를 고려하라는 한 줄을 주입하고, 그 외 모든 쓰기엔 침묵한다. UI
표면이 있는 플랜에만 작동하고 백엔드/CLI 전용은 건너뛴다.

### completion-gate

자산만 담는다 — 플러그인 파일은 건드리지 않는다. **완료 하드 게이트**다. 같은 턴에 검증 증거
(테스트/빌드/린트 명령, verifier/qa 서브에이전트, `PASS`/`0 failed` 같은 테스트 출력) 없이
"done/fixed/완료/통과" 주장을 하면 Stop 훅이 막고, 끝내기 전에 검증 한 번을 하라고 권한다. stop당
최대 한 번 발동하고, ralph/ultrawork/autopilot/team 루프에서는 빠지며, `OMC_SKIP_COMPLETION_GATE=1`로
끈다. 훅(`hooks/omc-completion-gate.mjs`)과 이를 `~/.claude/settings.json`에 멱등 등록하는 `deploy.sh`를
담는다. Superpowers의 "완료 전 검증" 규율에서 적응했다 — OMC엔 메인 루프 게이트가 없었다.

같은 훅은 **비차단 코멘트 위생 권고**(ai-slop-cleaner Pass 5의 "코드 작업 끝" 넛지)도 실는다. 완료가
검증까지 된 뒤, 그 턴의 파일 편집에서 계획 유출 주석(미래 독자에게 의미 없는 `P2 fallback`/`V1-V4`/
`Phase 0` 같은 계획 단계 ID)을 훑고, 있으면 파일명을 짚는 한 줄 `systemMessage`를 띄운다. 절대 막지
않고(권고≠게이트), 언어에 무관한 고정밀 계획 ID 패턴에만 발동하며(한글 존재 자체엔 반응 안 함),
`OMC_SKIP_COMMENT_HYGIENE=1`로 끈다.

### ai-slop-cleaner

대상: `skill-bodies/ai-slop-cleaner/SKILL.md`(3방향 머지 패치). OMC 슬롭 분류에 7번째 범주 —
**코멘트/주석 슬롭** — 과 최종 코드를 대상으로 마지막에 도는 **Pass 5: 코멘트 위생**을 더한다. 세
하위 종류: 부자연스러운 AI-한국어 주석(prose 전용 humanize-korean 오케스트레이터가 아니라
`writing-tropes.md` 기준으로 *간결하게* 고침), 계획 유출(`Phase 0`/`G1`/`V1-V4`가 계획 문서에서 떨어져
나온 것), 암호 같은 약어. 함께 넣은 **코멘트 위생 체크리스트**가 안전장치를 담는다: 주석은 비실행이라
재작성이 구조상 동작 안전하지만 load-bearing 항목(`eslint-disable`, `@ts-ignore`, `noqa`, shebang,
typegen docstring, doctest…)은 예외로 손대지 않는다. 삭제 우선이 원칙이고, 의도를 코드에서 확인 못 하면
지어내지 말고 지운다. 계획 유출은 정규식 *후보* + 저장소 grep 해소 확인이지 정규식 자동삭제가 아니다.

### code-minimalism

자산만 담는다 — 플러그인 파일은 건드리지 않는다. **ponytail**의 "lazy senior dev" 규율
(`DietrichGebert/ponytail`, `AGENTS.md`)을 소유 규칙 하나(`code-minimalism.md`)로 흡수해
`~/.claude/rules/`에 배포한다. OMC 기본 규칙 `karpathy-guidelines.md`에 없는 네 가지만 뽑았다:
7단 의사결정 사다리(YAGNI → 재사용 → stdlib → native → 의존성 → 한 줄 → 최소 코드), **안전 플로어**
(trust boundary 입력 검증·데이터 손실 방지·보안·접근성·하드웨어 캘리브레이션과 명시 요청은 절대 안
깎는다), 증상 아닌 근본원인 버그픽스(모든 caller를 grep해 공용 함수를 한 번 고침), `simplification:`
주석 규약(의도적 단축은 상한과 업그레이드 경로를 주석에 밝힘). **코드 작업 한정**이고 마인드셋은
`karpathy-guidelines.md`를 참조해 두 규칙이 중복 없이 합쳐진다. 플러그인의 intensity 레벨·statusline·
mode-tracker·MCP는 개인 오버레이엔 과잉이라 흡수하지 않았다. 드리프트 추적은 `sources/ponytail/`
(git-repo, `AGENTS.md`에 `git_blob` probe)에 등록해, 업스트림 사다리나 안전 플로어가 바뀌면
`reabsorb.sh`가 잡는다. 파생 개념이라 `ponytail`이 아니라 `code-minimalism`으로 이름 붙였다 —
`korean-writing` ← humanize-korean 선례와 같다. OMC가 세션 시작 시 읽으므로 새 세션부터 활성화된다.

### executor-minimalism

`agents/executor.md`를 패치해서 위 code-minimalism과 같은 ponytail 규율을 `<Code_Minimalism>`
블록으로 executor 에이전트의 역할 정의에 직접 박는다. 규칙 문서(위 code-minimalism)는 CLAUDE.md
규칙 블록을 타고 **메인 세션에만** 닿을 뿐, 서브에이전트 자신의 시스템 프롬프트에는 들어가지 않는다.
ralph·team·ultrawork 루프가 길어져 컨텍스트가 compaction되면 아예 사라질 수도 있다. 에이전트 정의에
박아두면 규율이 구조가 된다 — executor를 스폰할 때마다 7단 사다리와 안전 플로어가 그 자신의
프롬프트에 실려 서브에이전트 경계도 루프 중간 compaction도 넘긴다. 오케스트레이터가 아니라
서브에이전트 안에 살아야 하는 규율이라는 점에서 executor-tdd의 `<Executor_TDD_Mode>` 블록과 같은
논리, 같은 패턴이다.

executor-tdd와 **같은 대상 파일**에 겹쳐 얹는다. 그래서 `apply.sh`는 이 패치를 늘 "upstream drifted,
merged cleanly"로 보고한다 — 정상이다. 라이브 대상에는 tdd 블록이 항상 들어 있기 때문이다. 여기서
**`--update-baseline`은 절대 하지 마라.** 하면 손대지 않은 `baseline.md`에 tdd 내용이 섞여 오염된다
(`patches/executor-minimalism/NOTES.md` 참고). `sources/ponytail/provenance.json`에 두 번째 dependent로
등록해 뒀다. ponytail이 드리프트하면 이 블록도 함께 걸린다. 에이전트 정의는 세션 시작 때 로드되므로
새 세션부터 활성화된다.

## 원본 기준 다시 만들기 (잃어버렸을 때)

`baseline.md`는 그저 패치를 만들 때 기준이 된 손대지 않은 플러그인 파일이다. 다시 만들려면,
현재 `patched.md`에서 내 수정을 하나씩 되돌려 원래 플러그인 파일 상태로 만든 뒤, 그것이
원본과 같은지 확인한다(예: `md5` 체크섬 비교). `baseline.md`가 다시 정확해지면 `(원본, 수정본)`
쌍이 일관되어 병합이 정상으로 돌아간다.

## 메모

- 활성 버전(`~/.claude/plugins/installed_plugins.json`에서 읽음)과 마켓플레이스 소스 클론을
  대상으로 한다.
- `OMC_PATCH_ROOTS=<폴더1>:<폴더2>`로 루트 탐색을 덮어쓸 수 있다(테스트용).
- `OMC_SKILLS_DIR=<폴더>`로 소유 스킬 배포 위치를 덮어쓸 수 있다(테스트용).
- 자동이 아니다. oh-my-claudecode를 업데이트할 때마다 다시 돌려야 한다. 원하면 세션 시작 훅에
  걸어 자동으로 돌게 만들 수도 있다.
