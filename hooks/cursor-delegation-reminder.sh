#!/usr/bin/env bash
# Cursor Agent Delegation Reminder Hook
# This hook reminds Claude to use cursor-agent for expensive operations

# Read the hook input
input=$(cat)

# Parse tool name and input
tool_name=$(echo "$input" | jq -r '.tool_name // ""')
tool_input=$(echo "$input" | jq -r '.tool_input // {}')

# Check for expensive exploration patterns
should_remind=false
reminder_reason=""

# Check for Task tool with Explore subagent (expensive exploration)
if [ "$tool_name" = "Task" ]; then
    subagent_type=$(echo "$input" | jq -r '.tool_input.subagent_type // ""')
    if [ "$subagent_type" = "Explore" ]; then
        should_remind=true
        reminder_reason="Task/Explore subagent detected. Consider using cursor-agent for codebase exploration instead."
    fi
fi

# Check for Grep across many files (broad search)
if [ "$tool_name" = "Grep" ]; then
    pattern=$(echo "$input" | jq -r '.tool_input.pattern // ""')
    path=$(echo "$input" | jq -r '.tool_input.path // ""')
    # If searching from root or workspace root, suggest cursor-agent
    if [ -z "$path" ] || [ "$path" = "." ] || [[ "$path" == "workspaces/"* ]]; then
        should_remind=true
        reminder_reason="Broad Grep search detected. Consider using cursor-agent to batch multiple search queries efficiently."
    fi
fi

# Check for Glob with broad patterns
if [ "$tool_name" = "Glob" ]; then
    pattern=$(echo "$input" | jq -r '.tool_input.pattern // ""')
    # If pattern suggests broad search, remind
    if [[ "$pattern" == "**/"* ]]; then
        should_remind=true
        reminder_reason="Broad file search detected. Consider using cursor-agent to understand codebase structure."
    fi
fi

# Check for Bash commands running cursor-agent without proper timeout
if [ "$tool_name" = "Bash" ]; then
    command=$(echo "$input" | jq -r '.tool_input.command // ""')
    timeout=$(echo "$input" | jq -r '.tool_input.timeout // null')
    
    # Check cursor-agent configuration
    if [[ "$command" == *"cursor-agent"* ]]; then
        run_in_background=$(echo "$input" | jq -r '.tool_input.run_in_background // false')
        
        # Prefer background monitoring over timeout
        if [ "$run_in_background" = "false" ] || [ "$run_in_background" = "null" ]; then
            should_remind=true
            reminder_reason="cursor-agent detected. Use run_in_background=true for process monitoring. See CLAUDE.md monitoring strategy."
        fi
    fi
fi

# Output hook response
if [ "$should_remind" = true ]; then
    # Allow the operation but add a reminder message with specific reason
    cat <<EOF
{
  "userMessage": "⚡ Reminder: $reminder_reason",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
else
    # Allow without message
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
EOF
fi
