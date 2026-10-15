import { copyFile } from "node:fs/promises";
import { dirname, join } from "node:path";

import { describe, expect } from "vitest";

import { workspaceCliTest } from "../../support/cli/workspaceCliFixture.js";
import type { TestWorkspace } from "../../support/workspace/workspaceFixture.js";
import type { TestProcesses } from "../../support/process/processFixture.js";

type RuntimeLayout = "bundled" | "compiled";

const runtimePaths = {
  bundled: {
    mcp: "dist/mcp/main.js",
    mcpDoctor: "dist/cli-runtime/mcpDoctor.js",
    cli: "dist/cli-runtime/cli.js",
    cliOutput: "dist/cli-runtime/cliOutput.js",
    cliResultOutput: "dist/cli-runtime/cliResultOutput.js",
  },
  compiled: {
    mcp: "dist/main.js",
    mcpDoctor: "dist/mcpDoctor.js",
    cli: "dist/cli.js",
    cliOutput: "dist/cliOutput.js",
    cliResultOutput: "dist/cli/cliResultOutput.js",
  },
} as const;

/** Writes runtime stubs that report which layout the dispatcher loaded. */
const writeRuntime = async (
  workspace: TestWorkspace,
  layout: RuntimeLayout,
  empty = false,
): Promise<void> => {
  const paths = runtimePaths[layout];
  const tag = JSON.stringify(layout);
  const modules = {
    [paths.mcp]: `export const runEntrypoint = () => process.stdout.write(JSON.stringify({ adapter: "mcp", layout: ${tag} }));\n`,
    [paths.cli]: `export const cliConfigurationError = () => undefined; export const createCli = () => ({ serve: (args) => process.stdout.write(JSON.stringify({ adapter: "cli", layout: ${tag}, args })) });\n`,
    [paths.cliOutput]:
      "export const normalizeCliOutputArguments = (args) => args; export const validateCliOutputArguments = () => ({ ok: true }); export const renderCliOutputArgumentError = () => ''; export const renderEmptyFilteredCliOutput = () => undefined;\n",
    [paths.cliResultOutput]:
      "export const createCliResultOutput = () => undefined;\n",
    [paths.mcpDoctor]: `export const runProductionMcpDoctorCli = (args) => Promise.resolve({ output: JSON.stringify({ adapter: "mcp-doctor", layout: ${tag}, args }), exitCode: 0 });\n`,
  };
  for (const [path, contents] of Object.entries(modules)) {
    await workspace.mkdir(dirname(path));
    await workspace.write(path, empty ? "" : contents);
  }
};

/** Copies the dispatcher into the workspace and returns a runner for it. */
const prepareDispatcher = async (
  workspace: TestWorkspace,
  processes: TestProcesses,
) => {
  const scripts = await workspace.mkdir("scripts");
  await Promise.all([
    copyFile("scripts/rea.mjs", join(scripts, "rea.mjs")),
    workspace.write(
      "package.json",
      JSON.stringify({ type: "module", version: "1.0.0" }),
    ),
  ]);
  const run = (args: readonly string[]) =>
    processes.run(process.execPath, [join(scripts, "rea.mjs"), ...args], {
      cwd: workspace.root,
    });
  const invoke = async (args: readonly string[]): Promise<unknown> => {
    const { exitCode, stdout } = await run(args);
    expect(exitCode).toBe(0);
    return JSON.parse(stdout) as unknown;
  };
  return { run, invoke };
};

describe("executable dispatcher", () => {
  workspaceCliTest(
    "reserves production MCP routing for bare mode arguments",
    async ({ processes, workspace }) => {
      const { invoke } = await prepareDispatcher(workspace, processes);
      await writeRuntime(workspace, "bundled");
      const layout = "bundled";

      await expect(invoke(["mcp"])).resolves.toEqual({
        adapter: "mcp",
        layout,
      });
      await expect(invoke(["--mcp"])).resolves.toEqual({
        adapter: "mcp",
        layout,
      });
      await expect(invoke(["mcp", "doctor", "--json"])).resolves.toEqual({
        adapter: "mcp-doctor",
        layout,
        args: ["--json"],
      });
      await expect(invoke(["mcp", "add"])).resolves.toEqual({
        adapter: "cli",
        layout,
        args: ["mcp", "add"],
      });
      await expect(invoke(["--mcp", "extra"])).resolves.toEqual({
        adapter: "cli",
        layout,
        args: ["--mcp", "extra"],
      });
    },
  );

  workspaceCliTest(
    "starts compiled runtime modules when bundles are missing or empty",
    async ({ processes, workspace }) => {
      const { invoke } = await prepareDispatcher(workspace, processes);
      await writeRuntime(workspace, "compiled");
      const expectCompiled = async () => {
        const layout = "compiled";
        await expect(invoke(["mcp"])).resolves.toEqual({
          adapter: "mcp",
          layout,
        });
        await expect(invoke(["mcp", "doctor", "--json"])).resolves.toEqual({
          adapter: "mcp-doctor",
          layout,
          args: ["--json"],
        });
        await expect(invoke(["--help"])).resolves.toEqual({
          adapter: "cli",
          layout,
          args: ["--help"],
        });
      };

      await expectCompiled();
      await writeRuntime(workspace, "bundled", true);
      await expectCompiled();
    },
  );

  workspaceCliTest(
    "explains how to restore a missing compiled runtime",
    async ({ processes, workspace }) => {
      const { run } = await prepareDispatcher(workspace, processes);

      for (const args of [["mcp"], ["mcp", "doctor"], ["--help"]]) {
        const result = await run(args);
        expect(result).toMatchObject({
          exitCode: 1,
          stderr: expect.stringContaining(
            "REA's compiled runtime is missing. Run `npm ci && npm run build:cached` in",
          ),
        });
        expect(result.stderr).toContain(
          "If this is an installed package, reinstall rea-agents.",
        );
        expect(result).toMatchObject({
          stderr: expect.not.stringContaining("ERR_MODULE_NOT_FOUND"),
        });
      }
    },
  );
});
