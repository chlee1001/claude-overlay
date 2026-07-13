#!/usr/bin/env bash
# claude-overlay/patches/deep-interview-floor/deploy.sh
# Post-deploy step for the deep-interview-floor patch: idempotently register the
# di-floor PostToolUse hook in settings.json. Run by claude-overlay/apply.sh on
# --write, AFTER the hook file is mirrored into the hooks dir.
#
# settings.json is user-owned and survives OMC updates, so this is a one-time
# registration that stays put — re-running is a safe no-op (already-registered).
#
# The matcher targets the state-write MCP tool. OMC's state_write is an MCP tool
# named mcp__plugin_oh-my-claudecode_t__state_write; a bare "state_write" matcher is
# an EXACT match and never fires for MCP tools (Claude Code treats a matcher with no
# regex metacharacters as a whole-string match), so we use the unanchored regex
# mcp__.*__state_write. The in-hook identity re-gate (_meta.mode === 'deep-interview')
# is the real guard. Re-running self-heals an old/incorrect matcher.
#
# Honors: OMC_HOOKS_DIR (where the hook was mirrored), OMC_SETTINGS (testing override).
set -euo pipefail

HOOKS_DIR="${OMC_HOOKS_DIR:-$HOME/.claude/hooks}"
SETTINGS="${OMC_SETTINGS:-$HOME/.claude/settings.json}"
DEST="$HOOKS_DIR/omc-di-floor.mjs"
MARKER="omc-di-floor.mjs"

# Resolve a concrete node binary (hooks may run without node on PATH).
NODE_BIN="$(command -v node || true)"
[ -z "$NODE_BIN" ] && NODE_BIN="node"

python3 - "$SETTINGS" "$NODE_BIN" "$DEST" "$MARKER" <<'PY'
import json, os, sys, shutil

settings_path, node_bin, dest, marker = sys.argv[1:5]

data = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])

# state_write is an MCP tool (mcp__plugin_oh-my-claudecode_t__state_write); a bare
# "state_write" is an exact match that never fires for MCP tools, so match the
# mcp__<server>__state_write name with an unanchored regex.
MATCHER = "mcp__.*__state_write"

def find_block(arr):
    for block in arr:
        if any(marker in hk.get("command", "") for hk in block.get("hooks", [])):
            return block
    return None

block = find_block(post)
if block is not None and block.get("matcher") == MATCHER:
    print("settings.json: already-registered")
    sys.exit(0)

if block is not None:
    block["matcher"] = MATCHER  # self-heal an old/incorrect matcher (e.g. bare "state_write")
    status = "settings.json: matcher-updated"
else:
    post.append({
        "matcher": MATCHER,
        "hooks": [{"type": "command", "command": f'"{node_bin}" "{dest}"', "timeout": 5}],
    })
    status = "settings.json: registered (PostToolUse hook)"

if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".bak")
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(status)
PY
