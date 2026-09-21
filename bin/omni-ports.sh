#!/usr/bin/env bash
# Per-area local dev port blocks for the warm worktrees under ~/source/repos/<slug>.
#
# Sourced by ~/start-omni-<slug>.sh and ~/omni-configure-area.sh.
#
# The table is EXPLICIT on purpose. Deriving offsets from a sorted directory
# listing would renumber every existing area whenever one is added or renamed,
# silently invalidating the CORS origins and .env files already written to disk.
#
# Block layout, offset = 10 * n:
#   UI       = 3000 + off      IngestUI  = 3001 + off
#   APIhttp  = 5000 + off      APIhttps  = 5001 + off
#   IngestAPI= 5002 + off
#
# The main checkout (~/projects/omnibus, ~/start-omni.sh) keeps offset 0 and does
# NOT source this file — its appsettings.Local.json already carries 5000/5001 and
# its frontend runs on the base vite config. Offset 0 is listed here only so the
# allocator in create-warm-worktree.sh never hands it out again.
#
# ⚠️ OFFSET 60 IS PERMANENTLY RESERVED — DO NOT USE IT.
# It yields API ports 5060/5061, which are the SIP ports and sit on Chromium's
# kRestrictedPorts list (net/base/port_util.cc). The server binds them happily and
# curl reaches them, but every browser fetch fails with net::ERR_UNSAFE_PORT — so a
# stack on offset 60 looks healthy from the shell and is unusable in a browser.
# quickfix was moved 60 -> 90 after hitting exactly this. The guard in omni_ports()
# below now rejects any blocked port, so this cannot silently recur.

OMNI_PORT_OFFSETS="
main:0
omnibus1:10
omnibus2:20
assets:30
subrights:40
ingest:50
title-manager:70
imprint-map:80
quickfix:90
# <<< new areas appended here by create-warm-worktree.sh
"

# Ports Chromium refuses to connect to (net/base/port_util.cc kRestrictedPorts),
# limited to the ranges this scheme can reach. A browser-facing dev stack must never
# land on one of these.
OMNI_BLOCKED_PORTS="3659 4045 4190 5060 5061 6000 6566"

# omni_ports <slug> — resolve one area's port block into the caller's shell.
omni_ports() {
    local slug="${1:-}" off
    if [[ -z "$slug" ]]; then
        echo "omni_ports: no slug given" >&2
        return 2
    fi
    off=$(printf '%s\n' "$OMNI_PORT_OFFSETS" \
        | awk -F: -v s="$slug" '$1==s {print $2; found=1} END {exit !found}') || {
        echo "omni_ports: unknown area '$slug' — add it to the table in $HOME/omni-ports.sh" >&2
        return 1
    }
    UI_PORT=$((3000 + off))
    INGEST_UI_PORT=$((3001 + off))
    API_PORT_HTTP=$((5000 + off))
    API_PORT_HTTPS=$((5001 + off))
    INGEST_API_PORT=$((5002 + off))

    # Guard: refuse a block containing a port Chromium will not connect to. Without
    # this the failure is invisible from the shell — the server binds, curl succeeds,
    # and only the browser fails, with net::ERR_UNSAFE_PORT.
    local p b
    for p in "$UI_PORT" "$INGEST_UI_PORT" "$API_PORT_HTTP" "$API_PORT_HTTPS" "$INGEST_API_PORT"; do
        for b in $OMNI_BLOCKED_PORTS; do
            if [[ "$p" == "$b" ]]; then
                echo "omni_ports: area '$slug' (offset $off) maps to port $p, which browsers refuse" >&2
                echo "omni_ports: (Chromium kRestrictedPorts -> net::ERR_UNSAFE_PORT). Pick another offset." >&2
                return 3
            fi
        done
    done

    export UI_PORT INGEST_UI_PORT API_PORT_HTTP API_PORT_HTTPS INGEST_API_PORT
}
