---
name: reabsorb
description: >
  claude-overlay 재흡수 플로우 — 우리가 외부에서 흡수한 것(completion-gate←Superpowers, korean-writing←humanize-korean)의 원본이 업데이트됐는지 감지하고,
  OMC architect deep-analysis로 triage해서 우리 번들 자산에 다시 흡수한다. OMC 업데이트(apply.sh)와
  독립된 사이드 플로우. claude-overlay 폴더에서 실행.
  Triggers: "재흡수", "reabsorb", "흡수물 드리프트", "원본 업데이트 반영", "reabsorb 돌려줘",
  "humanize-korean 업데이트 반영".
triggers:
  - /reabsorb
  - 재흡수
  - reabsorb
  - 흡수물 드리프트 확인
  - 원본 업데이트 반영
---

# reabsorb — 흡수 출처 드리프트 감지 → OMC architect triage → 재흡수

> 설계: `docs/reabsorb-design.md` (결정 8개 락인). apply.sh(OMC 파일 3-way 머지)와 **독립**.
> 3-way 머지가 아니라 **provenance 기반**: 우리 자산은 원본의 줄-포크가 아니라 계약/개념의 파생물이라서.
> **claude-overlay 폴더에서 실행한다.**

## 언제
- 흡수한 외부 원본(humanize-korean/ponytail/Superpowers/vercel 등)이 업데이트됐을 수 있을 때.
- "재흡수 돌려줘", 주기 점검, 또는 humanize-korean 등 특정 원본 업데이트를 반영하고 싶을 때.

## 절대 규칙
- **기본은 dry-run.** 감지·triage·preview는 아무것도 안 쓴다. 쓰기는 사람 승인 후 명시 단계에서만.
- architect는 **read-only 제안만** 한다. 델타 적용은 사람이 번들 자산을 직접 편집(결정 #6).
- 앱 코드/배포본을 직접 안 건드린다 — 번들 자산(`patches/…`) + provenance만.

## 워크플로

### 1) 감지 (dry-run, 값쌈)
```
./reabsorb.sh
```
상태표(SOURCE/TYPE/RECORDED/CURRENT/STATUS)를 읽는다. STATUS 의미:
`CURRENT`=그대로 · `DRIFTED`=기준 이탈(어느 축인지 NOTE) · `UNKNOWN`=probe 불가(미설치/URL 미핀) · `ERROR`=probe 실패.
exit: 0 전부 current · 5 ≥1 drifted · 4 ≥1 unknown · 3 error · 2 breaking(triage 후).
`DRIFTED`가 없으면 여기서 끝.

### 2) triage 패킷 미리보기 (dry-run)
드리프트된 각 소스에 대해:
```
./reabsorb.sh --triage <id>
```
패킷(=provenance의 depends_on/break_if + dependent 자산 경로 + 업스트림 델타 기술자)을 확인한다.

### 3) OMC architect deep-analysis (분석 엔진 — 결정 사항)
드리프트된 소스마다(독립이면 병렬) architect를 read-only로 띄운다:
```
Task(subagent_type="oh-my-claudecode:architect",
     description="Re-absorb triage: <id>",
     prompt= 아래 4개 입력 + verdict 계약)
```
architect에 주는 입력:
1. 해당 `sources/<id>/provenance.json` 전문 (depends_on/break_if = 평가 루브릭).
2. 각 dependent 자산(`patches/…`)의 현재 전문.
3. 업스트림 델타: installed-plugin이면 새 계약 표면(예: 스킬 frontmatter/아티팩트 스키마 샘플 + 버전 필드), git-repo면 `git diff <recorded>..HEAD -- <paths>`.
4. 요구 verdict: `verdict.schema.json` 준수. **irrelevant | compatible | breaking**.
   - irrelevant = depends_on 무변 → bump만.
   - compatible = 변했으나 흡수 가능 → **반드시 구체 `proposed_delta`(from/to)**.
   - breaking = `break_if` 저촉 → 사람 판단.

### 4) verdict 검증 (고무도장 방지 — 기계 강제)
architect가 낸 verdict JSON을 파일로 저장하고:
```
./reabsorb.sh --validate-verdict <verdict.json>
```
`INVALID`면 (예: compatible인데 proposed_delta 없음, depends_on_assessment 빔, non-irrelevant인데 confidence:low) architect에 **재요청**한다. `VALID`만 다음 단계.

### 5) 사람 게이트 + 재흡수
- **irrelevant** → `./reabsorb.sh --bump <id>` (자산 무편집, 기록만 전진). 미리보기는 `--bump --dry-run <id>`.
- **compatible** → 사용자에게 `proposed_delta`를 보여주고 승인받는다 → **번들 진실원천 자산**(`patches/<name>/…`)을 델타대로 직접 편집 → `./apply.sh --write`로 재배포 → `./reabsorb.sh --bump <id>`.
- **breaking** → 자동 편집 금지. 구체적 break를 사용자에게 올리고 결정(경로 재핀/자산 재설계/수용) 후 수동 처리.

### 6) 롤백
잘못되면 overlay git 이력으로 되돌린다(`git revert`). 재흡수는 번들 자산 + provenance만 건드리므로 안전.

## 새 흡수물 등록 (self-register)
새로 무언가 흡수하면 `sources/<id>/provenance.json` 한 개를 추가한다. 필수 6필드:
`id, source_type(installed-plugin|git-repo|concept-source), locator, absorbed_version, dependents(asset+depends_on+break_if), drift_probe`.
`source_type`은 "가용한 최강 신호"로 — 설치 플러그인이면 installed-plugin(버전+해시), GitHub면 git-repo.

## 성공 기준
- [ ] `./reabsorb.sh` 상태표로 드리프트 파악(무쓰기)
- [ ] 드리프트마다 architect triage + `--validate-verdict` VALID
- [ ] compatible은 사람 승인 후 번들 편집 → `apply.sh --write` → `--bump`
- [ ] breaking은 사람 에스컬레이트, 자동편집 없음
- [ ] `./tests/run.sh` 통과 상태 유지

## 함정
- verdict 검증 건너뛰기 → 고무도장. 반드시 `--validate-verdict`.
- 배포본(`~/.claude/...`) 직접 편집 → apply.sh가 덮음. 번들 자산을 편집하라.
- architect에 write 기대 → read-only다. 델타는 사람이 적용.
