---
id: GOV-009
title: "Safe Command Execution — Anti-Hang Rules"
type: reference
status: APPROVED
owner: architect
agents: [all]
tags: [governance, standards, workflow, agentic-development, operations]
related: [GOV-005, GOV-008]
created: 2026-03-31
updated: 2026-03-31
version: 1.1.0
---

> **BLUF:** Every agent MUST follow these rules before running any shell command. Violations cause zombie processes, deadlocks, and phantom hangs that block the entire system. Read this before you run anything.

# GOV-009: Safe Command Execution — Anti-Hang Rules

**ALL agents MUST follow these rules.** Violations cause zombie processes that block the system.

---

## Rule 1: NEVER Walk the Full Repo Tree

The repo contains heavy directories (`.venv`, `.git`, `__pycache__`, node_modules, etc.). Walking them causes multi-minute hangs.

**❌ BANNED:**
```bash
# Never do this — hangs for 10+ minutes
find . -name "*.py" -exec python3 -c "..." {} \;
python3 -c "for root, dirs, files in os.walk('.')..."
ruff check .
```

**✅ REQUIRED: Scope to changed files or specific directories:**
```bash
# Use git to get only the files you care about
git diff --name-only HEAD~1 -- '*.py' | xargs python3 -m py_compile
git diff --name-only main -- '*.py' | xargs -I{} ruff check {}

# Or scope to specific directories
ruff check src/engine/
python3 -m py_compile src/engine/llm.py
```

---

## Rule 2: Set GIT_TERMINAL_PROMPT=0 for All Git Network Commands

Prevents git from ever blocking on an interactive credential/passphrase prompt.

```bash
# Always prefix git network commands:
GIT_TERMINAL_PROMPT=0 git fetch origin
GIT_TERMINAL_PROMPT=0 git push origin main
GIT_TERMINAL_PROMPT=0 git pull origin main
```

Local-only git commands (status, log, diff, branch, merge, commit) don't need this.

---

## Rule 3: Use Reasonable WaitMsBeforeAsync Values

| Command type | WaitMsBeforeAsync |
|:---|:---|
| `git status`, `git log`, `git branch` | 3000 |
| `git fetch`, `git push`, `git pull` | 10000 |
| `python3 -m py_compile <file>` | 5000 |
| `python3 -c "import ast; ..."` (AST check) | 5000 |
| `pytest` (single file) | 10000 |
| `pytest` (full suite) | 10000 (will go async) |
| Any `os.walk` or `find` on repo root | **BANNED** |
| `.venv/bin/python3 -c "import ..."` (heavy imports) | 10000 |
| `dotnet restore` | 10000 |
| `dotnet build` (standalone, NO pipe) | 10000 |
| `dotnet test` (standalone, NO pipe) | 10000 |
| `dotnet build 2>&1 \| tail` | **BANNED — see Rule 9** |
| `npm install` | 10000 |
| `npm run build` (standalone, NO pipe) | 10000 |

---

## Rule 4: Kill Before Re-running

If a command hung and you need to retry, **always kill the old one first**:
```
send_command_input(CommandId=..., Terminate=true)
```
Then wait before retrying. Never leave zombie processes.

---

## Rule 5: Syntax Checking — Use AST Parse, Not Imports

Heavy framework imports take 60+ seconds. Use `ast.parse()` instead:

```bash
# ✅ FAST: AST parse (no imports, instant)
python3 -c "import ast; ast.parse(open('src/engine/llm.py').read()); print('OK')"

# ❌ SLOW: Import (loads all framework dependencies — can take 60+ seconds)
.venv/bin/python3 -c "from engine.llm import LLMClient"
```

---

## Rule 6: Use fd/ripgrep Instead of find/grep

```bash
# Use fd (respects .gitignore, skips .venv/.git automatically)
fd -e py --max-depth 3 src/ | xargs python3 -m py_compile

# Use rg instead of grep
rg "some_pattern" src/engine/
```

---

## Rule 7: NEVER Poll command_status More Than Twice

The terminal metadata can show commands as "running" even after completion. This is a **phantom hang**.

**❌ BANNED:**
```
command_status(id, wait=30)  → "RUNNING"
command_status(id, wait=60)  → "RUNNING"
command_status(id, wait=120) → "RUNNING"  ← you are stuck in a loop!
```

**✅ REQUIRED: Max 2 polls, then verify directly:**
```
command_status(id, wait=10)  → "RUNNING, no output"
command_status(id, wait=15)  → "RUNNING, no output"
# STOP POLLING. Run a new verification command instead:
run_command("git log --oneline -1")   # Did the commit happen?
run_command("python3 -c 'import ast; ...'")  # Does it compile?
```

---

## Rule 8: Verify Outcomes, Don't Trust Process Status

Always verify the **result** of an operation rather than its **process status**:

| Instead of checking... | Verify by running... |
|:---|:---|
| "Is git commit still running?" | `git log --oneline -1` |
| "Did the file compile?" | `python3 -c "import ast; ast.parse(open('file').read())"` |
| "Did tests pass?" | Check the test report or re-run a single test |
| "Is the module importable?" | `python3 -c "import ast; ast.parse(...)"` (NOT `import`) |
| "Did dotnet build succeed?" | `dotnet build` exit code — 0 = success |

---

## Rule 9: NEVER Pipe dotnet Output Through tail or grep

Piping `dotnet build` (or `restore`/`test`) through `tail` or `grep` causes a **pipe-buffering deadlock** that hangs indefinitely ~50% of the time:

- `dotnet build` fills the OS pipe buffer (64KB) and **blocks** waiting for the reader
- `tail -n 30` waits for **EOF** before printing anything
- Neither side can proceed → the process hangs forever

**❌ BANNED — these patterns hang:**
```bash
dotnet build 2>&1 | tail -30
dotnet restore && dotnet build 2>&1 | tail -20
dotnet test 2>&1 | grep -E "Passed|Failed"
```

**✅ REQUIRED — run dotnet commands standalone:**
```bash
# Always run separately, never piped to tail/grep
dotnet restore
dotnet build
dotnet test
```

**✅ If you genuinely need only the last N lines, write to a file first:**
```bash
dotnet build > /tmp/build_out.txt 2>&1
cat /tmp/build_out.txt | tail -30
```

**✅ Verify outcomes directly instead of filtering output:**
```bash
# dotnet test always prints a summary line at the end — don't grep it
dotnet test --nologo   # Prints: "Passed! - Failed: 0, Passed: 28, Total: 28"
```

---

## Rule 10: npm/Node Pipe Rules (Same as dotnet)

The same pipe-buffering deadlock applies to long-running Node processes:

**❌ BANNED:**
```bash
npm run build 2>&1 | tail -20
npx tsc --noEmit 2>&1 | grep -i error
```

**✅ REQUIRED — run standalone:**
```bash
npm run build
npx tsc --noEmit
npm run lint
npm test
```
