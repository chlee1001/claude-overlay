#!/usr/bin/env python3
"""claude-overlay — canonical installed_plugins.json parser (single source).

The one place that knows the installed_plugins.json shape
(`{plugins: {<key>: [{installPath}]}}`). Consumed by BOTH the bash helper
(lib/omc-version.sh, via the CLI below) and the reabsorb core
(.reabsorb_core.py, via `import omc_version`), so a format change is a one-file fix.

CLI:  omc_version.py [plugin_key]   # prints the FULL installPath (default: OMC), or nothing
Reads OMC_INSTALLED_PLUGINS (falls back to ~/.claude/plugins/installed_plugins.json).
"""
import json
import os
import sys

DEFAULT_KEY = "oh-my-claudecode@omc"
DEFAULT_FILE = "~/.claude/plugins/installed_plugins.json"


def installpath(plugin_key, installed_file=None):
    """Full installPath of `plugin_key`'s first installed entry, or '' if absent.
    Never raises — a missing or malformed file yields ''."""
    f = installed_file or os.path.expanduser(
        os.environ.get("OMC_INSTALLED_PLUGINS", DEFAULT_FILE))
    if not os.path.exists(f):
        return ""
    try:
        with open(f) as fh:
            data = json.load(fh)
    except Exception:
        return ""
    plugins = data.get("plugins", data)
    for e in plugins.get(plugin_key, []):
        p = e.get("installPath", "")
        if p:
            return p
    return ""


if __name__ == "__main__":
    key = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_KEY
    print(installpath(key))
