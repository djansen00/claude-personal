#!/usr/bin/env bash
# Start the subrights persistent worktree dev stack (full stack).
#
# Brings up the complete local stack on THIS AREA's port block, resolved from the
# shared table in ~/omni-ports.sh (subrights = offset 40):
#   Omnibus API   https://local.edelweiss.plus:5041  (+ http :5040)
#   Omnibus UI    https://local.edelweiss.plus:3040
#   Ingest API    https://local.edelweiss.plus:5042
#   Ingest admin  https://local.edelweiss.plus:3041
#
# Each area has its own block, so several stacks run side by side and free_ports
# only ever touches THIS area's five ports. ~/omni-configure-area.sh writes the
# ports into this area's gitignored appsettings.Local.json / .env.development.local
# and generates its git-excluded vite.config.local.mts.
set -euo pipefail

# Disable the shared C# compiler + MSBuild node reuse. Under `dotnet run` these
# leak memory (VBCSCompiler ~18GB) and OOM the WSL box. See memory
# wsl-dotnet-disable-shared-compilation.
export UseSharedCompilation=false
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0

WORKTREE=/home/djansen/source/repos/subrights
API_DIR="$WORKTREE/Treeline.Services.Omnibus"
INGEST_DIR="$WORKTREE/Treeline.Services.Ingest"
EC_ROOT="$WORKTREE/Treeline.Clients.EdelweissComponents"
UI_DIR="$EC_ROOT/packages/apps/omnibus"
INGEST_UI_DIR="$EC_ROOT/packages/apps/ingest"

# Ports come from the shared table, keyed by this area's directory name — so the
# WORKTREE= line above is the only per-area value in this script.
SLUG="$(basename "$WORKTREE")"
source "$HOME/omni-ports.sh"
omni_ports "$SLUG"

API_LOG=/tmp/omnibus-api-subrights.log
UI_LOG=/tmp/omnibus-ui-subrights.log
INGEST_LOG=/tmp/ingest-api-subrights.log
INGEST_UI_LOG=/tmp/ingest-ui-subrights.log

TAG="[start-omni-subrights]"

