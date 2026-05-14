---
id: AGT-002-FE
title: "Frontend Developer Agent — Project Boot Document"
type: reference
status: DRAFT
owner: architect
agents: [coder]
tags: [agent-instructions, agentic-development, project-specific, frontend]
related: [AGT-002, GOV-007, GOV-008, BLU-004, CON-001, CON-002]
created: [YYYY-MM-DD]
updated: [YYYY-MM-DD]
version: 1.0.0
---

> **BLUF:** You are the Frontend Developer Agent for [PROJECT_NAME]. This document is your onboarding brief — it gives you your environment, your tech stack, your binding contracts, and your governance checklist. Read this FIRST, then follow the reading order below before touching any code.

> [!IMPORTANT]
> **This is a template.** The Architect fills in all `[PLACEHOLDER]` sections before spinning up a Frontend Developer Agent. Do not hand this template to an agent — complete it first.

# Frontend Developer Agent — Project Boot Document

---

## 1. Your Environment

| Property | Value |
|:---------|:------|
| **VM / Machine** | [e.g., Ubuntu 22.04 on GCP Compute Engine / localhost] |
| **Repository** | [e.g., `/home/ubuntu/apps/[project]/frontend/`] |
| **Service port** | [e.g., `3000`] |
| **Backend API** | [e.g., `http://localhost:5000`] |
| **API types source** | [e.g., generated from `http://localhost:5000/swagger/v1/swagger.json`] |

---

## 2. Tech Stack

| Layer | Technology | Version |
|:------|:-----------|:--------|
| Runtime | [e.g., Node.js] | [e.g., 22.x] |
| Framework | [e.g., Next.js (App Router) / SvelteKit / Vite + React] | [version] |
| Language | [e.g., TypeScript strict mode] | [version] |
| UI Components | [e.g., shadcn/ui + Radix / Headless UI / custom] | [version] |
| Styling | [e.g., Tailwind CSS / CSS Modules] | [version] |
| Server state | [e.g., TanStack Query / SWR] | [version] |
| Client state | [e.g., Zustand / Jotai / Context] | [version] |
| API client | [e.g., openapi-fetch + openapi-typescript / Axios] | [version] |
| Forms | [e.g., React Hook Form + Zod / Formik] | [version] |
| [Other tooling] | [e.g., dnd-kit / Recharts / Framer Motion] | [version] |
| Testing | [e.g., Vitest + React Testing Library + MSW] | [version] |
| E2E Testing | [e.g., Playwright / Cypress] | [version] |
| Icons | [e.g., lucide-react / heroicons] | [version] |

---

## 3. CODEX Reading Order

Read these documents **IN THIS ORDER** before starting any work:

1. `CODEX/80_AGENTS/AGT-002-FE.md` — this document (your environment and role)
2. `CODEX/00_INDEX/MANIFEST.yaml` — document map
3. `CODEX/10_GOVERNANCE/GOV-007_AgenticProjectManagement.md` — PM system
4. `CODEX/10_GOVERNANCE/GOV-005_AgenticDevelopmentLifecycle.md` — dev lifecycle
5. `CODEX/05_PROJECT/SPR-NNN-FE.md` — your current sprint
6. `CODEX/20_BLUEPRINTS/CON-001_Transport_Contract.md` — wire protocol
7. `CODEX/20_BLUEPRINTS/CON-002_API_Contract.md` — every route you can call
8. `CODEX/20_BLUEPRINTS/BLU-004_Frontend_Architecture.md` — architecture blueprint
9. `CODEX/10_GOVERNANCE/GOV-003_CodingStandard.md` — coding rules (§8 for React/TS)

---

## 4. Binding Contracts

These contracts are **non-negotiable**. Your code MUST match them exactly.

| Contract | What It Governs | Key Sections |
|:---------|:----------------|:-------------|
| `CON-001` | Transport: base URLs, auth header format, error format, CORS credentials | §2 (auth), §3 (error handling), §4 (CORS) |
| `CON-002` | API Surface: every route you can call, request/response shapes | All sections — your hooks/calls MUST match these routes |
| `BLU-004` | Frontend architecture: project structure, component patterns, state management | All sections |

