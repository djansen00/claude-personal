---
name: sql-direct-access
description: Use when querying or modifying any Treeline Azure SQL database directly from Claude — reads OR writes. Covers the corporate SQL Managed Instance (atl-sqlmi-01 → CatalogManagement, TreelineUW, Configuration, CatalogProcessing, Matterhorn, SalesTracking, Support, CampaignBuilder), the Omnibus app DB (treeline-omnibus-sql, private-endpoint-only) including the per-tenant `Omnibus-barn01..11` databases, and the Ingest databases on `treeline-ingest-sql` (prod) and `treeline-ingest-sql-dev` (dev). Triggers include: "check the database", "query the DB", "look at the data", "verify state in SQL", "what's in <table>", "let me look up <ID>", ad-hoc data fixes, user-privilege grants, schema spelunking, or any time direct SQL is the right tool because EF / the Treeline.Services.* repos don't fit. **Routing rule: every read goes through the `treeline-sql-diagnostics` MCP server; pyodbc is only for writes and for the documented MCP coverage gaps.** Includes the pyodbc + az CLI access-token connection pattern, the load-bearing inline-approval rule for non-read queries (INSERT/UPDATE/DELETE/MERGE/DDL/EXEC-with-writes), the bi-modal serverless-DB auto-pause/auto-resume caveat, and the per-server connection strings.
---

# Direct SQL access — MCP for reads, pyodbc for writes

## 🚦 Routing rule — decide this before you open a connection

**Every read-only activity goes through the `treeline-sql-diagnostics` MCP server. pyodbc is the write path.**

**`cc:sql-diagnostics` owns how to drive that server** — its prerequisites and auth, `list_connections`
verification, and the ordered workflows for performance triage, blocking investigation, and slow-query
analysis. Load it whenever the read is a diagnostic one. *This* skill owns the routing decision, the
write path, and the server/database topology below — it deliberately does not restate those workflows.

| What you're doing | Path |
|---|---|
| **Any read** — SELECT, row counts, verifying state, schema spelunking | **MCP server.** Use the specialized tool when one fits (`table_schema`, `find_objects`, …); `execute_query` only for ad-hoc business-data SELECTs |
| **A diagnostic read** — slow queries, blocking, waits, plans, index health | **MCP server, driven by `cc:sql-diagnostics`.** It has ordered workflows; don't improvise a tool sequence |
| **Any write** — INSERT / UPDATE / DELETE / MERGE / DDL / writing EXEC | **pyodbc**, under the inline-approval rule below. MCP `execute_query` rejects non-SELECT by design |
| A read the MCP genuinely cannot reach | pyodbc — but **name the gap in chat first** (see coverage below) |

Reaching for pyodbc on a read *without* hitting one of the documented gaps is the specific mistake
this rule exists to prevent. The MCP path is faster, is capped at sane row counts, cannot mutate
state through `execute_query`, and its specialized tools return curated columns instead of raw DMV
dumps.

⚠️ **`execute_proc` is the one MCP tool that can mutate.** "MCP" does not automatically mean "safe" —
if the proc writes, the inline-approval rule below applies exactly as it would to pyodbc.

### What the MCP actually covers (verified 2026-09-30)

Nine named connections. Pass the name via the `connection` parameter; `list_connections` re-checks.

| Connection | Server | Default DB | Reaches |
|---|---|---|---|
| `atl-sqlmi-01` | `atl-sqlmi-01.8c316f7fa116.database.windows.net` | `master` | **All MI databases** — pass `database` to switch (verified `master` → `CatalogManagement`) |
| `Omnibus` | `treeline-omnibus-sql.database.windows.net` | `Omnibus` | **`Omnibus` only** |
| `Ingest` | `treeline-ingest-sql.database.windows.net` | `Ingest` | **prod `Ingest` only** |
| `Advertising`, `Designer`, `Events`, `Messaging`, `ta-sql`, `Analytics Lakehouse` | various | various | Servers this skill does not otherwise document — available, untested here |

### The coverage gaps — the *only* sanctioned pyodbc reads

1. **Any Omnibus DB other than `Omnibus`.** `Omnibus-dev`, `Omnibus-qa`, `Omnibus-EDI`,
   `Omnibus-barn01`…`barn11`, the dated restores. Verified failing 2026-09-30: the `database`
   override errors on the `Omnibus` connection. Expected — a single-database Azure SQL logical
   server has no cross-database context switching, unlike the MI.
2. **Any Ingest DB other than prod `Ingest`** — `Ingest-qa`, `Ingest-staging`, `Ingest-dev`, and
   **everything on `treeline-ingest-sql-dev`**, which has no MCP connection at all.
3. **The MCP server is unavailable.** If it isn't registered at all, the fix is **`/cc-bootstrap`**, which
   writes it into `~/.claude.json` — see `cc:sql-diagnostics` § Prerequisites, which owns setup and the
   Azure auth the server needs. Dropping to pyodbc is what you do when you can't fix that right now; it
   is not the remedy. If one tool errors against a server that *is* registered, say so and fall back for
   that query only — don't abandon the MCP path wholesale.

