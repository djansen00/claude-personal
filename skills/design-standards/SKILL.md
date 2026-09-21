---
name: design-standards
description: Use when producing ANY standalone visual HTML deliverable — a published Artifact, a status or findings report, a customer-facing one-pager, a release summary, an internal memo, a metrics dashboard, a diagram page, an onboarding doc, a runbook rendered for humans. Codifies the method that makes generated pages read as one consistent system instead of nine different guesses: calibrate the treatment before designing, write a token plan before the code, honor the project's existing system first, theme at the token level, and refuse the specific set of looks that AI-generated design keeps defaulting to. Direction-agnostic — it teaches the method and bans the clichés; each deliverable still picks a palette specific to its subject. NOT for Omnibus product UI (that is docs/design-system.md in Treeline.Clients.EdelweissComponents) and NOT for responsive app/web UI work.
---

# Design Standards — Standalone Visual Deliverables

## Why this skill exists

Agents produce a lot of HTML that humans actually look at: findings reports, feedback
summaries, release notes, QA writeups, dashboards, one-pagers for merchants. Left
unguided, each one is designed from scratch and the results diverge — different greys,
different type, a giant hero on a two-paragraph memo, a page that is unreadable in dark
mode because the only definition of its text color sat inside a `@media` block.

The fix is not a template. A template makes every deliverable look the same regardless
of what it is, which is its own failure. The fix is a **method**: a small number of
decisions forced to happen *before* any markup is written, plus an explicit list of the
defaults to refuse.

These rules apply to standalone pages. For Omnibus product UI, the existing token system
governs — see `Treeline.Clients.EdelweissComponents/docs/design-system.md`.

## The rules

### 1. Calibrate the treatment before you design anything

The question is never *whether* to design — it is *which treatment the subject earns*.
There are two, and picking the wrong one is the most visible failure mode.

**Utilitarian** — a plan, a memo, a findings report, a QA summary, a runbook. Most
internal deliverables. Real typographic hierarchy, considered spacing, a proper palette,
and nothing else. No oversized hero. Flourishes stay tasteful and rare.

**Editorial** — a customer-facing one-pager, a launch summary, something that will be
shared outside the team or kept. Here you take a point of view, and spend one real
aesthetic risk where it serves the subject.

A two-paragraph status update with a full-viewport gradient hero is the single most
common tell that nobody made this call. When unsure, choose utilitarian: a well-composed
page is never wrong; an over-designed one sometimes is.

### 2. Write the token plan before the code

Do not open with markup. Write down, in three lines:

- **Color** — the palette as 4–6 *named* hex values (`ground`, `ink`, `muted`, `accent`, …).
- **Type** — at least two faces with assigned roles: a display face used with restraint,
  a body face, and a utility face for captions/data if the page needs one.
- **Layout** — the layout concept in one or two sentences.

Then build, deriving every single color and type decision from that plan. Most
inconsistency in generated pages comes from choices accreting one element at a time —
a grey picked for a caption here, another for a border there. Deciding all of them up
front is the whole mechanism.

### 3. Honor what already exists — precedence is fixed

Before choosing anything, look for a system already in play: `CLAUDE.md`, a tokens or
theme file, existing component styles. When one exists, apply it. This skill fills gaps;
it never overrides.

Precedence, always in this order:

1. The user's own words — if they named a direction, follow it exactly, **including** when
   they ask for one of the looks banned in rule 6.
2. The project's existing system.
3. Your choices.

### 4. Theme at the token level, and remember there are three states

This is where most "broken-looking page" bugs live. A viewer is in one of three states,
not two:

- `data-theme="dark"` on the root — explicit dark choice
- `data-theme="light"` on the root — explicit light choice
- **nothing stamped** — the default "system" setting, where only `prefers-color-scheme`
  separates light from dark. Most viewers are here.

So structure the CSS in three layers, and let components read *only* tokens:

```css
/* Right — complete light palette on bare :root, tokens redefined per state */
:root {
  --ground: #fbfaf8;
  --ink: #1c1a17;
  --muted: #6b665e;
  --accent: #7a4b2a;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {   /* explicit light must still beat a dark OS */
    --ground: #14120f;
    --ink: #f2efe9;
    --muted: #9a938a;
    --accent: #d99b6a;
  }
}
:root[data-theme="dark"] {            /* and the toggle must win the other way too */
  --ground: #14120f;
  --ink: #f2efe9;
  --muted: #9a938a;
  --accent: #d99b6a;
}

body { background: var(--ground); color: var(--ink); }
.caption { color: var(--muted); }
```

```css
/* Wrong — the color's ONLY definition sits inside a theme block.
   In the un-stamped state this never applies, and the page renders
   one theme's text on the other theme's ground. */
@media (prefers-color-scheme: dark) {
  .caption { color: #9a938a; }
}
```

Two more rules that keep a theme resolving as a set:

- `body` **must** set an explicit `background` from a token. A transparent body silently
  borrows whatever ground the host paints, in the host's theme, not yours.