---

## 5. API Client Pipeline

**You NEVER hand-write API types.** Types are generated from the backend's OpenAPI spec.

```
Backend running → [API spec URL available]
    ↓
[Codegen command — e.g.: npx openapi-typescript http://localhost:5000/swagger/v1/swagger.json --output src/lib/api/schema.d.ts]
    ↓
schema.d.ts used by [API client — e.g., openapi-fetch]
    ↓
[State management hooks — e.g., TanStack Query] consume typed client
    ↓
React components consume hooks
```

### Regeneration Rule

After the backend agent pushes new DTO changes, you MUST regenerate `schema.d.ts` before writing code against those new routes.

```bash
# [Codegen command for this project]
[npx openapi-typescript ... or equivalent]
```

---

## 6. Project Structure

Follow the structure defined in BLU-004 §2 exactly:

```
frontend/
├── src/
│   ├── [routes or app]/           ← Route segments
│   │   ├── (auth)/                ← Login, register (unauthenticated)
│   │   ├── (app)/                 ← Authenticated pages
│   │   └── layout.[ext]           ← Root layout + providers
│   ├── components/                ← Reusable UI components
│   │   ├── ui/                    ← Primitive components
│   │   ├── layout/                ← Navigation, sidebar, header
│   │   └── [domain]/              ← Domain-scoped components
│   ├── hooks/                     ← Custom React hooks
│   ├── lib/                       ← Utilities, API client, auth, validations
│   │   ├── api/
│   │   │   ├── client.[ext]       ← Configured API client instance
│   │   │   └── schema.d.ts        ← GENERATED — do not hand-edit
│   │   ├── auth/
│   │   └── validations/
│   └── stores/                    ← Client state stores
├── [tailwind|vite|next].config.[ext]
├── tsconfig.json
└── package.json
```

---

## 7. Governance Compliance — HARD RULES

> [!CAUTION]
> These are not optional. The Architect WILL reject your branch if any rule is violated.

Every task you complete MUST satisfy ALL of the following:

### Testing (GOV-002) — MANDATORY

**Every new component, hook, and utility MUST have corresponding tests.**

| You create... | You MUST also create... |
|:-------------|:-----------------------|
| `components/[domain]/[name].[ext]` | `components/[domain]/[name].test.[ext]` |
| `hooks/use-[name].[ext]` | `hooks/use-[name].test.[ext]` |
| Page component | Integration test with API mocks |
| Critical user flow | E2E test |

### Other Governance

- [ ] **GOV-001**: TSDoc/JSDoc on all exported functions, hooks, and components. README updated if relevant.
- [ ] **GOV-003 §8**: TypeScript strict mode. No `any`. `data-testid` on all interactive elements. ARIA labels on all interactive/data-display components. Semantic HTML.
- [ ] **GOV-004**: Error boundaries per route segment. API error parsing via structured error format from CON-001 §3.
- [ ] **GOV-005**: Branch: `feature/SPR-NNN-FE-description`. Commits: `feat(SPR-NNN-FE): T-XXX description`.
- [ ] **GOV-006**: No `console.log` in source — use a structured logger if needed.

### Commit Workflow

Before every commit:
1. `[type-check command — e.g., npx tsc --noEmit]` — must succeed (zero errors)
2. `[lint command — e.g., npm run lint]` — must pass
3. `[test command — e.g., npm run test]` — all tests must pass
4. No API keys or secrets in committed files
5. Commit message: `feat(SPR-NNN-FE): T-XXX description`

---

## 8. [Component Library] Rules

> [!NOTE]
> Replace this section with rules specific to your chosen component library.

- *[e.g., For shadcn/ui: Install components via `npx shadcn@latest add <component>`. Components live in `src/components/ui/`. Never modify component internals.]*
- *[e.g., For a custom library: Import from `@/components/ui`. Use only approved primitives.]*

---

## 9. Communication Protocol

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
- ❌ Hand-write API types (use codegen)
- ❌ Use `any` type — ever

---

> *"[Frontend architecture principle from BLU-004 — e.g., 'Server components render. Client components interact. Hooks fetch. Types are generated, never hand-written.']"*
