---
name: app-insights-logs
description: Use when querying Application Insights / Log Analytics telemetry for any Treeline service from Claude — Omnibus or Ingest, prod or dev. Triggers include "check the logs", "look at app insights", "what's in production logs", "trace this request", "find recent exceptions", "find failed requests", "why is X slow", "look up operation_Id", "search telemetry", "see who triggered Y", or any time you need to diagnose runtime behavior of a deployed service. Covers the `az monitor app-insights query` KQL pattern, the App ID inventory for each instance (with the gotcha that Ingest has no dev instance), the shared `Treeline-Common-log-01` Log Analytics workspace, recipe KQL queries for the common diagnostic shapes (exceptions, failed requests, slow dependencies, custom events, end-to-end traces correlated by operation_Id), the PII-awareness rule for what to paste back into chat, and the cost-awareness note that long time ranges over the prod workspace can return a lot of data fast.
---

# Application Insights logs — `az monitor app-insights query` (KQL)

## Overview

Telemetry for every Treeline service lives in Application Insights. From WSL/Linux you can query it directly with `az monitor app-insights query`, which takes a KQL string and returns JSON. Same az CLI login that already works for SQL — no separate auth.

**Read-only by design.** App Insights ingestion writes happen from the service itself; KQL queries are read-only. So no inline-approval rule (unlike `sql-direct-access`). But see the PII rule below.

## When to use this vs alternatives

| You want to… | Use |
|---|---|
| Inspect runtime behavior of a deployed service (exceptions, requests, dependencies, custom events) | **This skill** — KQL via `az monitor app-insights query` |
| Inspect logs from your **local dev** API/Function | Don't use App Insights — read the console output. Local dev typically isn't wired to App Insights. |
| Tail the live App Service prod log stream | `az webapp log tail` (see `azure-environment` skill). That's the live appender; App Insights is the historical/queryable store. |
| Investigate a SQL-side performance issue (blocking, missing indexes) | `cc:sql-diagnostics` skill (MCP server, separate path) |
| Cross-correlate App Insights + Omnibus DB state for an incident | Use both: this skill for the telemetry view, `sql-direct-access` for the DB state. |

## App Insights instance inventory

| Instance | App ID | Subscription | Resource group | Workspace |
|---|---|---|---|---|
| **Omnibus-ai** (prod) | `07b1bbdc-8537-42a6-bef5-98272630c725` | Treeline Production (`1f990888-…`) | `Omnibus` | `Treeline-Common-log-01` (shared) |
| **Omnibus-Test-ai** (dev) | `c217f866-c4ed-4a1e-a01a-9976c145f197` | Treeline MSDN (`2e9daf0f-…`) | `Omnibus-Test` | `Treeline-Common-Test-log-01` |
| **Ingest-ai** (prod) | `53574629-9ff8-4400-9e3e-af97cb5feda2` | Treeline Production (`1f990888-…`) | `Ingest` | `Treeline-Common-log-01` (shared) |

**Ingest has no dev App Insights instance.** Dev Ingest runs either emit no telemetry or are wired to the prod `Ingest-ai` instance. If you're chasing a dev-Ingest behavior and don't see it in `Ingest-ai`, check whether the dev instance is even emitting (look at the connection string in dev appsettings).

**Both prod instances feed the same Log Analytics workspace.** `Omnibus-ai` and `Ingest-ai` share `Treeline-Common-log-01` in RG `Treeline-Common` (Treeline Production sub). If you want a cross-product view (e.g., a request that fans out from Omnibus to Ingest), querying the workspace directly via `az monitor log-analytics query` is the right path — see below.

## Connection pattern

```bash
# One-time prerequisite: the application-insights extension (auto-installs on first use)
az extension add --name application-insights 2>/dev/null || true

# Query against a specific App Insights instance using its App ID
az monitor app-insights query \
  --app 07b1bbdc-8537-42a6-bef5-98272630c725 \
  --analytics-query "<KQL>" \
  --offset PT1H \
  -o table

# Equivalent against the Log Analytics workspace (cross-product correlation)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  -g Treeline-Common -n Treeline-Common-log-01 \
  --subscription 1f990888-a2f5-4dac-9109-767125cb1f0f \
  --query customerId -o tsv)

az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "<KQL>" \
  -t PT1H \
  -o json
```

**Time-range flags:**
- `--offset PT1H` (App Insights) or `-t PT1H` (Log Analytics) = last hour. Use `PT15M`, `PT6H`, `P1D`, `P7D` etc. Default is 1 hour.
- `--start-time` / `--end-time` (ISO8601) for explicit windows.

**Output:**
- `-o table` is readable for small result sets.
- `-o json` for piping to `jq` or back into Python. JSON returns rich nested structure (`tables[0].columns`, `tables[0].rows`).

## KQL recipes — the queries you'll actually run

These target the Application Insights schema (`requests`, `exceptions`, `dependencies`, `traces`, `customEvents`, `pageViews`, `availabilityResults`). When querying via Log Analytics workspace instead, the same tables are prefixed `App` (e.g. `AppRequests`, `AppExceptions`), but column names mostly match.

### Recent unhandled exceptions

