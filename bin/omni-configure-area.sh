#!/usr/bin/env bash
# Materialize one warm-worktree area's local dev ports onto disk.
#
#   ~/omni-configure-area.sh <slug>
#
# Idempotent. Writes ONLY files that git already ignores or excludes:
#   <area>/Treeline.Services.Omnibus/.../appsettings.Local.json  (gitignored)
#   <area>/Treeline.Services.Ingest/.../appsettings.Local.json   (gitignored)
#   <area>/.../apps/omnibus/.env.development.local               (gitignored)
#   <area>/.../apps/ingest/.env.development.local                (gitignored)
#   <area>/.../apps/omnibus/vite.config.local.mts                (git-excluded)
#   <area>/.../apps/ingest/vite.config.local.mts                 (git-excluded)
#
# Called by ~/start-omni-<slug>.sh after its seed step; safe to run standalone.
set -euo pipefail

SLUG="${1:-}"
[[ -n "$SLUG" ]] || { echo "usage: $(basename "$0") <slug>" >&2; exit 2; }

source "$HOME/omni-ports.sh"
omni_ports "$SLUG"

WORKTREE="$HOME/source/repos/$SLUG"
[[ -d "$WORKTREE" ]] || { echo "no such area: $WORKTREE" >&2; exit 1; }

EC_ROOT="$WORKTREE/Treeline.Clients.EdelweissComponents"
UI_DIR="$EC_ROOT/packages/apps/omnibus"
INGEST_UI_DIR="$EC_ROOT/packages/apps/ingest"
OMNI_SETTINGS="$WORKTREE/Treeline.Services.Omnibus/Treeline.Services.Omnibus.Api/appsettings.Local.json"
INGEST_SETTINGS="$WORKTREE/Treeline.Services.Ingest/Treeline.Services.Ingest.API/appsettings.Local.json"

TAG="[omni-configure-$SLUG]"
UI_ORIGIN="https://local.edelweiss.plus:$UI_PORT"
INGEST_UI_ORIGIN="https://local.edelweiss.plus:$INGEST_UI_PORT"

# Write jq output through a temp file so a jq failure leaves the original intact.
# These files are gitignored — a truncated write is unrecoverable.
jq_inplace() {
    local file="$1"; shift
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    if jq "$@" "$file" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        echo "$TAG jq failed on $file — left unchanged" >&2
        return 1
    fi
}

