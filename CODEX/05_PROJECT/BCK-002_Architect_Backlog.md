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
updated: 2026-05-14
version: 1.0.0
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

### Phase 1 — Blueprint & Contract Creation (Next)

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-007 | Fill in BLU-002 (Database Schema) | ARCH-CODEX | PRJ-001 §5 | BLU-002 APPROVED | [ ] Open |
| A-008 | Fill in BLU-002-SD (Seed Data Reference) | ARCH-CODEX | BLU-002 | BLU-002-SD APPROVED | [ ] Open |
| A-009 | Fill in BLU-003 (Backend Architecture — Go + Gin) | ARCH-CODEX | GOV-008 | BLU-003 APPROVED | [ ] Open |
| A-010 | Fill in BLU-004 (Mobile Architecture — Flutter) | ARCH-CODEX | GOV-008 | BLU-004 APPROVED | [ ] Open |
| A-011 | Fill in CON-001 (Transport Contract) | ARCH-CODEX | BLU-003 | CON-001 APPROVED | [ ] Open |
| A-012 | Fill in CON-002 (API Contract — full route map) | ARCH-CODEX | BCK-001 | CON-002 APPROVED | [ ] Open |

---

### Phase 2 — Agent Boot Documents

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-013 | Create AGT-002-BE (Backend Developer Boot doc) | ARCH-CODEX | BLU-003, CON-001, CON-002, RUN-001 | AGT-002-BE | [ ] Open |
| A-014 | Create AGT-002-MB (Mobile Developer Boot doc) | ARCH-CODEX | BLU-004, CON-001, CON-002 | AGT-002-MB | [ ] Open |

---

### Phase 3 — Sprint Document Creation

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-015 | Create SPR-001-BE (Backend Scaffold sprint doc) | ARCH-CODEX | A-009, A-011, A-012, A-013 | SPR-001-BE | [ ] Open |
| A-016 | Create SPR-001-MB (Mobile Scaffold sprint doc) | ARCH-CODEX | A-010, A-014 | SPR-001-MB | [ ] Open |
| A-017 | Create SPR-002-BE (Task CRUD backend sprint doc) | ARCH-CODEX | A-007, A-012 | SPR-002-BE | [ ] Open |
| A-018 | Create SPR-002-MB (Task UI mobile sprint doc) | ARCH-CODEX | SPR-002-BE | SPR-002-MB | [ ] Open |
| A-019 | Create SPR-003-BE (Attachments backend sprint doc) | ARCH-CODEX | A-007 | SPR-003-BE | [ ] Open |
| A-020 | Create SPR-003-MB (Attachments mobile sprint doc) | ARCH-CODEX | SPR-003-BE | SPR-003-MB | [ ] Open |
| A-021 | Create SPR-004-BE (Gamification backend sprint doc) | ARCH-CODEX | A-007, A-012 | SPR-004-BE | [ ] Open |
| A-022 | Create SPR-004-MB (Gamification mobile sprint doc) | ARCH-CODEX | SPR-004-BE | SPR-004-MB | [ ] Open |
| A-023 | Create SPR-005-BE (Recurring tasks backend sprint doc) | ARCH-CODEX | A-007 | SPR-005-BE | [ ] Open |
| A-024 | Create SPR-005-MB (Recurring tasks mobile sprint doc) | ARCH-CODEX | SPR-005-BE | SPR-005-MB | [ ] Open |
| A-025 | Create SPR-006-OPS (Fly.io deployment sprint doc) | ARCH-CODEX | GOV-008, RUN-001, RUN-002 | SPR-006-OPS | [ ] Open |

---

### Phase 4 — Sprint Audits (ongoing, one per sprint)

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-026 | SPR-001-BE Architect Audit | ARCH-AUDIT | SPR-001-BE complete | Audit report + pass/fail | [ ] Open |
| A-027 | SPR-001-MB Architect Audit | ARCH-AUDIT | SPR-001-MB complete | Audit report + pass/fail | [ ] Open |
| A-028 | SPR-002-BE Architect Audit | ARCH-AUDIT | SPR-002-BE complete | Audit report + pass/fail | [ ] Open |
| A-029 | SPR-002-MB Architect Audit | ARCH-AUDIT | SPR-002-MB complete | Audit report + pass/fail | [ ] Open |
| A-030 | SPR-003-BE Architect Audit | ARCH-AUDIT | SPR-003-BE complete | Audit report + pass/fail | [ ] Open |
| A-031 | SPR-003-MB Architect Audit | ARCH-AUDIT | SPR-003-MB complete | Audit report + pass/fail | [ ] Open |
| A-032 | SPR-004-BE Architect Audit | ARCH-AUDIT | SPR-004-BE complete | Audit report + pass/fail | [ ] Open |
| A-033 | SPR-004-MB Architect Audit | ARCH-AUDIT | SPR-004-MB complete | Audit report + pass/fail | [ ] Open |
| A-034 | SPR-005-BE Architect Audit | ARCH-AUDIT | SPR-005-BE complete | Audit report + pass/fail | [ ] Open |
| A-035 | SPR-005-MB Architect Audit | ARCH-AUDIT | SPR-005-MB complete | Audit report + pass/fail | [ ] Open |
| A-036 | SPR-006-OPS Architect Audit | ARCH-AUDIT | SPR-006-OPS complete | Audit report + pass/fail | [ ] Open |

---

### Phase 5 — Integration & Deployment

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-037 | Cross-service contract compliance test (mobile ↔ backend) | ARCH-INTEG | SPR-002-BE + SPR-002-MB complete | All routes return correct schemas | [ ] Open |
| A-038 | Provision Fly.io staging environment | ARCH-INFRA | SPR-006-OPS, GOV-008 | `task-nibbles-api-staging` live | [ ] Open |
| A-039 | Provision Fly.io production environment | ARCH-INFRA | A-038 passed | `task-nibbles-api` live | [ ] Open |
| A-040 | Provision AWS S3 bucket + IAM policy | ARCH-INFRA | GOV-008 | Bucket created, keys issued | [ ] Open |
| A-041 | Set all Fly.io secrets (staging + production) | ARCH-DEPLOY | A-038, A-039, A-040 | fly secrets set complete | [ ] Open |
| A-042 | First deploy to staging | ARCH-DEPLOY | A-041, SPR-001-BE | Staging up, /health 200 | [ ] Open |
| A-043 | Promote staging to production (post all audits) | ARCH-DEPLOY | All audits pass | Tag v1.0.0 on main | [ ] Open |
| A-044 | Configure custom domain + TLS (api.tasknibbles.com) | ARCH-DEPLOY | A-043 | Certificate issued, DNS verified | [ ] Open |

---

### Phase 6 — MANIFEST Update

| ID | Task | Category | Dependencies | Deliverable | Status |
|:---|:-----|:---------|:-------------|:------------|:-------|
| A-045 | Update MANIFEST.yaml (register all new docs) | ARCH-CODEX | A-007–A-025 | MANIFEST current | [ ] Open |

---

> *"The Architect is never idle. When developers build, the Architect audits, tests, and prepares."*
