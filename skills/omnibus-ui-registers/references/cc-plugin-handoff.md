# Handoff — Add a `design-standards` skill to the cc framework plugin

**For:** whoever maintains the cc plugin
**Repo:** `Treeline.AI.Claude` — https://dev.azure.com/abovethetreeline/Above%20The%20Treeline/_git/Treeline.AI.Claude
**Source to copy from:** `Treeline.Workspaces/Omnibus/.claude/skills/design-standards/SKILL.md`
(in the `CatalogManager` worktree; already working and registered locally)

---

## What and why

Claude Code ships a built-in `artifact-design` skill that fires before it writes any
HTML for a published Artifact. It is why those pages come out consistently clean. It is
internal to the binary — not a file, not something we can reference or extend, and it
**only** loads for Artifact publishes.

That leaves a real gap. Agents in our workflows generate a lot of HTML that never goes
through an Artifact publish: findings reports, QA writeups, release summaries, feedback
investigation output, dashboards, customer one-pagers. Those get designed from scratch
every time, and they diverge — different greys, different type, a full-viewport hero on a
three-paragraph memo, pages that are unreadable in dark mode.

The proposal is a `design-standards` skill in the cc plugin so every Treeline repo gets
the same discipline, not just the ones where someone happened to write it down.

It is **not** a template or a stylesheet. It is a method: force a small number of
decisions to happen before any markup exists, and name the specific defaults to refuse.
Direction-agnostic by design — each deliverable still picks a palette specific to its
subject, so output does not become uniformly beige.

## What it contains

Ten rules, each with Right/Wrong examples, plus a pre-ship checklist:

1. Calibrate the treatment first — utilitarian vs editorial (this is the fork that stops
   memos getting landing-page treatment)
2. Write the token plan before the code — 4–6 named hex, 2+ typefaces with roles, layout
   in a sentence
3. Honor the existing project system; fixed precedence (user's words → project system →
   your choices)
4. Theme at the token level, three viewer states — the single biggest source of
   broken-looking pages
5. Layout owns spacing (flex/grid `gap`, `overflow-x: auto`, `tabular-nums`, 65ch measure)
6. Refuse a named list of AI-design clichés
7. Structural devices must encode something true (no `01/02/03` on unordered content)
8. Copy is design material
9. Name the page like a product, not a caption
10. UI vs document — information design when it's operated, not read

## How to add it

Skills are **auto-discovered** from `./skills/` — `plugin.json` lists only `agents`, so
no manifest edit is needed.

```
skills/design-standards/SKILL.md
```

Copy the source file, then make the three changes below. Bump `plugin.json` version and
`VERSION`.

### Required change 1 — genericize the Omnibus reference

The local copy's frontmatter and body point at
`Treeline.Clients.EdelweissComponents/docs/design-system.md`. That path does not exist in
other repos. Replace with the conditional form:

> NOT for product UI where the repo already has a documented design system — that system
> wins. Check for a `docs/design-system.md`, a tokens/theme file, or design guidance in
> `CLAUDE.md` first.

Rule 3 (precedence) already encodes this correctly and needs no change.

### Required change 2 — reconcile with the existing `code-standards` skill

`design-standards` is a deliberate sibling to `code-standards`: same shape, different
axis (one is code quality, one is visual output). Worth a cross-reference line in each so
they are not mistaken for overlapping. They do not conflict — no rule in one touches the
other's subject.

### Required change 3 — decide whether `code-reviewer-design` should cite it

`agents/code-reviewer-design.agent.md` currently reviews architecture and SOLID. If we
want generated UI held to these rules at review time, that agent should load
`design-standards` when the diff touches markup or styles. **Recommend deferring this**
until the skill has run for a few weeks — adding it to the review gate before we know how
it behaves in practice risks noisy findings on legitimate design choices.

## Scoping note

Keep the plugin version direction-agnostic. If we later want a fixed Treeline house
palette and type pairing for customer-facing output, that belongs in a **separate**
skill that layers on top — not baked into this one. Baking a house style into the
method skill would make every internal one-pager look like marketing collateral, which is
the templated-output failure mode this is meant to prevent.

## Related work landed alongside this

`Treeline.Clients.EdelweissComponents/docs/design-system.md` — the product-UI counterpart.
Documents the three color systems that coexist in the Omnibus frontend
(`--vendor-*`, the ATL16821 shadcn semantic tokens, and the legacy numbered `primary-NNN`
sky scale), and records the measured adoption gap: 9,938 hand-paired
`text-gray-N dark:text-gray-N` literals against 246 uses of `text-muted-foreground`.
That doc is Omnibus-specific and should **not** move into the plugin.
