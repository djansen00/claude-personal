---
name: omnibus-ui-registers
description: MANDATORY FIRST STEP before writing or editing any Omnibus frontend UI — any file under Treeline.Clients.EdelweissComponents/packages/apps/*, any React/Tailwind/shadcn component, any page, drawer, modal, table, form, card, landing block or directory tile. Routes you to the correct design charter for the surface you are touching, because Omnibus has TWO UI registers that need opposite treatments and the charters do not reliably appear in the session skills list. Also carries the cross-cutting facts that live in no charter: which conventions a machine actually enforces, a known live violation you must not copy, known-stale docs you must not trust, and the accessibility bar. Triggers on any Omnibus/publisher/storefront frontend work, "build a component", "style this", "add a page", "fix the UI", "make this look better", or any task touching *.tsx in the frontend repo. NOT for backend work, and NOT for standalone HTML deliverables like reports or one-pagers (that is `design-standards`).
---

# Omnibus UI — which register, which charter

## What this skill is

A **router**, not a standard. It deliberately contains almost no design rules of its own.

The real charters are living documents that compound — they carry dated rulings, measured
costs, and sanctioned exceptions added PR by PR. Any copy of their rules kept here would drift
within weeks and then quietly contradict them, which is the exact failure this whole area
already suffered from. So this file routes you to them and gets out of the way.

What it *does* own is the set of facts that have no home in any charter: which conventions a
machine checks, where the machine and a charter disagree, what is live and broken, and what is
stale and must not be trusted.

> **Local-only file.** This lives in `~/.claude/skills/` — it is not in any repo and not in git.
> It loads in every session in every warm worktree, which is precisely why it exists: the
> charters themselves do not.

## How this local setup is wired

Three git-invisible layers. Nothing here is shared with the team yet.

| Layer | Where | Job |
|---|---|---|
| Always-loaded pointer | `~/.claude/CLAUDE.md` | Three sentences: two registers exist, charters may not load, only one is enforced |
| This router | `~/.claude/skills/omnibus-ui-registers/` | Routing + the cross-cutting facts that live in no charter |
| Merged skills dir | `<WT>/.claude/skills/` per warm worktree | Per-skill symlinks into **both** the workspace repo and the frontend repo, so the real charters appear in the skills list |

The third layer is maintained by **`~/sync-omni-skills.sh`** — idempotent, prunes stale links,
`--check` to dry-run, `--revert` to restore the original single symlink. Re-run it after
creating a worktree, and after a branch switch that adds or removes a skill (notably
`publisher-landing-design`, which only exists on the publisher-pages line of work).

Because that layer works, **prefer invoking a charter as a skill over reading it by path** — the
path fallback in Step 2 is there for worktrees where the sync has not been run.

Also user-level and git-invisible: the `design-standards` skill (standalone HTML deliverables),
`references/cc-plugin-handoff.md` in this skill's directory (the not-yet-shipped plugin
proposal), and `~/.claude/local-notes/RETIRED-design-system.md` (a retired doc, kept as record).

---

## Step 1 — Determine the register

Omnibus has two UI registers. They need opposite things, and the decisions that make one good
make the other bad. Ask one question:

> ### Is this surface **operated**, or is it **shown** to someone outside the company?

| | **Workflow register** | **Marketing register** |
|---|---|---|
| Test | Operated: scanned, filled in, acted on | Shown: looked at, and judged |
| Surfaces | Orders, inventory, receiving, the `/publisher/*` admin, editors, panels, wireframes | A publisher's public page, the publishers directory — `components/landing/*`, `components/blocks/*`, `components/directory/*` |
| Library | shadcn / Radix in `components/ui/` | `SectionKit.tsx` (landing) — build new parts here, never reach for an admin primitive |
| Colour | Semantic tokens — `bg-card`, `text-muted-foreground` | Derived from `--publisher-accent` via `accentTint()` |
| Depth | Borders and elevation on `bg-card` | Layered colour: gradients, radial glows, translucency, `backdrop-blur` |
| Type | One system face, UI scale | Two-slot display + body role system |
| Motion | Minimal, functional | Part of the polish; nothing snaps |
| **Charter** | **`omnibus-publisher-ui`** | **`publisher-landing-design`** |
| Machine-checked? | Yes — ESLint at `error` level | **No.** Prose only |

**Mixed surfaces.** Where a screen is both — the Site Presence editor, which previews a
marketing page inside an admin screen — the editor chrome is workflow, the previewed page is
marketing, and **the boundary is the preview frame**. `PublisherPagePreviewPage` is the worked
example: publisher chrome outside, the landing page verbatim inside.

**The registers must not leak.** An admin panel styled like a marketing page is as wrong as the
reverse.

---

## Step 2 — Read that register's charter before writing code

Both charters live in the frontend repo, not the workspace, so they may or may not be in your
skills list this session.

1. **If the charter name appears in your available skills, invoke it.**
2. **If it does not, Read it by absolute path.** Resolve `<WT>` as the warm-worktree root — the
   directory containing `Treeline.Clients.EdelweissComponents` (e.g. `~/source/repos/omnibus1`):

```
<WT>/Treeline.Clients.EdelweissComponents/.claude/skills/omnibus-publisher-ui/SKILL.md
<WT>/Treeline.Clients.EdelweissComponents/.claude/skills/publisher-landing-design/SKILL.md
```

Do this **every session**, before the first line of UI code. Not once per project — the charters
compound, so a version you read last week is already behind.

> **Caveat — `publisher-landing-design` is branch-dependent.** It shipped on the
> publisher-pages line of work and is present in the `omnibus1`, `omnibus2` and `title-manager`
> worktrees, but **not** in worktrees sitting on older release merges (`CatalogManager`,
> `assets`, `ingest`, `quickfix`, `subrights` as of 27 Aug 2026). If you are on a marketing
> surface and the file is absent, you are on a branch that predates the charter — say so rather
> than inventing the rules, and check whether the work belongs on a newer branch.

### The marketing register in one paragraph, for triage only

Purpose-built interactive elements, never default shadcn `Button`/`Card`/bordered white boxes;
depth from layered colour rather than a 1px border on flat white; every treatment derived from
the publisher's accent; display-scale type with generous tracking; motion on hover; and new page
furniture **integrated into an existing composition** rather than stacked as another band below
the hero. **This paragraph is not the standard** — it is enough to recognise a violation. Read
the charter for the actual rules, the sanctioned exceptions, and the approved treatments.

---

## Step 3 — Know what the machine actually checks

The single most useful fact about this codebase: **conventions a machine enforces have held;
conventions written only in prose have drifted.** Calibrate your caution accordingly.

**Enforced by ESLint** (root `.eslintrc.json`, scoped to `packages/apps/omnibus/**`) — `warn`
repo-wide, `error` in named new-feature directories:

- Raw `<button>` / `<input>` / `<select>` — use `ui/button`, `ui/input`, `ui/select`
- Arbitrary colour values in `className` — `[#…]`, `[rgb(…)]`, `[hsl(…)]`
- New `*.module.scss` imports — **`error` repo-wide** (one legacy file is allowlisted)
- Layering: `components`/`hooks`/`lib`/`utils` must not import `features/` or `pages/`
- Cross-feature deep imports — enter through a feature's `index.ts` barrel

**Enforced by nothing:** the entire marketing register, and every rule in
`publisher-landing-design`.

### ⚠ Known conflict — lint and the marketing charter contradict each other

The `error`-level ESLint override covers **all** of
`packages/apps/omnibus/src/features/publisher-pages/**` — including `landing/`, `blocks/` and
`directory/`, the three directories the marketing charter governs.

So on a marketing surface, lint says *"use `ui/button` instead of a raw `<button>`"* while the
charter says *"do not use the default shadcn Button here."* Nothing trips today only because
those components currently use anchors and `<div>`s.

**If you need a real interactive control on a marketing surface, you will hit this.** Do not
silently satisfy lint by importing the admin primitive — that is the regression the charter
exists to stop. Build the control in `SectionKit`, and if lint objects, raise it rather than
resolving it in either direction on your own. The proper fix is a path-keyed rule split, which
is a team-level change (see the bottom of this file).

### ⚠ Known live violation — do not pattern-match off it

```
features/publisher-pages/components/directory/PublisherDirectoryCard.tsx:31
  <Card className="h-full transition-colors hover:border-primary/50">
```

The bookseller-facing publisher tile is a shadcn `Card` with a border that hovers to the app's
primary. That breaks three marketing-charter rules at once, and it has been live on a
retailer-facing route since the directory shipped.

This matters because **code generation matches the majority pattern**, and this file is the
nearest example for any new directory tile. If you are adding to the directory, do not copy it.
Fixing it is a small, well-scoped change if you are already in that area.

---

## Design tokens — pointer, not a copy

The authoritative token vocabulary is a role→class table in:

```
<WT>/Treeline.Clients.EdelweissComponents/packages/apps/omnibus/CLAUDE.md
```

It auto-loads only when your session's cwd is at or below `packages/apps/omnibus/`, so from a
worktree root you must Read it. Use `bg-background` / `text-foreground` / `bg-card` /
`text-muted-foreground` / `border-border` / `ring-ring` rather than hand-paired
`bg-white dark:bg-gray-800` literals.

Three gotchas from that file that reliably bite, worth carrying here:

1. **The numbered `primary-50..950` scale is SKY, not the indigo accent.** Only the bare
   `primary` DEFAULT is indigo. Do not "fix" `bg-primary-600` to indigo — thousands of usages
   depend on it being sky.
2. **The `--vendor-*` layer is a separate token set** for the vendor portal's per-vendor
   theming. Do not fold it into the semantic tokens.
3. **A few literals are sanctioned**, e.g. the Switch thumb stays `bg-white` so the knob is
   white in both modes, and modal scrims stay `bg-black/30`.

**Migration policy is migrate-on-touch.** Legacy Omnibus UI outside the shadcn areas keeps its
existing Tailwind + Headless UI patterns. Replace when you are already editing a surface; never
bulk-migrate. The same applies to `Drawer.tsx` → `ui/sheet` and `AccessibleModal` → `ui/dialog`.

---

## The accessibility bar

Omnibus has **no recorded contrast standard**. The Storefront does, and it is the house
precedent — treat it as the bar for new work rather than inventing one:

- **WCAG 2.2 AA.** 4.5:1 for normal text; 3:1 for large text, UI components and focus indicators.
- Recorded in `~/source/repos/<WT>/Treeline.Workspaces/Storefront/docs/decisions/`, ADRs
  **0020** (colour tokens conform to AA) and **0022** (store-colour contrast floor).
- Enforced there by a real Jest suite that reads shipped token values —
  `packages/apps/storefront/src/lib/tokens.contrast.test.ts`, `color-contrast.test.ts`,
  `clamp-store-color.test.ts`.
- Note the pattern worth reusing: a focus indicator gets its **own** token, because a single
  value cannot satisfy both "white text on this fill clears 4.5:1" and "this ring clears 3:1
  against the page background."

If you are picking any new colour pair in any app, check it against these thresholds.

---

## Other apps — do not apply Omnibus guidance to them

| App | System | Guidance |
|---|---|---|
| `omnibus` | Tailwind + Headless UI (legacy) · shadcn (workflow) · SectionKit (marketing) | This file |
| `storefront` | Tailwind + shadcn | Storefront ADRs 0016/0018/0020/0022 |
| `edelweiss` | Material UI + SCSS modules | Its own system — intentionally separate |
| `advertising` | Ant Design + LESS | Its own system — intentionally separate |
| `ingest`, `reader` | Tailwind | No recorded standard. Follow Omnibus token discipline and say that you did |
| `internal-tools` | Not assessed | Ask before assuming |

---

## Do not trust these sources

| Source | Problem |
|---|---|
| `Treeline.Clients.EdelweissComponents/README.md` → "Styling notes" | Still SCSS-modules-first with no mention of Tailwind. Stale. ESLint now **errors** on new SCSS modules. Its MUI-portal / `EdelweissComponentRoot` rule and font-constant rule are still valid |
| `Treeline.Clients.EdelweissComponents/docs/design-system.md` | Duplicates the token table and contradicts migrate-on-touch policy. Do not follow it; prefer `packages/apps/omnibus/CLAUDE.md` |
| `Treeline.Clients.EdelweissComponents/docs/temp/proposed-skill-update-*.md` | 24 unapplied drafts. Explicitly marked not-deployed. Useful as evidence, never as instruction |
| `cc` plugin `code-standards/references/frontend-react.md` | Still shows `.module.scss` in its file-naming example |

Note the near-collision: `packages/apps/omnibus/docs/design-system/` is a **directory** holding
the register strategy; `docs/design-system.md` two levels up is the **file** you should not
trust.

---

## Standalone deliverables are a different job

Reports, one-pagers, dashboards, findings pages, published Artifacts — neither charter governs
these, and neither register applies. Use the `design-standards` skill instead.

---

## What this local layer cannot do

State this plainly rather than over-trusting it:

- **It substitutes agent discipline for a lint rule, which is strictly weaker.** A lint rule
  fails the build; this file only works if it is read and followed. The marketing register still
  has no machine check.
- **It cannot resolve the lint/charter conflict** — only a path-keyed rule split can.
- **It is one person's local setup.** Nothing here is shared with the team, so a teammate's
  session has none of it.

## When this is ready to push to the team

The team-level changes this local layer is standing in for, in priority order:

1. **Split the ESLint override by register** — `components/{landing,blocks,directory}/**` gets a
   marketing ruleset (ban `ui/button`/`ui/card`, ban `border` as container and `bg-white`/
   `bg-card`, ban the `primary` token family, keep the arbitrary-colour ban, drop the
   raw-control ban); everything else under `publisher-pages/**` keeps the workflow one. Start at
   `warn`, fix the directory card, ratchet to `error`. Ship with a narrowly-scoped escape hatch
   for legitimate admin primitives in error/empty states.
2. **Fix `PublisherDirectoryCard.tsx:31`** — the natural first test of that rule.
3. **Resolve the frontend repo's `.claude/skills` into the workspace skill path** so both
   charters load for everyone, retiring the shouted-reminder layers.
4. **Add a nested `CLAUDE.md` in `features/publisher-pages/`** naming both charters and the
   register test — nested files load from cwd upward, so it works regardless of skill resolution.
5. **Local `CLAUDE.md` for `storefront`, `ingest`, `reader`**; correct the README's styling
   section; add one routing index referenced from the root `CLAUDE.md`.
6. **Port the Storefront contrast suite to Omnibus.** Expect real failures.
