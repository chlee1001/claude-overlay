# Re-absorption Flow — 설계 문서 (DESIGN, 구현 전 게이트)

> 상태: **설계만**. 구현은 아래 §10 결정 필요 항목이 확정된 뒤 진행.
> 출처: OMC `architect`(deep analysis) 깊은 설계 + 합의 결정.
> 라이브 증거: insane-design 디스크상 `schema_version: 3.2`인데 design-discovery는 `3.1` 기준으로 흡수,
> **플러그인 버전 `0.5.3`은 그대로** — 버전만 보면 못 잡는 contract drift가 이미 존재.

---

## 1. 문제 — claude-overlay 모델의 빠진 반쪽

claude-overlay는 "OMC가 업데이트되면 우리 패치를 다시 적용"만 한다(3-way 머지). 그런데 우리가 흡수한 건 출처 결합도가 세 종류고, 그중 둘엔 재흡수 장치가 없다.

| 종류 | 예 | 현재 |
|---|---|---|
| **A. OMC 파일 패치** | git-master, planner-readable, executor-tdd, team-review | ✅ 3-way 머지 |
| **B. 개념을 우리 코드로 소유** | completion-gate←Superpowers, korean-writing←humanize-korean | ❌ 없음 |
| **C. 런타임 의존(외부 플러그인 참조)** | design-discovery → insane-design / insane-search / insane-build, dev-scan | ❌ 없음 |

이 문서가 설계하는 것 = **B·C의 재흡수 플로우.** 스코프는 흡수물 전부이며, 흡수물은 계속 늘어나므로 registry는 **추가형·자가등록**이어야 한다.

### 왜 3-way 머지가 B/C엔 안 통하나
`git merge-file <live> baseline.md patched.md`는 **같은 파일의 세 버전**(공통조상/우리편집/새업스트림)을 줄 단위로 화해시킨다. B/C는 이 전제가 없다 — 우리 자산은 원본의 *줄-포크*가 아니라 **인터페이스(계약)나 개념의 파생물**이다. `design-discovery/SKILL.md`는 insane-design 코드의 줄을 편집한 게 아니라 그 리포트 경로·frontmatter를 *참조*할 뿐이고, completion-gate는 Superpowers 소스의 복사가 아니라 *규율의 적응*이다. 줄 대응이 없으니 머지는 무의미하다.

**항(項)별 대체** — 머지 엔진을 의미 화해로 바꾼다:

| 3-way 머지 (A) | 재흡수 (B/C) |
|---|---|
| `baseline.md` (텍스트 공통조상) | **provenance 기록**: 흡수 당시 버전 + 계약 스냅샷 + 의존 기술 |
| `patched.md` (우리 편집본) | 자산 자체 (SKILL.md / hook / rule) |
| `<live>` 새 업스트림 파일 | 업스트림의 새 버전 + 계약 표면 |
| `git merge-file` (기계적 화해) | **OMC architect triage** (의미적 화해, read-only) |
| `CONFLICT` (업스트림이 우리 줄 건드림) | **BREAKING** (우리 `break_if`에 걸리는 변경) |
| `CLEAN` drift | **COMPATIBLE**(의존 변경, 한정 델타) / **IRRELEVANT**(의존 무변) |
| `--update-baseline` | `--bump` (재흡수 후 기록 버전 전진) |

배포는 그대로 `apply.sh`(owned-asset 미러 + `deploy.sh`)를 **재사용** — 새 배포 경로 없음.

---

## 2. 메커니즘 개요

```
provenance(출처·버전·의존 기록)
  → drift 감지(2축: 버전 + 계약 해시/스키마)
    → DRIFTED면 OMC architect triage(무관/호환/breaking + 근거 + 델타)
      → 사람 게이트
        → 재흡수: 번들 자산 편집 → apply.sh --write 재배포 → reabsorb --bump
```
스크립트가 기계(감지·패킷 조립·bump)를, 스킬이 판단(architect 호출·델타 적용)을 맡는다 — `apply.sh` vs `SKILL.md`와 동일 분업.

---

## 3. Provenance 데이터 모델 (Deliverable 1)

