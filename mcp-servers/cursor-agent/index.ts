#!/usr/bin/env -S node
/**
 * cursor-agent MCP Server
 *
 * Provides MCP tools for running cursor-agent queries with background
 * monitoring and status tracking.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn, ChildProcess, execSync } from "child_process";
import { z } from "zod";
import { randomUUID } from "crypto";
import { existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// Process tracking
interface QueryProcess {
  id: string;
  process: ChildProcess;
  query: string;
  output: string;
  status: "running" | "completed" | "failed" | "timeout";
  startedAt: Date;
  completedAt?: Date;
  exitCode?: number;
  timeoutHandle?: NodeJS.Timeout;
}

const activeQueries = new Map<string, QueryProcess>();

// Find cursor-agent executable path
function findCursorAgent(): string {
  // Try common locations
  const candidates = [
    "cursor-agent", // In PATH
    join(homedir(), ".local", "bin", "cursor-agent"),
    join(homedir(), ".local", "bin", "cursor-agent.cmd"),
    join(homedir(), ".local", "bin", "cursor-agent.exe"),
  ];

  for (const candidate of candidates) {
    try {
      // Check if file exists (for absolute paths)
      if (candidate.includes(homedir()) && existsSync(candidate)) {
        return candidate;
      }
      // Try to find in PATH using 'which' or 'where' command
      if (candidate === "cursor-agent") {
        const whichCmd = process.platform === "win32" ? "where" : "which";
        try {
          const result = execSync(`${whichCmd} cursor-agent`, {
            encoding: "utf8",
            stdio: ["ignore", "pipe", "ignore"],
          }).trim();
          if (result) return result.split("\n")[0]; // Return first match
        } catch {
          // Command failed, continue to next candidate
        }
      }
    } catch {
      continue;
    }
  }

  // Fallback to just "cursor-agent" and hope shell finds it
  return "cursor-agent";
}

// Find a working shell executable
// Priority: Git Bash (for Windows-installed tools), WSL (for Linux tools)
function findShell(): { shell: string; args: string[]; type: "wsl-sh" | "wsl-bash" | "bash" | "env-bash" } {
  // On Windows, check for shells
  if (process.platform === "win32") {
    // Try to find Git Bash first (for cursor-agent installed in Windows)
    // Git Bash shares the Windows filesystem, so $HOME resolves correctly
    try {
      const result = execSync("where bash", {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      if (result) {
        // Get all bash paths and filter out WSL bash
        const bashPaths = result.split("\n")
          .map(p => p.replace(/\r/g, '').trim())
          .filter(p => p && existsSync(p));

        // Find Git Bash (exclude System32 and WindowsApps which are WSL launchers)
        const gitBash = bashPaths.find(p =>
          !p.includes("System32") &&
          !p.includes("WindowsApps")
        );

        if (gitBash) {
          return { shell: gitBash, args: ["-c"], type: "bash" };
        }
      }
    } catch {
      // Command failed
    }

    // Try WSL with /bin/sh (works in NixOS and all POSIX systems)
    // Only use WSL if Git Bash isn't available
    try {
      execSync("wsl test -f /bin/sh", {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      // /bin/sh exists in WSL - use it
      return { shell: "wsl", args: ["/bin/sh", "-c"], type: "wsl-sh" };
    } catch {
      // /bin/sh doesn't exist or WSL not available
    }

    // Try WSL with /bin/bash
    try {
      execSync("wsl test -f /bin/bash", {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      // /bin/bash exists in WSL - use it
      return { shell: "wsl", args: ["/bin/bash", "-c"], type: "wsl-bash" };
    } catch {
      // /bin/bash doesn't exist in WSL
    }

    // Fallback to /usr/bin/env bash (works in Git Bash)
    return { shell: "/usr/bin/env", args: ["bash", "-c"], type: "env-bash" };
  }

  // On Unix systems, use standard paths
  if (existsSync("/bin/sh")) {
    return { shell: "/bin/sh", args: ["-c"], type: "wsl-sh" };
  }

  if (existsSync("/bin/bash")) {
    return { shell: "/bin/bash", args: ["-c"], type: "wsl-bash" };
  }

  // Fallback
  return { shell: "/usr/bin/env", args: ["bash", "-c"], type: "env-bash" };
}

// Create server instance
const server = new Server(
  {
    name: "cursor-agent-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Tool 1: Start cursor-agent query
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "cursor_agent_start",
        description:
          "Start a cursor-agent query in the background. Automatically uses --model auto -f (company pays, unlimited usage). Use for token-expensive codebase exploration.",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The query to send to cursor-agent",
            },
            timeout_seconds: {
              type: "number",
              description: "Timeout in seconds (default: 7200 = 120 minutes)",
              default: 7200,
            },
          },
          required: ["query"],
        },
      },
      {
        name: "cursor_agent_status",
        description: "Check the status of a running cursor-agent query",
        inputSchema: {
          type: "object",
          properties: {
            query_id: {
              type: "string",
              description: "The query ID returned from cursor_agent_start",
            },
          },
          required: ["query_id"],
        },
      },
      {
        name: "cursor_agent_result",
        description:
          "Get the final results of a cursor-agent query (blocks until complete if still running)",
        inputSchema: {
          type: "object",
          properties: {
            query_id: {
              type: "string",
              description: "The query ID returned from cursor_agent_start",
            },
            wait: {
              type: "boolean",
              description: "Wait for completion if still running (default: true)",
              default: true,
            },
          },
          required: ["query_id"],
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "cursor_agent_start": {
        const { query, timeout_seconds = 7200 } = args as any;

        const queryId = randomUUID();
        // Find cursor-agent executable
        const cursorAgentPath = findCursorAgent();

        // On Windows with MINGW/Git Bash, cursor-agent is a bash script
        // We need to use bash to execute it
        let command: string[];
        let spawnOptions: any;

        if (process.platform === "win32" && cursorAgentPath.includes(homedir())) {
          // Use shell to execute the script on Windows
          // Find appropriate shell (WSL /bin/sh, WSL /bin/bash, Git Bash, or fallback)
          const { shell, args, type } = findShell();

          // Convert Windows path to appropriate Unix path format based on shell type
          let unixPath: string;
          if (type === "wsl-sh" || type === "wsl-bash") {
            // WSL uses /mnt/c/ format
            unixPath = cursorAgentPath.replace(/\\/g, '/').replace(/^([A-Z]):/, (_, drive) => `/mnt/${drive.toLowerCase()}`);
          } else {
            // Git Bash uses /c/ format
            unixPath = cursorAgentPath.replace(/\\/g, '/').replace(/^([A-Z]):/, (_, drive) => `/${drive.toLowerCase()}`);
          }

          // For Git Bash, run the script directly to avoid shebang issues
          // For WSL, use -c with command string
          if (type === "bash") {
            // Git Bash: run script as argument to bash
            command = [shell, unixPath, "-p", query, "--model", "auto", "-f"];
          } else {
            // WSL: use -c with command string
            const cursorAgentCmd = `"${unixPath}" -p "${query.replace(/"/g, '\\"')}" --model auto -f`;
            command = [shell, ...args, cursorAgentCmd];
          }

          spawnOptions = {
            stdio: ["ignore", "pipe", "pipe"],
            env: { ...process.env },
          };
        } else {
          // Hard-coded: Always use --model auto -f (company pays, unlimited usage)
          command = [cursorAgentPath, "-p", query, "--model", "auto", "-f"];
          spawnOptions = {
            stdio: ["ignore", "pipe", "pipe"],
            env: { ...process.env },
            shell: true,
          };
        }

        // Spawn cursor-agent process
        const proc = spawn(command[0], command.slice(1), spawnOptions);

        let output = "";

        proc.stdout.on("data", (data) => {
          output += data.toString();
        });

        proc.stderr.on("data", (data) => {
          output += data.toString();
        });

        proc.on("close", (code) => {
          const queryProc = activeQueries.get(queryId);
          if (queryProc) {
            queryProc.status = code === 0 ? "completed" : "failed";
            queryProc.exitCode = code ?? undefined;
            queryProc.completedAt = new Date();
            if (queryProc.timeoutHandle) {
              clearTimeout(queryProc.timeoutHandle);
            }
          }
        });

        // Set timeout
        const timeoutHandle = setTimeout(() => {
          const queryProc = activeQueries.get(queryId);
          if (queryProc && queryProc.status === "running") {
            queryProc.process.kill();
            queryProc.status = "timeout";
            queryProc.completedAt = new Date();
          }
        }, timeout_seconds * 1000);

        const queryProcess: QueryProcess = {
          id: queryId,
          process: proc,
          query,
          output: "",
          status: "running",
          startedAt: new Date(),
          timeoutHandle,
        };

        // Store reference with output updates
        const outputRef = { current: "" };
        proc.stdout.on("data", (data) => {
          outputRef.current += data.toString();
        });
        proc.stderr.on("data", (data) => {
          outputRef.current += data.toString();
        });
        Object.defineProperty(queryProcess, "output", {
          get: () => outputRef.current,
        });

        activeQueries.set(queryId, queryProcess);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                query_id: queryId,
                status: "started",
                command: command.join(" "),
                started_at: queryProcess.startedAt.toISOString(),
              }, null, 2),
            },
          ],
        };
      }

      case "cursor_agent_status": {
        const { query_id } = args as any;
        const queryProc = activeQueries.get(query_id);

        if (!queryProc) {
          throw new Error(`Query ID ${query_id} not found`);
        }

        const duration = (
          (queryProc.completedAt ?? new Date()).getTime() -
          queryProc.startedAt.getTime()
        ) / 1000;

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                query_id,
                status: queryProc.status,
                output_preview: queryProc.output.substring(0, 500),
                duration_seconds: Math.round(duration),
                exit_code: queryProc.exitCode,
              }, null, 2),
            },
          ],
        };
      }

      case "cursor_agent_result": {
        const { query_id, wait = true } = args as any;
        const queryProc = activeQueries.get(query_id);

        if (!queryProc) {
          throw new Error(`Query ID ${query_id} not found`);
        }

        // Wait for completion if requested
        if (wait && queryProc.status === "running") {
          await new Promise<void>((resolve) => {
            const checkInterval = setInterval(() => {
              if (queryProc.status !== "running") {
                clearInterval(checkInterval);
                resolve();
              }
            }, 1000);
          });
        }

        const duration = (
          (queryProc.completedAt ?? new Date()).getTime() -
          queryProc.startedAt.getTime()
        ) / 1000;

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                query_id,
                status: queryProc.status,
                output: queryProc.output,
                duration_seconds: Math.round(duration),
                exit_code: queryProc.exitCode,
              }, null, 2),
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            error: error instanceof Error ? error.message : String(error),
          }),
        },
      ],
      isError: true,
    };
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("cursor-agent MCP server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
