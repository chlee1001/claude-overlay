#!/usr/bin/env bash
# claude-overlay/patches/design-discovery/deploy.sh
# Post-deploy step for the design-discovery patch: idempotently register a PostToolUse
# (Write|Edit) hook in settings.json that, when a finalized OMC plan is written under
# .omc/plans/*.md (but NOT *.readable.md / open-questions.md), injects a one-line
# suggestion to consider the /design-discovery skill. Silent for every other write.
#
# Run by claude-overlay/apply.sh on --write. settings.json is user-owned and survives
# OMC updates, so this is a one-time registration that stays put — re-running is a safe
# no-op (already-registered, matched by marker).
#
# Pairs with the owned skill at patches/design-discovery/skill/design-discovery/.
# Honors: OMC_SETTINGS (testing override).
set -euo pipefail

SETTINGS="${OMC_SETTINGS:-$HOME/.claude/settings.json}"
MARKER="[design-discovery] 플랜 저장됨"

# The hook command: jq inspects the tool input on stdin and emits hookSpecificOutput
# additionalContext only for a finalized plan path; otherwise `empty` -> no output (silent).
read -r -d '' HOOK_CMD <<'EOF' || true
jq -c '(.tool_input.file_path // "") as $f | if ($f | test("/\\.omc/plans/[^/]*\\.md$")) and (($f | test("(\\.readable\\.md|open-questions\\.md)$")) | not) then {hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:("[design-discovery] 플랜 저장됨: " + $f + " — UI 표면이 있는 플랜이면 /design-discovery " + $f + " 로 디자인 디스커버리 단계를 고려하세요 (백엔드/CLI 전용이면 무시).")}} else empty end' 2>/dev/null || true
EOF

python3 - "$SETTINGS" "$MARKER" "$HOOK_CMD" <<'PY'
import json, os, sys, shutil

settings_path, marker, hook_cmd = sys.argv[1:4]

data = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])

def has_marker(arr):
    return any(marker in hk.get("command", "")
              for block in arr for hk in block.get("hooks", []))

if has_marker(post):
    print("settings.json: already-registered")
    sys.exit(0)

post.append({
    "matcher": "Write|Edit",
    "hooks": [{
        "type": "command",
        "command": hook_cmd,
        "statusMessage": "design-discovery 제안 확인",
    }],
})
if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".bak")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("settings.json: registered (PostToolUse Write|Edit hook)")
PY