# --- Free the target ports up-front -----------------------------------------
# A previous run that aborted mid-startup (mise trust failure, Ctrl+C during
# dotnet restore) can leave child dotnet binaries squatting on the ports —
# `dotnet run` forks the actual API binary, and SIGTERM during restore is often
# ignored. Also evicts another worktree's stack running on these ports.
free_ports() {
    local ports="$1" pids
    pids=$(lsof -ti:"$ports" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$TAG freeing process(es) on ports $ports: $pids"
        echo "$pids" | xargs -r kill 2>/dev/null || true
        sleep 1
        pids=$(lsof -ti:"$ports" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            echo "$TAG still alive, SIGKILL: $pids"
            echo "$pids" | xargs -r kill -9 2>/dev/null || true
            sleep 1
        fi
    fi
}
free_ports "$API_PORT_HTTP,$API_PORT_HTTPS,$INGEST_API_PORT,$UI_PORT,$INGEST_UI_PORT"

# --- mise trust -------------------------------------------------------------
# A fresh worktree's mise.toml lives at a path mise hasn't trusted yet, which
# aborts `npm run dev` before the UI binds. The config is at the EdelweissComponents
# REPO ROOT, not the app subdir. No-op if mise isn't on PATH.
if command -v mise >/dev/null 2>&1 && [[ -f "$EC_ROOT/mise.toml" ]]; then
    mise trust "$EC_ROOT/mise.toml" >/dev/null 2>&1 || true
fi

# --- Seed gitignored local config the worktree didn't get -------------------
# mkcert certs aren't matched by EdelweissComponents/.worktreeinclude, so seed
# them into the omnibus app's certs/ dir — without them vite.config's
# hasLocalCerts is false and Vite serves HTTP (ERR_SSL_PROTOCOL_ERROR on https).
MAIN_OMNI=/home/djansen/projects/omnibus
MAIN_CERTS="$MAIN_OMNI/Treeline.Clients.EdelweissComponents/packages/apps/omnibus/certs"
WT_CERTS="$UI_DIR/certs"
if [[ ! -f "$WT_CERTS/local.edelweiss.plus+2.pem" && -f "$MAIN_CERTS/local.edelweiss.plus+2.pem" ]]; then
    echo "$TAG seeding mkcert certs into worktree from main checkout"
    mkdir -p "$WT_CERTS"
    cp -p "$MAIN_CERTS"/local.edelweiss.plus+2*.pem "$WT_CERTS"/ 2>/dev/null || true
fi

# Treeline.Services.Ingest has an EMPTY .worktreeinclude, so its API's
# appsettings.Local.json (Kestrel mkcert cert + dev DB/KV overrides) is NOT copied
# into the worktree — seed it. Omnibus' IS copied (its .worktreeinclude has
# **/appsettings.Local.json), so that seed is a defensive no-op. Seed both.
MAIN_OMNI_REPO=/home/djansen/projects/omnibus
seed_local_settings() {
    local rel="$1" src="$MAIN_OMNI_REPO/$1" dst="$WORKTREE/$1"
    if [[ ! -f "$dst" && -f "$src" ]]; then
        echo "$TAG seeding $rel from main checkout"
        mkdir -p "$(dirname "$dst")"
        cp -p "$src" "$dst"
    fi
}
seed_local_settings "Treeline.Services.Omnibus/Treeline.Services.Omnibus.Api/appsettings.Local.json"
seed_local_settings "Treeline.Services.Ingest/Treeline.Services.Ingest.API/appsettings.Local.json"

# --- Write this area's ports into its gitignored / git-excluded config -------
# Runs AFTER seeding, because seeding copies the main checkout's files (which
# carry 5000/5001) and this rewrites them to the area's block. Idempotent.
"$HOME/omni-configure-area.sh" "$SLUG"

# --- Shutdown handling ------------------------------------------------------
cleanup() {
    echo
    echo "$TAG shutting down..."
    for pid_var in API_PID INGEST_PID UI_PID INGEST_UI_PID; do
        pid="${!pid_var:-}"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    sleep 1
    # Second pass: SIGKILL the child binaries `dotnet run` / vite forked that
    # don't always die when their parent does.
    local leftovers
    leftovers=$(lsof -ti:"$API_PORT_HTTP,$API_PORT_HTTPS,$INGEST_API_PORT,$UI_PORT,$INGEST_UI_PORT" 2>/dev/null || true)
    if [[ -n "$leftovers" ]]; then
        echo "$TAG SIGKILL leftover(s): $leftovers"
        echo "$leftovers" | xargs -r kill -9 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Truncate previous logs so each run starts fresh.
: > "$API_LOG"; : > "$UI_LOG"; : > "$INGEST_LOG"; : > "$INGEST_UI_LOG"

# --- Omnibus API ------------------------------------------------------------
# launchSettings.json "Local" profile supplies ASPNETCORE_ENVIRONMENT=Local, which loads
# appsettings.Local.json and its mkcert cert. The PORTS come from that file's
# Kestrel:Endpoints section, which omni-configure-area.sh just set to this area's block.
# Kestrel endpoint config outranks the profile's applicationUrl, so expect an
# "Overriding address(es)" line in the log confirming the override took effect.
echo "$TAG starting Omnibus API (https://local.edelweiss.plus:$API_PORT_HTTPS) — log: $API_LOG"
( cd "$API_DIR" && stdbuf -oL -eL dotnet run --project Treeline.Services.Omnibus.Api 2>&1 | tee "$API_LOG" ) &
API_PID=$!

# --- Ingest API -------------------------------------------------------------
# --no-launch-profile + --urls overrides launchSettings' localhost:55530 so the
# service binds local.edelweiss.plus and shares the *.edelweiss.plus auth cookie.
# ASPNETCORE_ENVIRONMENT=Development is load-bearing: Production loads
# atl-ingest-kv (no dev access) and crashes before the port rebinds; Development
# uses Treeline-Common-Dev-kv which IS reachable from dev workstations.
echo "$TAG starting Ingest API (https://local.edelweiss.plus:$INGEST_API_PORT) — log: $INGEST_LOG"
( cd "$INGEST_DIR" && ASPNETCORE_ENVIRONMENT=Development \
    stdbuf -oL -eL dotnet run --project Treeline.Services.Ingest.API \
    --no-launch-profile --urls "https://local.edelweiss.plus:$INGEST_API_PORT" 2>&1 | tee "$INGEST_LOG" ) &
INGEST_PID=$!

# --- Omnibus UI -------------------------------------------------------------
# apps/omnibus/.env.development.local was just rewritten by omni-configure-area.sh with
# this area's API ports, plus same-origin /ext/* bases for the external common and search
# APIs (their CORS allowlist only covers :3000/:3001, so a moved frontend must proxy).
# --config loads the generated vite.config.local.mts, which pins server.port AND hmr.port
# to this area's UI port and proxies those /ext/* paths.
echo "$TAG starting Omnibus UI (https://local.edelweiss.plus:$UI_PORT) — log: $UI_LOG"
( cd "$UI_DIR" && stdbuf -oL -eL npm run dev -- --config vite.config.local.mts 2>&1 | tee "$UI_LOG" ) &
UI_PID=$!

# --- Ingest admin UI --------------------------------------------------------
# apps/ingest/.env.development.local was rewritten with this area's VITE_DEV_PORT and
# INGEST API port, plus its own same-origin /ext/common base (main.tsx consumes
# VITE_COMMON_API_URL, and that API allowlists only :3000/:3001). --config loads the
# generated vite.config.local.mts, which carries the port, strictPort, and that proxy.
# Self-signed cert via
# vite-plugin-basic-ssl — accept once at the URL on first load. Runs in the
# foreground so Ctrl+C here fires the cleanup trap for the whole stack.
echo "$TAG starting Ingest admin UI (https://local.edelweiss.plus:$INGEST_UI_PORT) — log: $INGEST_UI_LOG"
cd "$INGEST_UI_DIR"
stdbuf -oL -eL npm run dev -- --config vite.config.local.mts 2>&1 | tee "$INGEST_UI_LOG"
