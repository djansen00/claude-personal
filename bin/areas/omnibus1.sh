#!/usr/bin/env bash
cd /home/djansen/source/repos/omnibus1/ || exit 1
# Show this area's dev-port block before handing off to claude, so the ports are
# visible in the terminal as well as in the auto-loaded area-root CLAUDE.md.
_slug=${PWD#/home/djansen/source/repos/}; _slug=${_slug%%/*}
if source "$HOME/omni-ports.sh" 2>/dev/null && omni_ports "$_slug" 2>/dev/null; then
    printf '\n  %s  ->  UI :%s   API :%s   Ingest API :%s   Ingest UI :%s\n  start: ~/start-omni-%s.sh (foreground)\n\n' \
        "$_slug" "$UI_PORT" "$API_PORT_HTTPS" "$INGEST_API_PORT" "$INGEST_UI_PORT" "$_slug"
fi
exec claude -c "$@"
