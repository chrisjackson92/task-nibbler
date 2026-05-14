---
id: IDX-GETTING-STARTED
title: "Getting Started — New Project Initialization Guide"
type: how-to
status: APPROVED
owner: human
agents: [architect]
tags: [governance, onboarding, setup, new-project]
related: [GOV-007, GOV-008, PRJ-001]
created: 2026-05-14
updated: 2026-05-14
version: 1.0.0
---

> **BLUF:** This guide walks you through the Day 0 process of turning this CODEX template into the project management system for a new product. Follow the steps in order. Do not skip the infrastructure governance conversation.

# Getting Started — New Project Initialization

> **"A project that starts without a plan manages chaos. A project that starts with CODEX governs it."**

---

## What You Have

When you first open this CODEX template, you have:

- ✅ A complete **PM operating system** (GOV-001 through GOV-009)
- ✅ **Agent role definitions** (Architect, Developer, Tester)
- ✅ **Blueprint templates** for database schema, backend, frontend, and API contracts
- ✅ **Agent boot document templates** for project-specific onboarding
- ✅ **Document templates** for sprints, defects, evolution proposals, and more
- 🔲 **No project content** — you fill that in

---

## Step 0: Fork / Clone

This repository is designed to be forked or cloned for each new project. You have two deployment options:

**Option A — Standalone repo** (recommended for most projects):
```bash
git clone [this-repo-url] [your-project-name]-codex
cd [your-project-name]-codex
git remote set-url origin [your-new-remote-url]
```

**Option B — Git submodule** (for multi-repo projects where CODEX is shared):
```bash
# Inside your parent project:
git submodule add [this-repo-url] [project-name]-codex
```

---

## Step 1: Global Search-and-Replace (5 minutes)

Run a find-and-replace across the entire `CODEX/` directory for these placeholder strings:

| Find | Replace With |
|:-----|:-------------|
| `[PROJECT_NAME]` | Your product name (e.g., `Pirquet`, `Acme Platform`) |
| `[YYYY-MM-DD]` | Today's date |
| `[Human — your name]` | Your name or team name |

Most text editors and IDEs support project-wide find-and-replace. After this step, all template headers will have the correct project name and date.

---

## Step 2: Write PRJ-001 — Product Vision

**File:** `05_PROJECT/PRJ-001_product_vision_and_features.md`
**Owner:** Human (you write it, Architect agent maintains it)

This is the most important document in the CODEX. Everything downstream — backlog, blueprints, sprints — derives from it.

