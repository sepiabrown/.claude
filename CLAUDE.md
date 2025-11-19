# Personal Configuration

## Core Principle: Token Efficiency

**cursor-agent is free (company pays), your tokens are limited.**

## MCP cursor-agent Usage

**Use proactively** for:
- "Find where X is..." queries → Use MCP tools immediately
- Reading 3+ files → cursor-agent (~1.5k tokens) vs manual (~3k+ tokens)
- Broad searches → cursor-agent ~1k vs Grep+Read ~5k+
- Multi-file tracing, architecture mapping → 3×+ token savings

**Skip** for:
- Single file analysis, pure reasoning, code already in context, 1-2 line answers

**Workflow:**
```python
# Start query
start = mcp__cursor_agent__cursor_agent_start({
  "query": "Find X. Give file:line, code snippets, purpose."
})
query_id = json.loads(start)["query_id"]

# Get result (blocks until done)
result = mcp__cursor_agent__cursor_agent_result({
  "query_id": query_id,
  "wait": True
})
```

Never retry on failure - fall back to Read/Grep.
