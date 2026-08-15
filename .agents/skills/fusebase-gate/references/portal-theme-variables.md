---
version: "1.0.0"
mcp_prompt: none
source: "docs/portal-theme-variables.md"
last_synced: "2026-08-12"
title: "Portal theme styling (custom CSS override contract)"
category: specialized
---
# Portal theme styling (custom CSS override contract)

> **SOURCE**: This file is copied from `docs/portal-theme-variables.md` in the fusebase-gate repo. Edit that file, then run `npm run mcp:skills:generate`.

---
# Portal theme styling (custom CSS override contract)

To re-brand a portal from an agent, write custom CSS via
`updatePortalCustomCode` (CNAME-domain portals only) targeting the stable
styling hooks below. Gate auto-nests the CSS under the portal root container
`#main-scrolling-container` (so it can't leak into the customizer chrome) — write
plain **relative** selectors, do not prefix them with the container id yourself.

## daisyUI CSS variables do NOT re-brand the portal

The compiled CSS carries the daisyUI v4 variable set (`--p`, `--b1`, `--bc`, …),
but **overriding them re-brands nothing** on the core surfaces. Only ~7 cosmetic
daisyUI widgets consume them (`dui-avatar`, `dui-rating`, `dui-countdown`,
`dui-mask`); the page background, buttons and text are Tailwind **hex** utility
classes, and the theme is scoped by `nim-theme-*` classes on `<body>` that set no
variables. So do not set `--p`/`--b1`/`--bc` — set visual properties directly on
the hooks below.

## Structural hooks — `data-portal` attributes

Prefer these over classes; they never collide with Tailwind utilities and are the
declared public styling surface.

| Selector                       | Region                                   |
| ------------------------------ | ---------------------------------------- |
| `[data-portal="sidebar"]`      | Left navigation sidebar                  |
| `[data-portal="footer"]`       | Portal footer                            |
| `[data-portal="page-card"]`    | Main page column (breadcrumbs + content) |
| `[data-portal="note-content"]` | Page/note content wrapper                |
| `[data-portal="breadcrumbs"]`  | Breadcrumbs navigation                   |
| `[data-portal="search"]`       | Search overlay                           |

## Stable class hooks

Also part of the contract: `header.header`, `.header-wrapper`,
`.header-content`, `.sidebar-menu-item`, `.sidebar-menu-item-active`,
`.mobile-menu-button`, `.container`.

## Example

```css
[data-portal="sidebar"] {
  background: #101828;
}
[data-portal="note-content"] {
  color: #1d2939;
}
```

## Anti-contract (do NOT target)

- daisyUI theme variables (`--p`, `--b1`, …) — present but consumed only by a few
  cosmetic widgets; overriding them does not re-brand core surfaces.
- Tailwind utility classes (`.flex`, `.bg-white`, …) — implementation detail.
- Hashed / generated class names (e.g. `icon__icon___x`) — unstable between builds.

The machine-readable source of truth for these hooks is
`PORTAL_STYLE_CONTRACT` (`libs/pages/portal-client/src/lib/style-contract.ts` in
nx-frontend), versioned so consumers can detect breaking changes.
---

## Version

- **Version**: 1.0.0
- **Category**: specialized
- **Last synced**: 2026-08-12