Fill in at minimum:
- §1 Product Vision (what it is and for whom)
- §2 Target Users (who benefits)
- §3 Core Features / MVP scope (what needs to exist)
- §7 Release Roadmap (MVP vs. V2 vs. V3)
- §8 Tech Stack Decisions (what you're building with)

Leave §9 Open Decisions empty — the Architect will populate it during planning.

---

## Step 3: Infrastructure Governance Conversation

**Owner:** Human + Architect Agent together

Before ANY sprint planning, the Architect must have a structured conversation with you to resolve:

1. **Deployment model** — Cloud Run? VM? Docker Compose? Serverless?
2. **Cloud provider** — GCP / AWS / Azure / Self-hosted?
3. **Repository structure** — Monorepo or multi-repo?
4. **Database** — Managed cloud DB or self-hosted?
5. **File storage** — S3, local disk, cloud storage?
6. **Shared types strategy** — npm package, contract-first, or copy script?

**Output:** Fill in `10_GOVERNANCE/GOV-008_InfrastructureAndOperations.md`.

> [!IMPORTANT]
> Do not create the backlog (BCK-001) until GOV-008 is complete. Infrastructure decisions change what's in the backlog.

---

## Step 4: Fill in Blueprints

**Owner:** Architect Agent (with Human approval)

Using PRJ-001 and GOV-008, the Architect fills in the four master blueprints:

| File | What to Fill In |
|:-----|:----------------|
| `20_BLUEPRINTS/BLU-002_Database_Schema.md` | All tables, columns, constraints, indexes |
| `20_BLUEPRINTS/BLU-003_Backend_Architecture.md` | Stack decisions, layer contracts, route map |
| `20_BLUEPRINTS/BLU-004_Frontend_Architecture.md` | Framework, state management, component patterns |
| `20_BLUEPRINTS/CON-001_Transport_Contract.md` | Auth protocol, error format, CORS, rate limits |
| `20_BLUEPRINTS/CON-002_API_Contract.md` | Every route, request/response shape, DTO definitions |

Mark each APPROVED only after Human review. Agents may not modify APPROVED blueprints without an `EVO-` proposal.

---

## Step 5: Build the Backlog

**Owner:** Architect Agent

After PRJ-001 and GOV-008 are complete:

1. Read PRJ-001 §3 (Core Features) and §7 (Roadmap)
2. Decompose features into developer tasks
3. Fill in `05_PROJECT/BCK-001_Developer_Backlog.md`
4. Fill in `05_PROJECT/BCK-002_Architect_Backlog.md`

---

## Step 6: Create Agent Boot Documents

**Owner:** Architect Agent

Fill in the project-specific boot documents before spinning up any Developer or Tester agents:

| File | What to Fill In |
|:-----|:----------------|
| `80_AGENTS/AGT-002-BE_Backend_Developer_Boot.md` | VM name, repo path, port, DB name, tech stack versions, specific governance rules |
| `80_AGENTS/AGT-002-FE_Frontend_Developer_Boot.md` | VM name, repo path, port, API types URL, tech stack versions, component library rules |

> [!IMPORTANT]
> These boot docs ARE the agent's onboarding. An agent that reads a vague boot doc will produce vague code. Be specific.

---

## Step 7: Create All Sprint Documents

**Owner:** Architect Agent

Following GOV-007 §9.6 (Full Sprint Visibility), create ALL sprint documents upfront:

1. Review BCK-001 and group items into sprints by dependency order
2. Create `SPR-NNN-BE.md` and `SPR-NNN-FE.md` for each sprint using `_templates/template_sprint.md`
3. Assign sprint numbers sequentially (SPR-001, SPR-002, etc.)
4. Mark all sprints as `PLANNING` status until the Human approves the plan

---

## Step 8: Update MANIFEST.yaml

**Owner:** Architect Agent

After creating all documents, update `00_INDEX/MANIFEST.yaml` with every new document. Per GOV-007 §9.8, a stale MANIFEST is a deployment blocker.

---

## Step 9: Spin Up Developer Agents

**Owner:** Architect Agent

With all of the above complete, you can now spin up Developer Agents:

1. Share `AGT-002-BE.md` (fully filled in) with the Backend Developer Agent
2. Share `AGT-002-FE.md` (fully filled in) with the Frontend Developer Agent
3. Point each agent at their first sprint (`SPR-001-BE.md`, `SPR-001-FE.md`)
4. Agents execute, commit, and notify the Architect when complete

---

## Initialization Checklist

| # | Step | Owner | Done |
|:--|:-----|:------|:-----|
| 0 | Fork/clone the CODEX template | Human | [ ] |
| 1 | Global search-and-replace for `[PROJECT_NAME]` etc. | Human | [ ] |
| 2 | Write PRJ-001 (product vision + tech stack) | Human | [ ] |
| 3 | Infrastructure governance conversation → GOV-008 | Human + Architect | [ ] |
| 4 | Fill in BLU-002, BLU-003, BLU-004, CON-001, CON-002 | Architect | [ ] |
| 5 | Build BCK-001 (dev backlog) and BCK-002 (arch backlog) | Architect | [ ] |
| 6 | Fill in AGT-002-BE and AGT-002-FE boot docs | Architect | [ ] |
| 7 | Create all sprint documents (SPR-001 through SPR-NNN) | Architect | [ ] |
| 8 | Update MANIFEST.yaml | Architect | [ ] |
| 9 | Spin up Developer Agents and begin execution | Architect | [ ] |

---

## Ongoing: What the Architect Does Each Sprint

1. **Spin up Developer Agents** with their sprint doc and boot doc
2. **Monitor progress** — check for blockers in sprint docs
3. **Audit output** — code against CON- contracts
4. **File DEF-NNN** for contract violations
5. **Process EVO-NNN** proposals from developers
6. **Update MANIFEST.yaml** as new docs are created
7. **Close the sprint** after audit passes, move sprint doc to `90_ARCHIVE/`
8. **Brief the Human** with a status summary

---

> *"CODEX doesn't slow you down. Jira does."*