### The two identities — they are not the same principal

The MCP connects as a **service principal** (`95c63f21-9f3d-4dac-8fb8-99f40208c2cd`). pyodbc
connects as **Dave's own az CLI identity**. A read that works on one path can be denied on the
other, and the audit trail attributes them to different actors. When a permission error looks
surprising, check which identity you were using before concluding the data isn't there.

## 🛑 Load-bearing rule — non-read queries require inline display + explicit approval

**Before executing any non-read query, display the exact SQL inline in chat and wait for explicit user approval.** Reads (SELECT, read-only EXEC) can run directly. Writes cannot.

Non-read = anything that mutates state:
- `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE`
- `CREATE`, `ALTER`, `DROP` (any DDL)
- `EXEC` of a procedure that writes (when in doubt, treat as write)
- `BULK INSERT`, `SELECT … INTO`

### How to do it right

1. **Display the SQL inline** in a ```sql fence, with the parameters resolved (not bound-param placeholders).
2. **Ask** "approve to run" — explicitly naming what's being approved (the table, the key, the operation). A vague "looks good?" doesn't cut it.
3. **Wait for explicit approval** — the user must respond with something that names the operation. A bare "yes" can read as ambiguous to the auto-mode classifier and lead to a block at execution time.
4. **Quote the operation in the Bash tool's `description` field** when you actually run it — e.g. `"Approved INSERT into Group_Member_User (471273, admin-so, SO)"`. This gives the classifier the breadcrumb it needs to match against the user's most recent approval.
5. **Run a verification read after the write** (re-SELECT the affected row, EXEC the relevant SP, count rows). The classifier and the user both want to see the post-condition.

### Why this rule exists

- Pattern-matched writes against shared infra are how prod incidents start. Dave's role is fixing root causes for the team; silent writes ship the wrong category of fix.
- The Claude Code auto-mode classifier already enforces a version of this. If the SQL wasn't shown in the immediately preceding chat turn, the write tool call gets blocked mid-flow, costing a round trip.
- A `PreToolUse` hook at `.claude/hooks/check-sql-write.sh` is also wired up (see `.claude/settings.json`) — it pattern-matches risky SQL keywords inside `python3` + `pyodbc` invocations and forces a permission decision. Belt + suspenders.

If the hook or classifier blocks despite the inline-approval dance: stop, surface the block to the user, and ask for re-approval. **Do not retry the same command in different shapes hoping it slips through.** That's a workaround, not a fix.

## Connection pattern — the write path (verified 2026-05-12, WSL Ubuntu)

Use this for writes, and for reads only when one of the three coverage gaps above applies.

```python
import subprocess, struct, pyodbc

# 1. Get an AD access token for SQL via az CLI.
#    Memory: DefaultAzureCredential hangs ~30s in WSL. The az subprocess call
#    is the reliable path; AzureCliCredential (if azure-identity is installed)
#    is also fine.
token = subprocess.check_output(
    ["az", "account", "get-access-token",
     "--resource", "https://database.windows.net/",
     "--query", "accessToken", "-o", "tsv"],
    text=True
).strip()

# 2. Pack the token the way ODBC expects: int32 length + UTF-16-LE bytes.
exptoken = b''.join(bytes([b, 0]) for b in token.encode("utf-8"))
tokenstruct = struct.pack("=i", len(exptoken)) + exptoken
SQL_COPT_SS_ACCESS_TOKEN = 1256  # mssql-specific connection attribute

# 3. Connect — pick the DB you need. CatalogManagement here as the common case.
cs = ("DRIVER={ODBC Driver 18 for SQL Server};"
      "SERVER=tcp:atl-sqlmi-01.corp.abovethetreeline.com,1433;"
      "DATABASE=CatalogManagement;"
      "Encrypt=yes;TrustServerCertificate=yes")
conn = pyodbc.connect(cs, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: tokenstruct},
                       autocommit=False)  # True is fine for read-only
