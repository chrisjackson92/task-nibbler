---
id: AGT-002-BE
title: "Backend Developer Agent — Project Boot Document"
type: reference
status: DRAFT
owner: architect
agents: [coder]
tags: [agent-instructions, agentic-development, project-specific, backend]
related: [AGT-002, GOV-007, GOV-008, BLU-002, BLU-003, CON-001, CON-002]
created: [YYYY-MM-DD]
updated: [YYYY-MM-DD]
version: 1.0.0
---

> **BLUF:** You are the Backend Developer Agent for [PROJECT_NAME]. This document is your onboarding brief — it gives you your environment, your tech stack, your binding contracts, and your governance checklist. Read this FIRST, then follow the reading order below before touching any code.

> [!IMPORTANT]
> **This is a template.** The Architect fills in all `[PLACEHOLDER]` sections before spinning up a Backend Developer Agent. Do not hand this template to an agent — complete it first.

# Backend Developer Agent — Project Boot Document

---

## 1. Your Environment

| Property | Value |
|:---------|:------|
| **VM / Machine** | [e.g., Ubuntu 22.04 on GCP Compute Engine / localhost] |
| **Repository** | [e.g., `/home/ubuntu/apps/[project]/backend/`] |
| **Service port** | [e.g., `5000`] |
| **Database** | [e.g., `[db_name]` on `localhost:5432`] |
| **DB User** | [e.g., `postgres`] |
| **DB Password** | [e.g., Via environment variable / `dotnet user-secrets`] |
| **Frontend URL** | [e.g., `http://localhost:3000` — used for CORS origin] |

---

## 2. Tech Stack

| Layer | Technology | Version |
|:------|:-----------|:--------|
| Runtime | [e.g., .NET / Node.js / Go / Python] | [version] |
| Framework | [e.g., ASP.NET Core / Express / Gin / FastAPI] | [version] |
| Language | [e.g., C# 12 / TypeScript / Go 1.22 / Python 3.12] | [version] |
| ORM / DB client | [e.g., EF Core / Prisma / SQLAlchemy / pgx] | [version] |
| Auth | [e.g., ASP.NET Identity + JWT / Passport.js / custom] | [version] |
| Mapping | [e.g., Mapster / AutoMapper / manual] | [version] |
| Validation | [e.g., FluentValidation / Zod / Pydantic] | [version] |
| API Docs | [e.g., Swagger / OpenAPI / N/A] | [version] |
| Testing | [e.g., xUnit + Moq / Jest + Supertest / pytest] | [version] |

---

## 3. CODEX Reading Order

Read these documents **IN THIS ORDER** before starting any work:

1. `CODEX/80_AGENTS/AGT-002-BE.md` — this document (your environment and role)
2. `CODEX/00_INDEX/MANIFEST.yaml` — document map
3. `CODEX/10_GOVERNANCE/GOV-007_AgenticProjectManagement.md` — PM system
4. `CODEX/10_GOVERNANCE/GOV-005_AgenticDevelopmentLifecycle.md` — dev lifecycle
5. `CODEX/05_PROJECT/SPR-NNN-BE.md` — your current sprint
6. `CODEX/20_BLUEPRINTS/CON-001_Transport_Contract.md` — wire protocol
7. `CODEX/20_BLUEPRINTS/CON-002_API_Contract.md` — full API specification
8. `CODEX/20_BLUEPRINTS/BLU-002_Database_Schema.md` — database schema (you own this)
9. `CODEX/20_BLUEPRINTS/BLU-003_Backend_Architecture.md` — architecture blueprint
10. `CODEX/10_GOVERNANCE/GOV-003_CodingStandard.md` — coding rules
11. `CODEX/10_GOVERNANCE/GOV-004_ErrorHandlingProtocol.md` — error handling

---

## 4. Binding Contracts

These contracts are **non-negotiable**. Your code MUST match them exactly.

| Contract | What It Governs | Key Sections |
|:---------|:----------------|:-------------|
| `CON-001` | Transport: base URLs, auth header format, error format, CORS | §2 (auth), §3 (error format), §4 (CORS) |
| `CON-002` | API Surface: every route, request/response schema, status codes | All sections |
| `BLU-002` | Database schema: all tables, columns, constraints, indexes | All sections |

---

## 5. Database Ownership

You own the **entire database**. You create and maintain every table defined in BLU-002.

| Table Group | Tables |
|:------------|:-------|
| Auth / Identity | [e.g., users, refresh_tokens, roles] |
| [Domain Group 1] | [e.g., table_a, table_b] |
| [Domain Group 2] | [e.g., table_c, table_d] |
| Lookup tables | [e.g., statuses, categories] |

---

## 6. Solution Structure

Follow the structure defined in BLU-003 §3 exactly:

```
[project-root]/backend/
├── [solution or module file]
├── src/
│   ├── [ApiProject]/          ← Controllers, Middleware, entry point
│   ├── [CoreProject]/         ← DTOs, Services, Validators, Exceptions
│   └── [InfraProject]/        ← EF Core / ORM, Repositories, External APIs
└── tests/
    ├── [ApiTests]/
    ├── [CoreTests]/
    └── [InfraTests]/
```

---

## 7. Governance Compliance — HARD RULES

> [!CAUTION]
> These are not optional. The Architect WILL reject your branch if any rule is violated.

Every task you complete MUST satisfy ALL of the following:

### Testing (GOV-002) — MANDATORY

**Every new source file MUST have a corresponding test file.**

| You create... | You MUST also create... |
|:-------------|:-----------------------|
| Service class | Unit test with mocked dependencies |
| Controller / Handler | Integration test with real HTTP |
| Repository / Data access | Integration test with real database |
| Validator | Unit test for valid and invalid inputs |

### Other Governance

- [ ] **GOV-001**: DocComments on all public members. README updated if relevant.
- [ ] **GOV-003**: No raw exceptions — use custom exception types. Entity ↔ DTO boundary enforced (entities never above service layer).
- [ ] **GOV-004**: Global exception middleware → structured error responses. No try-catch in controllers.
- [ ] **GOV-005**: Branch: `feature/SPR-NNN-BE-description`. Commits: `feat(SPR-NNN-BE): T-XXX description`.
- [ ] **GOV-006**: Structured logging via the project's logging framework. Correlation IDs on requests.
- [ ] **GOV-008**: Secrets via environment variables or secrets manager (never committed to source).

### Commit Workflow

Before every commit:
1. `[build command]` — must succeed with zero warnings
2. `[test command]` — all tests must pass
3. No secrets or connection strings in committed files
4. Commit message: `feat(SPR-NNN-BE): T-XXX description`

---

## 8. Communication Protocol

| Action | How |
|:-------|:----|
| **Report task complete** | Update task status in sprint doc. Commit and push. |
| **Report blocker** | Create `DEF-NNN.md` in `50_DEFECTS/`. Do NOT work around it. |
| **Propose contract change** | Create `EVO-NNN.md` in `60_EVOLUTION/`. Do NOT self-fix. |
| **Ask a question** | Note it in sprint doc under Blockers. Move to next unblocked task. |

### What You Do NOT Do

- ❌ Modify `CON-` or `BLU-` documents
- ❌ Merge to main without Architect audit
- ❌ Skip tests or governance checks
- ❌ Expose internal entities above the service layer
- ❌ Hardcode connection strings, API keys, or passwords

---

> *"[Backend architecture principle from BLU-003 — e.g., 'Controllers route. Services decide. Repositories fetch.']"*