- Every element that sets a color takes it from the same token set as the surface behind
  it — never a literal that only happens to work in one theme.

Before shipping, scan the stylesheet for any color declared *only* inside a `@media` or
`[data-theme]` block. That is the classic unreadable-page bug.

A page that deliberately commits to one visual world may stay single-theme — then skip
the media query and the stamps entirely, but still paint background and every color
explicitly so it holds on either host ground. Make that a decision, not an omission.

### 5. Let layout own the spacing

```css
/* Right — one gap governs the rhythm */
.stack { display: flex; flex-direction: column; gap: 1.5rem; }

/* Wrong — per-element margins that silently collapse or double */
.stack > * { margin-bottom: 1.5rem; }
.stack > h2 { margin-top: 2rem; }
```

- Wide content — tables, code blocks, diagrams — gets `overflow-x: auto` on **its own
  container**, so the page body never scrolls sideways.
- `font-variant-numeric: tabular-nums` wherever digits line up in a column.
- Keep running text near 65 characters; give headings `text-wrap: balance`.
- Watch selector specificity. It is easy to generate a type-based class (`.section`) that
  fights an element-based one (`.cta`) over the same padding, and silently undoes your
  spacing.

### 6. Refuse these specific defaults

AI-generated design currently clusters around a small set of looks. Naming them is what
stops the drift. Unless the user asked for one, do not reach for:

- Warm cream (`#F4F1EA`) ground + serif display + terracotta accent
- Near-black with a single acid-green or vermilion pop
- Broadsheet hairline rules with dense columns
- A purple-to-blue gradient hero on white
- Inter or Space Grotesk as the "safe" face
- Emoji as section markers
- Everything centered
- `rounded-lg` on absolutely everything
- An accent bar or rail down the side of rounded cards

Also: choose the neutral, don't inherit it. A pure mid-grey reads as unconsidered; a grey
carrying a slight hue bias toward the page's accent reads as chosen. Pure white and
near-black are fine *grounds* — the point is that they were picked.

### 7. Structure must encode something true

Eyebrows, dividers, labels, and numbered markers are information, not decoration.
`01 / 02 / 03` is right only when the content genuinely **is** a sequence — a real process,
or a timeline where order carries meaning the reader needs. Numbering three unordered
findings tells the reader something false about them.

### 8. Copy is design material

Write from the reader's side of the screen. Name things the way the person recognizes
them, not the way the system is built — a merchant manages *notifications*, not *webhook
config*. Active voice. A control says exactly what happens (`Publish`, then a toast that
says `Published`). Errors say what went wrong and how to fix it — no apology, no vagueness.
Specific beats clever. Never ship lorem; build with real content throughout.

### 9. Name the page like a product, not a caption

The `<title>` is the deliverable's name in a tab and in the Artifact gallery, sitting
beside dozens of others. Give it a short noun phrase, typically two to four words,
specific to the subject — or, for a page that exists to answer one question, that
question. Stop at the name: a title carrying its own explainer after a dash or colon
reads as filler. The explanation goes in the publish `description` instead.

```
Right:  Receiving Sync Failures
Wrong:  Receiving Sync Failures — An Investigation Into Root Causes
Wrong:  Status Report          (could sit on any page in the gallery)
```

When a candidate pairs a real name with a generic word, keep the **name** and drop the
generic half — trimming the other way produces exactly the title that fits any page.

### 10. When it's a UI, not a document

A dashboard or tool is scanned and operated, not read top to bottom, so the craft shifts
from typography to information design:

- Summary before detail.
- Encode state in **form** as well as number — a pill, a chip, a severity stripe — so what
  needs attention reads at a glance.
- Semantic color (good / warning / critical) is a separate axis from the accent hue, and
  does not count as your accent.
- Give sparklines and charts real care: an area fill, a faint grid, an emphasized endpoint.
  For anything chart-shaped, load the `dataviz` skill.
- What is interactive must look interactive.

## Pre-ship checklist

- [ ] Treatment called explicitly: utilitarian or editorial
- [ ] Token plan written before the markup, and every color/type choice traces to it
- [ ] Existing project system checked and applied where one exists
- [ ] Complete light palette on bare `:root`; dark redefines **tokens only**, in both the
      `prefers-color-scheme` and `[data-theme="dark"]` forms
- [ ] No color declared only inside a `@media` or `[data-theme]` block
- [ ] `body` paints an explicit token background
- [ ] Spacing via flex/grid `gap`; wide content wrapped in `overflow-x: auto`
- [ ] `tabular-nums` on every column of digits
- [ ] Checked against the rule 6 list
- [ ] Numbering/eyebrows encode something true
- [ ] Real content, no lorem; copy in the reader's vocabulary
- [ ] `<title>` is a specific two-to-four-word name with no appended explainer
- [ ] Visible keyboard focus state; `prefers-reduced-motion` respected
- [ ] Every non-void element closed, every attribute double-quoted
