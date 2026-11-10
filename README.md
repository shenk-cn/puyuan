# Puyuan (蒲元)

English | [简体中文](README.zh-CN.md)

Puyuan is a Windows tool for building and packaging embedded firmware. Register your projects in one configuration file, choose a project and an action, and collect the firmware and logs in a separate directory for each run. Local AI agents can use the same functionality through the CLI.

Puyuan invokes locally installed compilers and SDKs. It supports STM32, GD32, ESP32, and other projects with a command-line build entry point. Use the appropriate programming tool to flash the resulting firmware to a device.

**Start with “Build your first project” below.** This page includes environment setup, project configuration, firmware naming, and troubleshooting. Expand the configuration examples for the project types you use.

The interactive menu supports English and Simplified Chinese, with English as the default. The CLI uses stable English field names and error codes. Additional agent and maintenance guides are currently in Chinese.

- [Build your first project](#first-build): prepare the environment, register a project, check the plan, build, and find the firmware.
- [Configure the local environment](#environment): missing tools, custom installation paths, and multiple tool versions.
- [Choose a project type](#project-types): Keil, ESP-IDF, CubeIDE, CMake, Make, PlatformIO, and custom packagers.
- [Manage projects and firmware names](#configuration): fields, versions, relative paths, and naming rules.
- [Use the CLI or a local AI agent](#cli): commands, options, and when they execute a build.
- [Troubleshoot a failed build](#troubleshooting): logs, error codes, and recovery.

<a id="first-build"></a>

## Build your first project

### 1. Place Puyuan in a stable directory and prepare your build environment

For example, put Puyuan in `C:/tools/puyuan` and keep your firmware project in `C:/work/board`. Your project can stay outside the Puyuan directory.

You need Windows PowerShell 5.1 and the build environment required by your project: the appropriate MDK compiler and device packs for Keil, or the matching SDK and tools for ESP-IDF. Python 3 is also required for the tests and Python-based packagers. Puyuan does not bundle or automatically install these tools. If they are missing, see [environment setup](#environment).

The following examples use `C:/work/board` as the project directory and `board` as its CLI ID. Replace both as needed. **Run all `.\puyuan.cmd` commands from PowerShell in the Puyuan directory.** In File Explorer, open that directory, type `powershell` in the address bar, and press Enter. Run each command at the step where it is explained.

### 2. Launch Puyuan and detect installed tools

Double-click `puyuan.cmd`. On first launch, Puyuan creates either of these configuration files if it is missing:

| File | What it stores | When to edit it |
|---|---|---|
| `toolchains.local.json` | Tool installation directories, Python environments, and the local menu language | A tool is missing, a component is unavailable, or you need another version |
| `projects.json` | Your projects, build methods, and firmware naming rules | You add a project or change its packaging or naming rules |

The title is always `Puyuan`. At the project list, press `L` to switch between English and Chinese and save the preference to `language` in `toolchains.local.json`. You can also edit that field to `en` or `zh-CN`. The default is English when no preference is stored. To override the saved language for one run, use:

```powershell
.\puyuan.cmd --lang zh-CN
```

Use `--lang en` for an English override. Language priority is `--lang`, then the saved local `language`, then English. A command-line override does not overwrite the saved preference; pressing `L` saves a new preference. Tool detection preserves it. Configuration guide paths follow the selected menu language.

Press `E` in the menu to detect tools again and inspect their paths, availability, and missing components. Detection preserves existing manual settings. Finding the components does not establish that a project's compiler version, device packs, and license are all correct; project checks and the actual build provide further validation.

**An empty project list on first launch is expected. Register a project in the next step.** Press `0` to close the menu before editing the configuration. Puyuan does not automatically add every project on your disk.

### 3. Register a project

Start with this **Keil project** example. Open `projects.json` in the Puyuan directory. For a new configuration, use the following contents and save the file as UTF-8:

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "Board",
      "path": "C:/work/board",
      "builder": "keil"
    }
  ]
}
```

This registers `C:/work/board` as a Keil project. The menu shows `Board`, the CLI selects it using `board`, and build deliverables go under Puyuan's `outputs` directory.

| Field | Meaning in this example |
|---|---|
| `schemaVersion` | Configuration format version; use `1` |
| `outputDirectory` | Deliverable directory, defaulting to `outputs`, relative to the configuration file |
| `projects` | The project array; each object is one project |
| `id` | A unique project ID used by CLI commands |
| `name` | The menu label and the default firmware prefix when `projectName` is absent |
| `path` | The actual project root; change this to your directory |
| `builder` | The build method; use `keil` for this example |

This minimal configuration requires exactly one `.uvprojx` / `.uvproj` file and one Target. See [Keil configuration](#keil) when there are multiple files or Targets.

**If your configuration already contains projects, preserve them and append a project object to the `projects` array.** JSON does not support comments or trailing commas. Use paths such as `C:/work/board`; if you use backslashes, escape them as `C:\\work\\board`.

For ESP-IDF or another build system, use the [corresponding complete configuration](#project-types), then continue. **Also replace `board` in subsequent commands with that configuration's `id`; for example, the ESP-IDF example uses `sensor`.** To open the file in an editor, run:

```powershell
notepad .\projects.json
```

### 4. Validate the configuration and preview the build

First check the project configuration. `--project board` selects the ID you registered. This reads project and toolchain information without compiling firmware:

```powershell
.\puyuan.cmd project validate --project board
```

An `ok: true` result with `code: "OK"` means this check passed. Inspect `root`, `target`, and `toolchain` under `data`. Resolve any error using the [troubleshooting table](#troubleshooting).

Next, preview the `all` action. `--dry-run` returns the commands and expected files without running the project's build commands:

```powershell
.\puyuan.cmd build --project board --action all --dry-run
```

Check the tools and arguments in `commands`, and the source paths and deliverable names in `artifacts`. Make sure the intended project and target are selected. Validation and previews may query compiler versions; the actual build happens in the next step.

### 5. Select a project and an action in the menu

Double-click `puyuan.cmd` again. Enter the project number, then select an action. **The menu shows only the actions configured for that project.** Not every project provides all three actions.

| Menu label | CLI action | Meaning |
|---|---|---|
| Build all artifacts | `all` | Build the selected project and deliver all of its declared artifacts |
| Generate factory firmware | `factory` | Deliver the declared factory package, typically for initial programming |
| Generate upgrade firmware | `upgrade` | Deliver the declared update package for an existing device update workflow |

“All” refers to **all deliverables of the selected project**. The minimal Keil configuration produces an application image, so it exposes only `all`. A factory package's Bootloader, partitions, and initial data, or an upgrade package's checksums, signatures, and protocol, must come from the project's build or packaging rules. Changing a filename does not create those contents. See [custom packagers](#packager).

After a successful build, the menu prints firmware paths and the log directory. Press `O` to open the output directory, `L` to view logs, or Enter to return to the project list.

### 6. Find this run's firmware and logs

Each build gets its own directory, for example:

```text
outputs/
└─ board/
   └─ 20261109-120000-a1b2c3d4/
      ├─ Board-application.hex
      ├─ step-1.log
      ├─ keil-1.log
      └─ result.json
```

This example assumes the minimal Keil configuration with HEX output enabled. Names and log counts depend on your project. If HEX output is disabled, the default is to export BIN from the newly built AXF.

`result.json` records the run result. On success, `data.artifacts` contains each file's absolute path, size, and SHA256; `data.logs` contains log paths. Deliver only files listed by the current successful result. Existing files from an earlier build are not evidence that the current build succeeded.

After initial setup, daily use is simply: double-click, select a project, and select an action.

<a id="environment"></a>

## Configure the local environment

### Read the detection result

Run this command in the Puyuan directory to inspect the full detection result. `--save` updates `toolchains.local.json`:

```powershell
.\puyuan.cmd env detect --save
```

For each entry in `data.tools`, inspect `id`, `root`, `available`, `missing`, and `components`:

| Result | Next step |
|---|---|
| No candidates | Install the environment or configure its actual installation path |
| Tools found, but components are missing | Check the expected component paths, install the necessary tools, and validate a real project |
| Multiple installations | Set the project's `toolchain` to an actual ID in the local configuration |
| Components found, but the build fails | Read the current build log and check versions, licenses, device packs, and SDK dependencies |

Detection reads `KEIL_ROOT`, `IDF_PATH`, `PATH`, the Keil registry entries, and common Keil, ST, and Espressif directories on C: and D:, including two subdirectory levels. It does not scan the entire disk. An invalid explicit path is preserved and reported so that you can correct it.

### Configure installation directories manually

Edit `toolchains.local.json` in the Puyuan directory. This complete example registers both Keil and ESP-IDF. **Keep only the environments you actually have, and update the relevant paths.**

<details>
<summary>Expand the local environment configuration</summary>

```json
{
  "schemaVersion": 1,
  "python": "C:/Python313/python.exe",
  "toolchains": [
    {
      "id": "keil-local",
      "kind": "keil",
      "root": "C:/Keil_v5"
    },
    {
      "id": "idf-local",
      "kind": "esp-idf",
      "root": "C:/Espressif/esp-idf-v5.4.3",
      "toolsPath": "C:/Espressif/tools"
    }
  ],
  "language": "en"
}
```

</details>

| Field | Meaning |
|---|---|
| `language` | Saved menu language: `en` or `zh-CN`; defaults to English and is preserved by tool detection |
| Top-level `python` | Python 3 executable used by the `firmware-script` adapter; ordinary Keil builds do not require it |
| `toolchains[].id` | Your unique name for this installation, such as `keil-local` |
| `kind` / `root` | Environment type and installation root; types are `keil`, `esp-idf`, and `cubeide` |
| `compilerRoot` | Optional custom ARMCC directory containing `bin`; register the compiler in µVision as well |
| `toolsPath` | ESP-IDF's downloaded tools and Python environment directory |
| `toolchains[].python` | Optional explicit `Scripts/python.exe` for a particular ESP-IDF virtual environment |

For example, a local entry with ID `keil-local` is selected by `"toolchain": "keil-local"` in the project configuration. Automatically generated IDs may instead be named `keil-1`; use the ID actually present in your file. Registering an installation does not automatically connect it to a `command` builder; that builder's tool paths are defined in `commands`.

### Install the components required by your project

| Project | Required components | Paths to check |
|---|---|---|
| Keil / ARMCC5 | µVision, the required ARMCC5 version, device packs, and a usable license | `root/UV4/UV4.exe`, `root/ARM/ARMCC/bin/armcc.exe` |
| Keil / ARMCLANG6 | µVision, the required ARMCLANG6 version, device packs, and a usable license | `root/ARM/ARMCLANG/bin/armclang.exe`; conversion also requires the matching `fromelf.exe` |
| ESP-IDF | The required SDK, target tools, and matching Python virtual environment | `root/export.bat`, `root/tools/idf.py`, `toolsPath/python_env` |
| CubeIDE | A working STM32CubeIDE installation and project build configuration | `headless-build.bat` in the installation directory |
| CMake / Make / PlatformIO | The build program, cross-compiler, and project dependencies | The configured `executable` or tools used by the command string |

For Keil, inspect `pCCUsed`, `uAC6`, and `PackID` in `.uvprojx`, or use the µVision project options. When an ARMCC5 build number is specified by the project, Puyuan checks it during compiler selection. See the [official µVision command-line reference](https://www.keil.com/support/man/docs/uv4/uv4_commandline.asp).

For ESP-IDF, follow the [official Windows setup instructions](https://docs.espressif.com/projects/esp-idf/en/v5.4.3/esp32/get-started/windows-setup.html) for the SDK version required by your project. Existing real-build acceptance used v5.4.3; this is not a requirement to use that version for every project. Prefer short ASCII paths without spaces for the SDK, tools, and projects. Puyuan looks for a Python environment matching the SDK's major and minor version; set the toolchain entry's `python` when there are multiple candidates.

After installation or configuration changes, run `env detect --save` again, then validate and preview an actual project.

<details>
<summary>Install ESP-IDF target tools and a Python environment from an existing SDK checkout</summary>

Use these commands only after downloading the SDK, initializing its required submodules, and installing a usable base Python. This example installs ESP32 tools; adjust paths and the target for your project:

```powershell
$env:IDF_TOOLS_PATH = 'C:/Espressif/tools'
$idfRoot = 'C:/Espressif/esp-idf-v5.4.3'
python "$idfRoot/tools/idf_tools.py" install --targets esp32
```

After that completes, install the Python environment for the same SDK:

```powershell
python "$idfRoot/tools/idf_tools.py" install-python-env --features core
```

Record the SDK root and tools directory in your local configuration. Puyuan initializes the SDK environment in the build subprocess.

</details>

<a id="project-types"></a>

## Choose a project type

Choose `builder` from the project's actual build entry point. The chip vendor alone does not determine the build method: an STM32 project might use Keil, CubeIDE, or CMake.

| Entry point | Integration | Section and validation status |
|---|---|---|
| `.uvprojx` / `.uvproj` | `keil` | [Keil](#keil); official STM32 and GD32 examples built successfully |
| Root `CMakeLists.txt` includes ESP-IDF's `project.cmake` | `esp-idf` | [ESP-IDF](#esp-idf); official v5.4.3 examples built successfully |
| `.project` and `.cproject` | `command` invoking CubeIDE | [CubeIDE](#cubeide); recipe provided, real environment validation pending |
| Ordinary `CMakeLists.txt` | `command` invoking CMake | [CMake](#cmake); generic invocation tested, project-specific commands need local validation |
| `Makefile` | `command` invoking Make | [Make](#make); generic invocation tested, project-specific commands need local validation |
| `platformio.ini` | `command` invoking PlatformIO | [PlatformIO](#platformio); recipe provided, real environment validation pending |
| Custom build or packaging script | `command`, or compatible `firmware-script` | [Custom packagers](#packager); adapter and failure recovery workflows tested |

If the project has only an `.ioc` file, generate a buildable project with STM32CubeMX first. `project inspect` lists recognized entry points; generic builders still require actual commands and exact artifact paths.

Each example below is a complete `projects.json` saved in the Puyuan directory. **When adding to an existing configuration, merge only the project object. Do not overwrite your existing project list with the entire example.**

<a id="keil"></a>

### Keil: select the project file and Target

For one project file with one Target, use the minimal configuration from the first-build walkthrough. To identify other entry points, run:

```powershell
.\puyuan.cmd project inspect --path "C:/work/board"
```

With one candidate, `suggestedConfig` is a project-object draft to place in `projects`, rather than a complete configuration file. Multiple candidates return `AMBIGUOUS_PROJECT`; select an entry from `error.details.candidates`. Set `projectFile` and `target` accordingly. Target names are case-sensitive.

<details>
<summary>Expand: select a Target and toolchain, and deliver Board-1.2.hex</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "Development board",
      "projectName": "Board",
      "path": "C:/work/board",
      "builder": "keil",
      "projectFile": "MDK-ARM/Board.uvprojx",
      "target": "Release",
      "toolchain": "keil-local",
      "outputFormat": "hex",
      "version": {
        "file": "include/version.h",
        "pattern": "(?m)^#define\\s+BOARD_VERSION\\s+\"([^\"]+)\""
      },
      "artifacts": [
        {
          "kind": "application",
          "source": "{outputDir}/{outputName}.hex",
          "name": "{project}-{version}.{ext}"
        }
      ]
    }
  ]
}
```

This assumes `MDK-ARM/Board.uvprojx`, a Target named `Release`, and a local toolchain named `keil-local`. The header `include/version.h` contains `#define BOARD_VERSION "1.2"`; the first regex capture group reads `1.2`. Replace these values with the actual project settings.

</details>

`outputFormat` accepts `hex`, `bin`, or `axf`. By default, Puyuan uses the project's HEX output, or exports BIN from the current AXF when HEX is disabled. Conversion uses the selected compiler's `fromelf`. Keil rebuilds the selected Target; Puyuan checks its name and the zero-error summary in the log. Warnings may still produce a successful result, with the warning count returned.

<a id="esp-idf"></a>

### ESP-IDF: application, factory, and upgrade images

Register a working `idf-local` toolchain first. The project root must contain a `CMakeLists.txt` that includes ESP-IDF's `project.cmake`. `target` is the chip name, such as `esp32`, and must match an existing `sdkconfig`.

<details>
<summary>Expand the ESP32 application and factory image configuration</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "sensor",
      "name": "ESP32 sensor",
      "projectName": "Sensor",
      "path": "C:/work/sensor",
      "builder": "esp-idf",
      "target": "esp32",
      "toolchain": "idf-local"
    }
  ]
}
```

</details>

Without explicit `artifacts`, this uses the default rules: `all` builds the application, Bootloader, and partitions, then merges an image using the SDK. It delivers `Sensor-factory.bin` and `Sensor-application.bin`. `factory` delivers only the merged image. Flash settings and offsets come from the project's build results.

`outputName` defaults to the root CMake `project(...)` name; set it explicitly for dynamic names. `buildDirectory` defaults to `build` and must remain inside the project directory.

Application updates require a matching device-side OTA workflow, partition layout, and validation. Once these exist, use the following configuration to explicitly declare the application BIN as an upgrade artifact:

<details>
<summary>Expand the application upgrade configuration</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "sensor",
      "name": "ESP32 sensor",
      "projectName": "Sensor",
      "path": "C:/work/sensor",
      "builder": "esp-idf",
      "target": "esp32",
      "toolchain": "idf-local",
      "artifacts": [
        {
          "kind": "factory",
          "source": "{outputDir}/merged-flash.bin",
          "name": "{project}-factory.{ext}"
        },
        {
          "kind": "upgrade",
          "source": "{outputDir}/{outputName}.bin",
          "name": "{project}-upgrade.{ext}"
        }
      ]
    }
  ]
}
```

</details>

With this configuration, the following command runs `idf.py app` and delivers `Sensor-upgrade.bin` without rebuilding the Bootloader:

```powershell
.\puyuan.cmd build --project sensor --action upgrade
```

OTA transfer, validation, and boot confirmation remain part of the device project. Puyuan regenerates the current ELF/BIN and restores the expected previous files if the build fails.

<a id="cubeide"></a>

### STM32CubeIDE: invoke the headless build entry point

Use `command` to invoke the installation's `headless-build.bat`. Read the Eclipse project name from `.project` and the build configuration from `.cproject`; these may differ from the directory name.

<details>
<summary>Expand: build Board/Release and deliver Release/Board.elf</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "CubeIDE board",
      "projectName": "Board",
      "path": "C:/work/cubeide-board",
      "builder": "command",
      "commands": {
        "all": {
          "executable": "C:/Windows/System32/cmd.exe",
          "arguments": [
            "/d",
            "/s",
            "/c",
            "call \"C:/ST/STM32CubeIDE/STM32CubeIDE/headless-build.bat\" -data \"{root}/.builder-workspace\" -import \"{root}\" -cleanBuild \"Board/Release\""
          ]
        }
      },
      "artifacts": [
        {
          "kind": "application",
          "source": "Release/Board.elf",
          "name": "{project}.{ext}"
        }
      ]
    }
  ]
}
```

</details>

Update three things: the actual `headless-build.bat` path, the project/configuration in `Board/Release`, and the output path in `artifacts.source`. The example uses a separate `.builder-workspace` to avoid sharing your interactive IDE workspace. `-import` imports the project and `-cleanBuild` builds the named configuration. This recipe has not yet been accepted against a real CubeIDE installation.

<a id="cmake"></a>

### CMake: use the project's cross-compilation configuration

Prepare the project's toolchain file, CMake, Ninja, and cross-compiler. This example configures the project and performs a clean build, assuming an output of `build/Board.elf`:

<details>
<summary>Expand the complete CMake configuration</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "CMake board",
      "projectName": "Board",
      "path": "C:/work/cmake-board",
      "builder": "command",
      "commands": {
        "all": {
          "executable": "C:/Windows/System32/cmd.exe",
          "arguments": [
            "/d",
            "/s",
            "/c",
            "\"C:/Tools/CMake/bin/cmake.exe\" -S \"{root}\" -B \"{root}/build\" -G Ninja -DCMAKE_TOOLCHAIN_FILE=\"{root}/cmake/arm-gcc.cmake\" && \"C:/Tools/CMake/bin/cmake.exe\" --build \"{root}/build\" --clean-first"
          ]
        }
      },
      "artifacts": [
        {
          "kind": "application",
          "source": "build/Board.elf",
          "name": "{project}.{ext}"
        }
      ]
    }
  ]
}
```

