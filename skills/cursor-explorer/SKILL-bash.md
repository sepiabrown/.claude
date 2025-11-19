---
name: cursor-explorer
description: Use for token-expensive operations requiring multi-file analysis - codebase exploration, broad searches, architecture understanding, tracing flows, finding implementations across files. Delegates to cursor-agent (company pays) with background monitoring. Do NOT use for single-file analysis, explaining code already in immediate context, or pure reasoning tasks.
allowed-tools: Bash, BashOutput, Read
---

# Cursor Explorer Skill

This skill provides efficient codebase exploration using cursor-agent with background monitoring.

## When to Use (Token Economics)

Trigger when answering would require:
- **Reading 3+ files** → Use cursor-agent (~1,500 tokens) vs manual reads (~3,000+ tokens)
- **Broad searches** → cursor-agent ~1,000 tokens vs Grep+Read ~5,000+ tokens
- **Multi-file tracing** → cursor-agent ~2,000 tokens vs manual exploration ~10,000+ tokens
- **Architecture mapping** → cursor-agent ~1,500 tokens vs reading many files ~8,000+ tokens

**Rule: If manual approach costs 3x more tokens → use cursor-agent**

## When NOT to Use

Skip cursor-agent when:
- **Single file in context** → Just read/explain it (~200 tokens)
- **Pure reasoning** → No file reads needed (use your expertise)
- **Code already shown** → User pasted code, just analyze it
- **Tiny scope** → Answer needs only 1-2 specific lines

## Workflow

### 1. Start cursor-agent in Background

```bash
Bash(
    command="cursor-agent -p '<batched query>' --model auto -f",
    run_in_background=true,
    description="Start cursor-agent exploration"
)
```

**Query Guidelines:**
- Batch multiple questions into one query
- Request file:line references
- Ask for code snippets
- Be specific about format

**Example batched query:**
```
"Find where X is implemented. For each location: 1) Give file:line reference, 2) Show code snippet, 3) Explain how it works, 4) List dependencies."
```

### 2. Monitor Process Status

```bash
# Loop until completion:
while cursor-agent is running:
    BashOutput(bash_id="<id>")  # Check status

    if status == "completed":
        break

    if status == "running":
        Bash(command="sleep 30", timeout=35000)  # Wait 30 seconds
        continue

    if status == "failed":
        # Accept failure, fall back to manual exploration
        break
```

### 3. Process Results

Once cursor-agent completes:
- Parse the output for file:line references
- Use Read tool for targeted file access
- Summarize findings for the user
- Provide actionable next steps

### 4. Never Retry

If cursor-agent fails or times out:
- Accept it as genuine failure
- Fall back to Read/Grep for targeted searches
- Don't retry cursor-agent

## Tool Restrictions

This skill is restricted to:
- `Bash`: For running cursor-agent and monitoring
- `BashOutput`: For checking process status
- `Read`: For reading specific files identified by cursor-agent

**No editing, writing, or broad searches allowed during exploration phase.**

## Token Efficiency

- cursor-agent query: ~500-2000 tokens (cursor's cost, company pays)
- Monitoring overhead: ~30 tokens per 30-second cycle
- Targeted reads: ~200-500 tokens per file
- **Total: 90%+ savings vs manual exploration**

## Examples

### Example 1: Find Implementation
**User:** "Where is the diffusion loss calculated?"

**Skill actions:**
```bash
# Start cursor-agent
Bash(
    command="cursor-agent -p 'Find where diffusion loss is calculated. Give file:line references and code snippets.' --model auto -f",
    run_in_background=true
)

# Monitor until complete (30-second intervals)
# Process results and summarize
```

### Example 2: Understand Architecture
**User:** "How does the training pipeline work?"

**Skill actions:**
```bash
# Batched query
Bash(
    command="cursor-agent -p 'Explain the training pipeline: 1) Data loading (file:line), 2) Model initialization (file:line), 3) Training loop (file:line), 4) Loss calculation (file:line). Show code snippets.' --model auto -f",
    run_in_background=true
)

# Monitor and summarize
```

## Key Principles

1. **Always batch questions** - One cursor-agent call > multiple calls
2. **Monitor patiently** - Let cursor-agent take as long as needed
3. **Request specific formats** - file:line, code snippets, explanations
4. **Read-only exploration** - No edits during investigation phase
5. **Trust cursor's findings** - Use the references directly
