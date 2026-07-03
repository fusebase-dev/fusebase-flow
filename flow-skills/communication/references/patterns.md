# Mode A — pattern library (lazy-loaded reference, v2.9.0+)

> **Load on demand.** This file is NOT loaded at session start — the main `flow-skills/communication/SKILL.md` references it. Read this only when you decide a Mode A reply genuinely warrants a visual (per the "When to use a visual" / "When NOT to use a visual" criteria in the main skill). Most Mode A chat output is tables, bullets, and short prose — patterns are for the cases where a whiteboard diagram would help.

8 patterns: project roadmap · status snapshot · decision tree · dependency graph · comparison table · timeline · state diagram · box-and-arrow architecture.

---

## Pattern library

### Pattern 1 — Project roadmap (phases + slices/tickets + status)

```
Phase 1 — Operator experience polish (3 slices)        ✅ COMPLETE
   ├── 01 Agent executionMode mismatch                  ✅
   ├── 02 Run management via AI Studio                  ✅
   └── 03 NL dashboard destination discovery (PATH B)   ✅

Phase 2 — Expand authoring capabilities (~6-10 slices)  🟡 IN PROGRESS
   ├── 04 Composition foundation (invoke_workflow)      🟡 in Codex now
   ├── 05 Router workflow shape (Brief 02 cont)         ⏸
   ├── 06 SPA composition authoring                     ⏸
   ├── 07 Audit + nested-run rendering                  ⏸
   ├── 08 Wait/delay step type                          ⏸
   └── 09 Scheduled triggers                            ⏸

Phase 3 — External integrations (~11-17 slices)         ⏸ NOT STARTED
   └── ...

Phase 4 — DEFERRED (out of this run's scope)
   └── ...
```

Status icons:

- ✅ Complete (deployed, DRAFT → DONE)
- 🟡 In progress (currently being worked on)
- ⏸ Pending / not started
- 🚧 Blocked (waiting on dependency or external)
- ❌ Failed / cancelled
- 🔄 Re-do / re-investigation needed

### Pattern 2 — Status snapshot at session bootstrap

```
Product Owner ready. Project state:

📋 Backlog (5 tickets parked)
🚧 In-flight (2 specs DRAFT)
📨 Recent handoffs: 2026-05-08-priority-fix-deploy.md (most recent)
📦 Recent commits: 33 today

📅 Roadmap status:

Phase A — Foundation (3 tickets)              ✅ COMPLETE
Phase B — Operator features (5 tickets)       🟡 IN PROGRESS (3/5)
   ├── retry-failed-classifications           ✅
   ├── profile-not-found-classification       ✅
   ├── tiktok-profile-avatar-caching          ✅
   ├── skip-already-fetched-fields            🟡 Tier 1+2 done; Tier 3 pending
   └── native-influencer-creation             ⏸
Phase C — External integrations (TBD)         ⏸ NOT STARTED

What's on your mind?
```

### Pattern 3 — Decision tree (in chat, NOT in decisions.md)

```
Operator submits Custom enrichment with archiveOptions
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
     lookbackDays set?           lookbackDays unset?
            │                         │
            ▼                         ▼
   ┌────────────────┐         ┌──────────────────┐
   │ Apply early-   │         │ Full grid scroll │
   │ exit at N=10   │         │ up to 1000-cap   │
   │ consecutive    │         │ (today's behavior│
   │ too-old videos │         │  preserved)      │
   └────────┬───────┘         └────────┬─────────┘
            ▼                          ▼
     ┌──────────────────────────────────────┐
     │ Backend defensive filter on          │
     │ source_videos.published_at           │
     │ before enqueue                       │
     └──────────────────────────────────────┘
```

### Pattern 4 — Dependency graph (which ticket blocks which)

```
   priority-fix
        │
        ▼
   ┌────────────────────────────────────────┐
   │  archive-lookback-days   queue-cohort- │
   │  (independent)           inventory     │
   │                          (independent) │
   └────────────────────────────────────────┘
                    │
                    ▼
   ┌────────────────────────────────────────┐
   │  queue-recency-ordering                │
   │  (depends on priority-fix shipped)     │
   └────────────────────────────────────────┘
                    │
                    ▼
   ┌────────────────────────────────────────┐
   │  creator-selection-recency             │
   │  (sibling to queue-recency-ordering)   │
   └────────────────────────────────────────┘
```

### Pattern 5 — Comparison table for decision-making

```
┌─ Option A: D1 (sequence column) ────────┐  ┌─ Option B: D2 (timestamp hack) ────┐
│                                         │  │                                    │
│  ✅ Clean schema (priority_seq column)  │  │  ✅ No migration                   │
│  ✅ Sortable independent of timestamp   │  │  ✅ Faster to implement            │
│  ❌ Migration required                  │  │  ❌ Hacky enqueued_at semantics    │
│  ❌ Risk: platform apply blocker        │  │  ✅ No platform-blocker risk       │
│                                         │  │                                    │
│  Effort: ~half day                      │  │  Effort: ~3 hours                  │
│  Risk: Medium (new schema)              │  │  Risk: Low (formula change only)   │
└─────────────────────────────────────────┘  └────────────────────────────────────┘

Recommendation: Option B (D2) due to platform blocker.
```

### Pattern 6 — Timeline of events

```
2026-05-08 timeline:

08:00 ━━━ Phase 1 retry-failed-classifications      shipped (deploy wnmzsiqn)
08:30 ━━━ Phase 1 profile-not-found-classification  shipped (deploy jcgy8mj4)
09:15 ━━━ Phase 2 tiktok-profile-avatar-caching     shipped (deploy xj6gwwyy)
10:30 ━━━ Phase 3 skip-already-fetched-fields T1+2  shipped (deploy skiu4d9v)
12:00 ━━━ Phase 4 Path 1 native-influencer-creation shipped (deploy gg8jxjoi)
14:30 ━━━ priority-fix D2                           shipped (deploy hsq0zy6d)

Total: 6 shipped phases
```

### Pattern 7 — State diagram (lifecycle of one entity)

```
┌──────────────┐
│ Investigating│   ← user files backlog ticket
└──────┬───────┘
       │
       ▼ user decides to ship
┌──────────────┐
│ Promoting    │   ← PO drafts spec.md (status DRAFT)
└──────┬───────┘
       │
       ▼ user locks decisions
┌──────────────┐
│ Implementing │   ← AI Developer executes T1, T2, ...
└──────┬───────┘
       │
       ▼ implementer reports gate
┌──────────────┐
│ Verifying    │   ← PO runs consistency checker
└──────┬───────┘
       │
       ▼ PO approves deploy
┌──────────────┐
│ Deploying    │   ← Deploy phase runs deploy + probes
└──────┬───────┘
       │
       ▼ all probes pass
┌──────────────┐
│ Done         │   ← spec.md DRAFT → DONE
└──────────────┘
```

### Pattern 8 — Box-and-arrow architecture

```
┌───────────┐       POST           ┌───────────────┐
│  Browser  │  ───────────────►    │   Backend     │
│ (operator)│                      │   (Hono)      │
└───────────┘                      └───────┬───────┘
                                            │
                                            ▼
                                    ┌────────────────┐
                                    │  Postgres      │
                                    │  (isolated     │
                                    │   store)       │
                                    └────────────────┘
                                            ▲
                                            │
┌───────────┐       claim          ┌───────┴───────┐
│  Worker   │  ───────────────►    │  Worker auth  │
│ (Browser) │                      │  middleware   │
└───────────┘                      └───────────────┘
```