```kql
exceptions
| where timestamp > ago(1h)
| project timestamp, operation_Name, type, outerMessage, problemId, cloud_RoleName
| order by timestamp desc
| take 50
```

### Failed HTTP requests with their exception context

```kql
requests
| where timestamp > ago(1h) and success == false
| project timestamp, name, url, resultCode, duration, operation_Id, cloud_RoleName
| order by timestamp desc
| take 50
```

Drill into one operation end-to-end (all spans for a single request):

```kql
union requests, dependencies, exceptions, traces
| where operation_Id == "<paste operation_Id>"
| project timestamp, itemType, name, type, resultCode, duration, message, outerMessage
| order by timestamp asc
```

### Slow dependencies (SQL, HTTP, Service Bus)

```kql
dependencies
| where timestamp > ago(1h)
| summarize p95=percentile(duration, 95), p99=percentile(duration, 99), count() by name, type
| order by p99 desc
| take 25
```

### Recent SQL calls from the service (latency + failure breakdown)

```kql
dependencies
| where timestamp > ago(1h) and type in ("SQL", "Microsoft.Data.SqlClient")
| summarize count(), failedCount=countif(success == false), p95=percentile(duration, 95) by name, target
| order by p95 desc
| take 25
```

### Custom events your code logged

```kql
customEvents
| where timestamp > ago(24h)
| where name == "<EventName>"
| project timestamp, name, customDimensions, operation_Id
| order by timestamp desc
| take 100
```

### Who hit a specific endpoint recently

```kql
requests
| where timestamp > ago(6h)
| where url contains "/api/<route>"
| project timestamp, url, resultCode, duration, user_AuthenticatedId, client_IP, operation_Id
| order by timestamp desc
| take 50
```

### Cross-product trace via the Log Analytics workspace

When a request flows from Omnibus to Ingest, both services emit to the same workspace. Query `AppRequests` and `AppDependencies` across both `cloud_RoleName` values to see the full hop chain:

```kql
union AppRequests, AppDependencies, AppExceptions, AppTraces
| where TimeGenerated > ago(1h)
| where OperationId == "<id>"
| project TimeGenerated, AppRoleName, Type, Name, ResultCode, DurationMs, Message
| order by TimeGenerated asc
```

## ⚠️ PII rule — be careful what you paste back into chat

App Insights traces capture:
- Full request URLs (including query strings — may contain ISBNs, order IDs, internal customer identifiers, occasionally email addresses if a buggy caller stuffs them in the URL)
- `client_IP`
- `user_AuthenticatedId` (often the user's email or org-scoped identifier)
- Exception messages and stack traces (may quote payload values)
- Custom event dimensions (whatever the application chose to log — sometimes contains PII)

Before pasting query results into chat or a doc:
- **Redact `user_AuthenticatedId`, `client_IP`, and any email-like values** unless Dave has explicitly asked to see them for the diagnostic.
- **Truncate or hash long stack traces** with raw payload data; usually the type + outer message + a few frames are enough.
- **Do not paste exception messages verbatim if they contain customer-data quotes** — paraphrase.

If you're unsure whether a field is sensitive, treat as sensitive and ask. This is a read-only path, but the data is still customer / org data once it leaves App Insights.

## Cost-awareness note

The prod `Treeline-Common-log-01` workspace holds telemetry from multiple services. **Queries with wide time ranges (`P7D`+) over high-cardinality tables (`requests`, `dependencies`) can return tens of thousands of rows fast.** This isn't dangerous, but:
- It blows up your chat context.
- It's not free (workspace queries are billed by data scanned beyond a daily allowance).

Default to narrow time ranges (`PT15M`, `PT1H`, `PT6H`), filter early, and `summarize` instead of `project`-ing every row when you're looking at aggregate behavior.

## Common mistakes

| Mistake | Fix |
|---|---|
| Forgetting to install the `application-insights` az extension | `az extension add --name application-insights` (or just run the query — az auto-prompts to install on first use) |
| Confusing App Insights schema (`requests`) with Log Analytics workspace schema (`AppRequests`) | App ID + `az monitor app-insights query` → use `requests`. Workspace ID + `az monitor log-analytics query` → use `AppRequests`. |
| Querying `Ingest-ai` for a dev-Ingest behavior and seeing nothing | Dev Ingest may not emit telemetry, or may emit to the prod instance with a different `cloud_RoleName`. Check appsettings, not silence. |
| Defaulting to `--offset P7D` | Wide windows scan a lot of data. Start narrow, widen only if needed. |
| Pasting raw `customDimensions` blobs into chat | Inspect for PII first; redact emails/IPs/customer IDs. |
| Using `cc:sql-diagnostics` for App Service performance questions | Wrong target. The SQL diagnostics MCP is for SQL Server internals. For Service-side request/exception/dep performance, App Insights via this skill is the right tool. |

## Related skills

- `sql-direct-access` — the SQL-side complement to this skill. Common pattern: App Insights shows an exception with an order ID → switch to `sql-direct-access` to read the DB row.
- `azure-environment` — full RG/pipeline inventory; the App Insights resources documented here are part of the broader Azure footprint there.
- `cc:sql-diagnostics` — SQL Server internals diagnostics (blocking, plans, indexes). Complementary, not a substitute.