</details>

Adjust the CMake path, generator, `cmake/arm-gcc.cmake`, and ELF output path. A configuration failure prevents the build step from running. For projects using CMakePresets, use their existing configure/build presets instead.

<a id="make"></a>

### Makefile: select the target and exact output file

This example requires `make.exe` and the project's cross-compiler on `PATH`. Its `all` target produces `build/firmware.bin`:

<details>
<summary>Expand the complete Make configuration</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "Make board",
      "projectName": "Board",
      "path": "C:/work/make-board",
      "builder": "command",
      "commands": {
        "all": {
          "executable": "make.exe",
          "arguments": [
            "--always-make",
            "all"
          ]
        }
      },
      "artifacts": [
        {
          "kind": "application",
          "source": "build/firmware.bin",
          "name": "{project}.{ext}"
        }
      ]
    }
  ]
}
```

</details>

`--always-make` causes the rules to run again. Update `arguments` and `artifacts.source` if the project uses other targets, board variables, or output locations.

<a id="platformio"></a>

### PlatformIO: select an environment from platformio.ini

Install [PlatformIO Core](https://docs.platformio.org/en/latest/core/quickstart.html) and make `pio` available on `PATH`, or use its executable's full path in the command string.

<details>
<summary>Expand: build env:esp32dev</summary>

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "PlatformIO board",
      "projectName": "Board",
      "path": "C:/work/pio-board",
      "builder": "command",
      "commands": {
        "all": {
          "executable": "C:/Windows/System32/cmd.exe",
          "arguments": [
            "/d",
            "/s",
            "/c",
            "pio run -e esp32dev -t clean && pio run -e esp32dev"
          ]
        }
      },
      "artifacts": [
        {
          "kind": "application",
          "source": ".pio/build/esp32dev/firmware.bin",
          "name": "{project}.{ext}"
        }
      ]
    }
  ]
}
```

