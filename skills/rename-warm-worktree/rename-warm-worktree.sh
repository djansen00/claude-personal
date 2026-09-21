#!/usr/bin/env bash
# rename-warm-worktree.sh — rename a warm Omnibus worktree area end to end.
#
# A warm area's slug is written into NINE places. Renaming the directory alone
# leaves eight of them stale, and most fail silently (dangling skill symlinks, a
# Terminal Keeper terminal that cd's nowhere, a port block keyed to a dead slug).
# This script moves all nine together.
#
# Usage:
#   rename-warm-worktree.sh <old-slug> <new-slug> [--label <tk-name>] [--dry-run] [--force]
#   rename-warm-worktree.sh --label-only <slug> <new-tk-name>
#
#   --label       set the Terminal Keeper display name explicitly (it does not have
#                 to equal the slug — titlemanager/title-manager already differ).
#   --label-only  rename ONLY the VS Code terminal label. Nothing on disk moves.
#   --dry-run     print every action, change nothing.
#   --force       proceed despite a live dev stack or processes sitting in the area.
#
# The port OFFSET is deliberately preserved across a rename: the ports are already
# baked into the area's gitignored appsettings.Local.json / .env.development.local /
# vite.config.local.mts and into CORS origins. Only the table KEY changes.

set -uo pipefail

REPOS="$HOME/source/repos"
TK="$REPOS/.vscode/sessions.json"
DRY=0; FORCE=0; LABEL=""; LABEL_ONLY=0; SKIP_HIST=0; HIST_ONLY=0
POS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY=1 ;;
    --force)      FORCE=1 ;;
    --label-only) LABEL_ONLY=1 ;;
    --skip-history) SKIP_HIST=1 ;;
    --history-only) HIST_ONLY=1 ;;
    --label)      shift; LABEL="${1:-}" ;;
    -h|--help)    sed -n '2,25p' "$0"; exit 0 ;;
    -*)           echo "unknown flag: $1" >&2; exit 2 ;;
    *)            POS+=("$1") ;;
  esac
  shift
done

# Find a home-dir script whose name may not match the directory's casing. The
# CatalogManager area is the live proof: ~/catalogmanager.sh and
# ~/start-omni-catalogmanager.sh are lowercase while ~/reset-omni-CatalogManager.sh
# is not. Exact match first, then case-insensitive.
hscript() {  # hscript <prefix> -> prints the real path, or returns 1
  local pre="$1" f
  f="$HOME/${pre}${OLD}.sh"
  [[ -f "$f" ]] && { printf '%s\n' "$f"; return 0; }
  f=$(find "$HOME" -maxdepth 1 -type f -iname "${pre}${OLD}.sh" 2>/dev/null | head -1)
  [[ -n "$f" ]] && { printf '%s\n' "$f"; return 0; }
  return 1
}

# Slug identity ignoring case and separators, so 'catalogmanager' counts as the
# slug of directory 'CatalogManager' rather than as a deliberate custom label.
nslug() { printf '%s' "${1,,}" | tr -d '_-'; }

# cwd -> ~/.claude/projects/ directory name. Verified against the live dirs:
# both '/' and '.' become '-'.
slugify() { printf '%s' "$1" | sed 's#[/.]#-#g'; }

note() { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run()  { if [[ $DRY -eq 1 ]]; then printf '   [dry-run] %s\n' "$*"; else eval "$@"; fi; }

# ---------------------------------------------------------------------------
# jq helper: rewrite one Terminal Keeper entry, located BY CWD (never by name —
# an area's terminal label is allowed to differ from its slug, and two of Dave's
# already do: title-manager/titlemanager, CatalogManager/catalogmanager).
# ---------------------------------------------------------------------------
tk_update() {  # tk_update <old-cwd-dir> <new-cwd-dir|""> <new-name|"">
  local oldcwd="$1" newcwd="$2" newname="$3" tmp
  command -v jq >/dev/null 2>&1 || { warn "jq missing — edit $TK by hand"; return 1; }
  [[ -f "$TK" ]] || { warn "$TK absent — no Terminal Keeper entry to update"; return 1; }

  local idx
  idx=$(jq -r --arg a "$oldcwd" \
    '[.sessions.default[]? | .cwd] | to_entries
     | map(select(.value == $a or .value == ($a + "/") or (.value | startswith($a + "/"))))
     | (.[0].key // "none")' "$TK")
  if [[ "$idx" == "none" ]]; then
    warn "Terminal Keeper: no entry with cwd '$oldcwd' — add/fix it by hand in $TK"
    return 1
  fi

  local curname
  curname=$(jq -r --argjson i "$idx" '.sessions.default[$i].name' "$TK")

  local curcwd newcwd_full=""
  curcwd=$(jq -r --argjson i "$idx" '.sessions.default[$i].cwd' "$TK")
  # Rewrite only the area-root PREFIX so a deliberate subdirectory survives.
  [[ -n "$newcwd" ]] && newcwd_full="$newcwd${curcwd#$oldcwd}"

  if [[ $DRY -eq 1 ]]; then
    printf '   [dry-run] Terminal Keeper entry[%s] name=%s -> %s\n' \
      "$idx" "$curname" "${newname:-$curname}"
    printf '   [dry-run]   cwd %s -> %s\n' "$curcwd" "${newcwd_full:-unchanged}"
    return 0
  fi

  tmp="$(mktemp)"
  # --indent 4 matches the file's existing style. Empty args leave a field alone.
  if jq --indent 4 --argjson i "$idx" --arg cwd "$newcwd_full" --arg name "$newname" '
        .sessions.default[$i] |=
          (if $cwd  != "" then .cwd  = $cwd  else . end)
        | .sessions.default[$i] |=
          (if $name != "" then .name = $name else . end)
      ' "$TK" > "$tmp" && jq -e . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$TK"
    note "Terminal Keeper: entry[$idx] name='$curname' -> '${newname:-$curname}'"
    [[ -n "$newcwd_full" ]] && note "Terminal Keeper: cwd '$curcwd' -> '$newcwd_full'"
  else
    rm -f "$tmp"
    warn "Terminal Keeper: failed to update $TK — edit it by hand"
    return 1
  fi
}

# migrate_history — move ~/.claude/projects dirs keyed to the old area path onto
# the new key and rewrite the cwd recorded inside each transcript. Uses OLDWT/NEWWT
# as plain strings: by the time --history-only runs, OLDWT no longer exists on disk.
migrate_history() {
  PROJ="$HOME/.claude/projects"
  OLDKEY="$(slugify "$OLDWT")"; NEWKEY="$(slugify "$NEWWT")"
  BACKUP="$HOME/.claude/rename-backups/$OLD-$(date +%Y%m%d-%H%M%S)"
  HIST=()
  if [[ -d "$PROJ" ]]; then
    # -iname, not -name: in --history-only mode the directory is already gone, so
    # the old slug's casing cannot be resolved from disk and the caller may have
    # typed a case variant. slugify() is a 1:1 character substitution, so the
    # matched prefix is always exactly ${#OLDKEY} chars and can be stripped by
    # length regardless of case.
    while IFS= read -r d; do HIST+=("$d"); done < <(
      find "$PROJ" -maxdepth 1 -mindepth 1 -type d \
        \( -iname "$OLDKEY" -o -iname "$OLDKEY-*" \) -printf '%f\n' 2>/dev/null | sort)
  fi
  if [[ ${#HIST[@]} -eq 0 ]]; then
    printf '   no conversation history keyed to the old path\n'
  else
    for h in "${HIST[@]}"; do
      nh="$NEWKEY${h:${#OLDKEY}}"
      _n=$(ls "$PROJ/$h"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
      if [[ $DRY -eq 1 ]]; then
        printf '   [dry-run] %s\n             -> %s   (%s transcripts)\n' "$h" "$nh" "$_n"
        continue
      fi
      if [[ -e "$PROJ/$nh" ]]; then
        warn "$nh already exists — leaving $h alone, merge by hand"
        continue
      fi
      # Hardlink backup: instant and near-zero disk, and `sed -i` writes a NEW inode
      # so the backup keeps the original bytes.
      mkdir -p "$BACKUP" && cp -al "$PROJ/$h" "$BACKUP/$h" 2>/dev/null \
        || warn "could not back up $h — continuing"
      mv "$PROJ/$h" "$PROJ/$nh"
      # Rewrite the cwd recorded inside each transcript.
      _r=0
      # Rewrite only the AREA SEGMENT of the path, case-insensitively. In
      # --history-only mode the directory is gone, so $OLD may be a case variant
      # of what the transcripts actually contain; an exact "$OLDWT" match would
      # silently rewrite nothing. \b keeps 'omnibus1' from matching 'omnibus11'.
      while IFS= read -r j; do
        grep -qiE "$REPOS/$OLD([/\"]|$)" "$j" 2>/dev/null || continue
        sed -i -E "s#($REPOS/)$OLD\b#\1$NEW#gI" "$j" && _r=$((_r+1))
      done < <(find "$PROJ/$nh" -name '*.jsonl' 2>/dev/null)
      printf '   %s\n     -> %s   (%s transcripts, %s rewritten)\n' "$h" "$nh" "$_n" "$_r"
    done
    [[ $DRY -eq 0 && -d "$BACKUP" ]] && note "   backup (hardlinks): $BACKUP"
  fi
}

# ===========================================================================
# --label-only: rename just the VS Code terminal. Nothing on disk moves.
# ===========================================================================
if [[ $LABEL_ONLY -eq 1 ]]; then
  [[ ${#POS[@]} -eq 2 ]] || die "usage: $(basename "$0") --label-only <slug> <new-tk-name>"
  SLUG="${POS[0]}"; NEWNAME="${POS[1]}"
  [[ -d "$REPOS/$SLUG" ]] || die "no warm area at $REPOS/$SLUG"
  tk_update "$REPOS/$SLUG" "" "$NEWNAME"
  note "done — reload the VS Code window for Terminal Keeper to pick it up."
  exit 0
fi

# ===========================================================================
# --history-only: finish a rename whose history step was deferred with
# --skip-history (because a live claude session was writing to that transcript
# directory). The area is ALREADY at the new path, so none of the normal
# preflight applies.
# ===========================================================================
if [[ $HIST_ONLY -eq 1 ]]; then
  [[ ${#POS[@]} -eq 2 ]] || die "usage: $(basename "$0") --history-only <old-slug> <new-slug>"
  OLD="${POS[0]}"; NEW="${POS[1]}"
  OLDWT="$REPOS/$OLD"; NEWWT="$REPOS/$NEW"
  [[ -d "$NEWWT" ]] || die "no area at $NEWWT — run the rename first"
  [[ -e "$OLDWT" ]] && warn "$OLDWT still exists — is the rename actually done?"
  INUSE=()
  for pd in /proc/[0-9]*; do
    c=$(readlink "$pd/cwd" 2>/dev/null) || continue
    [[ "$c" == "$NEWWT" || "$c" == "$NEWWT"/* ]] || continue
    grep -qE '(^|/)claude( |$)' <(tr '\0' ' ' < "$pd/cmdline" 2>/dev/null) || continue
    INUSE+=("${pd#/proc/}")
  done
  if [[ ${#INUSE[@]} -gt 0 && $FORCE -eq 0 && $DRY -eq 0 ]]; then
    die "a claude session is still running in this area (PID ${INUSE[*]}).
       Close it first — moving its transcript directory mid-session can split the
       conversation. (--force overrides.)"
  fi
  note "finishing deferred history migration: '$OLD' -> '$NEW'"
  migrate_history
  exit 0
fi

# ===========================================================================
# Full rename
# ===========================================================================
[[ ${#POS[@]} -eq 2 ]] || die "usage: $(basename "$0") <old-slug> <new-slug> [--label <tk-name>] [--dry-run] [--force]"
OLD="${POS[0]}"; NEW="${POS[1]}"
OLDWT="$REPOS/$OLD"; NEWWT="$REPOS/$NEW"

# The directory on disk is authoritative. Dave's areas are not uniformly cased
# (CatalogManager vs quickfix), and the name he types is often the Terminal Keeper
# label rather than the directory. Resolve case-insensitively and say what we picked.
if [[ ! -d "$OLDWT" ]]; then
  _m=$(find "$REPOS" -maxdepth 1 -mindepth 1 -type d -iname "$OLD" -printf '%f\n' 2>/dev/null | head -1)
  if [[ -n "$_m" ]]; then
    note "'$OLD' resolved to the directory actually on disk: '$_m'"
    OLD="$_m"; OLDWT="$REPOS/$OLD"
  fi
fi

[[ "$OLD" != "$NEW" ]]                  || die "old and new slug are identical"
[[ "$NEW" =~ ^[a-z0-9][a-z0-9-]*$ ]]    || die "new slug must be lowercase-kebab (matches create-warm-worktree)"
[[ -d "$OLDWT" ]]                       || die "no warm area at $OLDWT"
[[ ! -e "$NEWWT" ]]                     || die "$NEWWT already exists — pick another slug"
[[ -d "$OLDWT/Treeline.Clients.EdelweissComponents" ]] \
  || die "$OLDWT does not look like a warm area (no Treeline.Clients.EdelweissComponents)"

echo
note "renaming warm area '$OLD' -> '$NEW'"
[[ $DRY -eq 1 ]] && note "DRY RUN — nothing will change"

# --- 0. Preflight ----------------------------------------------------------
echo
note "preflight"

# 0a. The port block must not already be claimed under the new name.
if [[ -f "$HOME/omni-ports.sh" ]]; then
  grep -qE "^${NEW}:[0-9]+$" "$HOME/omni-ports.sh" \
    && die "'$NEW' already has a port block in ~/omni-ports.sh"
  grep -qE "^${OLD}:[0-9]+$" "$HOME/omni-ports.sh" \
    || warn "'$OLD' has no port block in ~/omni-ports.sh — nothing to re-key"
else
  warn "~/omni-ports.sh missing — skipping the port-table step entirely"
fi

# 0b. Nothing may be running IN the area: a moved directory strands every process
#     whose cwd is inside it (including, very possibly, the Claude session that is
#     running this script).
INUSE=(); LIVE_CLAUDE=0
for p in /proc/[0-9]*; do
  c=$(readlink "$p/cwd" 2>/dev/null) || continue
  [[ "$c" == "$OLDWT" || "$c" == "$OLDWT"/* ]] || continue
  # Match the FULL cmdline. Testing the truncated display string below would miss
  # a claude binary behind a long path (mise/npx shims are already close to 70 chars).
  _cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
  [[ "$_cmd" =~ (^|/)claude([[:space:]]|$) ]] && LIVE_CLAUDE=1
  INUSE+=("${p#/proc/}  $(cut -c1-90 <<<"$_cmd")")
done
if [[ ${#INUSE[@]} -gt 0 ]]; then
  # A directory rename does NOT break these: the kernel tracks cwd by inode, so
  # /proc/<pid>/cwd follows the move (verified). Only bash's cached $PWD string
  # goes stale — cosmetic, fixed by `cd "$(pwd -P)"`.
  #
  # The one step that genuinely races a live `claude` is step 8: it moves the
  # conversation-history directory the session is still appending to. So a live
  # session downgrades that step to a warning rather than blocking the rename.
  warn "processes have their cwd inside $OLDWT:"
  printf '     %s\n' "${INUSE[@]}" >&2
  warn "   (their cwd follows the rename — only bash's cached \$PWD goes stale)"
  if [[ $LIVE_CLAUDE -eq 1 && $SKIP_HIST -eq 0 && $HIST_ONLY -eq 0 ]]; then
    warn "   a LIVE claude session is in this area. Step 8 would move the transcript"
    warn "   directory it is still writing to, which can split the conversation."
    if [[ $FORCE -eq 0 && $DRY -eq 0 ]]; then
      die "re-run with --skip-history to rename everything else now, then close that
       session and run --history-only to finish. (--force overrides, at the risk above.)"
    fi
  fi
fi

# 0c. A live dev stack holds the old paths and the Ingest API's port is fixed at
#     launch, so it cannot be re-pointed without a restart.
if [[ -f "$HOME/omni-ports.sh" ]] && source "$HOME/omni-ports.sh" 2>/dev/null && omni_ports "$OLD" 2>/dev/null; then
  LIVE=()
  for prt in "$UI_PORT" "$INGEST_UI_PORT" "$API_PORT_HTTP" "$API_PORT_HTTPS" "$INGEST_API_PORT"; do
    ss -ltn "sport = :$prt" 2>/dev/null | grep -q LISTEN && LIVE+=("$prt")
  done
  if [[ ${#LIVE[@]} -gt 0 ]]; then
    warn "the '$OLD' dev stack is LIVE on ports: ${LIVE[*]}"
    if [[ $FORCE -eq 0 && $DRY -eq 0 ]]; then
      die "stop it first (Ctrl-C the ~/start-omni-$OLD.sh terminal), or re-run with --force"
    fi
  fi
  note "port block preserved: offset $((UI_PORT - 3000)) (UI $UI_PORT, API https $API_PORT_HTTPS)"
fi

# 0d. Inventory the repos and report dirt (informational — a rename is safe on a
#     dirty tree; you just want to know what is riding along).
REPO_DIRS=()
for d in "$OLDWT"/*/; do
  [[ -e "$d/.git" ]] || continue
  REPO_DIRS+=("$(basename "$d")")
done
[[ ${#REPO_DIRS[@]} -gt 0 ]] || die "found no git worktrees under $OLDWT"
note "repos in the area: ${#REPO_DIRS[@]}"
for r in "${REPO_DIRS[@]}"; do
  printf '     %-42s %-34s dirty=%s\n' "$r" \
    "$(git -C "$OLDWT/$r" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
    "$(git -C "$OLDWT/$r" status --porcelain 2>/dev/null | wc -l)"
done

# --- 1. Move the directory, then repair the worktree links -----------------
#     One `mv` of the whole area is a single same-filesystem rename(2): atomic and
#     instant, and it carries the non-repo files (CLAUDE.md, the flattened
#     .code-workspace, .cc-keep-worktree, .claude/) along for free. `git worktree
#     move` would have to run five times and leave those behind.
#     The admin dirs live in the MAIN checkout and do not move; what breaks is each
#     admin dir's `gitdir` pointer back to the worktree. `worktree repair`, run from
#     inside the moved worktree, is exactly the documented fix for that.
echo
note "1. moving $OLDWT -> $NEWWT"
run "mv \"$OLDWT\" \"$NEWWT\""
for r in "${REPO_DIRS[@]}"; do
  if [[ $DRY -eq 1 ]]; then
    printf '   [dry-run] git -C %s worktree repair\n' "$NEWWT/$r"
  else
    out=$(git -C "$NEWWT/$r" worktree repair 2>&1)
    if git -C "$NEWWT/$r" rev-parse --git-dir >/dev/null 2>&1; then
      printf '   %-42s repaired\n' "$r"
    else
      warn "$r: worktree link still broken — $out"
      warn "   recover with: git -C \"$NEWWT/$r\" worktree repair"
    fi
  fi
done

# --- 2. Rename the recyclable placeholder branch ---------------------------
#     feature/<slug>-wt is the area's local-only placeholder. If it was ever pushed
#     it is no longer purely local, so leave it and say so.
echo
note "2. placeholder branch feature/$OLD-wt -> feature/$NEW-wt"
for r in "${REPO_DIRS[@]}"; do
  G="$NEWWT/$r"
  [[ $DRY -eq 1 ]] && G="$OLDWT/$r"
  if git -C "$G" show-ref --verify --quiet "refs/heads/feature/$OLD-wt" 2>/dev/null; then
    if git -C "$G" rev-parse --abbrev-ref "feature/$OLD-wt@{upstream}" >/dev/null 2>&1; then
      warn "$r: feature/$OLD-wt has an upstream (was pushed) — NOT renaming it"
    else
      run "git -C \"$NEWWT/$r\" branch -m \"feature/$OLD-wt\" \"feature/$NEW-wt\""
      printf '   %-42s renamed\n' "$r"
    fi
  else
    printf '   %-42s (no placeholder branch)\n' "$r"
  fi
done

# --- 3. Re-key the shared port table (offset preserved) --------------------
echo
note "3. ~/omni-ports.sh — re-keying the port block, offset unchanged"
if [[ -f "$HOME/omni-ports.sh" ]] && grep -qE "^${OLD}:[0-9]+$" "$HOME/omni-ports.sh"; then
  run "sed -i -E \"s#^${OLD}:([0-9]+)\\\$#${NEW}:\\\\1#\" \"\$HOME/omni-ports.sh\""
  [[ $DRY -eq 0 ]] && printf '   %s\n' "$(grep -E "^${NEW}:[0-9]+$" "$HOME/omni-ports.sh")"
else
  printf '   (skipped)\n'
fi

# --- 4. The three home-dir scripts -----------------------------------------
#     Targeted per-field seds ONLY. A blanket s/$OLD/$NEW/g is wrong: a slug can be
#     a domain word that legitimately appears throughout the file ("ingest" is the
#     live example), and a global replace would silently corrupt it.
echo
note "4. home-dir scripts"

# 4a. launcher ~/<slug>.sh — the only slug-bearing line is the cd; everything else
#     derives the slug from $PWD at runtime. NOTE the cd may have no trailing slash
#     (~/catalogmanager.sh is `cd /…/CatalogManager|| exit 1`), so anchor on a word
#     boundary, not on '/'.
if F=$(hscript ""); then
  run "mv \"$F\" \"\$HOME/$NEW.sh\""
  run "sed -i -E \"s#(source/repos/)$OLD\\b#\\1$NEW#I\" \"\$HOME/$NEW.sh\""
  printf '   %-42s -> ~/%s\n' "${F/#$HOME/\~}" "$NEW.sh"
else
  warn "no launcher matching ~/$OLD.sh (any case) — nothing to rename"
fi

# 4b. dev-stack ~/start-omni-<slug>.sh
if F=$(hscript "start-omni-"); then
  run "mv \"$F\" \"\$HOME/start-omni-$NEW.sh\""
  run "sed -i -E \
    -e \"s#Start the $OLD persistent#Start the $NEW persistent#I\" \
    -e \"s#\\($OLD = offset#($NEW = offset#I\" \
    -e \"s#(WORKTREE=.*/source/repos/)$OLD\\b#\\1$NEW#I\" \
    -e \"s#-$OLD(\\.log)#-$NEW\\1#gI\" \
    -e \"s#\\[start-omni-$OLD\\]#[start-omni-$NEW]#I\" \
    \"\$HOME/start-omni-$NEW.sh\""
  printf '   %-42s -> ~/%s\n' "${F/#$HOME/\~}" "start-omni-$NEW.sh"
  if [[ $DRY -eq 0 ]]; then
    RESID=$(grep -in -- "$OLD" "$HOME/start-omni-$NEW.sh" || true)
    if [[ -n "$RESID" ]]; then
      warn "residual '$OLD' in ~/start-omni-$NEW.sh — review (a slug that is also a"
      warn "   domain word will match here legitimately; a path or log line will not):"
      printf '     %s\n' "$RESID" >&2
    fi
  fi
else
  warn "no dev-stack script matching ~/start-omni-$OLD.sh (any case) — nothing to rename"
fi

# 4c. reset wrapper ~/reset-omni-<slug>.sh
if F=$(hscript "reset-omni-"); then
  run "mv \"$F\" \"\$HOME/reset-omni-$NEW.sh\""
  run "sed -i -E \
    -e \"s#Reset the $OLD warm worktree#Reset the $NEW warm worktree#I\" \
    -e \"s#(reset-omni\\.sh\\\" )$OLD( |\\\"|\\$)#\\1$NEW\\2#I\" \
    \"\$HOME/reset-omni-$NEW.sh\""
  printf '   %-42s -> ~/%s\n' "${F/#$HOME/\~}" "reset-omni-$NEW.sh"
else
  warn "no reset wrapper matching ~/reset-omni-$OLD.sh (any case) — nothing to rename"
fi

# --- 5. Terminal Keeper ----------------------------------------------------
#     Located by cwd, not by name. The name follows the slug only when it WAS the
#     slug; a deliberately different label (titlemanager, catalogmanager) is kept
#     unless --label says otherwise.
echo
note "5. Terminal Keeper ($TK)"
TKNAME=""
if [[ -n "$LABEL" ]]; then
  TKNAME="$LABEL"
elif command -v jq >/dev/null 2>&1 && [[ -f "$TK" ]]; then
  CUR=$(jq -r --arg a "$OLDWT" \
    '[.sessions.default[]? | select(.cwd == $a or .cwd == ($a + "/") or (.cwd | startswith($a + "/"))) | .name][0] // ""' "$TK")
  if [[ -n "$CUR" && "$(nslug "$CUR")" == "$(nslug "$OLD")" ]]; then
    TKNAME="$NEW"
  elif [[ -n "$CUR" ]]; then
    note "keeping custom terminal label '$CUR' (it never matched the slug) — pass --label to change it"
  fi
fi
tk_update "$OLDWT" "$NEWWT" "$TKNAME"

# --- 6. Regenerate the derived, path-bearing artifacts ---------------------
echo
note "6. regenerating derived artifacts under the new slug"

# 6a. Skill symlinks are ABSOLUTE and every one of them now dangles.
if [[ -x "$HOME/sync-omni-skills.sh" ]]; then
  run "\"\$HOME/sync-omni-skills.sh\" \"$NEW\"" 2>&1 | sed 's/^/   /'
else
  warn "~/sync-omni-skills.sh missing — the area's .claude/skills symlinks all point at"
  warn "   the OLD path and are dangling. Restore the script and run it against '$NEW'."
fi

# 6b. Rewrites the area-root CLAUDE.md port block (which names the slug and the
#     ~/start-omni-<slug>.sh / ~/reset-omni-<slug>.sh paths) and re-verifies config.
if [[ -x "$HOME/omni-configure-area.sh" ]]; then
  run "\"\$HOME/omni-configure-area.sh\" \"$NEW\"" 2>&1 | sed 's/^/   /'
else
  warn "~/omni-configure-area.sh missing — the area-root CLAUDE.md still names '$OLD'"
fi

# --- 7. Live cc session state ----------------------------------------------
#     current-work.json is gitignored and dense with absolute area paths
#     (worktreeRoot, workspace, repositories[].path, sessionLog, specFile, planFile).
#     Left stale, the statusline and /work-resume point at a directory that no
#     longer exists. Session LOGS under work/*.md are historical records — those
#     are reported, never rewritten.
echo
note "7. cc session state"
if [[ $DRY -eq 1 ]]; then
  SCAN="$OLDWT"
else
  SCAN="$NEWWT"
fi
FOUND=0
while IFS= read -r f; do
  grep -q "$REPOS/$OLD" "$f" 2>/dev/null || continue
  FOUND=1
  if [[ $DRY -eq 1 ]]; then
    printf '   [dry-run] rewrite paths in %s\n' "${f#$SCAN/}"
  else
    cp -p "$f" "$f.bak-rename"
    sed -i "s#$REPOS/$OLD#$REPOS/$NEW#g" "$f"
    printf '   rewrote %s  (backup: .bak-rename)\n' "${f#$NEWWT/}"
  fi
done < <(find "$SCAN" -path '*/node_modules' -prune -o \
              -path '*/.claude/work-sessions/state/*.json' -print 2>/dev/null)
[[ $FOUND -eq 0 ]] && printf '   no active session state referencing the old path\n'

# Assert: nothing still names the old area, and every file pointer resolves.
if [[ $DRY -eq 0 ]]; then
  LEFT=$(grep -rl "$REPOS/$OLD" "$NEWWT" --include='current-work.json' 2>/dev/null || true)
  [[ -n "$LEFT" ]] && { warn "state files STILL reference the old path:"; printf '     %s\n' $LEFT >&2; }
  while IFS= read -r f; do
    while IFS= read -r ptr; do
      [[ -z "$ptr" || "$ptr" == "null" ]] && continue
      [[ -e "$ptr" ]] || warn "dangling pointer in ${f#$NEWWT/}: $ptr"
    done < <(jq -r '[.sessionLog, .specFile, .planFile, .workspace, .worktreeRoot] | .[]' "$f" 2>/dev/null)
  done < <(find "$NEWWT" -path '*/node_modules' -prune -o \
                -path '*/.claude/work-sessions/state/*.json' -print 2>/dev/null)
fi

STALE_LOGS=$(grep -rl "$REPOS/$OLD" "$SCAN" --include='*.md' \
  --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null | head -20)
if [[ -n "$STALE_LOGS" ]]; then
  note "   these markdown files still mention the old path (history — left as written):"
  printf '     %s\n' $STALE_LOGS
fi

# --- 8. Claude Code conversation history -----------------------------------
#     ~/.claude/projects/<slugified-cwd>/ is where `claude -c` looks for the
#     conversation to continue. The directory NAME is the slugified absolute cwd
#     ('/' and '.' both become '-'), so renaming the area orphans every history
#     dir under it and `claude -c` silently starts fresh. The transcripts also
#     record the old absolute path in a `cwd` field on each entry.
#     An area can have SEVERAL such dirs — one per cwd ever used in it (the area
#     root, plus any repo subdirectory a terminal was pointed at).
echo
note "8. Claude Code conversation history (~/.claude/projects)"
if [[ $SKIP_HIST -eq 1 ]]; then
  printf '   SKIPPED (--skip-history). `claude -c` will not find this area\x27s history\n'
  printf '   until you re-run:  %s --history-only %s %s\n' "$(basename "$0")" "$OLD" "$NEW"
fi
if [[ $SKIP_HIST -eq 0 ]]; then
  migrate_history
fi

# --- 9. Verify --------------------------------------------------------------
echo
if [[ $DRY -eq 1 ]]; then
  note "dry run complete — nothing changed."
  exit 0
fi
note "done. verification:"
for r in "${REPO_DIRS[@]}"; do
  printf '   %-42s %-34s %s\n' "$r" \
    "$(git -C "$NEWWT/$r" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'BROKEN')" \
    "$(git -C "$NEWWT/$r" rev-parse --git-dir >/dev/null 2>&1 && echo 'worktree ok' || echo 'WORKTREE LINK BROKEN')"
done
echo "   area root      : $NEWWT"
echo "   old path       : $([[ -e "$OLDWT" ]] && echo "STILL EXISTS — investigate" || echo "gone (ok)")"
echo "   CLAUDE.md      : $(grep -q "area is \`$NEW\`" "$NEWWT/CLAUDE.md" 2>/dev/null && echo "regenerated for '$NEW'" || echo "NOT updated — run ~/omni-configure-area.sh $NEW")"
if [[ -d "$NEWWT/.claude/skills" && ! -L "$NEWWT/.claude/skills" ]]; then
  _n=$(find "$NEWWT/.claude/skills" -maxdepth 1 -type l | wc -l | tr -d ' ')
  _d=$(find "$NEWWT/.claude/skills" -maxdepth 1 -xtype l | wc -l | tr -d ' ')
  echo "   skills dir     : $_n linked, $_d DANGLING $([[ "$_d" == "0" ]] && echo '(ok)' || echo '<- re-run ~/sync-omni-skills.sh')"
else
  echo "   skills dir     : not a merged dir — run ~/sync-omni-skills.sh $NEW"
fi
echo "   port block     : $(grep -E "^${NEW}:[0-9]+$" "$HOME/omni-ports.sh" 2>/dev/null || echo 'MISSING from ~/omni-ports.sh')"
echo "   launcher       : $([[ -x "$HOME/$NEW.sh" ]] && echo "~/$NEW.sh" || echo 'MISSING')"
echo "   dev stack      : $([[ -x "$HOME/start-omni-$NEW.sh" ]] && echo "~/start-omni-$NEW.sh" || echo 'MISSING')"
echo "   reset helper   : $([[ -x "$HOME/reset-omni-$NEW.sh" ]] && echo "~/reset-omni-$NEW.sh" || echo 'MISSING')"
echo "   terminal keeper: $(jq -r --arg a "$NEWWT" '[.sessions.default[]?|select(.cwd==$a or .cwd==($a+"/") or (.cwd|startswith($a+"/")))|"\(.name)  (cwd \(.cwd))"][0] // "NOT FOUND — fix by hand"' "$TK" 2>/dev/null)"
_hn=$(find "$PROJ" -maxdepth 1 -mindepth 1 -type d \( -name "$NEWKEY" -o -name "$NEWKEY-*" \) 2>/dev/null | wc -l | tr -d ' ')
_ho=$(find "$PROJ" -maxdepth 1 -mindepth 1 -type d \( -iname "$OLDKEY" -o -iname "$OLDKEY-*" \) 2>/dev/null | wc -l | tr -d ' ')
echo "   claude -c history: $_hn dir(s) under the new key$([[ "$_ho" != "0" ]] && echo " — $_ho STILL under the old key" || echo "")"
echo "   leftover ~/*$OLD* : $(ls -d "$HOME"/*"$OLD"* 2>/dev/null | tr '\n' ' ' || echo none)"
echo
echo "   Reload the VS Code window so Terminal Keeper picks up the new entry."