# --- Omnibus API: Kestrel ports + the area's CORS origin ---------------------
# Kestrel:Endpoints config OVERRIDES --urls / ASPNETCORE_URLS, so the ports have
# to live here rather than on the command line. Only the Url keys are touched;
# the Certificate sub-key is left exactly as it was.
# The origin is appended only if absent, preserving order — `unique` would sort
# the allowlist.
if [[ -f "$OMNI_SETTINGS" ]]; then
    jq_inplace "$OMNI_SETTINGS" \
        --arg http   "http://+:$API_PORT_HTTP" \
        --arg https  "https://+:$API_PORT_HTTPS" \
        --arg origin "$UI_ORIGIN" \
        '.Kestrel.Endpoints.Http.Url   = $http
       | .Kestrel.Endpoints.Https.Url  = $https
       | .Cors.AllowedOrigins = (
             (.Cors.AllowedOrigins // [])
             | if index($origin) then . else . + [$origin] end
         )'
    echo "$TAG omnibus API -> http :$API_PORT_HTTP / https :$API_PORT_HTTPS; CORS has $UI_ORIGIN"
else
    echo "$TAG WARN $OMNI_SETTINGS missing — start the dev stack once to seed it" >&2
fi

# --- Ingest API: CORS origins only ------------------------------------------
# Its Kestrel section uses Certificates.Default and its port arrives via --urls
# from the start script, so there are no Endpoints keys to patch.
if [[ -f "$INGEST_SETTINGS" ]]; then
    jq_inplace "$INGEST_SETTINGS" \
        --arg a "$UI_ORIGIN" --arg b "$INGEST_UI_ORIGIN" \
        '.Cors.AllowedOrigins = (
             (.Cors.AllowedOrigins // [])
             | if index($a) then . else . + [$a] end
             | if index($b) then . else . + [$b] end
         )'
    echo "$TAG ingest API CORS has $UI_ORIGIN and $INGEST_UI_ORIGIN"
else
    echo "$TAG WARN $INGEST_SETTINGS missing — start the dev stack once to seed it" >&2
fi

# --- Frontend env files -----------------------------------------------------
# Rewritten wholesale so the area's ports are unambiguous. Both are gitignored.
# VITE_DEV_PORT is what vite.config.local.mts reads via loadEnv, so a manual
# `npm run dev -- --config vite.config.local.mts` also lands on the right port
# with nothing exported.
#
# VITE_COMMON_API_URL / VITE_SEARCH_API_URL point at THIS app's own dev-server
# origin with an /ext/... path, not at dev-api.edelweiss.plus directly — the
# common API's CORS allowlist only permits the two well-known dev ports
# (:3000/:3001), so a moved frontend proxies through its own Vite server
# instead (see vite.config.local.mts below). VITE_EXT_API_TARGET is the real
# upstream the proxy forwards to; kept as its own var so it can be swapped to
# qa-api for a coherent qa session without touching the generated shim.
cat > "$UI_DIR/.env.development.local" <<EOF
VITE_DEV_PORT=$UI_PORT
VITE_OMNIBUS_API_URL=https://local.edelweiss.plus:$API_PORT_HTTPS
VITE_INGEST_API_URL=https://local.edelweiss.plus:$INGEST_API_PORT
VITE_COMMON_API_URL=https://local.edelweiss.plus:$UI_PORT/ext/common
VITE_SEARCH_API_URL=https://local.edelweiss.plus:$UI_PORT/ext/search
VITE_EXT_API_TARGET=https://dev-api.edelweiss.plus
EOF
echo "$TAG omnibus UI env -> port $UI_PORT, api :$API_PORT_HTTPS, ingest :$INGEST_API_PORT"

cat > "$INGEST_UI_DIR/.env.development.local" <<EOF
VITE_DEV_PORT=$INGEST_UI_PORT
VITE_INGEST_API_URL=https://local.edelweiss.plus:$INGEST_API_PORT
VITE_COMMON_API_URL=https://local.edelweiss.plus:$INGEST_UI_PORT/ext/common
VITE_EXT_API_TARGET=https://dev-api.edelweiss.plus
EOF
echo "$TAG ingest UI env -> port $INGEST_UI_PORT, api :$INGEST_API_PORT"

# --- Vite override configs (git-excluded) -----------------------------------
# Quoted heredocs: both files are byte-identical across areas and read their
# port/proxy target at runtime from VITE_DEV_PORT / VITE_EXT_API_TARGET via
# loadEnv, so nothing is interpolated here.

# Omnibus: proxies /ext/common AND /ext/search (this app's .env.development
# declares a search API; ingest's does not).
cat > "$UI_DIR/vite.config.local.mts" <<'EOF'
// GENERATED by ~/omni-configure-area.sh — do not edit by hand.
// Git-excluded via .git/info/exclude (**/vite.config.local.mts).
//
// vite.config.mts pins server.port AND — inside its `hasLocalCerts` branch —
// hmr.port to 3000. `--port` overrides the former; NOTHING overrides the latter
// (no CLI flag, no env hook). This config imports the tracked config and merges
// the area's ports over it, so upstream changes to the base are inherited
// rather than copied.
//
// The common API's CORS allowlist is hardcoded to the two well-known dev ports
// (:3000/:3001) and we do not own it, so a moved frontend cannot call it
// directly. Proxy it server-side instead: the browser sees a same-origin URL,
// so CORS never applies. api-service.ts getUrlHref() supports a base WITH a
// path, which is what makes this work without touching tracked code.
import { defineConfig, loadEnv, mergeConfig } from 'vite';
import base from './vite.config.mts';

export default defineConfig(async (env) => {
	const fileEnv = loadEnv(env.mode, process.cwd(), '');
	const uiPort = Number(fileEnv.VITE_DEV_PORT || 3000);
	const extTarget = fileEnv.VITE_EXT_API_TARGET || 'https://dev-api.edelweiss.plus';
	const resolved = await (typeof base === 'function' ? base(env) : base);

	return mergeConfig(resolved, {
		server: {
			port: uiPort,
			// Fail loudly on a busy port. Vite's default silently rolls to the
			// next free port, which then fails CORS and reads as an auth bug.
			strictPort: true,
			// Merge into an existing hmr block only (certs present), keeping its
			// protocol and host. With no certs the base has no hmr block and
			// Vite defaults HMR to server.port, which is already correct.
			...(resolved.server?.hmr ? { hmr: { port: uiPort } } : {}),
			proxy: {
				'/ext/common': {
					target: extTarget,
					changeOrigin: true,
					secure: true,
					rewrite: (p) => p.replace(/^\/ext\/common/, ''),
				},
				'/ext/search': {
					target: extTarget,
					changeOrigin: true,
					secure: true,
					rewrite: (p) => p.replace(/^\/ext\/search/, '/search'),
				},
			},
		},
	});
});
EOF
echo "$TAG wrote $UI_DIR/vite.config.local.mts"

# Ingest: proxies /ext/common only — the ingest app's .env.development
# declares no search API. strictPort lives here (not a start-script CLI flag)
# so a busy port fails loudly instead of silently rolling to the next free one.
cat > "$INGEST_UI_DIR/vite.config.local.mts" <<'EOF'
// GENERATED by ~/omni-configure-area.sh — do not edit by hand.
// Git-excluded via .git/info/exclude (**/vite.config.local.mts).
//
// Mirrors the omnibus shim: imports the tracked base config and merges the
// area's port over it. The ingest base config has no fixed HMR port to
// override, but its server.port is pinned the same way, so strictPort still
// matters — fail loudly on a busy port rather than silently rolling to the
// next free one, which then fails CORS and reads as an auth bug.
//
// The common API's CORS allowlist is hardcoded to the two well-known dev ports
// (:3000/:3001) and we do not own it, so a moved frontend cannot call it
// directly. Proxy it server-side instead: the browser sees a same-origin URL,
// so CORS never applies. api-service.ts getUrlHref() supports a base WITH a
// path, which is what makes this work without touching tracked code.
import { defineConfig, loadEnv, mergeConfig } from 'vite';
import base from './vite.config.mts';

export default defineConfig(async (env) => {
	const fileEnv = loadEnv(env.mode, process.cwd(), '');
	const uiPort = Number(fileEnv.VITE_DEV_PORT || 3000);
	const extTarget = fileEnv.VITE_EXT_API_TARGET || 'https://dev-api.edelweiss.plus';
	const resolved = await (typeof base === 'function' ? base(env) : base);

	return mergeConfig(resolved, {
		server: {
			port: uiPort,
			strictPort: true,
			...(resolved.server?.hmr ? { hmr: { port: uiPort } } : {}),
			proxy: {
				'/ext/common': {
					target: extTarget,
					changeOrigin: true,
					secure: true,
					rewrite: (p) => p.replace(/^\/ext\/common/, ''),
				},
			},
		},
	});
});
EOF
echo "$TAG wrote $INGEST_UI_DIR/vite.config.local.mts"

# --- Area-root CLAUDE.md (per-session port context) -------------------------
# Written to <area>/CLAUDE.md — the area ROOT, which is deliberately NOT inside
# any git repository (every repo's toplevel is a subdirectory of it). git cannot
# stage a path above its own toplevel, so this file is structurally un-committable:
# `git add ../CLAUDE.md` fails with "outside repository", and `git add -A` from a
# repo root never sees it. No .gitignore entry is needed or possible.
#
# The launcher ~/<slug>.sh cd's here before exec'ing claude, so this is cwd at
# session start and Claude Code loads it automatically — giving both the human and
# the assistant this area's ports without anyone looking them up.
#
# Generated from ~/omni-ports.sh, so it cannot drift from the real table. Only the
# delimited block is rewritten; any hand-written content in the file is preserved.
CLAUDE_MD="$WORKTREE/CLAUDE.md"
CLAUDE_BLOCK="$(mktemp)"
cat > "$CLAUDE_BLOCK" <<BLOCK
<!-- BEGIN omni-ports (generated by ~/omni-configure-area.sh — do not edit by hand) -->
## Local dev ports — this area is \`$SLUG\`

| Service | URL |
|---|---|
| Omnibus UI | https://local.edelweiss.plus:$UI_PORT |
| Omnibus API | https://local.edelweiss.plus:$API_PORT_HTTPS (http :$API_PORT_HTTP) |
| Ingest API | https://local.edelweiss.plus:$INGEST_API_PORT |
| Ingest admin UI | https://local.edelweiss.plus:$INGEST_UI_PORT |

Every warm-worktree area has its own block, so several stacks run at once. **Use the
ports above, not :3000/:5001** — those belong to the main checkout at \`~/projects/omnibus\`.

- Source of truth: \`~/omni-ports.sh\` (\`source ~/omni-ports.sh && omni_ports $SLUG\`)
- Start this stack: \`~/start-omni-$SLUG.sh\` — run it in a foreground terminal, never
  backgrounded (its cleanup trap SIGKILLs everything on these ports when the task is reaped)
- Reset between sessions: \`~/reset-omni-$SLUG.sh\`, then \`npm install\` in
  Treeline.Clients.EdelweissComponents if the branch moved far (node_modules goes stale)
- The frontends reach the external Edelweiss common/search APIs same-origin via
  \`/ext/common\` and \`/ext/search\`, proxied by the generated \`vite.config.local.mts\`,
  because that API's CORS allowlist only covers :3000/:3001
<!-- END omni-ports -->
BLOCK

CLAUDE_NEW="$(mktemp)"
if [[ -f "$CLAUDE_MD" ]] && grep -q '<!-- BEGIN omni-ports' "$CLAUDE_MD"; then
    awk -v bf="$CLAUDE_BLOCK" '
        /<!-- BEGIN omni-ports/ { skip=1; while ((getline l < bf) > 0) print l; next }
        /<!-- END omni-ports/   { skip=0; next }
        !skip { print }
    ' "$CLAUDE_MD" > "$CLAUDE_NEW"
elif [[ -f "$CLAUDE_MD" ]]; then
    { cat "$CLAUDE_MD"; echo; cat "$CLAUDE_BLOCK"; } > "$CLAUDE_NEW"
else
    cat "$CLAUDE_BLOCK" > "$CLAUDE_NEW"
fi
mv "$CLAUDE_NEW" "$CLAUDE_MD"
rm -f "$CLAUDE_BLOCK"
echo "$TAG wrote $CLAUDE_MD (port context for this area's Claude sessions)"

# --- Restart reminder -------------------------------------------------------
# Kestrel reloads its ENDPOINTS when this file changes, but the CORS allowlist is
# captured once at pipeline construction (Startup.cs UseCors lambda) and is frozen
# for the process lifetime. So a running API will silently move to the new ports
# while still enforcing the OLD allowlist — every curl check passes and only the
# browser fails, with no ACAO. If a stack is already running for this area, it MUST
# be restarted for these values to take full effect.
if lsof -ti:"$UI_PORT,$INGEST_UI_PORT,$API_PORT_HTTP,$API_PORT_HTTPS,$INGEST_API_PORT" >/dev/null 2>&1; then
    echo "$TAG NOTE: a stack is already listening on this area's ports." >&2
    echo "$TAG       Kestrel hot-reloads ports but NOT the CORS allowlist — restart the stack." >&2
fi