</details>

This corresponds to `[env:esp32dev]` in `platformio.ini`. It cleans that environment's build output, rebuilds it, and delivers `.pio/build/esp32dev/firmware.bin`. Change the command and `source` when the environment, `build_dir`, or output format differs. PlatformIO manages the platform, framework, and compiler. This recipe has not yet been accepted against a real PlatformIO environment.

<a id="packager"></a>

### Custom packagers: integrate factory and upgrade rules

Usually, use `builder: "command"`, invoke the project's complete build script in `commands.all`, and declare its exact output files in `artifacts`. For separate factory or upgrade actions, configure both `commands.factory` / `commands.upgrade` and artifacts with the corresponding `kind`.

Generic commands run with the project's `path` as their working directory. `executable` may be an absolute path, a project-relative path, or a program on `PATH`; each item in `arguments` is one argument. Invoke Python scripts through a Python executable and PowerShell scripts through `powershell.exe -File`. For batch files, use `cmd.exe` with exactly four arguments: `/d`, `/s`, `/c`, and the full command string. See the CubeIDE or CMake example. Keep complex initialization and multi-step packaging in the project's own script.

`successCodes` defaults to `[0]`; change it only when the build program explicitly documents other successful exit codes. A successful command still must produce the expected nonempty, fresh files.

