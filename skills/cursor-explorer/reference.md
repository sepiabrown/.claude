# Cursor-Agent Query Reference

*Note: Flags `--model auto -f` are hard-coded in the MCP server.*

## Query Format Best Practices

### ✅ Good Queries (Specific, Batched)
```bash
cursor-agent -p "Find X. For each: 1) file:line, 2) code snippet, 3) purpose." --model auto -f
```

### ❌ Bad Queries (Vague, Unbatched)
```bash
cursor-agent -p "Find X" --model auto -f
cursor-agent -p "What does X do?" --model auto -f
```

## MCP Workflow Pattern (Simple Blocking)

```typescript
// Start query
const start = mcp__cursor_agent__cursor_agent_start({query: "..."})
const queryId = JSON.parse(start).query_id

// Wait for completion (blocks until done)
const result = mcp__cursor_agent__cursor_agent_result({
    query_id: queryId,
    wait: true  // MCP server monitors internally every 1 second
})

// Process results
console.log(JSON.parse(result).output)
```

## Token Cost Estimates

- Small query (1 question): ~500 tokens
- Medium query (3-5 questions): ~1500 tokens
- Large query (comprehensive): ~3000 tokens
- Monitoring (10 minutes): ~600 tokens

**Compare to manual exploration: 10,000-20,000 tokens**
**Savings: 85-95%**
