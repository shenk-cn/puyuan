# 本地 AI 调用说明

本文面向能读取本地文件、运行终端并写配置的 AI。用户提供蒲元目录和工程目录后，可以按本文完成环境检查、项目配置和构建调用。日常手动使用见 [README](../README.zh-CN.md)。

仓库内的 [Puyuan Skill](../skills/puyuan/SKILL.md) 将本文流程封装为可发现的 Codex 技能。用户级安装、`PUYUAN_HOME` 设置及工程指引示例见 [README 的 Codex 接入说明](../README.zh-CN.md#在-codex-中启用蒲元)。Skill 从选定安装目录读取本文、Schema 和示例，安装副本不依赖仓库外的相对链接。

## 先确定任务和已有授权

把用户提供的蒲元绝对路径记为工具目录，工程绝对路径记为工程根目录。按用户已授权的范围执行；仅配置或只读分析时不编译，已有编译授权时完成构建和结果检查。

本机配置是 `toolchains.local.json`，工程列表是 `projects.json`，默认都位于工具目录。已有文件先读取，保留原条目；添加工程只合并到 `projects` 数组，不覆盖其他工程和手工工具路径。不需要交互菜单，带子命令的 CLI 全程非交互。

交互菜单未设置偏好时默认英文；本机配置顶层 `language` 可保存 `en` / `zh-CN`，菜单工程列表按 `L` 会保存新选择，重新检测环境会保留。启动参数 `--lang` 优先于已保存偏好，且只临时覆盖当前交互语言。它不翻译非交互结果的 JSON 字段或错误码，AI 调用无需设置。

## 1. 检查环境，生成本机配置

以下命令中的路径需替换成用户给出的工具目录。首次运行先检测，暂不保存：

```powershell
$puyuan = 'C:/tools/puyuan/puyuan.cmd'
& $puyuan env detect --json
```

解析 `data.configuration` 与 `data.tools`。每套工具包含 `id`、`kind`、`root`、`available`、`missing` 和组件路径。`guidance` 指向本地 README。检测读取环境变量、PATH、注册表和常见安装目录，不会安装 SDK 或编译器。

读取 `schema/toolchains.schema.json` 后生成或合并配置。顶层必需 `schemaVersion: 1`、`toolchains` 数组；每个工具条目必需唯一 `id`、`kind`、`root`。

| 环境 | 应从实际安装目录核对的内容 |
|---|---|
| `keil` | `UV4/UV4.exe`；ARMCC5 使用 `ARM/ARMCC/bin`，ARMCLANG6 使用 `ARM/ARMCLANG/bin`；格式转换需对应 `fromelf.exe` |
| `esp-idf` | `export.bat`、`tools/idf.py`、`toolsPath` 和匹配 SDK 的虚拟环境 Python；多候选时指定条目内 `python` |
| `cubeide` | `headless-build.bat`；实际项目通过 `command` 配置调用该路径 |
| 通用命令 | 从工程脚本和构建文件确定 `executable`、交叉编译器及 SDK 初始化方式 |

`compilerRoot` 可指定自定义 ARMCC 目录，含 `bin`；顶层 `python` 供兼容打包器使用。相对工具路径以本机配置文件所在目录为基准。完整样例为 `examples/toolchains.example.json`，仅保留实际安装的环境。

确认检测结果适合保存时执行：

```powershell
& $puyuan env detect --save --json
```

已有手工条目及 Python 设置会保留。安装缺失时，报告准确组件、预期路径、工程要求的版本和复查命令；有多套工具时用项目 `toolchain` 选择实际 ID，不能静默改用其他版本。

## 2. 读取真实工程入口，生成项目配置

先执行只读识别：

```powershell
& $puyuan project inspect --path 'C:/work/board' --json
```

一个候选且包含 `data.suggestedConfig` 时，它是单个工程对象草稿；需要放进完整配置的 `projects` 数组。多个候选返回 `AMBIGUOUS_PROJECT`，候选位于 `error.details.candidates`。每个候选可能带 `review` 注意事项。通用工程候选不一定包含可直接用的 `suggestedConfig`。

识别默认扫描根目录及三级子目录，跳过依赖、示例库、构建输出和目录链接。深层入口可直接将工程文件路径传给 `--path`，或明确设置 `projectFile`。

读取 `schema/projects.schema.json`。完整配置必须包含 `schemaVersion: 1` 和 `projects` 数组，每个工程必须有唯一 `id`、`name`、`path`、`builder`。读取对应的可复制示例并结合真实工程修改：

| 工程证据 | 配置方式与例子 | 需要确认的值 |
|---|---|---|
| `.uvprojx` / `.uvproj` | `keil`，`examples/keil.example.json`；最小配置为 `examples/projects.example.json` | XML 中的 `TargetName`、`pCCUsed`、`uAC6`、`PackID`、`OutputDirectory`、`OutputName`、`CreateHexFile` |
| ESP-IDF 根 CMake | `esp-idf`，`examples/esp-idf.example.json` | `project(...)`、`sdkconfig` 的芯片、SDK 版本；动态主名显式填 `outputName` |
| 已有 ESP-IDF OTA 流程 | `examples/esp-idf-ota.example.json` | 分区、已有 Bootloader 与 OTA 实现，升级交付源为应用 BIN |
| `.project` / `.cproject` | `command`，`examples/cubeide.example.json` | Eclipse 工程名、构建配置、headless 脚本路径、输出文件 |
| CMake / Makefile | `command`，`examples/cmake.example.json` / `examples/make.example.json` | 工具链文件、生成器或 Make 目标、实际输出路径 |
| `platformio.ini` | `command`，`examples/platformio.example.json` | `environment`、`build_dir` 与固件格式 |
| 自有打包器 | 通常 `command`；满足特定约定才使用 `examples/firmware-script.example.json` | 真实 CLI、首装布局、升级封装、版本编码、成功退出码和准确源文件 |

只有 `.ioc` 时尚缺构建入口，应先生成实际工程。芯片品牌不能替代工程类型判断。多个候选时依据项目说明和实际构建配置选择；信息仍不够时列出具体候选和缺失依据。

### 产物、路径和动作约定

- `path` 相对于 `projects.json`；`projectFile`、`version.file`、`artifacts.source` 及工程脚本相对于工程 `path`。显式命令行 `--config` / `--tools` 相对于调用目录。
- `projectName` 控制文件名前缀，默认使用 `name`。命名优先用 `artifacts[].name`，其次 `defaultName`，最后 `{project}-{kind}.{ext}`。
- 需要版本时，使用 `version.value`，或 `version.file` 加 `pattern`；两者互斥。正则恰好匹配一次，捕获组 1 为版本。命名例如 `{project}-factory-{version}.{ext}`。
- `source` 是工程内精确文件，不使用通配符；`name` 是交付时重命名，不能借此改变固件布局或协议。
- `all` 针对选中的工程，交付所有声明产物。`factory` / `upgrade` 要有对应 `kind` 的产物；`command` 还要有同名动作命令。缺升级协议依据时只配置可确认的应用构建。
- `command` 每个动作由 `executable` 与 `arguments` 数组组成，以工程 `path` 为工作目录。批处理通过 `cmd.exe` 调用，参数严格为 `/d`、`/s`、`/c`、完整命令字符串；`successCodes` 默认 `[0]`。
- 交付名称可用 `{project}`、`{version}`、`{target}`、`{date}`、`{kind}`、`{ext}`；源路径和命令参数可用 `{root}`、`{project}`、`{version}`、`{target}`、`{date}`。原生构建还提供 `{outputDir}` / `{outputName}`，Keil 另有 `{projectFile}` / `{keil}` / `{fromelf}`。

`firmware-script` 仅适用 Keil ARMCC5：脚本支持 `--keil ROOT --rebuild`；一次生成首装 HEX、升级 BIN 及合规 Keil 日志；公开 `envelope(data, numeric_version)` 并返回 `bytes`。版本为 `major.minor`，`User_Driver/boot_update.h` 中恰有一个 `*_FW_VERSION_ID` 十六进制宏，值为 `(major << 16) | minor`；工具链位于 `root/ARM/ARMCC`，顶层 Python 可用。执行升级时会运行脚本顶层代码。其他接口用 `command` 接入。

候选配置可先保存到独立文件，例如 `C:/Temp/board-projects.json`，用 `--config` 验证后再合并。不得为了通过检查而忽略真实版本、缺失产物或不明的升级协议。

## 3. 检查配置，再预览用户需要的动作

先检查配置、工具链及默认 `all` 计划：

```powershell
& $puyuan project validate --project board --json
```

通过后再预览实际动作，核对 `root`、`target`、`toolchain`、`commands`、`artifacts` 和 `supportedActions`：

```powershell
& $puyuan build --project board --action all --dry-run --json
```

用户需要 `factory` 或 `upgrade` 时，将 `all` 改为对应动作再检查。`project validate` 和 `build --dry-run` 可能查询工具版本，但不会执行工程构建命令。使用独立候选配置时，两条命令都要加同一个 `--config`；使用独立本机配置时加 `--tools`。

## 4. 构建，按结果交付

已有构建授权、计划检查通过后，执行同一动作并去掉 `--dry-run`：

```powershell
& $puyuan build --project board --action all --json
```

`--json` 的 `stdout` 是单个 UTF-8 JSON 对象，编译器原始输出写入日志。检查进程退出码和 `ok` / `code`，不能仅根据固件目录已有文件判断成功。

| 结果 | 处理方式 |
|---|---|
| 成功 | `data` 包含 `projectId`、`action`、`version`、`warnings`、`elapsedSeconds`、`runDirectory`、`logs` 和 `artifacts` |
| 交付文件 | 每个 `artifact` 包含 `kind`、绝对 `path`、`bytes`、`sha256`；只交付这次成功结果列出的文件 |
| 失败 | 读取 `code`、`error.message`、`error.details`；后者可能包含 `candidates`、`supportedActions`、`log` 或 `runDirectory` |

缺工具先修环境，有歧义先明确配置，编译失败先读本次日志。完整错误码与处理集中在 [README 排错表](../README.zh-CN.md#troubleshooting)。

| 退出码 | 含义 |
|---|---|
| `0` | 命令成功；环境检测仍需查看 `available` / `missing`，构建仍需查看 `warnings` |
| `2` | 用法、配置、环境、歧义、工程忙或工具启动失败 |
| `3` | 构建、超时或产物验证失败 |
| `4` | 内部异常，保存复现信息 |

同一工程通过 Mutex 防止蒲元并发构建，冲突返回 `PROJECT_BUSY`；IDE 构建仍需保持空闲。预期旧产物先备份，常规失败会恢复。每次运行保留 `result.json` 与日志，每步进程默认超时 30 分钟。恢复的旧文件不能视作本次交付。[验证范围](testing.md)

## 可直接给 AI 的任务描述

> 工具目录为 `C:/tools/puyuan`，工程目录为 `C:/work/board`。阅读 `docs/cli-for-agents.md`，检查本机环境与实际工程入口，保留已有配置，生成或合并符合 Schema 的工程配置。先运行 `project validate` 和所需动作的 `build --dry-run`，报告缺失组件或有依据仍无法消除的歧义。按照我已授权的任务范围完成构建，返回本次成功固件的路径、SHA256、`warnings` 和日志，或失败的错误码及具体原因。

如果只希望配置，在任务里明确“只生成和验证配置，不执行构建”；需要构建时，明确工程和 `all` / `factory` / `upgrade` 动作即可。
