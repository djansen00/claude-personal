---
name: sql-direct-access
description: Use when querying or modifying any Treeline Azure SQL database directly from Claude — reads OR writes. Covers the corporate SQL Managed Instance (atl-sqlmi-01 → CatalogManagement, TreelineUW, Configuration, CatalogProcessing, Matterhorn, SalesTracking, Support, CampaignBuilder), the Omnibus app DB (treeline-omnibus-sql, private-endpoint-only) including the per-tenant `Omnibus-barn01..11` databases, and the Ingest databases on `treeline-ingest-sql` (prod) and `treeline-ingest-sql-dev` (dev). Triggers include: "check the database", "query the DB", "look at the data", "verify state in SQL", "what's in <table>", "let me look up <ID>", ad-hoc data fixes, user-privilege grants, schema spelunking, or any time direct SQL is the right tool because EF / the Treeline.Services.* repos don't fit. Includes the pyodbc + az CLI access-token connection pattern, the load-bearing inline-approval rule for non-read queries (INSERT/UPDATE/DELETE/MERGE/DDL/EXEC-with-writes), the bi-modal serverless-DB auto-pause/auto-resume caveat, and the per-server connection strings.
---

# Direct SQL access (pyodbc) — connection pattern + safety rule

You have direct SQL access to the corporate Azure SQL MI from this WSL environment via **pyodbc** + an **az CLI access token**. This is the path used for ad-hoc reads, user-privilege grants, and other one-off SQL that doesn't fit through the .NET service repos.

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

## Connection pattern (verified 2026-05-12, WSL Ubuntu)

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

- **Diagnostics** (slow query analysis, blocking, plans, missing indexes): prefer the `treeline-sql-diagnostics` MCP server if loaded — it's purpose-built and read-only. The pyodbc path is for one-off reads/writes the MCP doesn't cover.
- **Omnibus app data** (reading/writing `Omnibus.dbo.*`): prefer the .NET service path. Direct SQL bypasses the layered architecture, the repository pattern, and the read-only-projection invariant for `Treeline.Data` scaffolded entities.
- **Treeline.Data scaffolded contexts** (CatalogManagement / TreelineUW): these are **read-only projections** in the .NET layer. Writes through them are greenfield and require an EntityConfiguration audit — but writing direct SQL via pyodbc to those DBs is the explicitly sanctioned path for ad-hoc fixes.

## Related skills + memories

- `project_user_privilege_grant_path.md` — group-based privilege model in CatalogManagement, the SP that serves privileges, and the two caches that gate downstream visibility. Read before granting any `ingest.*` or similar privilege.
- `title-manager-data-sources` skill — write-shape rules for Title Manager (IsbnMaster ↔ BookAttribute sync contract, ONIX SP boundary). Applies when the direct-SQL work touches title data.
- `cc:sql-diagnostics` skill — diagnostic workflows via the MCP server, complementary to this one.
