# cursor-agent MCP Server

MCP (Model Context Protocol) server that provides clean integration between Claude Code and cursor-agent for efficient codebase exploration.

## Features

- 🚀 **Background Execution**: Run cursor-agent queries asynchronously
- 📊 **Status Monitoring**: Check query progress in real-time
- ⏱️ **Timeout Handling**: Automatic timeout management (default: 10 minutes)
- 🔄 **Process Tracking**: Monitor multiple concurrent queries
- 🎯 **Token Efficient**: Delegates exploration to cursor-agent (company pays)

## Tools Provided

### 1. `cursor_agent_start`
Start a cursor-agent query in the background.

**Input:**
```json
{
  "query": "Find where diffusion loss is calculated. Give file:line references.",
  "model": "auto",
  "force": true,
  "timeout_seconds": 600
}
```

**Output:**
```json
{
  "query_id": "abc-123-def",
  "status": "started",
  "command": "cursor-agent -p '...' --model auto -f",
  "started_at": "2025-01-20T10:30:00Z"
}
```

### 2. `cursor_agent_status`
Check the status of a running query.

**Input:**
```json
{
  "query_id": "abc-123-def"
}
```

**Output:**
```json
{
  "query_id": "abc-123-def",
  "status": "running",
  "output_preview": "First 500 chars...",
  "duration_seconds": 45,
  "exit_code": null
}
```

### 3. `cursor_agent_result`
Get final results (blocks until complete if still running).

**Input:**
```json
{
  "query_id": "abc-123-def",
  "wait": true
}
```

**Output:**
```json
{
  "query_id": "abc-123-def",
  "status": "completed",
  "output": "Complete cursor-agent output...",
  "duration_seconds": 87,
  "exit_code": 0
}
```

## Installation

### 1. Install Dependencies

```bash
cd .claude/mcp-servers/cursor-agent
npm install
```

### 2. Build the Server

```bash
npm run build
```

### 3. Register with Claude Code

```bash
claude mcp add --transport stdio cursor-agent -- \
  node ~/.claude/mcp-servers/cursor-agent/dist/index.js
```

Or add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "cursor-agent": {
      "command": "node",
      "args": [
        "~/.claude/mcp-servers/cursor-agent/dist/index.js"
      ],
      "transport": "stdio"
    }
  }
}
```

### 4. Restart Claude Code

Changes take effect after restart.

## Usage in Claude Skills

Update your `cursor-explorer` skill to use MCP tools instead of Bash:

```markdown
### 1. Start cursor-agent Query

```javascript
// Old approach (Bash)
Bash(command="cursor-agent -p '...' --model auto -f", run_in_background=true)

// New approach (MCP)
const result = mcp__cursor_agent__cursor_agent_start({
  query: "Find where X is implemented. Give file:line references.",
  timeout_seconds: 600
})
// Returns: { query_id: "abc-123", status: "started", ... }
```

### 2. Monitor Status

```javascript
// Check status every 30 seconds
while (true) {
  const status = mcp__cursor_agent__cursor_agent_status({
    query_id: result.query_id
  })

  if (status.status !== "running") break
  sleep(30)
}
```

### 3. Get Results

```javascript
// Get final results (blocks until complete)
const final = mcp__cursor_agent__cursor_agent_result({
  query_id: result.query_id,
  wait: true
})

console.log(final.output)
```

## Benefits vs Bash Approach

| **Feature** | **Bash Approach** | **MCP Server** |
|-------------|------------------|----------------|
| Background execution | Manual (run_in_background) | Automatic |
| Status monitoring | Manual (BashOutput loop) | Built-in tool |
| Process tracking | Manual (bash_id) | Automatic (query_id) |
| Timeout handling | Manual (timeout param) | Automatic |
| Error handling | Exit codes only | Structured status |
| Multiple queries | Complex coordination | Native support |
| Code cleanliness | Verbose loops | Clean tool calls |

## Development

```bash
# Watch mode for development
npm run watch

# Test locally
node dist/index.js
```

## Troubleshooting

**Server not found:**
- Verify installation: `claude mcp list`
- Check path in settings is absolute
- Restart Claude Code after changes

**Query hangs:**
- Default timeout is 10 minutes
- Increase with `timeout_seconds` parameter
- Check cursor-agent is installed: `which cursor-agent`

**No output:**
- Verify cursor-agent works: `cursor-agent -p "test" --model auto -f`
- Check stderr in output (both stdout/stderr captured)

## License

MIT