<details>
<summary>Existing scripts that satisfy the firmware-script contract: configuration and requirements</summary>

The `firmware-script` adapter implements a specific packaging contract. Check all requirements before using it:

- A Keil ARMCC5 project whose Python script accepts `--keil ROOT --rebuild` and returns `0` on success.
- One complete invocation produces a factory HEX, an upgrade BIN, and a Keil log with the Target and a zero-error summary.
- The script exposes `envelope(data, numeric_version)` and returns image `bytes`. Upgrade adaptation executes the script's top-level code.
- The software version is `major.minor`. `User_Driver/boot_update.h` has exactly one matching hexadecimal `*_FW_VERSION_ID` macro with value `(major << 16) | minor`.
- The configuration explicitly supplies `script`, `keilLog`, the version source, and exact factory/upgrade files. Tools reside under Keil's `root/ARM/ARMCC`, and the local configuration's top-level `python` is usable.

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "Board firmware",
      "projectName": "Board",
      "path": "C:/work/board",
      "builder": "firmware-script",
      "projectFile": "MDK-ARM/Board.uvprojx",
      "target": "Board",
      "script": "tools/firmware.py",
      "keilLog": "MDK-ARM/build-upgrade.log",
      "upgradeEnvelope": "envelope-v1",
      "version": {
        "file": "User_Driver/boot_update.h",
        "pattern": "(?m)^#define\\s+BOARD_FW_VERSION\\s+\"[^,]+,([^\"]+)\""
      },
      "artifacts": [
        {
          "kind": "factory",
          "source": "{outputDir}/factory-{version}.hex",
          "name": "{project}-factory-{version}.{ext}"
        },
        {
          "kind": "upgrade",
          "source": "{outputDir}/mcu-{version}.bin",
          "name": "{project}-upgrade-{version}.{ext}"
        }
      ]
    }
  ]
}
```

The example header contains `BOARD_FW_VERSION "HW1,1.2"` and `BOARD_FW_VERSION_ID 0x00010002UL`; the regex reads the software version `1.2` after the comma. The deliverables are `Board-factory-1.2.hex` and `Board-upgrade-1.2.bin`.

`all` invokes the complete script once and delivers both files. `factory` also runs the complete script but delivers only the factory file. `upgrade` rebuilds the application, exports the current AXF with `fromelf`, and invokes `envelope`; it does not require an existing `bootloader.bin`. Use `command` for other directory layouts, version encodings, encryption formats, or script interfaces.

</details>

<a id="configuration"></a>

## Manage projects and firmware names

### Keep projects in one projects array

Keep one top-level configuration and put each project object in `projects`, separated by commas. For example, one computer can manage both Keil and ESP-IDF projects:

```json
{
  "schemaVersion": 1,
  "outputDirectory": "outputs",
  "projects": [
    {
      "id": "board",
      "name": "Board",
      "path": "C:/work/board",
      "builder": "keil"
    },
    {
      "id": "sensor",
      "name": "ESP32 sensor",
      "projectName": "Sensor",
      "path": "C:/work/sensor",
      "builder": "esp-idf",
      "target": "esp32",
      "toolchain": "idf-local"
    }
  ]
}
```

`id` must be unique, use letters, digits, `_`, or `-`, and start with a letter or digit. Use a readable menu label and set `projectName` separately for the filename prefix; for example, display `ESP32 sensor` while using `Sensor` in filenames.

### Configure versions and filename templates

The default filename template is `{project}-{kind}.{ext}`, such as `Board-application.hex`. Two settings can override it:

| Setting | Scope | Example |
|---|---|---|
| Top-level `defaultName` | Artifacts without an individual name | `{project}-{kind}-{version}.{ext}` |
| An artifact's `artifacts[].name` | That artifact, with higher priority | `{project}-factory-{version}.{ext}` |

With project name `Board` and version `1.2`, the second template produces `Board-factory-1.2.hex`. The [compatible packager example](#packager) includes complete factory and upgrade naming rules.

**Source paths and deliverable names are separate settings.** `artifacts[].source` points to the file actually produced by the compiler or packager. `name` is the filename used when copying it into this run's delivery directory. It does not rename the compiler's own output.

Before using `{version}`, configure the project's `version` using one of these alternatives:

- A fixed version: `"version": {"value": "1.2"}`.
- A file source: `file` plus `pattern`. The regex must match exactly once and capture the version in group 1. See the complete [Keil example](#keil).

These sources are mutually exclusive. If you do not need a version, omit `version` and use a template without `{version}`.

| Variable | Meaning | Where it can be used |
|---|---|---|
| `{project}` | `projectName`, falling back to `name` | Deliverable names, source paths, command arguments |
| `{version}` | The resolved version | Deliverable names, source paths, command arguments |
| `{target}` / `{date}` | Build target / local date as `yyyyMMdd` | Deliverable names, source paths, command arguments |
| `{kind}` / `{ext}` | Artifact purpose / extension without its dot | Deliverable names |
| `{root}` | Absolute project directory | Source paths, command arguments |
| `{outputDir}` / `{outputName}` | Native Keil / ESP-IDF output directory and base name | Source paths, command arguments |
| `{projectFile}` / `{keil}` / `{fromelf}` | Keil project file / selected installation root / conversion tool | Keil-related command arguments |

Artifact `kind` is `application`, `factory`, or `upgrade`. `source` must identify an exact file inside the project directory; wildcards are not supported. Deliverable names must be valid Windows filenames and unique. The `step-` and `keil-` prefixes, and `result.json`, are reserved for logs and results.

### Look up fields and relative path rules

| Field | Use and default behavior |
|---|---|
| `schemaVersion` / `projects` | Required; format version is `1`, and the project array may be empty |
| `outputDirectory` / `defaultName` | Optional top-level fields, defaulting to `outputs` / `{project}-{kind}.{ext}` |
| `id` / `name` / `path` / `builder` | Required per project: ID, menu label, root directory, and build method |
| `projectName` | Optional deliverable prefix, defaulting to `name` |
| `projectFile` / `target` | Explicit Keil entry point and Target; ESP-IDF uses `target` for the chip |
| `toolchain` | Local toolchain ID; omission requires a unique compatible candidate |
| `outputFormat` | Keil output format: `hex`, `bin`, or `axf` |
| `outputName` / `buildDirectory` | ESP-IDF base name / build directory, defaulting to `project(...)` / `build` |
| `version` / `artifacts` | Version source / output sources, purposes, and names |
| `commands` | Executable and arguments for each `command` action |
| `script` / `keilLog` / `upgradeEnvelope` | Fields specific to the `firmware-script` adapter |
| `$schema` | Optional editor hint; runtime validation uses Puyuan's bundled schemas |

Relative paths are resolved as follows:

| Relative path | Base directory |
|---|---|
| `projects[].path`, top-level `outputDirectory` | The directory containing `projects.json` |
| `projectFile`, `version.file`, `artifacts.source`, project scripts | That project's `path` |
| Local `root`, `compilerRoot`, `toolsPath`, `python` | The directory containing `toolchains.local.json` |
| Explicit CLI `--config` / `--tools` | The caller's current working directory |

See the [project schema](schema/projects.schema.json) and [local tools schema](schema/toolchains.schema.json) for exact constraints. The `examples` directory contains copyable versions of this page's complete configurations.

<a id="cli"></a>

## Use the CLI or a local AI agent

Use the CLI for automation and troubleshooting, or the interactive menu for manual builds. Both use the same configuration files.

| Task | Command from the Puyuan directory | Executes a build? |
|---|---|---|
| List usage | `.\puyuan.cmd help` | No |
| Find installed tools | `.\puyuan.cmd env detect` | No; `--save` persists the environment configuration |
| Inspect entry points and Targets | `.\puyuan.cmd project inspect --path "C:/work/board"` | No; it also does not save a project configuration |
| List registered projects | `.\puyuan.cmd project list` | No |
| Validate configuration and environment | `.\puyuan.cmd project validate --project board` | No; it may query tool versions |
| Preview an action | `.\puyuan.cmd build --project board --action all --dry-run` | No; it may query tool versions |
| Build and deliver artifacts | `.\puyuan.cmd build --project board --action all` | Yes |

`build` defaults to `all` when `--action` is absent. To check another supported action, replace `all` with `factory` or `upgrade` and preview it with `--dry-run` first.

`--lang en` / `--lang zh-CN` temporarily overrides the interactive language. It does not translate project names, compiler logs, JSON fields, or error codes, and does not change the response of noninteractive commands. Unsupported language values return `USAGE`; an invalid saved `language` returns `CONFIG_INVALID` when the local configuration is read.

Commands default to the two configuration files in the Puyuan directory. Use `--config PATH` and `--tools PATH` for alternatives. From another working directory, invoke Puyuan by its full path:

```powershell
& "C:/tools/puyuan/puyuan.cmd" build --project board --action all
```

Local AI agents should use `--json`, parse the single JSON response, and check the process exit code. The [local AI guide (Chinese)](docs/cli-for-agents.md) covers detection, configuration generation, and result handling. Give the agent that guide, the Puyuan directory, and the project directory.

### Enable Puyuan in Codex

The repository includes a reusable [Puyuan skill](skills/puyuan/SKILL.md). Install it at user scope so Codex can use it while working in other firmware repositories. Keeping the skill only inside the Puyuan repository does not make it discoverable from unrelated projects.

1. Install the skill. In Codex, ask the built-in skill installer:

   ```text
   Use $skill-installer to install skills/puyuan from shenk-cn/puyuan into my user-level ~/.agents/skills directory.
   ```

   Alternatively, for a first manual installation, run this from the Puyuan directory in PowerShell. It refuses to overwrite an existing skill:

   ```powershell
   $skillDestination = Join-Path $env:USERPROFILE '.agents/skills/puyuan'
   if (Test-Path -LiteralPath $skillDestination) { throw 'The Puyuan skill already exists. Review it before updating.' }
   New-Item -ItemType Directory -Path (Split-Path -Parent $skillDestination) -Force | Out-Null
   Copy-Item -LiteralPath '.\skills\puyuan' -Destination $skillDestination -Recurse
   ```

2. Record this computer's Puyuan installation directory. Run this while PowerShell is still in the Puyuan directory:

   ```powershell
   [Environment]::SetEnvironmentVariable('PUYUAN_HOME', (Get-Location).Path, 'User')
   ```

   The skill checks the process variable first, then the saved Windows user variable, then `puyuan.cmd` on `PATH`. An installation path supplied in the task takes priority. A user variable is readable by the skill even before the current app inherits a refreshed environment. If an existing process variable points to another installation, update it or restart the app to use the saved value.

3. In a firmware project's existing `AGENTS.md`, add a short routing instruction. Replace `board` with its actual configured project ID and preserve other project instructions:

   ```text
   Use the puyuan skill and Puyuan CLI for firmware builds in this project, unless the user explicitly requests another method.
   The registered Puyuan project ID is board; verify its root matches this project before building.
   Use --json and report current artifact paths, SHA256, warnings, and logs. Keep device flashing a separate task.
   ```

The installed skill is available on the next turn. If it is missing from the skill selector, restart Codex. Then request a firmware build naturally, or invoke `$puyuan` explicitly, for example: “Use $puyuan to generate this project's factory firmware and report its paths and SHA256.” The skill resolves the project, validates and previews the action, and performs an authorized build through the same CLI.

Keep machine paths and project registrations in local configuration. The public skill contains no machine-specific installation or project IDs. It requires terminal access to the Windows build host and the project's actual toolchain. This integration uses the CLI directly; it does not install an MCP server.

<a id="troubleshooting"></a>

## Troubleshoot a failed build

Read `code` and `error.message`, then inspect log paths under `error.details`. Compiler diagnostics are in `step-*.log` or `keil-*.log`; they provide the specific cause behind a build failure.

| Error code or symptom | What to check |
|---|---|
| `USAGE` | Compare commands and options with `help` |
| `CONFIG_MISSING` | Check the default configuration directory or explicit `--config` / `--tools` paths |
| `CONFIG_INVALID` | Check JSON syntax, required fields, unknown fields, duplicate IDs, and version regexes |
| `PROJECT_MISSING` | Check the project ID and directory; detection scans the root and three subdirectory levels, excluding dependencies and build outputs |
| `PROJECT_INVALID` | Check for corrupt project XML or an invalid ESP-IDF root CMake entry |
| `TARGET_MISSING` | Use the exact, case-sensitive Keil `TargetName` |
| `AMBIGUOUS_PROJECT` / `AMBIGUOUS_TARGET` | Select a candidate explicitly through `projectFile` and `target` |
| `TOOLCHAIN_MISSING` | Inspect expected component paths and correct the [local environment](#environment) |
| `AMBIGUOUS_TOOLCHAIN` | Set `toolchain` to an actual candidate ID |
| `TOOLCHAIN_VERSION_MISMATCH` | Install the project's required compiler version and check the ARMCC build number |
| `VERSION_MISSING` | Check the version file and regex: exactly one match, with a nonempty group 1 |
| `TEMPLATE_INVALID` | Check unknown variables, invalid characters, duplicate names, and reserved log names |
| `ACTION_UNSUPPORTED` | Check `supportedActions`, artifact purposes, and the corresponding action command for a `command` builder |
| `PROJECT_BUSY` | Wait for the current build of that project, and keep IDE builds of the same directory idle |
| `TOOL_START_FAILED` | Check the executable, working directory, permissions, and dependencies |
| `BUILD_FAILED` | Read the current log and resolve the compiler error, license issue, or missing dependency |
| `BUILD_TIMEOUT` | Each process defaults to a 30-minute timeout; read the saved output and check for tools waiting for input |
| `ARTIFACT_MISSING` | The declared file was not generated; check `source`, the output base name, and extension |
| `ARTIFACT_STALE` | The file is empty or was not generated by this run; check the build target and packager |
| `INTERNAL_ERROR` | Preserve the complete error, configuration, and reproduction command when reporting a tool issue |

After fixing a configuration, repeat validation, preview, and then the actual build.

**ESP-IDF paths and caches:** A missing header that exists on disk, or failure to create `.obj.d`, may result from expanded path length. Shorten SDK tools, project, and build paths. After changing SDKs, Python environments, or path aliases, use a new `buildDirectory` or clean a disposable old cache according to SDK instructions. Chip changes must also account for `sdkconfig`, partitions, and tool dependencies.

**Recovery:** Puyuan backs up expected previous artifacts and restores them on ordinary failures. Forcefully terminating PowerShell or losing power may leave `.puyuan-*.bak` files. Confirm the build has stopped, then inspect backups and source outputs before recovering needed files. Power loss, disk exhaustion, and device hardware behavior have not been destructively validated.

## Distribution and maintenance

`projects.json`, `toolchains.local.json`, and `outputs` are local data covered by ignore rules. Share the generic configurations in `examples`. Git ignore rules do not remove private data from a manually created ZIP or a browser upload; distribute only the intended source files, documentation, schemas, examples, and license. Do not bundle vendor SDKs, compilers, device firmware, or local build logs.

For development and validation details, see these additional guides, currently in Chinese:

- [Local AI guide](docs/cli-for-agents.md): machine invocation and configuration generation.
- [Tests and failure coverage](docs/testing.md): regression commands, recovery, and validation limits.
- [Public project build records](reports/github-acceptance.md): pinned upstream commits and real-build evidence.
- [Contribution guide](CONTRIBUTING.md): reporting issues, changing code, and maintaining examples.

## License

Puyuan is licensed under the [Apache License 2.0](LICENSE). External compilers, SDKs, and firmware projects retain their own licenses.
