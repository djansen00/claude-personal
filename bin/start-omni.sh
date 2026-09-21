#!/usr/bin/env bash
set -euo pipefail

# Disable the shared C# compiler + MSBuild node reuse. Under `dotnet run` these
# leak memory (VBCSCompiler ~18GB) and OOM the WSL box. See memory
# wsl-dotnet-disable-shared-compilation.
export UseSharedCompilation=false
export MSBUILDDISABLENODEREUSE=1
export DOTNET_CLI_USE_MSBUILD_SERVER=0

API_DIR="/home/djansen/projects/omnibus/Treeline.Services.Omnibus"
INGEST_DIR="/home/djansen/projects/omnibus/Treeline.Services.Ingest"
UI_DIR="/home/djansen/projects/omnibus/Treeline.Clients.EdelweissComponents/packages/apps/omnibus"
INGEST_UI_DIR="/home/djansen/projects/omnibus/Treeline.Clients.EdelweissComponents/packages/apps/ingest"
API_LOG="/tmp/omnibus-api.log"
INGEST_LOG="/tmp/ingest-api.log"
UI_LOG="/tmp/omnibus-ui.log"
INGEST_UI_LOG="/tmp/ingest-ui.log"

cleanup() {
    echo
    echo "[start-omni] shutting down..."
    for pid_var in API_PID INGEST_PID UI_PID; do
        pid="${!pid_var:-}"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT INT TERM

# Truncate previous logs so each run starts fresh — easier to grep for "the latest 500"
# without scrolling past yesterday's session.
: > "$API_LOG"
: > "$INGEST_LOG"
: > "$UI_LOG"
: > "$INGEST_UI_LOG"

echo "[start-omni] starting Omnibus API (https://local.edelweiss.plus:5001) — log: $API_LOG"
# `tee` mirrors output into the log file while keeping it visible in this terminal.
# `unbuffer` would be nicer but isn't a default install; `stdbuf` is — force line-buffering
# so tail -f stays current rather than waiting for 8KB chunks.
( cd "$API_DIR" && stdbuf -oL -eL dotnet run --project Treeline.Services.Omnibus.Api 2>&1 | tee "$API_LOG" ) &
API_PID=$!

# --no-launch-profile + --urls overrides launchSettings.json's localhost:55530 so the
# service binds to local.edelweiss.plus and shares the *.edelweiss.plus auth cookie
# with the Omnibus UI on :3000. The mkcert cert wiring lives in the gitignored
# Treeline.Services.Ingest.API/appsettings.Local.json (Kestrel:Certificates:Default).
#
# ASPNETCORE_ENVIRONMENT=Development is load-bearing: without it, --no-launch-profile
# leaves us in Production, which loads atl-ingest-kv.vault.azure.net (no dev access)
# and crashes startup before the port can rebind. Dev mode uses Treeline-Common-Dev-kv
# which IS accessible from dev workstations.
echo "[start-omni] starting Ingest API (https://local.edelweiss.plus:5002) — log: $INGEST_LOG"
( cd "$INGEST_DIR" && ASPNETCORE_ENVIRONMENT=Development \
    stdbuf -oL -eL dotnet run --project Treeline.Services.Ingest.API \
    --no-launch-profile --urls "https://local.edelweiss.plus:5002" 2>&1 | tee "$INGEST_LOG" ) &
INGEST_PID=$!

echo "[start-omni] starting Omnibus UI (https://local.edelweiss.plus:3000) — log: $UI_LOG"
( cd "$UI_DIR" && stdbuf -oL -eL npm run dev 2>&1 | tee "$UI_LOG" ) &
UI_PID=$!

# Ingest admin UI runs alongside the Omnibus UI on port 3001 (override via
# packages/apps/ingest/.env.development.local: VITE_DEV_PORT=3001 +
# VITE_INGEST_API_URL=https://local.edelweiss.plus:5002). Shares the
# *.edelweiss.plus auth cookie with the rest of the stack. Self-signed cert
# via vite-plugin-basic-ssl — accept once at the URL on first load.
echo "[start-omni] starting Ingest admin UI (https://local.edelweiss.plus:3001) — log: $INGEST_UI_LOG"
cd "$INGEST_UI_DIR"
stdbuf -oL -eL npm run dev 2>&1 | tee "$INGEST_UI_LOG"
