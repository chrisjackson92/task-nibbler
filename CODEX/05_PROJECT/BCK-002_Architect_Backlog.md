---
id: BCK-002
title: "Architect Agent Backlog — Task Nibbles"
type: planning
status: APPROVED
owner: architect
agents: [architect]
tags: [project-management, backlog, architect, audit, deployment]
related: [BCK-001, GOV-007, GOV-008, RUN-001, RUN-002]
created: 2026-05-14
updated: 2026-05-15
version: 1.1.0
---

> **BLUF:** The Architect Agent has its own work stream parallel to developer sprints. This backlog tracks: CODEX document creation, sprint audits, contract compliance testing, deployment execution, and MANIFEST maintenance. The Architect is never idle while developers build.

# Architect Agent Backlog — Task Nibbles

---

## Work Categories

| Category | Code | Description |
|:---------|:-----|:------------|
| **Infrastructure** | ARCH-INFRA | Environment setup, Fly.io provisioning, S3 bucket configuration |
| **CODEX** | ARCH-CODEX | Document creation/maintenance, MANIFEST, sprint doc creation |
| **Audit** | ARCH-AUDIT | Sprint audit against CON-001/CON-002 contracts + GOV standards |
| **Integration** | ARCH-INTEG | Cross-service contract compliance testing (mobile ↔ backend) |
| **Deploy** | ARCH-DEPLOY | Fly.io deployment execution, environment promotion, rollback |
| **Monitor** | ARCH-MON | Agent progress monitoring, blocker resolution, status reporting |

---

## Backlog

### Phase 0 — CODEX Initialization (Complete ✅)

| ID | Task | Category | Deliverable | Status |
|:---|:-----|:---------|:------------|:-------|
| A-001 | Complete infrastructure governance conversation (GOV-008) | ARCH-INFRA | GOV-008 filled in | ✅ Done |
| A-002 | Fill in PRJ-001 Product Vision from docx requirements | ARCH-CODEX | PRJ-001 APPROVED | ✅ Done |
| A-003 | Create RUN-001 (Fly.io Platform & Development) | ARCH-CODEX | RUN-001 APPROVED | ✅ Done |
| A-004 | Create RUN-002 (Fly.io Deployment Playbook) | ARCH-CODEX | RUN-002 APPROVED | ✅ Done |
| A-005 | Create BCK-001 (Developer Backlog) | ARCH-CODEX | BCK-001 APPROVED | ✅ Done |
| A-006 | Create BCK-002 (this document) | ARCH-CODEX | BCK-002 APPROVED | ✅ Done |

---

### Phase 1 — Blueprint & Contract Creation (Complete ✅)

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-007 | Fill in BLU-002 (Database Schema) | ARCH-CODEX | PRJ-001 §5 | BLU-002 APPROVED | ✅ Done |
| A-008 | Fill in BLU-002-SD (Seed Data Reference) | ARCH-CODEX | BLU-002 | BLU-002-SD APPROVED | ✅ Done |
| A-009 | Fill in BLU-003 (Backend Architecture — Go + Gin) | ARCH-CODEX | GOV-008 | BLU-003 APPROVED | ✅ Done |
| A-010 | Fill in BLU-004 (Mobile Architecture — Flutter) | ARCH-CODEX | GOV-008 | BLU-004 APPROVED | ✅ Done |
| A-011 | Fill in CON-001 (Transport Contract) | ARCH-CODEX | BLU-003 | CON-001 APPROVED | ✅ Done |
| A-012 | Fill in CON-002 (API Contract — full route map) | ARCH-CODEX | BCK-001 | CON-002 APPROVED | ✅ Done |

---

### Phase 2 — Agent Boot Documents (Complete ✅)

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-013 | Create AGT-002-BE (Backend Developer Boot doc) | ARCH-CODEX | BLU-003, CON-001, CON-002, RUN-001 | AGT-002-BE | ✅ Done |
| A-014 | Create AGT-002-MB (Mobile Developer Boot doc) | ARCH-CODEX | BLU-004, CON-001, CON-002 | AGT-002-MB | ✅ Done |

---

### Phase 3 — Sprint Document Creation (Complete ✅)

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-015 | Create SPR-001-BE (Backend Scaffold sprint doc) | ARCH-CODEX | A-009, A-011, A-012, A-013 | SPR-001-BE | ✅ Done |
| A-016 | Create SPR-001-MB (Mobile Scaffold sprint doc) | ARCH-CODEX | A-010, A-014 | SPR-001-MB | ✅ Done |
| A-017 | Create SPR-002-BE (Task CRUD backend sprint doc) | ARCH-CODEX | A-007, A-012 | SPR-002-BE | ✅ Done |
| A-018 | Create SPR-002-MB (Task UI mobile sprint doc) | ARCH-CODEX | SPR-002-BE | SPR-002-MB | ✅ Done |
| A-019 | Create SPR-003-BE (Attachments backend sprint doc) | ARCH-CODEX | A-007 | SPR-003-BE | ✅ Done |
| A-020 | Create SPR-003-MB (Attachments mobile sprint doc) | ARCH-CODEX | SPR-003-BE | SPR-003-MB | ✅ Done |
| A-021 | Create SPR-004-BE (Gamification backend sprint doc) | ARCH-CODEX | A-007, A-012 | SPR-004-BE | ✅ Done |
| A-022 | Create SPR-004-MB (Gamification mobile sprint doc) | ARCH-CODEX | SPR-004-BE | SPR-004-MB | ✅ Done |
| A-023 | Create SPR-005-BE (Recurring tasks backend sprint doc) | ARCH-CODEX | A-007 | SPR-005-BE | ✅ Done |
| A-024 | Create SPR-005-MB (Recurring tasks mobile sprint doc) | ARCH-CODEX | SPR-005-BE | SPR-005-MB | ✅ Done |
| A-025 | Create SPR-006-OPS (Fly.io deployment sprint doc) | ARCH-CODEX | GOV-008, RUN-001, RUN-002 | SPR-006-OPS | ✅ Done |