### 위치
**`sources/<source-id>/provenance.json`** — 출처당 한 폴더. `patches/<name>/`(각자 `baseline-version`) 관례를 그대로 따른다. 중앙 파일이 아니라 출처별 파일이라 **자가등록 = `mkdir` + JSON 1개**, 중앙 파일 머지 충돌도 없다. 감지는 `apply.sh`가 `patches/*/`를 훑듯 `sources/*`를 훑는다.

**출처-키(patch-키 아님)인 이유**: 한 출처가 여러 자산을 먹일 수 있고(humanize-korean → writing-tropes.md + korean-writing.md), 한 자산이 여러 출처에 의존할 수 있다. 자연 키는 출처, `dependents[]`로 역참조.

### 스키마 (insane-design 예시)
```jsonc
{
  "schema": 1,                                   // 우리 provenance 포맷 버전
  "id": "insane-design",                         // 폴더명 == 안정 id
  "display_name": "insane-design (gptaku-plugins)",
  "source_type": "installed-plugin",             // installed-plugin | git-repo | concept-source
  "absorbed_at": "2026-06-15",

  "locator": {                                   // drift 감지가 출처를 찾는 법
    "plugin_key": "insane-design@gptaku-plugins",
    "manifest_path": "~/.claude/plugins/marketplaces/gptaku-plugins/plugins/insane-design/.claude-plugin/plugin.json"
  },

  "absorbed_version": {                          // 다축: 코드 버전 AND 계약
    "plugin_version": "0.5.3",
    "contract": {
      "report_path_glob": ".../docs/reports/<slug>/design.md",
      "frontmatter_schema_version": "3.1",
      "frontmatter_keys": ["schema_version", "medium"],
      "token_block_hash": "sha256:<리포트 frontmatter 토큰블록 정규화 해시>"
    }
  },

  "dependents": [                                // 누가·무엇에 의존하나
    {
      "asset": "patches/design-discovery/skill/design-discovery/SKILL.md",
      "depends_on": [
        "리포트 파일 경로 layout reports/<slug>/design.md",
        "design.md frontmatter schema_version 토큰 계약",
        "P3 greenfield 값-주입에 쓰는 frontmatter 토큰 키"
      ],
      "break_if": [
        "리포트 경로/slug layout 이동",
        "토큰을 재구성하는 schema_version MAJOR bump",
        "토큰 키 rename/삭제"
      ]
    }
  ],

  "drift_probe": {                               // 감지기가 읽을 신호
    "kind": "manifest_version + artifact_schema",
    "schema_probe": { "file_glob": "docs/reports/*/design.md", "field": "schema_version" },
    "token_hash_probe": { "file_glob": "docs/reports/*/design.md", "block": "frontmatter" }
  },

  "last_triage": { "verdict": "compatible", "at": "2026-06-15", "by": "architect", "confidence": "high" }
}
```

**자가등록 필수 6필드**: `id`, `source_type`, `locator`, `absorbed_version`, `dependents`, `drift_probe`. 선택: `display_name`, `last_triage`. → 새 흡수 = 이 6개 채운 `sources/<id>/provenance.json` 한 개 추가.

