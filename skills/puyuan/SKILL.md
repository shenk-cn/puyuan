---
name: puyuan
description: Build and package embedded firmware with Puyuan. Use for MCU compilation, factory images, upgrade packages, build configuration, or toolchain diagnosis in Keil, ESP-IDF, and command-based projects.
license: Apache-2.0
---

# Puyuan firmware builds

Use Puyuan's CLI on the Windows host that has the project and its toolchain. Reuse its build adapters, packaging rules, artifact validation, and JSON results. Follow an explicitly requested alternative build method when the user chooses one.

## Locate the installation

Use an installation path supplied by the user first. Otherwise check the process `PUYUAN_HOME`, the Windows user-level `PUYUAN_HOME`, and then `puyuan.cmd` on `PATH`, in that order. Read the user-level variable with `[Environment]::GetEnvironmentVariable('PUYUAN_HOME','User')`; this also works when the current Codex process has not inherited a newly saved variable. Report an invalid explicit path rather than silently choosing another installation.

For the environment-variable and PATH cases:

```powershell
$puyuanHome = $env:PUYUAN_HOME
if (!$puyuanHome) { $puyuanHome = [Environment]::GetEnvironmentVariable('PUYUAN_HOME', 'User') }
if ($puyuanHome) {
    $puyuan = Join-Path $puyuanHome 'puyuan.cmd'
} else {
    $puyuan = (Get-Command puyuan.cmd -CommandType Application -ErrorAction Stop).Source
    $puyuanHome = Split-Path -Parent $puyuan
}
if (!(Test-Path -LiteralPath $puyuan) -or !(Test-Path -LiteralPath (Join-Path $puyuanHome 'puyuan.ps1'))) {
    throw 'The selected PUYUAN_HOME is not a complete Puyuan installation.'
}
```

Puyuan's default `projects.json` and `toolchains.local.json` are in that installation directory. Honor task-specific `--config` and `--tools` paths, and pass the same choices to subsequent commands. Explicit relative configuration paths are relative to the calling directory.

## Resolve the project and action

Read the target project's `AGENTS.md` and run `project list --json`. If a project ID is supplied by the user or project instructions, verify that its configured root resolves to the intended project. Otherwise match by normalized absolute project directory and, where needed, Target. Resolve each relative project `path` against the directory containing its configuration file. Match Windows paths without case sensitivity. Display names and the current working directory's basename are insufficient to identify a project.

When no entry matches, use `project inspect --path` with the actual project root or build entry point. Read `docs/cli-for-agents.md` from the selected Puyuan installation for configuration generation, and consult its schemas and the relevant `examples` file. Preserve other projects and explicit toolchain choices. An inspection suggestion is one project object, not a complete configuration. A temporary candidate configuration can be validated with `--config` before merging.

Use `all` for an ordinary full build, or the requested `factory` / `upgrade` action. Confirm the requested purpose is actually supported. Factory layouts and upgrade protocols must come from the project; renaming an application image does not create either package. Resolve multiple project or Target candidates from project evidence and the user's intent; report the specific ambiguity when the evidence is insufficient.

## Validate, build, and report

Use noninteractive commands with `--json`. Validate the selected project and preview the requested action, then execute the same plan when a build is within the user's authorized scope. A read-only or preview-only request stops at the plan. Device flashing is a separate task.

After resolving `$projectId` and `$action`, run these separately and inspect each response before proceeding:

| Operation | Command |
|---|---|
| Validate | `& $puyuan project validate --project $projectId --json` |
| Preview | `& $puyuan build --project $projectId --action $action --dry-run --json` |
| Authorized build | `& $puyuan build --project $projectId --action $action --json` |

Missing tools call for `env detect --json` and a check of the reported components, compiler version, SDK, and Python environment. Save detection results when updating local configuration is needed. Do not silently replace an explicitly chosen compiler or change the chip, Target, firmware version, or packaging protocol to make a build pass.

Check the process exit code and the JSON `ok` / `code`. On success, report only the current result's `data.artifacts`: absolute path, size, and SHA256, together with `warnings`, `logs`, and `runDirectory`. On failure, read `error.details`, including nested `cause` data and the current logs, and report the actionable cause. Restored old outputs and files left by previous runs are not current deliverables.

Prefer the selected installation's current schemas, examples, and CLI output over copied assumptions about a project's layout or toolchain.
