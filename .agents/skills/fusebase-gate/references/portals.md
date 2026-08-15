---
version: "1.98.0"
mcp_prompt: portals
last_synced: "2026-08-11"
title: "Fusebase Gate Portals Operations"
category: specialized
---
# Fusebase Gate Portals Operations

> **MARKER**: `mcp-portals-loaded` — When this marker is present in context, MCP prompts for this topic may skip conceptual sections and use API reference only.

> **VERSION CHECK**: If operations fail unexpectedly, load MCP prompt `portals` for latest content.

---
## Table of contents

- [Fusebase Gate Portals Operations](#fusebase-gate-portals-operations)
- [Relevant Operations](#relevant-operations)
- [Portal page and folder permissions](#portal-page-and-folder-permissions)
- [Portal block presentation](#portal-block-presentation)
  - [Appearance](#appearance)
  - [Layout](#layout)
  - [Content](#content)
- [Draft Staging Rule (read before any write)](#draft-staging-rule-read-before-any-write)
- [Publish Permission Rule (read before every publish)](#publish-permission-rule-read-before-every-publish)
- [Portal Roles And The Customizer/Portal Distinction](#portal-roles-and-the-customizerportal-distinction)
- [Identity And Scoping Rules](#identity-and-scoping-rules)
- [Operation Sequence Rules](#operation-sequence-rules)
- [Read Flow Rules](#read-flow-rules)
- [listPortalContent Flow Rules](#listportalcontent-flow-rules)
- [Editing an existing portal block](#editing-an-existing-portal-block)
- [updatePortalNoteBlock](#updateportalnoteblock)
- [updatePortalHeadingBlock](#updateportalheadingblock)
- [updatePortalTextBlock](#updateportaltextblock)
- [updatePortalImageBlock](#updateportalimageblock)
- [updatePortalEmbedBlock](#updateportalembedblock)
- [updatePortalDatabaseBlock](#updateportaldatabaseblock)
- [updatePortalCardBlock](#updateportalcardblock)
- [updatePortalCarouselBlock](#updateportalcarouselblock)
- [updatePortalCountdownBlock](#updateportalcountdownblock)
- [updatePortalBpmnDiagramBlock](#updateportalbpmndiagramblock)
- [updatePortalDynamicTableBlock](#updateportaldynamictableblock)
- [updatePortalRecentFilesBlock](#updateportalrecentfilesblock)
- [updatePortalLinkedBlock](#updateportallinkedblock)
- [updatePortalFormBlock](#updateportalformblock)
- [updatePortalCardGroupBlock](#updateportalcardgroupblock)
- [updatePortalInfoBlock](#updateportalinfoblock)
- [updatePortalCustomWidgetBlock](#updateportalcustomwidgetblock)
- [updatePortalHtmlCssBlock](#updateportalhtmlcssblock)
- [updatePortalTimelineBlock](#updateportaltimelineblock)
- [updatePortalFileUploaderBlock](#updateportalfileuploaderblock)
- [updatePortalChatBlock](#updateportalchatblock)
- [updatePortalAppBlock](#updateportalappblock)
- [updatePortalAiAgentBlock](#updateportalaiagentblock)
- [movePortalBlock](#moveportalblock)
- [deletePortalBlock](#deleteportalblock)
- [Portal Fields](#portal-fields)

---
## Fusebase Gate Portals Operations

These operations manage organization portals exposed by Gate.
A portal is a client-facing site (notes, pages, apps) served on a portal
subdomain or a custom CNAME domain. The customizer is the editor surface
where a portal is built and published; the portal is the published
end-user view of that content.

## Relevant Operations

Read:
- listPortals: returns all portals visible to the caller in the organization.
- getPortal: returns detailed information for a single portal by its ID.
- listPortalContent: returns the menu tree of a portal (folders, pages, system items), each with its full `path`.
- listPortalAiAgents: search or browse the org's AI agents for the AI Agent block picker.
- getPortalPageBlockCount: count matching blocks already on a page (published + draft).
- listPortalDatabaseBlockSources: discovers the exact Database/Dashboard/View ids required by addPortalDatabaseBlock.
- listPortalLinkableBlocks: discovers the exact source block ids required by addPortalLinkedBlock.
- listPortalPageBlocks: lists EVERY block of one page in display order — the discovery step before reading, updating, moving or removing a block.
- getPortalBlock: reads ONE block's semantic kind and current public settings — the step before a typed update.
- searchPortalInfoBlockIcons: discovers the exact icon id required by addPortalInfoBlock.

Content & settings (all STAGED in the customizer draft — see Draft Staging Rule):
- updatePortalNoteBlock: edit the title and layout of an existing note-backed block (note, blank, Kanban, task list).
- updatePortalHeadingBlock: edit the content, appearance or layout of an existing Text & Media Heading block.
- updatePortalTextBlock: edit the content, appearance or layout of an existing Text & Media Simple text block.
- updatePortalImageBlock: edit the layout of an existing Text & Media Image block.
- updatePortalEmbedBlock: edit the title, source, link visibility or layout of an existing Embed block.
- updatePortalDatabaseBlock: edit the source view, title, page size, appearance or layout of an existing Database block.
- updatePortalCardBlock: edit the Card Type, content, destination, appearance or layout of an existing Card block.
- updatePortalCarouselBlock: replace Carousel slides or edit its layout.
- updatePortalCountdownBlock: edit Countdown title, target, appearance or layout.
- updatePortalBpmnDiagramBlock: edit BPMN Diagram title, canvas height, appearance or layout.
- updatePortalDynamicTableBlock: edit Dynamic Table title, appearance or layout.
- updatePortalRecentFilesBlock: edit Recent files title, source or layout.
- updatePortalLinkedBlock: change the exact source mirrored by a Linked block.
- updatePortalFormBlock: edit Form title, content, appearance or layout.
- updatePortalCardGroupBlock: edit Card group title, content, appearance or layout.
- updatePortalInfoBlock: edit Info title, image, destination, new-tab behavior or layout.
- updatePortalCustomWidgetBlock: edit Custom widget title, bricks, appearance or layout.
- updatePortalHtmlCssBlock: edit HTML/CSS title, raw code or layout on a verified custom-CNAME portal.
- updatePortalTimelineBlock: edit Timeline view, title, steps, appearance or layout.
- updatePortalFileUploaderBlock: edit File uploader metadata or layout.
- updatePortalChatBlock: edit a Chat widget target, access, title or layout.
- updatePortalAppBlock: edit a published app binding or App block title.
- updatePortalAiAgentBlock: change the exact agent used by an AI Agent block.
- movePortalBlock: reorder an existing block within its own page using a semantic anchor.
- deletePortalBlock: remove an existing block from a page, keeping every backing resource.
- createPortalFolder: create a new empty root folder in the sidebar, topbar or footer.
- createPortalLink: add an external-URL menu item to the sidebar, topbar or footer.
- createPortalPage: create a new EMPTY page in a portal menu bar (no note, no block).
- createPortalPageWithNote: create a new sidebar page backed by a fresh Fusebase note.
- addPortalInternalSpacePage: add an EXISTING Internal Space page (by note id or its URL) to the portal as its own page.
- addPortalNoteBlock: embed an existing portal note as a block on an existing page.
- addPortalBlankNoteBlock: create a new EMPTY note and add it as a block on an existing page.
- addPortalKanbanBlock: add the Customizer's Project management "Kanban" tile — a new note holding a new Kanban board — as a block on an existing page.
- addPortalTaskListBlock: add the Customizer's Project management "Task list" block (a new note with a new task list) to an existing page.
- addPortalTasksDashboardMenuItem: add a root navigation item for the portal's system Tasks dashboard (fixed `/tasks-dashboard`), creating the page and its canonical block when the portal has none.
- addPortalEmbedBlock: add one Embeds & Integrations (iframe/Custom Embed) block to an existing page.
- addPortalDatabaseBlock: add the Customizer's "Database" block (a Database table/view or a shared Dashboard source) to an existing page.
- addPortalBpmnDiagramBlock: add the Customizer's "BPMN Diagram" block (an empty BPMN process canvas) to an existing page.
- addPortalDynamicTableBlock: add the Customizer's Dynamic "Table" block (an unconfigured HubSpot/Asana/monday.com integration table) to an existing page.
- addPortalHeadingBlock: add a Text & Media Heading block to an existing page.
- addPortalTextBlock: add a Text & Media Simple text block to an existing page.
- addPortalImageBlock: add a Text & Media Image block to an existing page.
- addPortalCardBlock: add the Customizer's Content display "Card" block to an existing page.
- addPortalInfoBlock: add the Customizer's Content display "Info block" tile to an existing page.
- addPortalCardGroupBlock: add the Customizer's Content display "Card group" block (a row of small linked cards) to an existing page.
- addPortalFormBlock: add the Customizer's Content display "Form" block to an existing page.
- addPortalCountdownBlock: add the Customizer's Content display "Countdown" block to an existing page.
- addPortalCarouselBlock: add the Customizer's Content display "Carousel" block to an existing page.
- addPortalRecentFilesBlock: add the Customizer's File management "Recent files" block to an existing page.
- addPortalFileUploaderBlock: add the Customizer's File management "File uploader" block to an existing page.
- addPortalFilesDashboardMenuItem: add a root navigation item for the portal's system Files dashboard (fixed `/files-dashboard`), creating the page and its canonical block when the portal has none.
- addPortalLinkedBlock: add the Customizer's Custom "Linked block" (a live copy of another page's block) to an existing page.
- addPortalCustomWidgetBlock: add the Customizer's Custom "Custom widget" block to an existing page.
- addPortalHtmlCssBlock: add the Customizer's Custom "HTML/CSS block" to an existing page (custom-CNAME-domain portals only).
- addPortalTimelineBlock: add the Customizer's Project management "Timeline" block to an existing page.
- listPortalChatChannels: list a portal's chat channels for the Chat block picker.
- listPortalChatUsers: search or browse a portal's DM target users for the Chat block picker.
- addPortalChatBlock: add a Chat widget block (channel or DM) to an existing page.
- addPortalChatsDashboardMenuItem: add a root menu item pointing at the portal's EXISTING system Chat dashboard page (`/chats-dashboard`); it never creates the page or the block.
- addPortalAiAgentBlock: add an AI Agent block to an existing page.
- addPortalAppPage: add a published app as a NEW sidebar page (embed).
- addPortalAppBlock: add a published app as one block to an EXISTING page.
- duplicatePortalItem: copy a folder or page (and a folder's subtree) within a portal.
- updatePortalItem: rename / re-icon / show-hide / reorder / move a menu item between bars.
- deletePortalItem: delete a menu item (a folder deletes its whole subtree).
- updatePortalAccess: set who may open the portal (access mode).
- updatePortalCustomCode: set custom CSS/JS (CNAME-domain portals only).
- updatePortalHomepage: set the homepage settings (title, sidebar toggles).
- updatePortalStyle: set the portal branding (color theme, logo, favicon).

Applied immediately (NOT staged in the draft):
- setDashboardViewReadonly: allow or restrict editing of a Dashboard View. A global View setting.
- updatePortalContentPermissions: replace or extend the user access list for one
  published portal page or folder, selected by its exact full path. The change is
  applied immediately; it is NOT staged in the customizer draft and does not need
  publishPortalDraft. For a folder, the same permissions are applied recursively
  to every child folder and page.

Publish:
- publishPortalDraft: publish the portal's staged draft to the live portal
  (the programmatic equivalent of the customizer's Publish button).

Members:
- inviteToPortal: invite a user (client, member, or manager) to a portal via a magic link.
- bulkInviteToPortal: invite MANY users to ONE portal in a single call (use instead of looping inviteToPortal).
- invitePortalManager: shortcut to invite a portal manager (customizer access) via a magic link.

Creating portals themselves (createPortal, duplicatePortal, createWorkspace) is
covered by the separate `portals-create` prompt group.

## Portal page and folder permissions

Use updatePortalContentPermissions to control access to one published portal page
or folder by email. Pass the exact full `path`, for example `/inspiration-page`
or `/docs/start`. If the path is unknown, call listPortalContent first and use
`items[].path`; do not reconstruct a nested path from `slug`.

Choose the mode strictly from the user's wording:
- `replace`: use when the user says "only", "only these users", "restrict to",
  or otherwise asks to replace the current access list. Existing user access is
  removed and only the supplied emails remain in the client-facing item ACL.
- `add`: use when the user says "add", "also give access", or otherwise asks to
  extend access. Existing user access must remain unchanged. Never translate an
  add request into replace.

The operation resolves emails and creates a targeted portal membership when
needed. Do NOT call inviteToPortal first: a full-access portal invite can grant
access to every private page, which is broader than the user's request.

The path is resolved before anything is created, so a call that fails invites
nobody. Fix the path and retry; there is nothing to clean up.

Permissions are applied immediately. Do NOT call publishPortalDraft after this
operation. A folder update affects its entire subtree. Item permissions are an
additional restriction and never bypass portal-level access or workspace
membership. Portal owners and users with console access retain their
administrative access even when mode is `replace`.

If `add` targets an item that is already open to everyone, the operation is a
successful no-op because that user already has access. Do not silently make the
item private.

## Portal block presentation

When an operation supports presentation options, it may expose Appearance, Layout, Content, or a subset of them. Omit an optional group unless the user asks to change it; the operation's documented default then applies.

### Appearance

When an operation supports `appearance`, it configures the Customizer Appearance section. Omit it unless the user asks to change presentation; the operation's documented default then applies.

Backdrop type is `none`, `blank`, or `custom`. For a custom color use a Tailwind palette token, for example `red-200` or `orange-900`, never HEX. If the user says only “red”, ask for the shade (50–950); normalize “red 200” to `red-200`. Do not ask about or set opacity/transparency. A gradient uses two Tailwind tokens. For an image use only the exact preset or existing asset id explicitly supported by the operation; never upload an image, invent an asset id/URL, or send CSS classes/raw styles. Padding and Show title are sent only when the operation's appearance schema supports them.

### Layout

When an operation supports `layout`, it configures the Customizer Layout section. The common controls are Width — one of 2, 3, 4, 5, or 6 columns — and Height — `Auto` (`height: null`) or `Manual` (`height` is a pixel value). Use the operation's documented limits and defaults for manual height. `rowspan`, row placement and responsive values are block-specific: send them only when the operation contract explicitly exposes them.

### Content

When an operation supports `content`, send its text settings inside the `content` object; never put them at the request root. Supported fields are defined by the operation contract. For Heading and Simple text they are `content.text`, `content.color`, `content.size`, `content.styles` and `content.align`.

`content.text` is plain text, not HTML, Markdown, CSS or Tailwind classes. Preserve only `{{ClientName}}` and `{{ClientLastName}}` literally; do not invent or resolve variables. `content.size` is `s`, `m`, `l`, `xl`; `content.styles` is a unique array containing `bold`, `italic`, `underline` and/or `lineThrough`; `content.align` is `left`, `center`, `right`, `justify`.

`content.color` is one palette token: `transparent`, `white`, `black` or `<hue>-<shade>`. Hues: slate, gray, zinc, neutral, stone, red, orange, amber, yellow, lime, green, emerald, teal, cyan, sky, blue, indigo, violet, purple, fuchsia, pink, rose. Shades: 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950. Never send HEX, CSS, opacity or internal theme tuples/classes. A bare hue such as `red` is ambiguous: ask for the shade; normalize `red 200` to `red-200`. Ask for explicit confirmation before using `transparent`.

Content text and the block wrapper title are different. Do not use `content.text` as a wrapper title unless an operation explicitly says so.

Structured Content uses these standard groups only when the operation explicitly lists them:

#### Content.Image
`content.image.visible`. Never send src, URL, upload data, file name, base64, local path, or an invented asset id.

#### Content.Heading
`content.heading.visible`, `content.heading.text`, `content.heading.color`, `content.heading.size`, `content.heading.styles`, and `content.heading.align`.

#### Content.Description
`content.description.visible`, `content.description.text`, `content.description.color`, `content.description.size`, `content.description.styles`, and `content.description.align`.

#### Content.Button
`content.button.visible` and `content.button.text`. The Button label is ALWAYS `content.button.text`; there is no `label` field and sending one is rejected with 400. A Button URL is not part of this group unless the operation explicitly exposes one.

#### Content.Destination URL
`content.destination`, using only a semantic destination form explicitly supported by the operation. Never send raw DynamicLink fields.

#### Content.Items
`content.items` — the FULL desired list in visual order, never a partial patch: sending it replaces the operation's default items. Use the operation's own count limits. Each item carries only the semantic fields that operation lists; the item index comes from the array position, so never send an index, id, `src`, media URL/asset id, raw DynamicLink or raw brick JSON. An item field left out is absent from the created item.

`visible` defaults to `true`, so a visible Content item does NOT need `visible: true` — send its settings alone, for example `content.button: {text: "Open"}`. Send `visible: false` only to hide an item, and then send no other field for that same item. Hiding keeps the canonical item disabled; it does not delete a raw brick. Never send `enabled`, brick ids, indexes, brick types, or raw brick JSON.

The only dynamic variables are `{{ClientName}}` and `{{ClientLastName}}`. Preserve these exact tokens in the text; they are resolved for the portal user when the block is rendered. Do not invent variables or substitute a client's personal data while writing a block. If the user requests another `{{...}}` variable, ask them to revise the text.

An action label and its Destination are separate. Send a Button label or link only when the operation explicitly exposes it. Button text is plain text and does not support dynamic variables unless the operation says so. Never send a raw DynamicLink, numeric internal link type, caller-supplied internal page title/path, targetId, open/error flags, or renderer fields.

For a semantic Destination use only a form supported by the operation: an exact pageId in the same portal, an absolute HTTPS URL, or an email address. portal-service validates an internal page against effective portal state and builds its canonical title and URL. Never send javascript:, data:, a protocol-relative URL, URL credentials, HTML, or CSS. Send null for no link only when the operation explicitly allows it. Do not choose the link target unless the operation exposes that setting.

`block.title` (the wrapper title) and Content.Heading are different. Set the wrapper title only when the operation exposes it and the block shows a title; use `content.heading.text` for the visible heading inside a structured block.

The operation contract is authoritative: it defines whether Appearance, Layout or Content is available and the exact allowed fields and values.

## Draft Staging Rule (read before any write)

- Every content and settings write (createPortalFolder, createPortalPage, createPortalPageWithNote,
  addPortalInternalSpacePage,
  addPortalNoteBlock, addPortalBlankNoteBlock, addPortalEmbedBlock, addPortalChatBlock,
  addPortalChatsDashboardMenuItem,
  addPortalAiAgentBlock, addPortalDatabaseBlock,
  addPortalBpmnDiagramBlock,
  addPortalDynamicTableBlock,
  addPortalHeadingBlock, addPortalTextBlock, addPortalImageBlock, addPortalCardBlock,
  addPortalInfoBlock,
  addPortalCarouselBlock, addPortalCountdownBlock, addPortalFormBlock,
  addPortalFileUploaderBlock, addPortalRecentFilesBlock,
  addPortalFilesDashboardMenuItem,
  addPortalKanbanBlock, addPortalTaskListBlock,
  addPortalTasksDashboardMenuItem,
  addPortalLinkedBlock,
  addPortalTimelineBlock,
  addPortalCardGroupBlock, addPortalAppPage,
  addPortalCustomWidgetBlock, addPortalHtmlCssBlock,
  addPortalAppBlock, updatePortalItem, deletePortalItem,
  updatePortalAccess, updatePortalHomepage, updatePortalStyle,
  updatePortalCustomCode) is STAGED in the
  portal's customizer draft. It is NOT published immediately and is NOT yet visible
  on the live portal.
- These operations always return `staged: true` plus the draft `branchId` and the
  assigned sequence number(s).
- EXCEPTION: duplicatePortalItem is applied to the published portal immediately
  (it delegates to portal-service /menus/copy, which deep-clones the inner notes).
  It returns `published: true` and is NOT staged.
- EXCEPTION: setDashboardViewReadonly is not a portal write at all — it changes a
  Dashboard View globally and takes effect immediately, everywhere the View is used.
- After any such call, tell the user the change is PENDING and that a portal manager
  must open the customizer to review and publish it before clients see it.
- This mirrors how the customizer itself works: an agent's edits show up in the
  customizer for the owner to review, exactly like manual edits.
- To publish staged changes WITHOUT opening the customizer, call publishPortalDraft.
  It applies the ENTIRE staged draft (every pending change, including any the owner
  staged manually in the customizer) to the live portal at once — so only publish when
  the user explicitly asks to go live, and prefer letting the owner review in the
  customizer otherwise.

## Publish Permission Rule (read before every publish)

- publishPortalDraft applies the ENTIRE pending draft to the live portal at once,
  not only the most recent change made by the agent. The draft may also contain
  changes that the owner or another user staged manually in the customizer.
- Before EVERY publishPortalDraft call:
  1. Tell the user that the entire pending draft will go live, including manually
     staged customizer changes.
  2. Ask one clear yes/no question requesting permission to publish that draft now.
  3. Wait for the user's explicit confirmation.
  4. Call publishPortalDraft only after an unambiguous affirmative answer.
- Do not infer publish permission from a request to create, update, add, configure,
  continue, or finish portal work, or from a successful staged operation.
- If the user does not confirm, declines, or gives an ambiguous answer, do not call
  publishPortalDraft. Leave the draft pending and suggest reviewing it in the
  customizer.
- Confirmation is single-use and applies only to the current pending draft and one
  publish attempt. Ask again after any new staged change, a 409 stale-draft response,
  re-staging, any failed publish attempt, or before any later publish call.

## Portal Roles And The Customizer/Portal Distinction

When inviting users or reasoning about who sees what, distinguish three roles
(the `orgRole` field on inviteToPortal):
- `client` — an end user who only views portal content. No customizer access.
  Their visibility depends on `isFullAccess`:
    true  = Full access — sees all portal pages, including private ones.
    false = Shared only — sees only public/shared pages.
- `member` — an organization/workspace member. Always full access to portal pages.
  No customizer access by default.
- `manager` — a PORTAL MANAGER: has access to the CUSTOMIZER and can build, edit, and
  publish the portal (layout, settings, widgets, custom code). Always full access.
  Prefer the dedicated invitePortalManager operation to invite one; inviteToPortal
  with orgRole='manager' is equivalent.

Customizer vs portal: the customizer is the admin/editing surface (managers); the
portal is the published view clients see. Widget SETTINGS and the publish action
belong to the customizer (managers only); a client only sees the rendered widget/page.
Because Gate content ops stage into the draft, their effect is visible in the
customizer immediately but on the live portal only after a manager publishes.

## Identity And Scoping Rules

- `orgId` is a required path parameter for all portals operations.
- `portalId` is the opaque portal identifier returned by `listPortals`. Do not invent portal IDs.
- Read operations (`listPortals`, `getPortal`) require `portals.read` permission scoped to the organization.

- inviteToPortal: invites a user to a portal via a magic link (no email confirmation needed).
  Required path params: `orgId`, `portalId`.
  Required body: `email`.
  Optional body fields:
    `orgRole` — role in the organization: 'client' (default), 'member', or 'manager'.
    `workspaceRole` — role in the workspace: 'reader' or 'editor' (default 'editor').
    `isFullAccess` — only relevant when orgRole='client'.
      true  = Full access: user sees all portal pages including private ones (default).
      false = Shared only: user sees only public/shared pages.
      For orgRole 'member' or 'manager' this is always Full access — field is ignored.
  Invarian — access clarification rule for client invites:
    When inviting a client (orgRole='client' or no orgRole specified),
    ALWAYS ask the user before calling: 'Full access (all pages) or Shared only (public pages)?'
    Do not assume a default silently.
    For 'member' or 'manager' — skip the question, always full access.
  Example flow:
    User: 'invite client user@example.com to portal develop'
    MCP:  'What access level? Full access (all pages) or Shared only (public pages)?'
    User: 'Full access'
    MCP:  calls inviteToPortal with orgRole='client', isFullAccess=true
  Returns: magicLink (share with the invitee), url (portal URL), userId.

- bulkInviteToPortal: invites MANY users to ONE portal in a single call.
  Use this instead of calling inviteToPortal N times in a loop (e.g. inviting several clients at once).
  Required path params: `orgId`, `portalId`.
  Required body: `invitations` — a non-empty array, each item with the same fields as inviteToPortal
    (`email` required; optional `fullName`, `orgRole`, `workspaceRole`, `isFullAccess`).
  Optional body fields:
    `concurrency` — max invites processed in parallel (default 5, clamped to 1..5); the rest are queued.
    `background` — when true, returns immediately (status='processing') and runs invites in the background;
      when false (default) waits and returns aggregated results (status='completed').
  Portal discovery runs once for the whole batch (not per invitee).
  Same client access clarification rule applies: if ANY invitation is a client (orgRole='client' or unset),
    ALWAYS ask 'Full access (all pages) or Shared only (public pages)?' before calling, and set isFullAccess per invitee.
  Returns: total, status; for status='completed' also succeeded, failed, results[] (per-invitation
    { email, status: 'success'|'error', magicLink?, url?, userId?, error? }); for status='processing' also accepted.

- invitePortalManager: dedicated shortcut to invite a PORTAL MANAGER (customizer access).
  Required path params: `orgId`, `portalId`.
  Required body: `email`. Optional body: `fullName`.
  Equivalent to inviteToPortal with orgRole='manager', workspaceRole='editor'. A manager
  always has the customizer and full access to all pages, so NO access question is needed
  (unlike a client invite). Returns: magicLink (share with the invitee), url, userId.

- updatePortalAccess: sets who may open the portal.
  Required path params: `orgId`, `portalId`.
  Required body: `accessMode` — one of:
    'open'           — anyone can view, no email required.
    'invite-only'    — only invited users (clients/members/managers); no public access.
    'email'          — visitor must enter an email, no verification.
    'email-verified' — visitor must enter an email and confirm it.
  The change is STAGED in the portal's customizer draft, not published immediately.
  Tell the user the access change is pending and they must open the customizer to
  review and publish it. Returns: accessMode, branchId, seq, staged (always true).

- createPortalFolder: creates a new empty root folder (a portalSection) in a portal menu bar.
  Required path params: `orgId`, `portalId`.
  Required body: `name` — display name of the folder.
  Optional body: `icon` — icon key (default 'folder').
    `positionType` — 'sidebar' (default), 'top' (topbar) or 'footer'.
  Use `listPortalContent` first to avoid creating a duplicate folder.
  The folder is STAGED in the portal's customizer draft, not published immediately.
  Tell the user the new folder is pending and they must open the customizer to
  review and publish it. Returns: folderId, pageId, url, branchId, seqs, staged (always true).

- createPortalLink: creates a menu item that opens an EXTERNAL URL. No page is created,
  so there is nothing to add blocks to. This is the only way to build a topbar or footer
  nav of external links (e.g. Chat / Case Studies / Contact).
  Required path params: `orgId`, `portalId`.
  Required body:
    `name` — display name of the link (max 100 characters).
    `url` — absolute http(s) URL the link opens.
  Optional body:
    `positionType` — 'sidebar' (default), 'top' (topbar) or 'footer'.
    `icon` — icon key (default 'custom_link').
    `openInNewTab` — default true.
    `parentId` — existing folder menu item id to nest the link under. When set,
      the link inherits the parent's bar and `positionType` is ignored.
  The link is STAGED in the portal's customizer draft, not published immediately.
  Tell the user the new link is pending and they must open the customizer to
  review and publish it. Returns: menuItemId, branchId, seqs, staged (always true).

- createPortalPage: creates a new EMPTY page in a portal menu bar.
  Required path params: `orgId`, `portalId`.
  Required body:
    `title` — non-empty page title and sidebar item name (max 100 characters).
  Optional body:
    `parentId` — existing published or active-draft folder/menu item id
      (omit to create the page in the root sidebar).
    `positionType` — 'sidebar' (default), 'top' (topbar) or 'footer'. When
      `parentId` is set the page inherits the parent's bar and this is ignored.
  The service assigns the standard page icon; the caller does not choose it.
  The operation creates only the page node and sidebar menu item. It does NOT
  create a Fusebase note and does NOT add any block. Use createPortalPageWithNote
  when the user asks for a new page that already contains a new document/note.
  The page is STAGED in the customizer draft, not visible on the live portal
  until publishPortalDraft. The returned pageId may immediately be passed to
  semantic block operations (addPortalBlankNoteBlock, addPortalNoteBlock,
  addPortalTaskListBlock, addPortalEmbedBlock). Do not call
  listPortalContent to
  rediscover that draft-only page and do not invent page ids.
  Returns: menuItemId, pageId, url, branchId, seqs, staged (always true).

- updatePortalItem: updates an EXISTING menu item (folder, page, or link) by `itemId`.
  Required path params: `orgId`, `portalId`, `itemId` (from `listPortalContent`).
  Optional body (pass only what changes; at least one is required):
    `name` — rename (also renames the backing page, if any).
    `icon` — icon key.
    `visible` — show (true) or hide (false) the item.
    `index` — 0-based position among its siblings; use this to fix the newest-first
      root ordering (lower index = higher in the bar).
    `positionType` — move to another bar: 'sidebar', 'top', or 'footer'. A nested
      item moves to the root of that bar unless `parentId` names a folder there.
    `parentId` — re-parent under another folder ('' = root). The item follows its
      new parent's bar.
  `parentId` must name an item in the menu that can hold children — a folder,
  note, section, process or page. A link, dashboard, tag list or the home item
  is rejected.
  It may not be the item itself or one of its own descendants. A re-parented
  item moves to the parent's bar together with its whole subtree, so
  `positionType` (when also passed) must match it.
  The item may be PUBLISHED or exist only in the ACTIVE DRAFT: use the exact itemId
  from listPortalContent for a published item, or the menuItemId/folderId returned by
  createPortalPage, createPortalPageWithNote, createPortalFolder or createPortalLink
  for a draft-only one. Draft-created parents work the same way. Never guess ids.
  The change is STAGED in the draft until the user confirms publishPortalDraft.
  Returns: branchId, seqs, staged (always true).

- deletePortalItem: deletes an EXISTING menu item (folder, page, or link) by `itemId`.
  Deleting a folder removes its whole subtree, including items created in the same
  draft. The home item cannot be deleted.
  The item may be PUBLISHED or exist only in the ACTIVE DRAFT: use the exact itemId
  from listPortalContent, or the id its create operation returned. Never guess ids.
  Required path params: `orgId`, `portalId`, `itemId`.
  The deletion is STAGED in the draft until the user confirms publishPortalDraft.
  Returns: branchId, seq, staged (always true).

- createPortalPageWithNote: creates a new sidebar page backed by a freshly created
  Fusebase note (document-style page).
  Required path params: `orgId`, `portalId`.
  Required body: `title` — page title (also used as the backing note's title).
  Optional body:
    `parentId` — id of an existing folder menu item to nest the page under
      (from `listPortalContent`); omit to create the page at the portal root.
    `icon` — icon key for the menu item (default 'page').
    `content` — initial text or html appended to the note after creation.
    `format` — format of `content`: 'text' (default) or 'html'.
  The note is created in the portal's workspace and shared into the portal, then the
  page (page node + note menu item + note content block) is STAGED in the draft.
  Returns: noteId, menuItemId, pageId, url, branchId, seqs, staged (always true).

- addPortalInternalSpacePage: adds an EXISTING Internal Space page (Fusebase note)
  to the portal as its own page — the customizer's "Internal Space Content" tile.
  Required path params: `orgId`, `portalId`.
  Required body: exactly one of
    `noteId` — global id of the existing note, or
    `noteUrl` — the Internal Space page URL the user pasted, e.g.
      https://acme.nimbusweb.me/space/<workspaceId>/page/<noteId>.
  Optional body:
    `title` — page and menu item title (defaults to the note's own title). The
      block header always shows the NOTE's title: publishing backfills it from
      the note's share, so do not promise the user a renamed block.
    `parentId` — id of an existing folder menu item to nest the page under.
    `icon` — icon key for the menu item (default 'page').
    `positionType` — 'sidebar' (default), 'top' or 'footer'; ignored with `parentId`.
  The note must already exist in the portal's workspace; it is shared into the
  portal when the draft is published. Use createPortalPageWithNote for a NEW note,
  and addPortalNoteBlock to embed a note as one more block on an existing page.
  The page (page node + note menu item + `content` block) is STAGED in the draft.
  Returns: noteId, menuItemId, pageId, blockId, url, branchId, seqs, staged.

- addPortalNoteBlock: embeds an EXISTING portal note as a content block on an
  EXISTING page (no new page or sidebar item is created).
  Required path params: `orgId`, `portalId`.
  Required body:
    `pageId` — the target page node id (from `listPortalContent`, the `pageId` field).
    `noteId` — the Fusebase note to embed. The note must already exist in the portal's
      workspace and be shared into the portal (e.g. created via createPortalPageWithNote).
  Optional body: `title` — block title (defaults to the page's current title; keep the
    default to avoid renaming the page).
  The block is STAGED in the draft. Returns: blockId, pageId, branchId, seqs, staged.

- addPortalBlankNoteBlock: creates a new empty Fusebase note and adds it as a
  note block to an EXISTING portal page. This is the programmatic equivalent of
  the Customizer's "Blank Block" action. It does NOT create a new portal page or
  sidebar menu item.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page,
  resolve `pageId` from `listPortalContent`. For a page created in the active
  draft, use the `pageId` returned by the page-creation operation. Do not invent
  page ids.
  Optional body:
    `title` — the block title (default: "New Document").
  The operation creates the note in the portal's workspace, shares it into the
  portal, and stages one `addBlock` change event with block type `note` on the
  target page. The note starts with no content and no note template.
  Use `addPortalNoteBlock` when the note already exists and is already shared
  into the portal. Use `createPortalPageWithNote` when the user asks for a new
  sidebar page backed by a note.
  The block is STAGED in the portal's customizer draft and is not visible on the
  live portal until the draft is published. Returns: noteId, blockId, pageId,
  branchId, seqs, staged (always true).

- addPortalKanbanBlock: creates a new Fusebase note, initialises a Kanban board
  inside it and adds the note as a block to an EXISTING portal page. This is the
  programmatic equivalent of the Customizer's Project management "Kanban" tile.
  It does NOT create a new portal page or sidebar menu item.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page,
  resolve `pageId` from `listPortalContent`. For a page created in the active
  draft, use the `pageId` returned by the page-creation operation. Do not invent
  page ids.
  Optional body:
    `title` — title of the block, its note and its board, non-empty and at most
      100 characters (default: "Kanban").
    `columns` — 1 to 10 column titles, in order, each non-empty and at most 100
      characters (default: "To do", "In progress", "Done").
  The board is created EMPTY: this operation adds no tasks and there is no way to
  seed them. Portal users add tasks in the board itself.
  Use `addPortalBlankNoteBlock` when an empty note without a board is wanted.
  The block is STAGED in the portal's customizer draft and is not visible on the
  live portal until the draft is published. Returns: noteId, boardId, blockId,
  pageId, branchId, seqs, staged (always true).
- addPortalTaskListBlock: creates a new Fusebase note with a new task list and
  adds it as a note block to an EXISTING published or draft-only portal page.
  Use it when the user asks for the Customizer's "Task list" block from Project
  management. It creates a NEW task list for the new note; it does NOT attach an
  existing note or task list, and it does NOT create a portal page or sidebar
  menu item.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page,
  resolve the exact `pageId` from `listPortalContent`. For a page created in the
  active draft, use the `pageId` returned by the page-creation operation. Never
  invent a page id. No task-list discovery is required because the operation
  creates a new list.
  Optional body:
    `title` — the visible block title (default: "Task list");
    `layout.colspan` — 3, 4, 5, or 6 (default: 6);
    `layout.height` — a manual height of at least 50 or null for Auto
      (default: null).
  Use the shared `Portal block presentation` rules for all Content, Appearance
  and Layout parameters. This operation has no public Appearance settings and no
  public Task list Content settings: do not send colors, wrapper values, tasks,
  assignees, labels, comments, deadlines, note content,
  taskListId, taskListIds, source ids, templateKey, origin, room, raw editor
  operations, blocks, bricks, indexes, CSS, eventJson, dtoJson, or changeEvents.
  `rowspan` is not supported by this operation.
  Use `addPortalBlankNoteBlock` for a new EMPTY note block. Use
  `addPortalNoteBlock` to embed an EXISTING note that is already shared into the
  portal. Use `createPortalPageWithNote` when the user asks for a NEW sidebar
  page backed by a note.
  The operation creates and shares the note, initializes its task list, and
  stages one addBlock change in the Customizer draft. The list starts empty —
  portal users add the tasks. It does not publish the portal. Call
  `publishPortalDraft` separately only when the user explicitly asks to publish.
  Returns: noteId, taskListId, blockId, pageId, branchId, seqs, staged (always
  true).
  Example:
    addPortalTaskListBlock({
      orgId: "org_123",
      portalId: "portal_123",
      pageId: "page_123",
      title: "Launch tasks",
      layout: { colspan: 6, height: null }
    })

- addPortalTasksDashboardMenuItem: adds a ROOT navigation item for the portal's
  SYSTEM Tasks dashboard, which shows each viewer the portal tasks they are
  allowed to access. If the portal has no `/tasks-dashboard` page yet, the page
  and its canonical `tasks-dashboard` block are created in the same batch; if it
  already has one, only the navigation item is added, so several bars can link
  to the same dashboard. Use it when the user wants a Tasks dashboard entry in
  the portal navigation.
  Do NOT use it for a Task list, a Kanban board, a Database dashboard, a selected
  task or a caller-selected page: for those use addPortalTaskListBlock,
  addPortalKanbanBlock or addPortalDatabaseBlock on an existing page.
  Required path params: `orgId`, `portalId`. There is no `pageId` and no
  `parentId`: the item is always a root item and the operation resolves the page
  itself, so do not run page discovery first and do not send pageId, path or
  slug.
  Optional body:
    `title` — the visible item name, also used as the block title when the
      dashboard page is created (default `Task Dashboard`, trimmed plain text
      1..100 characters). The system page title, route and icon stay fixed;
    `positionType` — `sidebar` (default), `top` (topbar) or `footer`.
  No task discovery is needed. Apart from `title` the block has no Content,
  Appearance or Layout settings, and the operation accepts no taskId, taskListId,
  workspaceId, query, sort, limit, permissions, roles, raw blocks, bricks,
  internal ids, CSS, wrapper/theme values, eventJson, dtoJson or changeEvents.
  The renderer obtains the current portal context and applies each viewer's task
  access at runtime; creating the block does not create tasks or widen task
  access.
  Everything is STAGED atomically in the customizer draft. The operation creates
  no task, task list or Kanban board and does not publish the portal. Call
  `publishPortalDraft` separately only when the user explicitly asks to publish.
  Returns: menuItemId, pageId, blockId (only when the page was created), url,
  pageCreated, branchId, seqs, staged (always true).
  Example:
    addPortalTasksDashboardMenuItem({
      orgId: "org_123",
      portalId: "portal_123",
      title: "Client tasks",
      positionType: "sidebar"
    })

- addPortalEmbedBlock: adds one Customizer-compatible Embed block to an
  EXISTING portal page. It does NOT create a page or sidebar item.
  Required path params: `orgId`, `portalId`, `pageId`.
  Required body:
    `title` — non-empty block title;
    `embedType` — one of custom, youtube, google-drive, ms-doc, calendly,
      hubspot, airtable, loom, data-studio, figma, miro.
  For `custom`, pass the URL or embed code in the `content` field; do not send the `url` field.
  For every other type, pass `url` and do not pass `content`. Never construct
  `contentUrl` or an iframe yourself; the service creates the canonical block.
  Optional body:
    `showEmbedLink` — default true;
    `colspan` — 2..6, default 3;
    `rowspan` — 1..4, default 1;
    `height` — positive number or null, default null.
  `hubspot` here is an iframe Embed block, not a Flexible Block integration
  brick. Never put credentials, access tokens, cookies, or private URLs into an
  embed URL/code.
  For a published page, resolve `pageId` from `listPortalContent`. For a page
  created in the active draft, use the `pageId` returned by the page-creation
  operation. Do not invent page ids.
  The block is STAGED in the customizer draft and is not visible on the live
  portal until `publishPortalDraft`.

- listPortalChatChannels: lists a portal's real chat channels (DMs, group DMs and
  hidden channels excluded; default channel first) so a Chat block can target one by
  exact id. Required path params: `orgId`, `portalId`. ALWAYS call this before
  addPortalChatBlock with a channel target — never guess a channel id and never
  assume `general` exists. Returns: channels[] of { id, name, isPublic, isDefault }.

- listPortalChatUsers: lists available DM targets for a portal. Call it before
  addPortalChatBlock when the user wants a direct message.
  Required: orgId and portalId. Optional: query (2..100 characters matched
  case-insensitively against display name, username and email), limit (default
  20, max 50) and the opaque nextCursor from the previous response.
  Returns: users[] of { id, displayName, username?, email }, total (all matches)
  and nextCursor when more pages exist.
  When the person is not known, call it WITHOUT query and with limit 20 to browse.
  Show ONLY the users returned by that one call, listing displayName and email
  (email tells apart two people with the same display name). Then:
    - if nextCursor is present, ask 'Found <total> users. Show the next 20?'
      (say only 'There are more users. Show the next 20?' when total is absent);
    - only if the user agrees, call the operation again with that nextCursor, the
      same query (or still none) and the same limit.
  Never decode the cursor, restart pagination silently, fetch all pages, or
  aggregate the full list before showing results.
  Use the selected exact users[].id as numeric target.userId. Never guess an id
  or reuse an id from another service or an earlier conversation.

- addPortalChatBlock: adds a Chat WIDGET block to an EXISTING page — the programmatic
  equivalent of the customizer's 'Chat' action. This is a chat widget on a page,
  DISTINCT from the portal's system chat menu item and the `chats-dashboard` block.
  Required path params: `orgId`, `portalId`, `pageId`.
  Required body:
    `title`  — non-empty block title.
    `target` — exactly one of `{ type: 'channel', channelId }` (id from
      listPortalChatChannels) or `{ type: 'dm', userId }` (an active org
      member/owner). Ask the user which target type when the intent is unclear.
      For target.type='dm', first call listPortalChatUsers. If no person was
      specified, browse the first page without a query. If the result is empty, say that no
      matching DM target is available; do not call addPortalChatBlock with an
      invented userId.
  Optional body:
    `membersOnly` — channels only (default true; a private channel requires true;
      forbidden for `dm`). `colspan` (3..6, default 6), `rowspan` (1..4, default 1),
      `height` (positive number or null).
  Only ONE active Chat block is allowed per page — a second returns 409 (pick another
  page). The block is STAGED in the customizer draft, not live until the draft is
  published. Returns: blockId, pageId, branchId, seqs, staged (always true).

- addPortalChatsDashboardMenuItem: adds a ROOT navigation item pointing at the
  portal's system Chat dashboard page (`/chats-dashboard`). Use it when the user
  asks for the Chat dashboard from the customizer's Dashboards menu.
  The dashboard page and its block already exist in every portal — they are
  created with the portal — so this operation never creates them. If the portal
  has no `/chats-dashboard` page the request returns 409 and stages nothing:
  report that, do not work around it by adding a raw dashboard block.
  Do NOT use it for a chat widget on an existing page: for a channel or direct
  message widget use addPortalChatBlock after listPortalChatChannels or
  listPortalChatUsers. No channel, DM user, app, note or database discovery is
  needed here.
  Required path params: `orgId`, `portalId`. There is no `pageId` and no
  `parentId`: the dashboard item is always a ROOT item and folders are not
  supported.
  Optional body:
    `title` — the visible navigation name (default `Chat Dashboard`, trimmed
      length 1..100). The page title, icon and route are managed by the service.
    `positionType` — root menu bar: `sidebar` (default), `top` or `footer`.
  DUPLICATES are allowed, as in the customizer: a bar may carry several Chat
  dashboard items, and every one of them points at the same dashboard.
  The item is STAGED in the customizer draft and does not publish the portal.
  Call `publishPortalDraft` separately only when the user explicitly asks to
  publish.
  Returns: menuItemId, pageId, url, positionType, branchId, seqs, staged
  (always true).
  Example: addPortalChatsDashboardMenuItem({ orgId: 'org_1', portalId: 'portal_1',
    body: { title: 'Team chat', positionType: 'sidebar' } }).

- listPortalAiAgents: lists the AI agents available to the caller (the org's own
  agents plus the available default agents). Call it before addPortalAiAgentBlock.
  Required path param: `orgId`. Optional: query (1..100 characters matched
  case-insensitively against the agent title), limit (default 20, max 50) and the
  opaque nextCursor from the previous response.
  Returns: agents[] of { id, title, description?, iconName?, iconColor? } and
  nextCursor when more pages exist.
  When the agent is not known, call it WITHOUT query and with limit 20 to browse.
  Show ONLY the agents that one call returned and let the user pick; never
  auto-pick the first result. If nextCursor is present, ask before fetching the
  next page and pass the same query and limit with it. Never decode the cursor,
  fetch all pages, or invent an agent id.

- getPortalPageBlockCount: universal preflight — how many active blocks of a given
  type a page already carries, counted over the PUBLISHED portal AND its active
  customizer draft (so a block staged earlier in this session counts).
  Required path params: `orgId`, `portalId`, `pageId`. Required query: `type` (a
  canonical portal block type). Optional query: `templateType`, allowed ONLY with
  type='flexible', narrowing by the flexible template.
  Returns: { count }. Never blocks, bricks, ids or draft events.

- addPortalAiAgentBlock: adds an AI Agent block to an EXISTING page — the
  programmatic equivalent of the customizer's 'AI Agent' tile (a flexible block
  with one ai-agent brick). No new page and no sidebar menu item.
  Required path params: `orgId`, `portalId`, `pageId`.
  Required body: `agentId` — the exact `agents[].id` from listPortalAiAgents.
  Nothing else is accepted: the block title is the agent's current title and the
  layout, wrapper and brick are fixed by the service.
  REQUIRED SEQUENCE:
    1. listPortalAiAgents → let the user pick an exact agents[].id;
    2. getPortalPageBlockCount(type='flexible', templateType='ai-agent');
    3. only when count is 0, addPortalAiAgentBlock({ agentId }).
  When the count is greater than 0 the page already has an AI Agent block: pick
  another page or ask whether the existing block should be edited instead — a
  second one returns 400 (not retryable; a 409 means only that the draft moved).
  The block is STAGED in the customizer draft, not live until the draft is
  published. Returns: blockId, pageId, branchId, seqs, staged (always true).
- listPortalDatabaseBlockSources: discovers the exact Database/Dashboard/View ids
  required by addPortalDatabaseBlock. Required path param: `orgId`. Required query:
  `type` — `database` or `dashboard`.
  For `type=database` with no `databaseId`, returns ONE page of databases:
    `databases[]` ({id, title, alias}), `page`, `limit` (always 20), `total` and an
    optional `nextPage`. Optional `query` searches Database title and alias
    case-insensitively — call it with the user's database name instead of paging, e.g.
    query `Canban` returns that Database with its id. If several match, show the titles
    and ask the user to choose. Use `nextPage` only when the user asks for more.
    Never enumerate every Database or invent a database id.
  After a Database is chosen, call the same operation with
    `type=database&databaseId=<id>`: it returns that Database's Tables and each Table's
    Views. A Table id IS the `dashboardId`; pick an exact view id from its `views[]`.
    Do not assume the first View.
  For `type=dashboard`, returns ALL available Dashboard sources (no pagination), each
    with its `views[]` — this is where sources such as All forms appear. Use it after
    the user chooses Dashboard. Never use a Database-bound Table as a Dashboard source.

- addPortalDatabaseBlock: adds an existing Database table/view to an EXISTING portal
  page as the customizer's "Database" block. Supports Type `database`
  (Database → Table → View) and Type `dashboard` (a shared source, e.g. All forms →
  View). It does NOT create a database, dashboard, view, page or sidebar item.
  Required path params: `orgId`, `portalId`, `pageId`.
  Required body: `target` — exact ids returned by listPortalDatabaseBlockSources:
    {type:'database', databaseId, dashboardId, viewId} or
    {type:'dashboard', dashboardId, viewId}. Never infer ids from a name, alias or URL.
    Ask whether the user means Database or Dashboard when it is ambiguous. For Database
    the dashboard must belong to `databaseId`; the view must belong to `dashboardId`.
  Optional body: `title` (default 'Database'); `itemsPerPage` (10, 20, 50, 100, 200,
    500; default 100); `appearance` and `layout` — see `Portal block presentation`.
    This op supports `appearance.backdrop`, `appearance.padding`,
    `appearance.showTitle`, `layout.colspan` and `layout.height`; it does NOT support
    `rowspan`, row placement or responsive layout. Defaults: {backdrop:'blank'},
    padding `m`, showTitle true, colspan 6, height Auto. Manual height is >= 50px.
  To change whether the chosen View is editable, call setDashboardViewReadonly
  separately and explain it affects every use of the View, not just this block.
  The block is STAGED in the draft. Returns: blockId, pageId, branchId,
  seqs, staged.

- addPortalDynamicTableBlock: adds one Dynamic Table block to an EXISTING
  portal page — the programmatic equivalent of the Customizer's `Table` tile
  in the `Dynamic` category. Use this operation when the user asks for a
  dynamic table or says `Table from Customizer`. Do NOT confuse it with
  addPortalDatabaseBlock: Database displays a Fusebase Database Dashboard/View,
  while Dynamic Table is the OAuth integrations table shell.
  Required path params: `orgId`, `portalId`, `pageId`. First resolve the exact
  pageId with listPortalContent, or use the pageId returned by an earlier
  draft page-creation operation. Never invent a page id.
  The body may be empty. Optional body: `title` (default `Dynamic Table`),
  `appearance`, and `layout` with `colspan` 2..6 (default 6) and `height` null
  or at least 50 (default null/Auto).
  Use the shared `Portal block presentation` rules for the `title`, `appearance`
  and `layout` parameters; this operation has no `content` field. An omitted
  `appearance` keeps the blank backdrop with the title shown.
  Version 1 creates the same unconfigured integration shell that Customizer
  creates before Data source selection. It does not connect HubSpot, Asana or
  monday.com and does not accept tokenId, provider source ids, raw mappings,
  filters, sorting, pagination, template or bricks. `configured:false` in the
  response means Data source and fields must still be selected in Customizer.
  If the user requests a configured provider table, explain this limitation
  and create the shell only after the user explicitly agrees to configure it
  manually. Never ask for, guess or pass an OAuth tokenId.
  The change is STAGED in the active Customizer draft and does not publish the
  portal. Call publishPortalDraft separately and only when the user explicitly
  asks to publish.
  Returns: blockId, pageId, branchId, seqs, staged, configured (always false).
  Example: addPortalDynamicTableBlock({ orgId: 'org_1', portalId: 'portal_1',
  pageId: 'page_1', title: 'Client requests', layout: { colspan: 6 } }).

- addPortalTimelineBlock: adds one Customizer "Timeline" block to an EXISTING
  published or draft-only portal page. Use it for a visual ordered sequence of
  project phases, milestones, or steps with completion progress. Do not use it
  for a Task list, Kanban, Carousel, Card group, process state/action, or a new
  portal page.
  See the shared `Portal block presentation` section above. Use the shared
  `Portal block presentation` rules for all Content, Appearance and Layout
  parameters.
  Required path params: `orgId`, `portalId`, `pageId`. For a published target
  page, get the exact pageId from listPortalContent. For a page created in the
  active draft, use the pageId returned by its create operation. Never guess an
  id or substitute a page title/path.
  Optional `view` is `horizontal` (default) or `vertical`. Optional `title` is
  the wrapper title (default `Timeline`) and supports only {{ClientName}} and
  {{ClientLastName}}.
  Omit `content` to keep the Customizer defaults: the built-in image, project
  description, completed Vision and Arrangements steps, incomplete Launch, and a
  View project button.
  Optional `content.image.visible` shows or hides the built-in image. This
  operation cannot select, upload, or accept an image URL, asset id, filename,
  base64, or local path.
  Optional `content.description` supports `visible`, `text`, `color`, `size`,
  `styles`, and `align`. Description text supports only {{ClientName}} and
  {{ClientLastName}}.
  Optional `content.steps` replaces the full step list and must contain 1..6
  steps in visual order. Every step requires `title` of at most 25 characters
  and may contain `completed` plus `destination` or null. Completed steps must
  be consecutive from the start: no completed step may follow an incomplete one.
  Omitted `completed` is false.
  Optional `content.button` supports `visible`, plain `text`, and `destination`
  or null. Button text does not support variables.
  A step or Button destination may use an exact pageId in this same portal, an
  absolute HTTPS URL, or an email address. Resolve an internal destination with
  listPortalContent first, or reuse the id returned when that page was created
  in the active draft. Never send raw DynamicLink fields.
  Optional `appearance` supports the operation's documented semantic backdrop,
  background, padding, and showTitle fields. Optional `layout`: `colspan` is 2,
  3, 4, 5, or 6 (default 6); `height` is null for Auto or a number of at least
  50 for Manual (default null). Never send HEX, CSS, wrapper/theme tuples,
  block/brick/item IDs, indexes, or changeEvents.
  The operation stages exactly one block in the Customizer draft. It does not
  create a page or sidebar item and does not publish the portal. Call
  publishPortalDraft separately only when the user explicitly asks to publish
  the entire pending draft.
  Example:
    addPortalTimelineBlock({ orgId: 'org-id', portalId: 'portal-id',
    pageId: 'page-id', view: 'vertical', content: { steps: [
    { title: 'Plan', completed: true },
    { title: 'Launch', destination: { type: 'portalPage',
    pageId: 'launch-page-id' } } ] } })
  Returns: blockId, pageId, branchId, seqs, staged (always true).

- addPortalHeadingBlock: adds one Text & Media Heading block to an EXISTING
  portal page. Required path params: `orgId`, `portalId`, `pageId`. Required
  body: an object that may be empty `{}` and may contain only `content`,
  `appearance`, and `layout`.
  For their exact fields and values, follow the operation contract and the
  corresponding Content, Appearance, and Layout subsections of `Portal block
  presentation` above. For an image background this operation accepts only
  preset `azure`, `mira`, `solis`, `serenity`, or `glow`, with optional
  `blur`; never send an image URL, asset id, filename, or upload data.
  Defaults: content text "Your Title Goes Here", size `l`, no styles, left
  alignment, blank backdrop, width 6, Auto height. Manual height is >= 50px.
  Do not send HTML, CSS, classes, a wrapper title, or raw bricks. The block is
  STAGED in the draft. Returns: blockId, pageId, branchId, seqs, staged.

- addPortalTextBlock: adds one Text & Media Simple text block to an existing
  portal page. Required path params: `orgId`, `portalId`, `pageId`. Its body
  shape and presentation rules are the same as addPortalHeadingBlock. Defaults:
  content text "Your journey starts here! Add your unique message to engage
  your audience.", size `m`, no styles, left alignment, blank backdrop, width
  6, Auto height. Manual height is >= 50px. The block is STAGED in the draft.
  Returns: blockId, pageId, branchId, seqs, staged.

- addPortalImageBlock: adds one Text & Media Image block to an existing page.
  Required path params: `orgId`, `portalId`, `pageId`. Required body: an object
  that may be empty `{}` and may contain only `layout`.
  It supports only Layout (width 2..6, Auto/manual height), not Appearance,
  Content/text settings or an image source. For Layout, follow the `Portal
  block presentation` rules above; manual height is >= 50px. It always creates
  the Customizer's default stock-image block. Never send an image URL, asset
  id, base64, local path, filename, HTML or raw brick JSON. The block is STAGED
  in the draft. Returns: blockId, pageId, branchId, seqs, staged.

- addPortalCardBlock: adds one Card to an EXISTING portal page and stages it
  without publishing. Required path params: `orgId`, `portalId`, `pageId`.
  Required body: an object that may be empty `{}` and may contain only `view`,
  `content`, `appearance`, and `layout`.
  Before calling this operation, resolve the exact existing target page. If the
  user did not explicitly choose a Card Type, STOP and ask exactly one question:
  "Which Card variant would you like to add?" Show these user-facing choices:
  Card with image, Card with left image, Card with right image, and Card with
  background image. Map them respectively to `top-image`, `left-image`,
  `right-image`, and `fill-image`. Do not silently use the API default
  `top-image`.
  After the Card Type is known, ask whether the user wants the remaining
  Customizer defaults or wants to configure the Card. If they want defaults, send
  only the selected `view` and omit Content, Appearance, and Layout.
  If they want configuration, collect one group at a time and skip every value
  the user already supplied. This operation supports exactly these Content
  properties from `Portal block presentation`:
  1. Content.Image: `content.image.visible`;
  2. Content.Heading: `content.heading.visible`, `.text`, `.color`, `.size`,
     `.styles`, `.align`;
  3. Content.Description: `content.description.visible`, `.text`, `.color`,
     `.size`, `.styles`, `.align`;
  4. Content.Button: `content.button.visible`, `.text`;
  5. Content.Destination URL: `content.destination`, using an exact pageId in
     this portal, HTTPS URL, email, or null for no link;
  6. Appearance: preserve the canonical Card backdrop, or none/blank/custom;
  7. Layout: width 2..6 and Auto/manual height.
  For allowed values, defaults, validation, and safety rules, follow the matching
  Content.Image, Content.Heading, Content.Description, Content.Button, and
  Content.Destination URL subsections of `Portal block presentation` above. Do
  not ask all configuration questions in one message. Do not ask again for a
  choice already stated by the user.
  The Card image uses the built-in template image. This operation can hide it,
  but cannot select or upload another image. Never send an image URL, local
  path, base64, file name, or invented asset id.
  Destination is shared by the whole Card and its Button. Use an exact pageId
  for a page in the same portal, an absolute HTTPS URL, an email address, or
  null for no link. Never send raw DynamicLink fields or numeric internal enums.
  The operation does not control whether the link opens in a new tab.
  Image, Heading, Description, and Button may be hidden with visible: false.
  When hidden, do not send other fields for that item. Heading and Description
  use the common semantic text presentation fields. Button supports only plain
  text and no dynamic variables.
  Appearance omitted preserves the Card's canonical bare wrapper. For an image
  background this operation accepts only preset `azure`, `mira`, `solis`,
  `serenity`, or `glow`, with optional `blur`. Layout defaults to width 3 and
  Auto height; width supports 2 through 6 and manual height is >= 50px.
  The block is STAGED in the draft. Returns: blockId, pageId,
  branchId, seqs, staged.
  A visible Content item does not need `visible: true`; it is the default, so
  send `content.button: {text: "Open"}` to set an enabled Button label. The
  Button label key is `text`, never `label`.

- addPortalCardGroupBlock: adds one Card group — a row of small linked
  cards — to an EXISTING portal page and stages it without publishing.
  Required path params: `orgId`, `portalId`, `pageId`. Required body: an object
  that may be empty `{}` and may contain only `title`, `content`, `appearance`,
  and `layout`.
  Before calling this operation, resolve the exact existing target page. Then
  ask whether the user wants the Customizer defaults (four template cards) or
  wants to define the cards. If they want defaults, send an empty body and omit
  Content, Appearance, and Layout.
  If they want their own cards, collect them one group at a time and skip every
  value the user already supplied:
  1. `content.items`: 1 to 6 cards. Each card takes `title` (the caption, plain
     text, no dynamic variables), an optional `image` and an optional
     `destination`. Ask for the captions and links first; omit `image` unless
     the user names one of the built-in ones.
  2. Content.Description: `content.description.visible`, `.text`, `.color`,
     `.size`, `.styles`, `.align` — the text shown above the cards;
  3. `title`: the wrapper title above the cards, default "Card group";
  4. Appearance: preserve the canonical Card group backdrop, or none/blank/custom;
  5. Layout: width 2..6 (default 4) and Auto/manual height (>= 50px).
  For allowed values, defaults, validation, and safety rules of Description
  follow the Content.Description subsection of `Portal block presentation`
  above, and for a card link follow Content.Destination URL: an exact pageId in
  this portal, an absolute HTTPS URL, or an email address. Omitting a card's
  `destination` keeps the template link of that position; send `null` for a card
  with no link. Never send raw DynamicLink fields or numeric
  internal enums, and the operation does not control whether a link opens in a
  new tab.
  A card image is one of the four built-in tile images only: `calendar`, `book`,
  `pen`, or `briefcase`. Never send an image URL, local path, base64, file name,
  or invented asset id; there is no upload here. Omitting `image` keeps the
  template image of that position.
  Per-card colours, the gap between cards, and their justification are
  customizer-only settings; do not attempt to send them, nor CSS, Tailwind
  classes, or raw brick JSON.
  The block is STAGED in the draft. Returns: blockId, pageId,
  branchId, seqs, staged.

- addPortalCarouselBlock: adds one Customizer Content display "Carousel" block
  to an EXISTING portal page. Use it when the user wants a rotating set of
  visual slides. Do not use it for a single Card, Card group, static Image,
  Hero carousel, or a new portal page.
  For every presentation setting below, follow `Portal block presentation`. In
  particular, use its Content.Items, Content.Destination URL, and Layout rules;
  this operation-specific text only narrows those shared rules to the Carousel
  fields, limits, and defaults.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page, get
  the exact pageId from listPortalContent. For a page created in the active
  draft, use the pageId returned by the page-creation operation. Never guess a
  page id.
  The body is optional settings only. Omit `content` to create the Customizer
  default of three slides: Deliberation, Elaboration, and Presentation, with
  built-in images, descriptions, More buttons, and default links.
  Optional `content.items` replaces the default slide list and must contain 1..6
  items in visual order. Each item may contain `caption`, `description`,
  `button: {text}` or null, and `destination` or null. Destination uses an exact
  pageId in this same portal, an absolute HTTPS URL, or an email address. For an
  internal destination, first resolve the exact page with listPortalContent.
  Description supports only {{ClientName}} and {{ClientLastName}}; Caption and
  Button text support no dynamic variables. The slide surface and its Button
  share the same item destination.
  The operation uses built-in images only. It cannot select, upload, or accept
  an image/video URL, asset id, file name, base64, local path, raw DynamicLink,
  raw item index, brick, CSS class, autoplay, duration, controls, or indicators.
  If the user requires custom media, explain that this create operation cannot
  set it; do not invent or upload media.
  Optional `layout`: `colspan` is 2, 3, 4, 5, or 6 (default 6); `height` is null
  for Auto or a number of at least 50 for Manual (default null). Carousel has no
  public Appearance settings.
  The operation stages exactly one block in the Customizer draft. It does not
  create a page or sidebar item and does not publish the portal. Call
  publishPortalDraft separately only when the user explicitly asks to publish
  the entire pending draft.
  Returns: blockId, pageId, branchId, seqs, staged (always true).

- addPortalCountdownBlock: adds one Customizer-compatible Countdown block to an
  EXISTING portal page. Use it when the user wants a live days/hours/minutes/
  seconds countdown to a future date. Do not use it for a Timeline, calendar
  event, reminder, delayed job, or elapsed-time timer.
  Resolve exact ids first. If `portalId` is unknown, use the portal listing
  flow. For a published page, call `listPortalContent` and use the selected
  exact `pageId`; if several pages match, let the user choose. For a page
  created earlier in the active draft, use the `pageId` returned by the
  page-creation operation. Never guess ids or send a page title/path as an id.
  Required path params: `orgId`, `portalId`, `pageId`.
  The body may be empty. Optional body:
    `title` — wrapper title, default `Countdown`; apply the dynamic-variable
      rules from the shared `Portal block presentation` section above;
    `content.targetAt` — an absolute RFC 3339 date-time with `Z` or an explicit
      UTC offset, for example `2026-08-15T09:00:00+07:00`; default is 30 days
      after creation. It must not be in the past or more than 99 days after
      creation. Never send epoch seconds/milliseconds, a timezone-less local
      date, duration, raw `timestamp`, brick, or renderer style;
    `appearance` — Backdrop `none`, `blank`, or `custom`; omitted keeps the
      canonical blank backdrop with the title shown. A custom backdrop uses the
      shared Portal block presentation rules for background, padding
      (`none|s|m|l`, default `s`) and `showTitle` (default true);
    `layout.colspan` — Width 2..6, default 6;
    `layout.height` — `null` for Auto (default) or a manual pixel value at
      least 50.
  Countdown always contains one fixed countdown item. Its days/hours/min/sec
  labels, boxes style, internal title, ids and order are not configurable.
  Apply the shared `Portal block presentation` section above to `title`,
  `appearance`, and `layout`, including its dynamic-variable, background,
  padding, title-visibility, color-safety, and manual-height rules. The
  `content.targetAt` rules are Countdown-specific and are defined here. Never
  send HEX, CSS, opacity, raw theme tuples, classes, blocks, bricks,
  changeEvents, eventJson, dtoJson, ids, index, batch ids, or client event ids.
  The operation stages the change in the Customizer draft. It does not publish
  the portal. Call `publishPortalDraft` separately only when the user explicitly
  asks to publish.
  Returns: blockId, pageId, branchId, seqs, staged (always true).
  Example: addPortalCountdownBlock with orgId `org_123`, portalId `portal_456`,
  pageId `page_789`, title `Launch`, content.targetAt `2026-08-15T09:00:00+07:00`.

- searchPortalInfoBlockIcons: searches the supported Portal Info block icon
  catalog. Use it before addPortalInfoBlock when the user asks for an Icon
  rather than an Emoji or a Custom image. It does not return SVG content and
  does not modify a portal. The catalog is global: it takes no `orgId` and no
  path params. Optional query: `query` (a short English word for the user's
  concept), `limit` (1..50, default 20) and the opaque `cursor` from the
  previous response. Returns: items[] of { id, label }, total, and nextCursor
  when more pages exist. Use the exact returned `id` as `image.iconId`; never
  invent one or derive it from a label. If one result clearly matches,
  continue; if several materially different results match, show their labels
  and ask one short question. Example: searchPortalInfoBlockIcons({query:
  "user"}).

- addPortalBpmnDiagramBlock: adds one empty Customizer-compatible BPMN Diagram
  block to an existing published or active-draft portal page. Use it when the
  user wants a BPMN process canvas that they will edit or import in the Portal
  Customizer. Do not use it for Mermaid, a generic flowchart, a database
  diagram, a Timeline, or an image.
  This creation operation does not accept or generate BPMN XML, upload a
  `.bpmn` file, or configure links for BPMN Task elements. If the user asks to
  populate the process, explain that this operation creates the block and the
  diagram content must currently be edited or imported in Customizer.
  Resolve exact ids first. If `portalId` is unknown, use the portal listing
  flow. For a published page, call `listPortalContent` and use the selected
  exact `pageId`; if several pages match, let the user choose. For a page
  created earlier in the active draft, use the `pageId` returned by the
  page-creation operation. Never guess ids or send a page title/path as an id.
  Required path params: `orgId`, `portalId`, `pageId`.
  The body may be empty. Optional body:
    `title` — wrapper title, default `BPMN Diagram`; it supports only
      `{{ClientName}}` and `{{ClientLastName}}` using the shared
      dynamic-variable rules from `Portal block presentation`;
    `content.diagramHeight` — integer BPMN canvas height in pixels from 150 to
      5000, default `500`; this is distinct from the block Layout height;
    `appearance` — Backdrop `none`, `blank`, or `custom`; omitted keeps the
      canonical blank backdrop with the title shown. Custom supports semantic
      background, padding `none|s|m|l` (default `s`), and `showTitle`
      (default true);
    `layout.colspan` — Width `2..6`, default `6`;
    `layout.height` — `null` for Auto (default) or a manual block height of at
      least `50` pixels.
  Use the shared `Portal block presentation` rules for all Content, Appearance
  and Layout parameters.
  Never send BPMN XML, files, base64, local paths, task ids, data/details,
  DynamicLink, `diagramType`, template/view, raw wrapper/theme/classes, blocks,
  bricks, internal ids, index/rowspan, changeEvents, eventJson, dtoJson, batch
  ids, or client event ids.
  The operation changes an existing page only. It does not create a page,
  sidebar item, or change the page icon. It stages the new block in the
  Customizer draft and does not publish the portal. Call `publishPortalDraft`
  separately only when the user explicitly asks to publish the whole pending
  draft.
  Returns: blockId, pageId, branchId, seqs, staged (always true).
  Example: addPortalBpmnDiagramBlock with orgId `org_123`, portalId
  `portal_456`, pageId `page_789`, title `Order approval process`,
  content.diagramHeight `700`.

- addPortalInfoBlock: adds ONE Customizer-compatible Info block to an EXISTING
  portal page — the compact clickable image-and-title tile from Content display.
  It does not create a page, sidebar item, note, app, Card or Embed block.
  Do not use addPortalCardBlock either: a Card is a flexible
  multi-brick content card with Card Type, description and button controls,
  while an Info block is the small `Info block` tile with one image, one title
  and one destination.
  Before calling, resolve the exact `portalId` with listPortals. Resolve a
  published target page with listPortalContent; for a page created earlier in
  the active draft, use the exact pageId that page-creation operation returned.
  Do not invent ids. For an internal destination, resolve its exact pageId the
  same way.
  Required path params: `orgId`, `portalId`, `pageId`.
  Required body:
    `title` — non-empty text shown inside the tile;
    `image` — exactly one semantic variant:
      {type: "emoji", emoji} with one visible Unicode emoji;
      {type: "icon", iconId} with an exact id from searchPortalInfoBlockIcons;
      {type: "custom", url} with an exact existing absolute HTTPS image URL the
        user supplied — this operation does not upload files;
    `destination` — exactly one of {type: "portalPage", pageId} for a page in
      this portal or {type: "external", url} for an absolute HTTPS URL.
  Optional body: `openInNewTab` (default true); `layout.colspan` (1, 2 or 3,
    default 1); `layout.height` (null for Auto, the default, or a number >= 50
    for Manual). There is no row count: the Customizer's Rows control is
    feature-flagged off, so the block always spans one row.
  Presentation: follow the shared `Portal block presentation` prompt, especially
  its Layout rules. This operation supports Content through `title`, `image`,
  `destination` and `openInNewTab`; it does NOT support Appearance and always
  uses the canonical filled wrapper. Its Layout subset is the two fields above
  with exactly those limits and defaults. `image` is NOT the standard
  Content.Image group: it names a concrete Emoji, Icon or Custom image. Never
  send base64, a local path, upload data, or the internal `emoji#...`,
  `icon#...`, `url#...` format. Do not send Appearance, raw wrappers, CSS,
  blocks, bricks, ids, indexes, eventJson, dtoJson or change events.
  The operation works with an existing published or draft-only page and stages
  one addBlock change in the customizer draft. It does not publish the portal;
  call publishPortalDraft separately only when the user explicitly asks to
  publish all pending changes.
  Emoji example: addPortalInfoBlock({orgId, portalId, pageId}, {title:
  "Support", image: {type: "emoji", emoji: "🥳"}, destination: {type:
  "portalPage", pageId: "page_support"}}).
  Icon example: searchPortalInfoBlockIcons({query: "user"}) then
  addPortalInfoBlock({orgId, portalId, pageId}, {title: "Microsoft", image:
  {type: "icon", iconId: "user"}, destination: {type: "external", url:
  "https://microsoft.com"}}).

- addPortalFormBlock: adds one Customizer Content display "Form" block to an
  EXISTING portal page. Use it when the user wants a data-entry, contact, or
  questionnaire form. Do not use it for a sign-in form, App UI, Database
  block, Form responses dashboard, or a new portal page.
  Resolve exact ids first: call `listPortals` for the exact `portalId`, then
  `listPortalContent` for the exact existing `pageId`. For a page created
  earlier in the active draft, use the `pageId` that operation returned. Never
  guess either id. No other discovery is needed: creating a Form does not
  select a note, app, agent, channel, database, media asset, or external
  entity.
  Required path params: `orgId`, `portalId`, `pageId`.
  The body may be empty. Optional body: `title`, `content`, `appearance`,
  `layout`.
  Build ONE complete payload before calling the operation. Do not probe it with
  partial/default forms: every successful call stages another Form block.
  MCP input nesting is strict: `args` must be an object; put `orgId`, `portalId`,
  and `pageId` directly in `args`, and put `title`, `content`, `appearance`, and
  `layout` only inside `args.body`. Never put `title` beside `orgId`, and never
  put `title` inside `content`. Never pass `args` or `body` as a JSON string.
  If the transport says `args expected record, received string`, rebuild `args`
  as an object and retry the SAME complete call; do not create smaller test forms.
  Defaults: title `Form`; a visible Description with the Customizer contact
  and company copy; visible Form content; five fields in order — required
  half-width First name, required half-width Last name, required half-width
  Contact email, optional half-width Project name, optional full-width Project
  overview; a visible Submit button with text `Submit`; reusable true; blank
  backdrop with the title shown; width 6; Auto height.
  `content.description` supports `visible` plus the common semantic text
  fields `text`, `color`, `size`, `styles`, `align`; follow the `Content`
  section of `Portal block presentation` above. Only {{ClientName}} and
  {{ClientLastName}} are supported variables.
  `content.form` supports `visible`, `fields`, `submit`, and `reusable`.
  `fields` is the COMPLETE visual-order list: omit it to keep the five default
  fields, and send [] only when the user explicitly wants no fields. Never
  send field ids, indexes, cols, brick data, or raw renderer schema.
  Each field requires `type`: text, textarea, number, phone, email, checkbox,
  select, file, or date. Optional field settings are `label`, `required`, and
  `width` (`half` or `full`). `placeholder` is available only for text,
  textarea, number, phone, email, and select. `options` is a string array for
  select only; never send a newline-separated string. Field labels,
  placeholders, options, and the submit text are plain text and support no
  dynamic variables.
  `content.form.submit` supports `visible` and `text`. `reusable: true` lets
  the same portal user submit again; false leaves the form disabled after its
  first response. `content.form.visible: false` hides the entire form content
  brick; send no fields, submit, or reusable settings beside it. The
  Description is hidden independently the same way.
  Follow the `Appearance` and `Layout` sections of `Portal block presentation`
  above: backdrop none, blank, or custom; custom background, padding
  (`none|s|m|l`, default `s`) and `showTitle` (default true); width 2-6; Auto
  height or a manual height >= 50px. Omit Appearance and Layout unless the
  user asks to change them. Never send HEX, CSS, opacity, internal theme
  tuples or classes, rowspan, responsive values, blocks, bricks, changeEvents,
  eventJson, dtoJson, ids, index, batch ids, or client event ids.
  The operation creates one Form block on the existing page and stages it in
  the Customizer draft. It does not create a page, submit a response, upload a
  file, or publish the portal. Call `publishPortalDraft` separately only when
  the user explicitly asks to publish the entire pending draft.
  Returns: blockId, pageId, branchId, seqs, staged (always true).
  Correct complete call shape:
  addPortalFormBlock({
    args: {
      orgId: "org_123",
      portalId: "portal_456",
      pageId: "page_789",
      body: {
        title: "Contact form",
        content: {
          form: { fields: [
            { type: "email", label: "Work email", required: true, width: "full" }
          ] }
        }
      }
    }
  })

- addPortalCustomWidgetBlock: adds one Customizer Custom "Custom widget" block
  to an EXISTING portal page. Use it when the user wants a freely composed
  widget: a stack of headings, paragraphs, an image, an avatar, a rating, a link
  and a button. Do not use it for a Card, Card group, Carousel, HTML/CSS block,
  or a new portal page.
  For every presentation setting below, follow `Portal block presentation`. In
  particular, use its Appearance, Destination URL, and Layout rules; this
  operation-specific text only narrows those shared rules to the Custom widget
  fields, limits, and defaults.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page, get
  the exact pageId from listPortalContent. For a page created in the active
  draft, use the pageId returned by the page-creation operation. Never guess a
  page id.
  The body is optional settings only. Omit `content` to create the Customizer
  default "Your Consultant" widget of nine bricks.
  Optional `content.bricks` replaces the default brick list entirely and holds
  the bricks in visual order. Each brick is one of `heading`, `text`, `image`,
  `avatar`, `rating`, `link`, `button` — the seven kinds the Customizer's
  "Add block" palette offers. A field belonging to another brick kind is
  REJECTED with 400 rather than silently dropped, so send only the fields the
  contract lists for that `type`.
  A `link` brick requires `destination`; a `button` brick without one is
  created unlinked and the user can add the link in the Customizer.
  Destination uses an exact pageId in this same portal, an absolute HTTPS
  URL, or an email address. For an internal destination, first resolve the exact
  page with listPortalContent.
  Heading and text copy support only {{ClientName}} and {{ClientLastName}};
  avatar, link and button copy support no dynamic variables — the avatar is
  never substituted and would show the placeholder to the portal visitor.
  The operation uses built-in images only. It cannot select, upload, or accept
  an image URL, asset id, file name, base64, local path, raw DynamicLink, raw
  brick index, CSS class, or theme override. If the user requires custom media,
  explain that this create operation cannot set it; do not invent or upload it.
  Optional `title` is the block title (default "Your Consultant"), shown by the
  `blank` and `custom` backdrops. Omitting `appearance` keeps the widget's own
  `blank` backdrop with the title shown; `background`, `padding` and `showTitle`
  apply only to `backdrop: custom`.
  Optional `layout`: `colspan` is 2 through 6 (default 2); `height` is null for
  Auto or a number of at least 50 for Manual (default null).
  The operation stages exactly one block in the Customizer draft. It does not
  create a page or sidebar item and does not publish the portal. Call
  publishPortalDraft separately only when the user explicitly asks to publish
  the entire pending draft.
  Returns: blockId, pageId, branchId, seqs, staged (always true).

- addPortalHtmlCssBlock: adds one Customizer Custom "HTML/CSS block" to an
  EXISTING portal page. Use it only when the user explicitly wants raw HTML,
  CSS or JavaScript on the page. Prefer a semantic block (Card, Card group,
  Carousel, Text & Media, Custom widget) whenever one covers the request.
  ONLY portals served from a verified custom CNAME domain may carry this
  block; on a Fusebase-owned portal subdomain the call is REJECTED with 400
  naming the CNAME requirement. On THAT message say so and stop rather than
  retrying; any other 400 is a body problem you can fix and retry.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page, get
  the exact pageId from listPortalContent. For a page created in the active
  draft, use the pageId returned by the page-creation operation. Never guess a
  page id.
  The body is optional settings only. Omit `content` to create the Customizer
  demo pie chart.
  Optional `content` replaces that demo entirely: `html` is markup inserted
  as-is, `style` is raw CSS with NO `<style>` tag, `script` is raw JavaScript
  with NO `<script>` tag. An omitted field is empty, not the demo value, and
  each is at most 50000 characters.
  The style is injected globally on the page, so scope every rule with your own
  class names instead of styling bare tags. Write only code the user asked for:
  it is stored verbatim, is NOT sanitized, and runs for every portal visitor.
  Never add analytics, trackers, external script tags or network calls that the
  user did not request.
  Optional `title` normally only labels the block inside the Customizer
  (default "HTML/CSS Block") because the wrapper hides it BY DEFAULT — but the
  owner can turn on Appearance "Show title", so keep it presentable. It may
  contain {{ClientName}} or {{ClientLastName}} and no other variables.
  The operation exposes no `appearance` field: the wrapper is pinned to the
  Customizer's edge-to-edge one, and the owner adjusts backdrop, padding and
  Show title in the Customizer afterwards.
  Optional `layout`: `colspan` is 2 through 6 (default 3); `height` is null for
  Auto or a number of at least 50 for Manual (default null).
  The operation stages exactly one block in the Customizer draft. It does not
  create a page or sidebar item and does not publish the portal, so the portal
  owner reviews the code before it goes live. Call publishPortalDraft separately
  only when the user explicitly asks to publish the entire pending draft.
  Returns: blockId, pageId, branchId, seqs, staged (always true).

- addPortalLinkedBlock: adds one Customizer-compatible Linked block to an EXISTING
  portal page. Use it when the user wants the SAME block to appear on a second
  page and to keep following the original — a live reference, not a copy. Do not
  use it to duplicate a page (duplicatePortalItem) or to create a new block of the
  same kind.
  Resolve exact ids first, in this order:
    1. `listPortalContent` on the SOURCE portal for the page holding the block;
    2. `listPortalLinkableBlocks` with that portalId and pageId — it returns the
       page's blocks as `blockId`, `type`, `templateType`, `title` and `draftOnly`;
    3. let the USER pick one when more than one block could match. Never select a
       block automatically and never guess or invent a blockId.
  Required path params: `orgId`, `portalId`, `pageId` — the TARGET portal and page.
  Required body: `source` — the exact `{portalId, pageId, blockId}` triple of the
    block to mirror.
  There is nothing else to send. The Linked block MIRRORS the source's title,
  width, height, backdrop and actions and keeps following it, so a title,
  `layout`, `appearance`, `content`, bricks or an index are REJECTED with 400.
  Rules enforced by the server:
    both portals must be in the same organization and the caller must be allowed
      to edit both;
    a `draftOnly: true` source can be linked ONLY inside the SAME portal — a
      cross-portal source must be published first (publish that portal's draft);
    a Linked block cannot point at another Linked block — link its original
      source block instead;
    the source block cannot live on the target page itself.
  The operation stages the change in the TARGET portal's Customizer draft. It does
  not touch the source portal and does not publish. Call `publishPortalDraft`
  separately only when the user explicitly asks to publish.
  Returns: blockId, pageId, branchId, seqs, staged (always true).
  Example: listPortalLinkableBlocks with orgId `org_123`, portalId `portal_456`,
  pageId `page_789`, then addPortalLinkedBlock with orgId `org_123`, portalId
  `portal_456`, pageId `page_111` and source `{portalId: 'portal_456', pageId:
  'page_789', blockId: 'block_222'}`.

- addPortalFileUploaderBlock: adds one File uploader block from the Customizer's
  File management category to a page already present in the published portal or
  the active Customizer draft. Use it when the user wants a page area where
  non-visitor portal users can upload and manage files. Do not use it to upload a
  file now, attach an existing file, create a file dashboard, or show recent
  files; this operation creates only the empty uploader block.
  Required path params: `orgId`, `portalId`, `pageId`. For a published page,
  resolve the exact `pageId` with `listPortalContent`. For a page created in the
  active draft, use the `pageId` returned by its page-creation operation. Never
  guess an id from a page title, slug, or URL.
  The body may be empty. Optional body:
    `title` — non-empty plain text, default `File uploader`;
    `description` — plain text up to 50 characters, default empty;
    `showAuthor` — show the uploader's Author column, default false;
    `showUploadDate` — show the Upload date column, default false;
    `layout.colspan` — 3, 4, or 6 columns, default 3;
    `layout.height` — null for Auto (default) or a manual pixel value >= 50.
  Use the shared `Portal block presentation` rules for all Content, Appearance
  and Layout parameters. This operation exposes General and Layout only; it does
  not expose Appearance. Do not send `appearance`, `rowspan`, upload permissions,
  bucket ids, file ids, query/sort/limit, raw blocks, CSS, or change events.
  The block itself does not bypass file permissions: visitors cannot upload.
  The change is STAGED in the Customizer draft and is not visible on the live
  portal yet. This operation does not publish the portal. Call
  `publishPortalDraft` separately only when the user explicitly asks to publish.
  Returns: blockId, pageId, branchId, seqs, staged (always true).
  Example: addPortalFileUploaderBlock with orgId `org_123`, portalId `portal_123`,
  pageId `page_123`, title `Send your documents`, description `Upload signed
  documents here`, showAuthor true, layout { colspan: 4, height: null }.

- addPortalRecentFilesBlock: adds one Customizer File management "Recent files"
  block to an existing portal page, including a page staged only in the active
  Customizer draft. Use it when the user wants to show the five
  most recently created files from the entire portal or from one portal page.
  Do not use it to upload, create, list or modify files, to create a page, or to
  add a file bucket/dashboard.
  First call `listPortalContent` to obtain the exact target page id. If the source
  is one page, also use its exact page id from `listPortalContent`. A page id
  returned by a preceding portal-page creation operation is also valid for a
  draft-only page. Never guess ids from page titles or paths.
  Required path params: `orgId`, `portalId`, `pageId`.
  Optional body:
    `title` — non-empty visible title, max 100 characters (default `Recent files`).
    `source` — `{ type: 'entirePortal' }` (default) or
      `{ type: 'portalPage', pageId }` for exactly one page in this portal.
    `layout.colspan` — 3, 4, 5 or 6 (default 3).
    `layout.height` — null for Auto (default) or a number >= 50 for Manual.
  Sort order (`createdAt` descending), item count (5), offset, file types, raw
  query/link data, Appearance and Rows are not configurable.
  Use the shared `Portal block presentation` rules for all Content, Appearance
  and Layout parameters.
  The operation stages the block in the Customizer draft; it does not publish
  the portal. Call `publishPortalDraft` separately only when the user explicitly
  asks to publish.
  Example: addPortalRecentFilesBlock({ orgId: 'org_1', portalId: 'portal_1',
    pageId: 'page_1', body: { source: { type: 'portalPage', pageId: 'page_2' },
    layout: { colspan: 3 } } }).

- addPortalFilesDashboardMenuItem: adds a ROOT navigation item for the portal's
  SYSTEM Files dashboard — the full File Manager, showing each viewer the portal
  files they are allowed to access. If the portal has no `/files-dashboard` page
  yet, the page and its canonical `files-dashboard` block are created in the same
  batch; if it already has one, only the navigation item is added, so several
  bars can link to the same dashboard. Use it when the user wants a Files entry
  in the portal navigation.
  Do NOT use it to put a file list on a page of your choice, to upload a file or
  to create a bucket: for a compact latest-files list use addPortalRecentFilesBlock
  and for an upload area use addPortalFileUploaderBlock, both on an existing page.
  Required path params: `orgId`, `portalId`. There is no `pageId` and no
  `parentId`: the item is always a root item and the operation resolves the page
  itself, so do not run page discovery first and do not send pageId, path or
  slug.
  The body may be empty. Optional body:
    `title` — the visible item name, also used as the block title when the
      dashboard page is created (default `Files`, trimmed plain text
      1..100 characters). The system page title, route and icon stay fixed;
    `positionType` — `sidebar` (default), `top` (topbar) or `footer`.
  No file discovery is needed. Apart from `title` the block has no Content,
  Appearance or Layout settings, and the operation accepts no fileId, bucketId,
  workspaceId, query, sort, limit, permissions, roles, raw blocks, bricks,
  internal ids, CSS, wrapper/theme values, eventJson, dtoJson or changeEvents.
  The renderer obtains the current portal context and applies each viewer's file
  access at runtime; creating the block does not upload files or widen file
  access.
  Everything is STAGED atomically in the customizer draft. The operation does not
  publish the portal. Call `publishPortalDraft` separately only when the user
  explicitly asks to publish.
  Returns: menuItemId, pageId, blockId (only when the page was created), url,
  pageCreated, branchId, seqs, staged (always true).
  Example:
    addPortalFilesDashboardMenuItem({
      orgId: "org_123",
      portalId: "portal_123",
      title: "Client files",
      positionType: "sidebar"
    })

- setDashboardViewReadonly: allows or restricts editing of an existing Dashboard View.
  Required path params: `orgId`, `dashboardId`, `viewId`. Required body: `readonly`
  (boolean). This is a GLOBAL View setting, not a portal-block setting: it applies
  everywhere the View is used, including other portals and the Dashboard itself, and
  it is applied IMMEDIATELY (not staged). Call it only when the user explicitly asks
  to restrict or allow editing, and warn about the global effect. Never send it as
  part of addPortalDatabaseBlock. Returns: viewId, readonly.

- App discovery and selection:
  Use `findPublishedApps` to resolve the App and its Product metadata before
  calling `addPortalAppPage` or `addPortalAppBlock`.

  NEVER select the first result from `findPublishedApps` automatically.
  A write operation is allowed only after the user has made an explicit,
  unambiguous App selection.

  If the user did not identify a specific App:
  1. Ask whether they want to see:
     - private Apps from "Your Products/Apps";
     - managed Apps from "Managed Products";
     - or both.
  2. Call `findPublishedApps`.
  3. Filter by the selected product type when only one type was requested.
  4. Show the matching candidates with App title, Product title and
     private/managed type.
  5. Ask the user to choose one App.
  6. Wait for the user's choice before calling either write operation.

  If the user identified an App by name, call `findPublishedApps` with the
  name filter:
  - exactly one unambiguous match: use that result;
  - multiple matches: show all matches and ask the user to choose;
  - no matches: report that no matching published App was found and do not
    perform a write.

  Always pass `productId`, `appId`, `productType` and `productOrgId` from
  the selected `findPublishedApps` result. Do not guess ids, Product ownership
  or managed/private type from names.

- Operation selection:
  Use `addPortalAppPage` when the user wants the App as a NEW sidebar page.
  Use `addPortalAppBlock` when the user wants the App on an EXISTING page.
  If this intent is unclear, ask before performing a write.

- addPortalAppPage: adds a published App as a NEW sidebar page containing one
  flexible app-feature block.
  Required path params: `orgId`, `portalId`.
  Required body:
    `productId` — Product that owns the App;
    `appId` — published App to embed.
  Optional body:
    `productType` — "private" for Your Products/Apps or "managed" for
      Managed Products; use the value returned by findPublishedApps;
    `productOrgId` — Product owner organization returned by findPublishedApps;
      required for managed Products;
    `title` — page/menu/block title (default: "App" for private,
      "Managed Products" for managed);
    `parentId` — published or active-draft folder/menu item id;
    `icon` — sidebar icon key (default: "note").
  Resolve productId, appId, productType and productOrgId with
  `findPublishedApps`. Do not guess ids or managed/private type from the name.
  The operation stages page, menu item and App block as one Customizer draft
  change. It does not publish the draft.
  Returns: pageId, menuItemId, blockId, url, branchId, seqs, staged.

- addPortalAppBlock: adds a published App as one flexible app-feature block
  to an EXISTING portal page.
  Required path params: `orgId`, `portalId`, `pageId`.
  Required body:
    `productId` — Product that owns the App;
    `appId` — published App to embed.
  Optional body:
    `productType` — "private" for Your Products/Apps or "managed" for
      Managed Products; use the value returned by findPublishedApps;
    `productOrgId` — Product owner organization returned by findPublishedApps;
      required for managed Products;
    `title` — block title (default: "App" for private,
      "Managed Products" for managed).
  Resolve productId, appId, productType and productOrgId with
  `findPublishedApps`. Do not guess ids or managed/private type from the name.
  Use this operation only when the user wants to add an App to an existing
  page. It stages one App block and does not create a page or sidebar item.
  It does not publish the draft.
  For a published page, resolve `pageId` from `listPortalContent`. For a page
  staged earlier in the active draft, use the `pageId` returned by the
  page-creation operation.
  Returns: pageId, blockId, branchId, seqs, staged.

- Publishing:
  Both App operations stage changes in the active Customizer draft.
  Do not call `publishPortalDraft` unless the user explicitly asks to make the
  change live or confirms publishing after the staged result.

  Supported flows:
  `findPublishedApps` → explicit App selection → `addPortalAppPage`
    → optional confirmed `publishPortalDraft`
  `findPublishedApps` → explicit App selection → `addPortalAppBlock`
    → optional confirmed `publishPortalDraft`

- duplicatePortalItem: copies a menu item (folder, note page, portal page, or link)
  within the SAME portal. For a folder the whole subtree of copyable children is
  copied, including each page's content blocks.
  Required path params: `orgId`, `portalId`, `itemId` — the source menu item id
    (from `listPortalContent`).
  Optional body:
    `name`     — name for the copied root (default: '<source name> copy').
    `parentId` — an existing menu item to place the copy under (default: next to
      the source).
  Inner Fusebase notes are DEEP-CLONED (each copy gets a fresh noteId), so editing
  a note later does NOT affect the original. Unlike the other content ops, the copy
  is applied to the published portal IMMEDIATELY (not staged). Returns: itemId, published.

- updatePortalCustomCode: sets custom CSS/JS for the portal.
  Required path params: `orgId`, `portalId`.
  Body (at least one field required; only provided fields change):
    `css`      — custom CSS for the portal. Write selectors RELATIVE to the
                 portal content, e.g. `.my-class { ... }` — do NOT prefix them
                 with `#main-scrolling-container` yourself. Gate auto-nests your
                 CSS under `#main-scrolling-container` (the portal's root element),
                 which keeps styles inside the portal zone and out of the customizer
                 UI (which sits OUTSIDE that container). Never target
                 `body`/`html`/`:root` (they live outside the portal container).
    `headCode` — HTML/JS injected at the start of `<head>`.
    `bodyCode` — HTML/JS injected at the end of `<body>`.
  Pass an empty string to clear a field; omitted fields keep their current value.
  Custom code ONLY renders on portals served from a custom CNAME domain — tell the
  user it has no effect on `*.p.<env-domain>` portal subdomains.
  The change is STAGED in the draft. Returns: branchId, seq, staged (always true).

  Portal re-branding via custom CSS: target the stable styling hooks and set
  visual properties directly (hex is fine). Do NOT override daisyUI vars
  (`--p`/`--b1`/…): they exist in the compiled CSS but only ~7 cosmetic widgets
  read them — core surfaces are Tailwind hex utilities, so overriding vars
  re-brands nothing. Structural hooks: `[data-portal="sidebar"|"footer"|
  "page-card"|"note-content"|"breadcrumbs"|"search"]`. Write RELATIVE selectors
  in `css` (Gate auto-nests under `#main-scrolling-container`; no manual prefix),
  e.g. `[data-portal="sidebar"] { background: #101828; }`. Full contract:
  reference `portal-theme-variables`.

- updatePortalHomepage: sets the portal Homepage settings — the same panel the
  customizer shows under Homepage settings.
  Required path params: `orgId`, `portalId`.
  Body (at least one field required; only provided fields change):
    `title`                   — homepage title. Renames the portal's Home menu
                                item and, with it, the homepage itself.
    `showSidebarOnOtherPages` — show the sidebar on pages other than the homepage.
    `showSidebarOnHomePage`   — show the sidebar on the homepage.
    `expandSidebarByDefault`  — start the sidebar expanded rather than collapsed.
  Omitted fields are left out of the change events entirely, so they keep their
  current value — never restate a field just to change another one.
  This operation does not manage page content: to add blocks to the homepage,
  resolve its `pageId` from listPortalContent (menu item `type: "home"`) and call
  the normal semantic block operations (e.g. addPortalTextBlock,
  addPortalCardBlock) with that `pageId`, exactly as for any other page.
  One call stages up to two events (sidebar theme, homepage title) in a single
  draft write, so a mixed update is all-or-nothing.
  The change is STAGED in the draft and appears in the customizer under Homepage
  settings. Returns: branchId, seqs (one per staged event), staged (always true).

- updatePortalStyle: sets the portal branding — the same fields the customizer's
  Portal style panel writes.
  Required path params: `orgId`, `portalId`.
  Body (at least one field required; only provided fields change):
    `theme`    — color theme key. One of: light_purple, soft_light, quite_green,
                 space_gray, carbon, oxford, ultramarine, milky_blue,
                 shades_of_green, savvy_red, light_orange, light_blue,
                 lemon_drop. Recolors the whole portal consistently.
    `logo`     — `{ storedFileUUID }` of an uploaded image, shown in the header.
    `favicon`  — `{ storedFileUUID }` of an uploaded image, the browser tab icon.
  Upload images first with the files operations (see MCP prompt `files`) and pass
  the returned `storedFileUUID`.
  Colors are named themes, NOT arbitrary values: the portal theme model has no
  hex-color and no web-font fields, so a request like "make the buttons #2563eb"
  or "use the Fraunces font" cannot be served by this operation. Pick the closest
  theme, then use updatePortalCustomCode for anything more specific (CNAME-domain
  portals only; see reference `portal-theme-variables`).
  Read the current branding back from `getPortal` → `style`
  (`theme`, `logoUrl`, `faviconUrl`).
  The change is STAGED in the draft. Returns: branchId, seq, staged (always true).

- publishPortalDraft: publishes the portal's staged draft to the live portal.
  Required path params: `orgId`, `portalId`. No body.
  Applies EVERY staged change in the draft (the whole pending branch, including
  anything the owner or another user staged manually in the customizer) through
  the same pipeline the customizer's Publish button uses.
  This operation is allowed only after completing the Publish Permission Rule:
  warn the user that the entire pending draft will go live, ask one clear yes/no
  confirmation question, wait for an unambiguous affirmative answer, and only
  then call publishPortalDraft. A content-edit request or successful staging is
  not publish permission. Never publish automatically.
  Returns 400 if the draft is empty (nothing staged) and 409 if the portal was
  published elsewhere since the draft was based. In the 409 case the draft is
  stale: re-stage the changes, explain the new draft state, and obtain a new
  explicit confirmation before another publish attempt.
  Any failed publish attempt consumes the previous confirmation. Ask again
  before retrying.
  Returns: branchId, newBranchId, appliedEventCount, lastPublishedAt, published (true).

## Operation Sequence Rules

- Always discover first: `listPortals` (to get a `portalId`) then `listPortalContent`
  (to inspect existing folders/pages) before creating content, to avoid duplicates and
  to obtain the `pageId`/`parentId` values other operations need.
- Empty page vs note page: use `createPortalPage` for a blank page (then add
  content with a semantic block op), and `createPortalPageWithNote` when the page should
  already contain a new document/note. Both stage into the draft and return a `pageId`.
- Menu bars: `createPortalPage`, `createPortalPageWithNote`, `addPortalAppPage`,
  `createPortalFolder` and `createPortalLink` place their item in the sidebar unless
  you pass `positionType` ('sidebar' | 'top' | 'footer'). A nested item (one with
  `parentId`) always inherits its parent's bar, so `positionType` only applies at the root.
  A topbar/footer nav of external links needs `createPortalLink`, not a page op.
- To nest a page under a folder: create the folder with `createPortalFolder`, then pass
  the `folderId` it returns as `parentId` to `createPortalPage` / `createPortalPageWithNote` / `addPortalAppPage`.
  All content ops stage into ONE shared draft branch, so a folder you just staged is a
  valid `parentId` for later calls in the same draft — do NOT publish the folder first,
  and do NOT flatten pages to the root. Publishing is only needed to make content live.
- To add a note block to a page: the page must already exist (use its `pageId` from
  `listPortalContent`) and the note must already be a portal note. If you need a brand
  new note on its own page, use `createPortalPageWithNote` instead.
- A page or note created in the draft but not yet published is not addressable by
  `pageId` via `listPortalContent` (which reads published content); publish first, then
  re-list, before targeting it with `addPortalNoteBlock`. `addPortalBlankNoteBlock`
  is the exception: it also accepts a draft-only `pageId` returned by the
  page-creation operation — including the `pageId` from a just-staged `createPortalPage`,
  which you can pass straight to a semantic block op without publishing first.
- To add an app to a portal: follow the App discovery and selection rules above —
  `findPublishedApps`, an explicit user choice, then `addPortalAppPage` (NEW sidebar
  page) or `addPortalAppBlock` (EXISTING page). The app does not need to be a portal
  note or pre-shared; the embed loads from productId/appId at render time.
- To duplicate existing content: get the source item's id from `listPortalContent`
  and call `duplicatePortalItem`. It only copies PUBLISHED content (it reads the
  published menu/blocks), so publish any pending draft changes before duplicating
  items that depend on them.
- Batch related edits, then tell the user to open the customizer once to review and
  publish the whole draft.

## Read Flow Rules

- Use `listPortals` to discover available portals when you do not yet have a `portalId`.
- Use `getPortal` when you already have the `portalId` and need full portal details including CNAME info, status, version, publish timestamps, and the published branding (`style`: `theme`, `logoUrl`, `faviconUrl`).
- `getPortal` returns 404 when the portal does not exist or is not accessible.

## listPortalContent Flow Rules

- Use `listPortalContent` before creating folders or pages to avoid duplicates.
- Required path params: `orgId`, `portalId`.
- Returns `items[]` — a nested tree. Each item has:
  `id`: opaque menu item identifier (use as reference for content operations).
  `type`: raw portal-service type — `note`, `portalPage`, `notesFolder`, `home`, `link`,
    `portalSection`, `portalProcess`, `allPages`, `tasks`, `chat`, `folders`, `tags`,
    `portalFilesDashboard`, `filesManager`, `portalTasksDashboard`, `portalChatsDashboard`.
  `name`: display name of the item.
  `slug`: URL slug.
  `positionType`: menu position — `top`, `sidebar`, or `footer`.
  `pageId`: present for `note` and `portalPage` items — id of the page in portal-service.
  `noteId`: present only for `note` items — id of the underlying Fusebase note.
  `children`: nested items (same structure, recursive).
- `note` items are pages backed by a single Fusebase note (document-style). Use `noteId` to reference the note.
- `portalPage` items are constructor pages with arbitrary blocks. Blocks are added via dedicated block operations.
- `notesFolder` items are containers backed by a Fusebase folder.
- System items (`home`, `link`, `chat`, etc.) are returned but should not be modified through Gate content operations.

## Editing an existing portal block

Changes to an existing block are staged in the active Customizer draft and are
not published automatically.

Always resolve the block first: call listPortalPageBlocks with the exact
portalId and pageId. It returns every block of the page in DISPLAY ORDER as
`blockId`, `type`, `templateType`, `title`, `editOperation`, `place` and
`draftOnly`.
Let the user choose when several blocks may match — show their titles and
kinds. Never guess a portal, page or block id. A blockId returned by an
addPortal*Block operation may be used directly.

The returned order is the current page order — the blocks are grouped by page
area (`place`, e.g. `page_header`, `page_body`, `page_footer`) top to bottom and
ordered inside each area — and it is what a move anchor refers to. `place` also
tells you which blocks may anchor each other: a block only moves within its own
area, so an anchor with a different `place` is rejected with 400.
`editOperation` names the typed update operation for that block, or
is null when its kind has none yet — a null does NOT mean the block cannot be
moved or removed.

Never send raw blocks, bricks, wrappers, theme tuples, CSS classes, internal
indexes, DynamicLink fields, response data, changeEvents, eventJson, dtoJson,
batch ids or client event ids to any of these operations.

Then call getPortalBlock with the selected blockId and inspect its current
settings before changing anything. It returns the block's semantic `kind` — the
vocabulary the typed updates use — plus `title`, `place`, `layout` and the
kind-specific `settings`. Show the user what is set today and confirm the change.

Call the typed updatePortal*Block operation named by `editOperation`. Send only
the settings the user asked to change: omitted fields and omitted nested fields
keep their current value, and the add operation's defaults do NOT apply. null
clears a value only where the operation contract allows it. An update cannot
change a block's type or template, and cannot create a page, menu item or
replacement block.

When an array is sent it is the FULL desired list in visual order, not an item
patch — preserve every item the user did not ask to remove. A discriminated
object such as appearance, target, destination or visible must be a complete
valid variant when sent.

An empty patch, or one the block already satisfies, is rejected with 400 rather
than silently staging nothing.

## updatePortalNoteBlock

Updates the portal wrapper of an existing note-backed block, including one
created by addPortalNoteBlock, addPortalBlankNoteBlock, addPortalKanbanBlock or
addPortalTaskListBlock — they all persist as the same block kind.

It accepts only title and layout. layout.colspan is 3, 4, 5 or 6;
layout.height is null for Auto or a number of at least 50 for Manual.

It cannot replace noteId, boardId or taskListId and cannot edit note content,
Kanban columns, tasks or task-list items. Use the corresponding product
operations for that content.

Example — widen a note block and rename it:
updatePortalNoteBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_107",
body:{title:"Q3 report",layout:{colspan:6}}}})

## updatePortalHeadingBlock

Updates content, appearance or layout of an existing Text & Media Heading
block. content supports text, color, size, styles and align. Follow the shared
text, color, variable, background and Layout rules. An image background accepts
only azure, mira, solis, serenity or glow with optional blur. Send appearance
complete: re-send the one getPortalBlock reports and change the field you want.
Under backdrop custom an omitted background keeps the block's current one.
This operation does not accept a wrapper title, HTML, CSS, image URL or raw
bricks.

## updatePortalTextBlock

Updates content, appearance or layout of an existing Text & Media Simple text
block. content supports text, color, size, styles and align. Follow the shared
text, color, variable, background and Layout rules. An image background accepts
only azure, mira, solis, serenity or glow with optional blur. Send appearance
complete: re-send the one getPortalBlock reports and change the field you want.
Under backdrop custom an omitted background keeps the block's current one.
This operation does not accept a wrapper title, HTML, CSS, image URL or raw
bricks.

## updatePortalImageBlock

Updates only layout of an existing Text & Media Image block. Width is 2..6;
height is null for Auto or at least 50 for Manual.

The image remains the block's existing built-in image. Never send an image URL,
asset id, upload data, base64, local path, filename, content or appearance.

## updatePortalEmbedBlock

Updates title, embedType, url or content, showEmbedLink, colspan, rowspan or
height of an existing Embed block.

For embedType=custom use content and do not send url. For a named embed type use
an absolute supported URL and do not send content. When changing embedType,
send the complete valid source variant in the same request. colspan is 2..6,
rowspan is 1..4, and height is null for Auto or a supported pixel value.

## updatePortalDatabaseBlock

Updates target, title, itemsPerPage, appearance or layout of an existing
Database block.

Before changing target, call listPortalDatabaseBlockSources and use the exact
databaseId, dashboardId and viewId chain it returns. Send the complete target
variant. itemsPerPage is 10, 20, 50, 100, 200 or 500. Follow the shared
Appearance and Layout rules; layout width is 2..6 and manual height is >=50.

Example — change the source view and width while preserving other settings:
updatePortalDatabaseBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_101",body:{target:{type:"database",
databaseId:"database_1",dashboardId:"table_2",viewId:"view_3"},
layout:{colspan:4}}}})

## updatePortalCardBlock

Updates view, content, appearance or layout of an existing Card block.

Each content item is a complete variant: send only what changes and the
rest of that item is kept. A hidden item is reported as visible:false and
only; re-show it with visible:true alone and it keeps its stored text and
styles. destination is the Card's single link, shared with its Button, and
null removes it. Changing view repaints the text colours unless an explicit
color is sent with it. getPortalBlock reports no appearance for a Card on
its original wrapper: that is not a backdrop you can send back. Follow the
shared Appearance and Layout rules; layout width is 2..6 and manual height
is >=50.

Example — retitle the heading and widen the Card:
updatePortalCardBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_101",body:{content:{heading:{
text:"Client resources"}},layout:{colspan:4}}}})

## updatePortalCarouselBlock

Updates content or layout of an existing Carousel block. content.items is the
FULL desired list of 1..6 slides in visual order. Each slide may contain
caption, description, button {text} or null, and destination or null.

The slide surface and Button share one destination. Description supports only
{{ClientName}} and {{ClientLastName}}; caption and Button text support no
variables. Images remain built in. Do not send media, autoplay, duration,
controls, indicators, appearance or item ids. Width is 2..6; manual height is
at least 50.

## updatePortalCountdownBlock

Updates title, content.targetAt, appearance or layout of an existing Countdown
block. targetAt is an absolute RFC 3339 date-time with Z or an explicit UTC
offset. It must not be in the past or more than 99 days from the update.

Never send epoch time, a timezone-less date, duration or internal countdown
items. Follow the shared title, Appearance and Layout rules; width is 2..6 and
manual height is at least 50.

## updatePortalBpmnDiagramBlock

Updates title, content.diagramHeight, appearance or layout of an existing BPMN
Diagram block. diagramHeight is the canvas height from 150 to 5000 pixels;
layout.height is the separate outer block height.

This operation cannot accept BPMN XML, import a .bpmn file or edit process
elements and links. Follow the shared Appearance and Layout rules.

## updatePortalDynamicTableBlock

Updates title, appearance or layout of an existing Dynamic Table block. It does
not configure or replace the integration provider, OAuth connection, data
source, columns or rows. Follow the shared Appearance and Layout rules; width is
2..6 and manual height is at least 50.

## updatePortalRecentFilesBlock

Updates title, source or layout of an existing Recent files block. source is
either {type:"entirePortal"} or {type:"portalPage",pageId}. Resolve an exact
same-portal pageId before changing to portalPage.

The operation cannot change sort order, the five-item limit, offset, file type,
query data or appearance. Width is 3, 4, 5 or 6; manual height is at least 50.

## updatePortalLinkedBlock

Changes the source of an existing Linked block. First resolve the source page
with listPortalContent, then call listPortalLinkableBlocks and use the exact
{portalId,pageId,blockId} source it returns. Let the user choose when several
blocks match.

Both portals must belong to the same organization and be editable by the
caller. A draft-only source is allowed only in the same portal. A Linked block
cannot reference another Linked block or a source on its own target page. The
operation accepts no title, content, appearance or layout because these are
mirrored from the source.

## updatePortalFormBlock

Updates title, content.description, content.form, appearance or layout of an
existing Form block.

content.form.fields is the FULL desired field list in visual order. Preserve
the fieldId returned by getPortalBlock for every existing field, omit fieldId
only for a new field, and omit an existing field from the list only when the
user wants to delete it. Never invent a fieldId.

Once the block has response data every field must carry its fieldId, so a new
field cannot be added; and if reusable=false, fields, submit controls and
reusable itself cannot be changed. Never send response data, brick ids or
field indexes.

## updatePortalCardGroupBlock

Updates title, content, appearance or layout of an existing Card group block.
content.items is the FULL desired list of 1..6 cards in visual order. Each card
has a plain title and may use built-in image calendar, book, pen or briefcase
and a destination or null. Never send image URLs or uploads.

content.description follows the shared Description rules. Card destinations
use an exact same-portal pageId, absolute HTTPS URL or email. Follow shared
Appearance and Layout rules; width is 2..6 and manual height is at least 50.

## updatePortalInfoBlock

Updates title, image, destination, openInNewTab or layout of an existing Info
block. image is one complete variant: emoji, an exact iconId returned by
searchPortalInfoBlockIcons, or an allowed absolute HTTPS custom-image URL.

destination is one complete variant: an exact same-portal pageId or an absolute
HTTPS URL. Never invent icon ids or send raw persisted image/link values.
Layout width is 1, 2 or 3; manual height is at least 50.

## updatePortalCustomWidgetBlock

Updates title, content, appearance or layout of an existing Custom widget.
content.bricks is the FULL desired visual-order list. Each brick is heading,
text, image, avatar, rating, link or button and may contain only fields allowed
for that type. Preserve all bricks the user did not ask to remove.

A link requires a destination; a button may remain unlinked. Resolve internal
destinations to exact same-portal pageIds. Images remain built in; never send an
image URL or upload. Follow shared Appearance and Layout rules; width is 2..6
and manual height is at least 50.

## updatePortalHtmlCssBlock

Updates title, content.html, content.style, content.script or layout of an
existing HTML/CSS block. Use it only for a verified custom CNAME portal and only
when the user explicitly asks to change raw HTML, CSS or JavaScript.

Within update content is a partial patch: omitted html, style or script remains
unchanged; send an empty string to clear one. style contains no <style> tag and
script contains no <script> tag. Scope CSS with block-specific class names.
Never add analytics, trackers, external scripts or network calls the user did
not request. The operation exposes no appearance. Width is 2..6 and manual
height is at least 50.

Example — clear only JavaScript while preserving HTML and CSS:
updatePortalHtmlCssBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_103",body:{content:{script:""}}}})

## updatePortalTimelineBlock

Updates view, title, content, appearance or layout of an existing Timeline.
view is horizontal or vertical. content.steps is the FULL desired list of 1..6
steps in visual order. Step title is at most 25 characters; completed steps must
form one consecutive prefix. A step destination may be a same-portal pageId,
HTTPS URL, email or null.

Image visibility, Description and Button use their documented semantic fields.
Button and step labels support no variables. Follow shared Appearance and
Layout rules; width is 2..6 and manual height is at least 50.

## updatePortalFileUploaderBlock

Updates title, description, showAuthor, showUploadDate or layout of an existing
File uploader block. description is plain text up to 50 characters. Width is 3,
4 or 6; height is null for Auto or at least 50 for Manual.

It cannot upload files or change permissions, bucket ids, file ids, query,
sort, limit, appearance or rows.

## updatePortalChatBlock

Updates title, target, membersOnly, colspan, rowspan or height of an existing
Chat widget block. Before changing target, use listPortalChatChannels for a
channel or listPortalChatUsers for a DM and use the exact returned id.

target is one complete variant: {type:"channel",channelId} or
{type:"dm",userId}. membersOnly is channel-only, defaults are not reapplied,
and a private channel requires true. Do not send membersOnly for a DM. colspan
is 3..6 and rowspan is 1..4. This is not a chats-dashboard menu item.

Example — switch the widget to an exact DM target:
updatePortalChatBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_105",body:{target:{type:"dm",userId:42},
title:"Chat with Alex"}}})

## updatePortalAppBlock

Updates the published app binding or title of an existing App block. Use exact
productId, appId, productType and productOrgId values returned by the published
app discovery flow; never infer ids from names.

When changing the app binding, send a complete consistent identity set.
productType is private or managed. productOrgId is required for managed and
must not identify another owner for private. This operation edits a block on an
existing page; it does not create or update an App page or menu item.

Example — replace the complete managed app binding:
updatePortalAppBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_106",body:{productId:"product_1",
appId:"app_2",productType:"managed",productOrgId:"owner_org_3",
title:"Customer app"}}})

## updatePortalAiAgentBlock

Changes the AI Agent used by an existing AI Agent block. First call
listPortalAiAgents and use the exact returned agentId. Never infer an id from an
agent title. The service synchronizes the canonical block title with the chosen
agent. The operation accepts no custom title, prompt, appearance or layout and
does not edit the agent itself.

## movePortalBlock

Moves an existing block within the same portal page and stages the change in
the customizer draft.

First use listPortalPageBlocks to resolve the exact pageId and blockId. Use the
returned block order to identify an anchor block when needed. Never guess ids.

Pass exactly one position: `{position:"first"}`, `{position:"last"}`,
`{beforeBlockId:"..."}`, or `{afterBlockId:"..."}`.

The anchor block must belong to the same page, carry the same `place` as the
block being moved, and must not be that block itself — `first` and `last` also
mean first and last WITHIN that area. Anything else is rejected with 400 and the
message names the reason. Never send a numeric index or the internal append sentinel 999. This
operation cannot move a block to another page or change its page area. It does
not publish the draft.

Example — move one block immediately after another block on the same page:
movePortalBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_to_move",
body:{afterBlockId:"anchor_block"}}})

## deletePortalBlock

Removes one existing removable block from a portal page and stages the deletion
in the Customizer draft.

First use listPortalPageBlocks to resolve the exact pageId and blockId. If more
than one block may match, show their titles and kinds and let the user choose.
Never delete a block based on a guessed id or an ambiguous title.

The operation takes orgId, portalId, pageId and blockId and has no body. It
deletes only the portal block. It does not delete a backing note, Kanban board,
task list, app, agent, database/dashboard source or files.

The deletion is staged and does not affect the live portal until the draft is
published. Call publishPortalDraft only when the user explicitly asks to
publish the entire pending draft.

Example:
deletePortalBlock({args:{orgId:"org_123",portalId:"portal_456",
pageId:"page_789",blockId:"block_107"}})

## Portal Fields

- `id`: opaque portal identifier.
- `orgId`: organization the portal belongs to.
- `workspaceId`: workspace the portal is scoped to.
- `domain`: the portal's public domain.
- `status`: portal lifecycle status (e.g. draft, published).
- `version`: monotonically increasing publish version.
- `lastPublishedAt`: unix timestamp of the last publish, absent if never published.
- `cnameType`, `cnameValue`, `cnameStatus`: optional custom domain CNAME configuration.
---

## Version

- **Version**: 1.98.0
- **Category**: specialized
- **Last synced**: 2026-08-11
- **Priority rule**: If the MCP prompt has a higher version, follow the prompt's API Reference as source of truth.