### 타입 범위를 보여주는 두 인스턴스
**completion-gate → Superpowers (결정 #3: git-repo로 추적 — 실신호 확보)**
```jsonc
{ "id": "superpowers-completion-discipline", "source_type": "git-repo",
  "locator": { "repo": "https://github.com/<owner>/superpowers",   // 구현 전 실제 URL 핀
               "tracked_paths": ["<discipline 담은 파일경로>"], "clone_state": "ls-remote" },
  "absorbed_version": { "commit": "<흡수 당시 커밋 SHA>", "concept_ref": "verification-before-completion discipline" },
  "dependents": [{ "asset": "patches/completion-gate/hooks/omc-completion-gate.mjs",
    "depends_on": ["규칙: 같은 턴 검증증거 없는 완료주장 차단"],
    "break_if": ["업스트림 규율 재정의(증거 범주 변경 등)"] }],
  "drift_probe": { "kind": "git_commit", "ref": "HEAD", "diff_paths": ["<discipline 파일>"] } }
```
> concept-source/manual 티어는 모델에 남되 현재 쓰는 출처는 없음(§10). 진짜 무신호 출처 생기면 `staleness_days: 30`.
**korean-writing → humanize-korean (명목상 "개념"이나 실제론 설치된 플러그인 → 강한 신호)**
```jsonc
{ "id": "humanize-korean", "source_type": "installed-plugin",
  "locator": { "plugin_key": "humanize-korean@...", "taxonomy_path": ".../references/ai-tell-taxonomy.md" },
  "absorbed_version": { "plugin_version": "1.5.0",
    "contract": { "taxonomy_file_hash": "sha256:<ai-tell-taxonomy.md 해시>", "categories": "10 / 40+ patterns" } },
  "dependents": [
    { "asset": "patches/korean-writing/rules/writing-tropes.md", "depends_on": ["트로프 분류체계"], "break_if": ["분류 재구성/범주 삭제"] },
    { "asset": "patches/korean-writing/rules/korean-writing.md", "depends_on": ["humanize 패스 컨벤션"], "break_if": ["패스 의미 변경"] }],
  "drift_probe": { "kind": "manifest_version + file_hash", "hash_target": "references/ai-tell-taxonomy.md" } }
```
> **핵심 교훈**: `source_type`은 "가용한 최강 신호"지 고정 라벨이 아니다. "개념"으로 흡수한 게 사실 버전+해시 가능한 설치 플러그인(humanize-korean)이면 **installed-plugin으로 승격**, GitHub에 있으면(Superpowers) **git-repo로 승격**해 신호를 쓴다. `concept-source/manual`은 진짜 무신호일 때만(현재 없음).

---

## 4. Drift 감지 (Deliverable 2)

`reabsorb.sh`(기본 read-only)가 `sources/*`를 훑고 `drift_probe.kind`별로:

- **installed-plugin**: 현재 버전을 두 경로로 — `installed_plugins.json`의 installPath basename(`apply.sh:41-48` 동일 파싱) **+** 마켓플레이스 `plugin.json` version. 그다음 **계약 probe**: 정규 리포트의 `schema_version` 읽기 / `taxonomy.md` 해시. **두 축 모두** `absorbed_version`과 비교.
  - 두 축은 독립이다. **검증된 사실: `plugin_version 0.5.3` 불변 + `schema_version 3.1→3.2` 이동.** 버전만 보면 CURRENT로 잘못 보고하고 계약 변화를 놓친다 → **계약 probe는 선택이 아니라 필수.**
- **git-repo**: `git rev-parse <ref>` vs 기록 커밋, 또는 미클론이면 `git ls-remote`. `upstream-changes.sh`의 커밋/diffstat 리포팅 재사용.
- **concept-source**: 솔직히 약한 감지, 최선 신호 순:
  1. 실은 설치 플러그인 → installed-plugin으로 재분류.
  2. git repo로 도달 가능(GitHub Superpowers) → 해당 파일 해시 스냅샷 = file-hash/git-repo.
  3. 둘 다 아니면 `UNKNOWN` + **staleness 시계**(last_reviewed 경과일). 절대 자동 bump 안 함, "수동 검토 권장(N일 경과)" 넛지만.

### 상태 출력
```
SOURCE            TYPE              RECORDED            CURRENT             STATUS
insane-design     installed-plugin  0.5.3 / schema 3.1  0.5.3 / schema 3.2  DRIFTED (계약축: schema 3.1→3.2)
humanize-korean   installed-plugin  1.5.0 / hash abc123 1.5.0 / hash abc123 CURRENT
superpowers-...   git-repo          <commit abc123>     <commit abc123>     CURRENT
```
`CURRENT`=두 축 일치 · `DRIFTED`=어느 축이든 이동(어느 축인지 명시) · `UNKNOWN`=probe 불가(미설치/무신호) · `ERROR`=probe 실패.

---

## 5. Triage 계약 (Deliverable 3) — 분석 엔진 = OMC architect

### 호출 (DRIFTED 출처당 architect 1개, 독립이라 병렬)
```
Agent(subagent_type="oh-my-claudecode:architect",  // read-only; analyst가 대안
      description="Re-absorb triage: <id>",
      prompt=<아래 triage 패킷>)
```
스크립트가 패킷을 조립, 스킬이 architect 호출+델타 적용을 구동. architect는 read-only라 **제안만, 편집 안 함**.

### Triage 패킷(architect 입력)
1. 해당 `provenance.json` 전체 — `depends_on`·`break_if`로 분석을 우리 의존에만 한정.
2. 각 dependent 자산의 현재 전문(파생물).
3. 업스트림 델타: installed-plugin이면 새 계약 표면(새 `design.md` frontmatter 샘플 = `schema_version: 3.2`+토큰키, insane-design SKILL/계약 문서) + 클론에 이력 있으면 `git diff <recorded>..HEAD -- <paths>`; git-repo면 커밋 diff; concept면 사람 요약 또는 "현재 업스트림 vs 기록 `concept_ref` 평가".
4. 의존 기술(`depends_on`+`break_if`)을 명시 평가 루브릭으로 반복.

### architect가 **반드시** 반환할 구조(계약)
```jsonc
{
  "source_id": "insane-design",
  "verdict": "irrelevant | compatible | breaking",
  "confidence": "high | medium | low",
  "depends_on_assessment": [               // depends_on 항목당 1행 — 필수
    { "aspect": "리포트 경로 layout", "changed": false, "evidence": "reports/adidas/design.md 문서화 경로에 존재" },
    { "aspect": "frontmatter schema_version 계약", "changed": true,
      "nature": "additive (medium_confidence 추가; 토큰키 보존)",
      "evidence": "schema_version: 3.2; hex/font/spacing 키 유지" }
  ],
  // verdict==compatible 일 때만 — 구체적 한정 편집 필수:
  "proposed_delta": {
    "asset": "patches/design-discovery/skill/design-discovery/SKILL.md",
    "edits": [ { "anchor": "schema_version 3.1 인용 줄", "from": "schema_version 3.1",
                 "to": "schema_version 3.2 (토큰키 불변; medium_confidence 신규)",
                 "rationale": "additive bump; greenfield 값-주입 무영향" } ],
    "risk": "low"
  },
  // verdict==breaking 일 때만:
  "break": { "what": "...", "impact": "...", "human_decision_needed": "..." },
  "recommended_action": "bump | apply-delta-then-bump | escalate",
  "new_absorbed_version": { "plugin_version": "0.5.3", "frontmatter_schema_version": "3.2" }
}
```

### 분류 규칙
- **irrelevant** → `depends_on` 무변 → `--bump`만. (예: 0.5.3→0.5.4 버그픽스, 스키마/경로 불변)
- **compatible** → `depends_on` 변했으나 **구체 `proposed_delta`로 흡수 가능**. (예: schema 3.1→3.2 additive — 우리 라이브 케이스)
- **breaking** → `break_if`에 걸려 사람 판단/자산 재설계 필요 → 구체적 break로 에스컬레이트. (예: 경로 이동, 토큰 재구성)

### 고무도장 방지 가드 ("false compatible" 직격)
- `compatible`은 구체 `proposed_delta`(from/to) 없으면 **무효** — 손으로 보여주게 강제.
- 비-irrelevant인데 `confidence: low` → **자동 에스컬레이트**.
- 모든 aspect에 `evidence` 필수.
- 다중 dependent → dependent당 1행, **출처 전체는 최악 verdict로** 에스컬레이트.

---

## 6. 재흡수 + apply (Deliverable 4)

- **irrelevant** → `reabsorb.sh --bump <id>`: 감지된 `absorbed_version`+`absorbed_at`을 provenance에 기록. 자산 무편집. (`apply.sh --update-baseline` 직접 대응)
- **compatible** → **사람 게이트**: `proposed_delta` 검토 → 승인 시 **번들 진실원천 자산**(`patches/<name>/`) 편집 → **`apply.sh --write`**로 `~/.claude/...`에 verbatim 재배포(+hook/settings면 `deploy.sh` 재실행) → `reabsorb.sh --bump <id>`. architect(read-only)는 편집 안 함; 사람 또는 `executor`가 델타를 spec대로 적용.
- **breaking** → 에스컬레이트, 자동편집 없음. 사람이 path-glob 재타깃 / 자산 재설계 / break 수용 후 수동 bump.

**우아한 재사용**: 재흡수는 **번들 자산 + provenance 기록만** 건드린다. 배포는 이미 `apply.sh`가 해결 → 새 배포 코드 0.

**사람 게이트 2곳**: (1) triage 후·자산 편집 전(델타 승인/breaking 인지), (2) 기존 `apply.sh --write`의 "글로벌 파일 쓰기 전 정지" 규율(전 프로젝트 영향이므로 유지).

---

## 7. 커맨드 표면 (Deliverable 5)

`/reabsorb` end-to-end (OMC 업데이트와 **독립** 사이드 플로우, installed-plugins 파싱·`upstream-changes.sh` 스타일 리포팅 공유):
1. **Dry-run 리포트**(`reabsorb.sh` 기본, 무쓰기): §4 상태표.
2. **Triage**(스킬 구동): `DRIFTED`마다 architect 패킷 스폰 → 구조 verdict 수집·렌더.
3. **사람 승인**(출처별).
4. **Apply + bump**: compatible→번들 편집→`apply.sh --write`→`reabsorb --bump`; irrelevant→`--bump`; breaking→사람 해결.

### apply.sh 어휘 매핑(두 도구가 같게 읽히도록)
| apply.sh | reabsorb.sh | 의미 |
|---|---|---|
| `OK` | `CURRENT` | 기록==현재, 무작업 |
| `CLEAN`(drift) | `DRIFTED` | 기준 이탈, triage 필요 |
| `CONFLICT` | `BREAKING` | 의존 변경, 사람 필요 |
| `MISSING` | `UNKNOWN` | probe 불가(미설치/무신호) |
| `ERROR` | `ERROR` | probe 실패 |
| (triage 후) | `IRRELEVANT` / `COMPATIBLE` | triage verdict |

종료코드: `0` 전부 current · `2` ≥1 breaking · `3` probe error · `4` ≥1 unknown · `5` ≥1 drifted. (`apply.sh:280-285` 계열)

**수동 지금 / 감지기 나중**: 1단계 dry-run이 곧 `SessionStart`/cron 훅이 돌려 "N개 출처 drift — `/reabsorb` 실행" 넛지를 낼 지점. 배선 포인트만 격리.

---

### 7.6 Dry-run 모드 모델 (기본은 항상 dry-run, 쓰기는 명시)
모든 변이 단계는 **자기 dry-run 미리보기**를 갖는다. 쓰기는 명시 플래그로만.

| 모드 | 명령 | 부작용 | 비용 | 출력 |
|---|---|---|---|---|
| **detect** (기본 dry-run) | `reabsorb.sh` | 없음 | 싸다(에이전트 없음) | §4 상태표만 |
| **preview** (full dry-run) | `reabsorb.sh --triage` / `/reabsorb --preview` | 없음 | architect 호출(토큰) | verdict + **would-apply 델타 미리보기**(번들 자산에 적용될 from→to를 보여주되 쓰지 않음) |
| **bump preview** | `reabsorb.sh --bump --dry-run <id>` | 없음 | 싸다 | "would write absorbed_version X→Y" |
| **apply** (write) | 사람 승인 → 번들 편집 → `apply.sh --write` → `reabsorb.sh --bump` | 번들 자산 + provenance만 | — | 적용 결과 |

원칙: ① 기본 호출은 부작용 0. ② triage는 토큰을 쓰므로 **기본 dry-run은 detect-only**, 비싼 preview는 opt-in. ③ apply 단계조차 `apply.sh --write`가 자체 dry-run을 이미 가짐(중첩 안전). ④ "dry-run이 authoritative" 교리(§8) — preview에서 본 델타가 곧 적용될 것과 동일.

## 8. 실패 모드 / 엣지케이스 (Deliverable 6)
- **버전 skew**(installed_plugins basename vs plugin.json 불일치/캐시 지연): `apply.sh`의 "dry-run이 authoritative" 교리 — 둘 다 보고, 불일치는 drift로 취급(추정 금지).
- **출처 미설치/rename**(`plugin_key` 부재): `UNKNOWN`(≠DRIFTED), 절대 bump 안 함, "출처 사라짐 — 자산이 死중량일 수 있음, 폐기/재지정" (MISSING 대응).
- **다중 자산-단일 출처**: dependent별 평가; 한 출처가 자산별로 compatible/breaking 갈리면 **최악으로** 에스컬레이트, 전부 해결 후 bump.
- **부분 재흡수**: 출처별 provenance라 자연 멱등 — 3개 중 1개 승인·bump, 나머지는 다음 run에 재부상.
- **provenance drift vs 자산 drift**: 배포본 수동편집은 이미 `apply.sh`가 잡음(`UPDATE`, 번들 우선). reabsorb는 번들+provenance만. (번들 수동편집 감지는 git 몫.)
- **무신호 concept**: `UNKNOWN`+staleness, 자동 bump 금지, `last_reviewed`=스누즈.
- **스키마는 움직였는데 버전은 안 움직임**(라이브 3.1→3.2@0.5.3): 계약 probe만이 잡음 — 2축 감지의 구체 정당화.
- **버전 bump 없이 토큰 키만 rename**: `token_block_hash` probe(스키마 신뢰 너머 심층방어).
- **probe 대상 로컬 편집/재생성**: 정규/선언 소스(insane-design SKILL의 *선언* schema_version)를 샘플 아티팩트와 교차검증 — 선언=의도, 샘플=현실.
- **한 출처가 B이자 C**(개념+런타임): 허용 — 성격 다른 `dependents` 다수.

---

## 9. 대안 비교 + 권고 (Deliverable 7)
| 옵션 | Pros | 판정 |
|---|---|---|
| **A. provenance + drift-probe + architect triage + 사람게이트 apply (권장)** | 의미/계약 관계에 맞음, apply.sh 재사용, 자가등록, 2축이 실제 3.1→3.2 잡음 | 체크리스트보다 부품 많음, architect 판단 의존(엄격 계약+게이트로 완화) |
| B. 업스트림 스냅샷→유사 3-way 머지 | 익숙 | **머지엔 기각**(파생물은 줄-후손 아님→무의미). **감지엔 부분채택**: 계약 아티팩트 스냅샷=drift probe, 감지에만 |
| C. 업스트림 벤더링 | 자족적 | **기각**: design-discovery는 insane-design *라이브* 100리포트를 써야 함; 개념 벤더링=그냥 우리 자산 쓰기+업그레이드 신호 상실 |
| D. 순수 수동 체크리스트 | 인프라 0 | **전체해법 기각**(확장불가·망각); concept-source 바닥 티어로만 채택 |
| E. 완전 자동(compatible 자동적용) | 빠름 | **기각**(요구 #4·false-compatible 위험); architect read-only 유지 |

**권고: A.** B의 스냅샷은 *감지에만* 재사용, D는 concept-source 폴백 티어로 유지.

---

## 10. 결정 (확정 — 2026-06-30 인터랙티브 락인)
| # | 항목 | 확정 | 비고 |
|---|---|---|---|
| 1 | registry 위치 | **top-level `sources/<id>/provenance.json`** | 출처-키, 자가등록 1파일 |
| 2 | 버전 단위 | **출처당 `absorbed_version` 1개 + dependent별 break 평가** | |
| 3 | Superpowers 추적 | **git-repo 출처로 추적** | concept-source/manual 아님 — 실신호 확보. 구현 전 repo URL + discipline 담은 파일경로 핀 필요 |
| 4 | 계약 probe 정규소스 | **선언 schema + 샘플 아티팩트 둘 다** (교차검증) | 불일치 자체가 신호 |
| 5 | 커맨드 표면 | **`/reabsorb` 분리** (≠ `/claude-overlay`) | OMC 업데이트와 독립 사이드 플로우 |
| 6 | compatible 델타 적용 | **사람 직접** 번들 자산 편집 | architect는 read-only 제안만; 델타가 작아 사람이 적용 |
| 7 | 롤백 | **overlay git 이력** | 별도 history 구조 없음 = git revert |
| 8 | UNKNOWN staleness 임계 | **30일** | manual 폴백 티어용(현재 해당 출처 없음 — 잠재 기본값) |

> 결과: 현재 흡수물엔 순수 manual/concept-source가 **없다** — insane-design·humanize-korean·dev-scan·insane-search=installed-plugin, Superpowers=git-repo. `concept-source/manual` 티어는 미래 무신호 출처용으로 모델에만 남긴다(staleness 30일).

---

## 11. 테스트 전략 & 테스트 가능성 (설계부터 박는다)

핵심: **테스트 가능하게 만든 뒤 구현한다.** 아래 4개는 `reabsorb.sh`/`/reabsorb` 설계 *요구사항*이지 사후 추가가 아니다.

### 11.1 Testability by construction (구현 요구)
- **env override** — `reabsorb.sh`는 `OMC_SOURCES_DIR`(fixture registry), 플러그인/probe 경로 override를 받아야 한다. `apply.sh`의 `OMC_PATCH_ROOTS`/`OMC_SKILLS_DIR` 패턴 그대로 → 테스트가 실제 `~/.claude`를 절대 안 건드림.
- **순수 probe 함수** — 버전 파싱·`schema_version` 추출·해시 계산을 입력→출력 순수 함수로 분리(부수효과 없는 단위 테스트 대상).
- **verdict 스키마 검증기** — architect JSON을 `verdict.schema.json`(JSON Schema)으로 검증. 불합격(예: `compatible`인데 `proposed_delta` 없음, `depends_on_assessment` 누락, 비-irrelevant인데 `confidence:low`)이면 **거부+재시도**. → §5의 고무도장 방지가 prose가 아니라 **기계로 강제**됨.
- **명시 exit code** — §7 종료코드 매트릭스(0/2/3/4/5)를 테스트가 단언.

### 11.2 테스트 종류
1. **drift 감지 단위** — fixture provenance + fake source state → 기대 status/축. **회귀 fixture(영구 핀): insane-design `3.1@0.5.3` 기록 + `3.2` 샘플 리포트 → `DRIFTED(계약축)`** — 이 플로우의 존재이유인 버그를 박제.
2. **probe 파싱 단위** — design.md frontmatter → `schema_version`; `installed_plugins.json` fixture → plugin version; frontmatter 토큰블록 → 정규화 해시.
3. **verdict 스키마 검증** — good/bad verdict fixture를 검증기에 → 통과/거부 단언(특히 `compatible` without `proposed_delta` 거부).
4. **bump 멱등성** — fixture provenance bump → `absorbed_version` 갱신; 재실행 → 안정(no-op).
5. **E2E golden** — 임시 샌드박스(fixture `sources/` + fake plugin tree + temp skills dir): `reabsorb.sh` detect → 상태표 단언; **mock verdict**(architect 실호출 없음) → apply 경로 → 번들 자산에 델타 적용 + `--bump` 기록 + 재실행 멱등.
6. **exit code 매트릭스** — current-only→0, breaking→2, probe error→3, unknown→4, drifted→5.

### 11.3 테스트 경계 (안 하는 것 — 정직하게)
- **architect verdict의 *의미적 정확성*은 단위 테스트 불가** — 그게 사람 게이트의 몫. 테스트는 **기계와 계약**(감지·파싱·스키마·멱등·exit)만 덮는다. "이 변경이 정말 호환인가"는 사람이 판정.
- LLM 호출은 CI에서 **mock**(고정 verdict fixture)으로 대체 — 비결정·토큰비용 배제.

### 11.4 하네스
- `tests/` 신설. **bash + jq + python3**만(기존 의존 외 추가 없음). fixture는 `tests/fixtures/sources/…`, `tests/fixtures/plugins/…`.
- repo 스타일 계승: `apply.sh` dry-run 자체가 이미 self-check인 것과 같은 결. `tests/run.sh`가 전체를 돌리고 exit code로 종합.
- (선택) `apply.sh`에도 회귀 안전망이 없으니, 같은 하네스에 apply.sh dry-run 스모크를 끼워도 좋음 — 범위 밖이면 생략.

## 12. 구현 범위 (이번 아님)
이 문서는 게이트다. §10 확정 후 구현 대상:
- `sources/<id>/provenance.json` (insane-design / humanize-korean / superpowers부터, 이어서 insane-search·insane-build·dev-scan)
- `reabsorb.sh` — dry-run 모드 모델(§7.6: detect / `--triage` preview / `--bump [--dry-run]`), `apply.sh` 어휘·파싱 재사용, **env override 훅**(`OMC_SOURCES_DIR` 등, §11.1)
- `verdict.schema.json` — architect triage 출력 JSON Schema + 검증 단계(§11.1 고무도장 방지 강제)
- `/reabsorb` 스킬 (architect triage 구동 + verdict 검증 + 사람 게이트 델타 적용 가이드)
- `tests/` — §11.2 6종 + insane-design 3.1→3.2 회귀 fixture + `tests/run.sh`(bash/jq/python3)
- README/README.ko에 사이드 플로우 문서화
> 첫 실제 케이스가 이미 대기 중: **insane-design schema 3.1→3.2** 재흡수.
> 구현 전 핀 1건: 결정 #3 Superpowers 실제 repo URL + discipline 파일경로.
