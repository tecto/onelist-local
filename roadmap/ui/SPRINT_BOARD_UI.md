# Sprint Board UI — Roadmap Item R5

**Status:** DEFERRED  
**Priority:** LOW  
**Estimated Effort:** 2-3 days  
**Prerequisite:** R1-R4 complete, migration done

---

## Overview

Visual board for sprint management in Onelist.

## Features

### Core
- Kanban columns by status (queued → active → blocked → review → done)
- Drag-drop to change task status
- Sprint selector dropdown
- Filter by owner, priority, tags

### Advanced
- Dependency arrows between tasks
- Blocked task highlighting
- Progress bar / burndown
- Phase grouping within sprint

## Technical Approach

### Frontend
- LiveView component: `SprintBoardLive`
- Real-time updates via PubSub
- Drag-drop via JS hooks (Sortable.js or similar)

### Backend
- Uses existing entry/tag/relationship APIs
- May need WebSocket subscription for live updates
- Query: `GET /api/v1/entries?entry_type=task&tags[]=sprint-009`

### Data Model
Relies on:
- Entry types: `sprint`, `task`, `phase` (R1)
- Relationships: `contains`, `blocks` (R2)
- Metadata: `status`, `priority`, `owner` (R3)

## Mockup

```
┌─────────────────────────────────────────────────────────────────┐
│ Sprint: [SPRINT-009 ▼]  Filter: [All Owners ▼] [All Priority ▼] │
├─────────────────────────────────────────────────────────────────┤
│ QUEUED      │ ACTIVE       │ BLOCKED      │ DONE              │
├─────────────┼──────────────┼──────────────┼───────────────────┤
│ ┌─────────┐ │ ┌──────────┐ │ ┌──────────┐ │ ┌───────────────┐ │
│ │ Task 1  │ │ │ Task 3   │ │ │ Task 5   │ │ │ Task 7        │ │
│ │ @Atlas  │ │ │ @Oracle  │ │ │ blocked  │ │ │ ✅ complete   │ │
│ │ HIGH    │ │ │ MEDIUM   │ │ │ by T3    │ │ │               │ │
│ └─────────┘ │ └──────────┘ │ └──────────┘ │ └───────────────┘ │
│ ┌─────────┐ │              │              │ ┌───────────────┐ │
│ │ Task 2  │ │              │              │ │ Task 8        │ │
│ │ @Forge  │ │              │              │ │ ✅ complete   │ │
│ └─────────┘ │              │              │ └───────────────┘ │
└─────────────┴──────────────┴──────────────┴───────────────────┘
```

## Implementation Notes

1. Start with read-only board (no drag-drop)
2. Add drag-drop after basic view works
3. Dependency arrows are optional polish

## When to Implement

After:
- [ ] SPRINT-009 complete (R1-R4 + migration)
- [ ] At least 2 weeks of Onelist-based work tracking
- [ ] Demand from users for visual board

---

*Deferred from SPRINT-009. Will become separate sprint when prioritized.*