cur = conn.cursor()
```

### Confirmed available on this machine

- `pyodbc` 5.1.0 (`python3 -c "import pyodbc; print(pyodbc.version)"`)
- `[ODBC Driver 18 for SQL Server]` (`odbcinst -q -d`)
- `az` CLI logged in as the workspace owner (`az account show`)
- `azure-identity` (Python pkg) is **not** installed — use the `az` subprocess call

## Servers + databases

There are **three SQL infrastructures** you can reach with this pattern. Same auth pattern (az CLI token + pyodbc) works against all three — only the SERVER value in the connection string changes.

### 1. Corporate SQL Managed Instance — `atl-sqlmi-01.corp.abovethetreeline.com,1433`

Shared legacy DBs used by Edelweiss, Ingest pipelines, and Omnibus reads. Hosts:

| Database | Common use |
|---|---|
| `CatalogManagement` | Catalogs, group-based privileges, org membership |
| `CatalogProcessing` | ONIX ingest pipeline, write-via-SP boundary |
| `Configuration` | `LanguageResource` (localized lookups) |
| `TreelineUW` | Title metadata, `BookAttribute`, `IsbnMaster` |
| `Matterhorn` | Sales/inventory legacy |
| `SalesTracking` | Sales reporting |
| `Support` | Support DB |
| `CampaignBuilder` | Campaign metadata |

### 2. Omnibus app DB — `treeline-omnibus-sql.corp.abovethetreeline.com,1433`

Azure SQL DB on a logical server, **private-endpoint-only** (`publicNetworkAccess: Disabled`). The `.corp.abovethetreeline.com` form is the private DNS alias; the public `.database.windows.net` FQDN will not resolve to anything reachable. Requires corp network / VPN.

| Database | Common use |
|---|---|
| `Omnibus` | Prod Omnibus app data |
| `Omnibus-qa` | QA |
| `Omnibus-dev` | Shared dev DB |
| `Omniubus-dev` | **Typo'd duplicate** of `Omnibus-dev` — exists, ownership unclear, ask before touching |
| `Omnibus-EDI` | EDI workload |
| `Omnibus-barn01` … `Omnibus-barn11` | **Per-tenant / per-customer DBs (10 total).** Never run schema or cross-cutting data fixes across `barn*` without explicit per-tenant approval. Always name the specific tenant in the inline-approval ask. |
| `Omnibus11192025`, `Omnibus_2026-02-16-restore`, `Omnibus_2026-05-07-03PM` | Dated backup / restore copies — read-only by convention; do not write or delete without explicit confirmation |

### 3. Ingest app DBs — two separate logical servers

Both are Azure SQL DBs on the serverless tier (`GP_S_Gen5_*`), which **auto-pauses when idle** and **auto-resumes on connection**. Opening a connection to a paused DB triggers a billable resume that takes 30–60s — your first query of the day will be slow. Not a write per se, but worth flagging in chat before connecting to a paused DB if cost/latency matters.

**Prod server: `treeline-ingest-sql.database.windows.net,1433`** (public FQDN works; or use the corp DNS alias `treeline-ingest-sql.corp.abovethetreeline.com,1433` from VPN)

| Database | Status as of 2026-05-15 | Common use |
|---|---|---|
| `Ingest` | Online | Prod Ingest app DB |
| `Ingest-qa` | Paused | QA |
| `Ingest-staging` | Paused | Staging slot DB |
| `Ingest-dev` | Paused | Dev DB **on the prod server** (don't confuse with `Ingest-Dev` on the dev server — case differs) |
| `Ingest_20260323` | Paused | Dated backup |

**Dev server: `treeline-ingest-sql-dev.database.windows.net,1433`**

| Database | Status as of 2026-05-15 | Common use |
|---|---|---|
| `Ingest-Dev` | Paused | Per-developer dev DB **on the dev server** (case differs: `Ingest-Dev` here vs `Ingest-dev` on the prod server) |

### Picking the right server

Memory aid: **legacy/shared = sqlmi-01**, **Omnibus app = treeline-omnibus-sql**, **Ingest app = treeline-ingest-sql[-dev]**. If the question is about catalogs, ONIX, titles, privileges, or BISAC — it's almost certainly on the MI. If it's about Omnibus features (orders, events, inventory, store locations, TBO) — it's on `treeline-omnibus-sql`. If it's about Ingest jobs/files/run history — it's on one of the Ingest servers.

## Multi-resultset stored procedures

`UserManagement_LoadPrivileges` and similar SPs return multiple result sets. Walk them all:

```python
cur.execute("EXEC dbo.UserManagement_LoadPrivileges @UserID=?, @GroupName=?", userid, orgcode)
results = []
while True:
    if cur.description:
        results += [r[0] for r in cur.fetchall()]
    if not cur.nextset():
        break
```

## When NOT to use this path

- **Any read at all** — not just diagnostics: use the `treeline-sql-diagnostics` MCP server. See the routing rule at the top. pyodbc reads are limited to the three documented coverage gaps, and you should say which one you hit.
- **Omnibus app data** (reading/writing `Omnibus.dbo.*`): prefer the .NET service path. Direct SQL bypasses the layered architecture, the repository pattern, and the read-only-projection invariant for `Treeline.Data` scaffolded entities.
- **Treeline.Data scaffolded contexts** (CatalogManagement / TreelineUW): these are **read-only projections** in the .NET layer. Writes through them are greenfield and require an EntityConfiguration audit — but writing direct SQL via pyodbc to those DBs is the explicitly sanctioned path for ad-hoc fixes.

## Related skills + memories

- `project_user_privilege_grant_path.md` — group-based privilege model in CatalogManagement, the SP that serves privileges, and the two caches that gate downstream visibility. Read before granting any `ingest.*` or similar privilege.
- `title-manager-data-sources` skill — write-shape rules for Title Manager (IsbnMaster ↔ BookAttribute sync contract, ONIX SP boundary). Applies when the direct-SQL work touches title data.
- `cc:sql-diagnostics` skill — **the companion to this one.** It owns the MCP server: prerequisites, auth,
  connection verification, and the diagnostic workflows. This skill owns routing, writes, and topology.
  Between them the rule is: reads and diagnostics there, writes here.
