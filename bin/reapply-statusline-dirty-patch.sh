#!/usr/bin/env bash
# Re-apply the statusline dirty-count patch after a cc-plugin upgrade.
#
# WHY THIS EXISTS: the real statusline script ships INSIDE the cc plugin
# (~/.claude/plugins/cache/treeline-cc-framework/cc/<ver>/tools/statusline-script.sh).
# A plugin upgrade installs a new versioned directory, so the patch silently
# disappears and the dirty indicator just stops showing -- no error, no warning.
# Run this after any cc plugin update. Idempotent; safe to run any time.
#
# Applied first 2026-09-01. Original backed up alongside as *.bak-2026-09-01.
set -uo pipefail

resolve() {
  local p=""
  if command -v jq >/dev/null 2>&1 && [ -f "$HOME/.claude/plugins/installed_plugins.json" ]; then
    p=$(jq -r '.plugins["cc@treeline-cc-framework"][0].installPath // empty' \
          "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
  fi
  if [ -z "$p" ] || [ ! -d "$p" ]; then
    p=$(ls -d "$HOME/.claude/plugins/cache/treeline-cc-framework/cc"/*/ 2>/dev/null | sort -V | tail -1)
    p="${p%/}"
  fi
  printf '%s' "$p"
}

V="$(resolve)"
S="$V/tools/statusline-script.sh"
[ -f "$S" ] || { echo "ERROR: statusline script not found at $S" >&2; exit 1; }
echo "target: $S"

python3 - "$S" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
if 'CC_DIRTY_PATCH' in s:
    print("already patched — nothing to do"); raise SystemExit(0)

old = '''if git rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(git branch --show-current 2>/dev/null)
    [[ -z "$branch" ]] && branch="detached"
fi'''
new = '''dirty_count=""   # CC_DIRTY_PATCH
if git rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(git branch --show-current 2>/dev/null)
    [[ -z "$branch" ]] && branch="detached"
    # CC_DIRTY_PATCH: uncommitted-change count, matching `git status --porcelain | wc -l`.
    dirty_count=$(git status --porcelain --no-renames 2>/dev/null | grep -c . )
    [[ "$dirty_count" == "0" ]] && dirty_count=""
fi'''
if old not in s:
    print("ERROR: upstream changed the git-branch block; patch by hand", file=sys.stderr)
    raise SystemExit(2)
s = s.replace(old, new, 1)

old2 = '''# Work session
if [[ -n "$work_id" ]]; then'''
new2 = '''# CC_DIRTY_PATCH: dirty indicator, rendered only when non-clean.
if [[ -n "$dirty_count" ]]; then
    sections+=("${bg_red}|${fg_white}| ● ${dirty_count} dirty ")
fi

# Work session
if [[ -n "$work_id" ]]; then'''
if old2 not in s:
    print("ERROR: upstream changed the work-session section; patch by hand", file=sys.stderr)
    raise SystemExit(2)
s = s.replace(old2, new2, 1)
p.write_text(s)
print("patched OK")
PY
rc=$?
[ $rc -eq 0 ] && bash -n "$S" && echo "syntax OK"
exit $rc