---

### Phase 4 — Sprint Audits (ongoing, one per sprint)

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-026 | SPR-001-BE Architect Audit | ARCH-AUDIT | SPR-001-BE complete | Audit report + pass/fail | ✅ Done — AUD-001-BE (APPROVED_WITH_NOTES) |
| A-027 | SPR-001-MB Architect Audit | ARCH-AUDIT | SPR-001-MB complete | Audit report + pass/fail | ✅ Done — AUD-005-MB |
| A-028 | SPR-002-BE Architect Audit | ARCH-AUDIT | SPR-002-BE complete | Audit report + pass/fail | ✅ Done — AUD-002-BE |
| A-029 | SPR-002-MB Architect Audit | ARCH-AUDIT | SPR-002-MB complete | Audit report + pass/fail | ✅ Done — AUD-007-MB |
| A-030 | SPR-003-BE Architect Audit | ARCH-AUDIT | SPR-003-BE complete | Audit report + pass/fail | ✅ Done — AUD-003-BE |
| A-031 | SPR-003-MB Architect Audit | ARCH-AUDIT | SPR-003-MB complete | Audit report + pass/fail | ✅ Done — AUD-009-MB |
| A-032 | SPR-004-BE Architect Audit | ARCH-AUDIT | SPR-004-BE complete | Audit report + pass/fail | ✅ Done — AUD-004-BE |
| A-033 | SPR-004-MB Architect Audit | ARCH-AUDIT | SPR-004-MB complete | Audit report + pass/fail | ✅ Done — AUD-010-MB |
| A-034 | SPR-005-BE Architect Audit | ARCH-AUDIT | SPR-005-BE complete | Audit report + pass/fail | ✅ Done — AUD-006-BE |
| A-035 | SPR-005-MB Architect Audit | ARCH-AUDIT | SPR-005-MB complete | Audit report + pass/fail | ✅ Done — AUD-012-MB |
| A-036 | SPR-006-OPS Architect Audit | ARCH-AUDIT | SPR-006-OPS complete | Audit report + pass/fail | ✅ Done — AUD-008-OPS |
| A-046 | SPR-007-BE Architect Audit | ARCH-AUDIT | SPR-007-BE complete | Audit report + pass/fail | ✅ Done — AUD-011-BE |
| A-047 | SPR-008-MB sprint doc creation | ARCH-CODEX | SPR-008-MB complete | SPR-008-MB.md | ✅ Done |
| A-048 | SPR-008-MB Architect Audit | ARCH-AUDIT | SPR-008-MB complete | AUD-013-MB | ✅ Done |
| A-049 | SPR-009-MB sprint doc creation | ARCH-CODEX | SPR-009-MB complete | SPR-009-MB.md | ✅ Done |
| A-050 | SPR-009-MB Architect Audit | ARCH-AUDIT | SPR-009-MB complete | AUD-014-MB | ✅ Done |
| A-051 | PLN-003 sprint planning session | ARCH-CODEX | SPR-009-MB audit done | PLN-003.md | ✅ Done |
| A-052 | BCK-001 update (B-057–B-066, M-040–M-058) | ARCH-CODEX | SPR-008/009 complete | BCK-001 current | ✅ Done |

---

### Phase 5 — Integration & Deployment

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-037 | Cross-service contract compliance test (mobile ↔ backend) | ARCH-INTEG | SPR-002-BE + SPR-002-MB complete | All routes return correct schemas | 🟡 Post-MVP |
| A-038 | Provision Fly.io staging environment | ARCH-INFRA | SPR-006-OPS, GOV-008 | `task-nibbles-api-staging` live | ✅ Done |
| A-039 | Provision Fly.io production environment | ARCH-INFRA | A-038 passed | `task-nibbles-api` live | ✅ Done |
| A-040 | Provision AWS S3 bucket + IAM policy | ARCH-INFRA | GOV-008 | Bucket created, keys issued | ✅ Done |
| A-041 | Set all Fly.io secrets (staging + production) | ARCH-DEPLOY | A-038, A-039, A-040 | fly secrets set complete | ✅ Done |
| A-042 | First deploy to staging | ARCH-DEPLOY | A-041, SPR-001-BE | Staging up, /health 200 | ✅ Done |
| A-043 | Promote staging to production (post all audits) | ARCH-DEPLOY | All audits pass | Tag v1.0.0 on main | ⏳ Pending Human approval |
| A-044 | Configure custom domain + TLS (api.tasknibbles.com) | ARCH-DEPLOY | A-043 | Certificate issued, DNS verified | [ ] Open |
| A-053 | Update CON-002 with 3 new SPR-009-MB endpoints | ARCH-CODEX | SPR-009-MB audit | CON-002 current | ✅ Done |
| A-054 | Create SPR-010-MB sprint doc | ARCH-CODEX | PLN-003 | SPR-010-MB.md | ✅ Done |
| A-055 | MANIFEST.yaml update (SPR-008, SPR-009, AUD-013, AUD-014, PLN-003) | ARCH-CODEX | All docs created | MANIFEST current | ✅ Done |

---

### Phase 6 — MANIFEST Update

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-045 | Update MANIFEST.yaml (register all new docs) | ARCH-CODEX | A-007–A-025 | MANIFEST current | [ ] Open |

---

> *"The Architect is never idle. When developers build, the Architect audits, tests, and prepares."*
