# 蒲元（Puyuan）

[English](README.md) | 简体中文

蒲元是一个 Windows 固件构建工具：把多个嵌入式工程登记在配置文件中，双击启动，选择工程和操作，即可编译、打包，并把固件和日志放进独立的交付目录。也支持本地 AI 通过命令行调用。

它调用本机已有的编译器和 SDK，适用于 STM32、GD32、ESP32 等工程。产出固件后，设备烧录由对应的烧录工具完成。

**第一次使用，按下面的“完成第一次构建”逐步操作即可。** 环境安装、工程配置、文件命名和排错都在本页；不同类型的完整配置可在对应小节展开。

- [完成第一次构建](#first-build)：准备环境 → 添加工程 → 检查 → 从菜单编译 → 找到固件。
- [配置本机环境](#environment)：自动检测不到、工具缺失或安装了多个版本时看这里。
- [选择工程类型](#project-types)：Keil、ESP-IDF、CubeIDE、CMake、Make、PlatformIO 和自有打包器。
- [配置多个工程和固件名称](#configuration)：配置字段、版本、路径及命名规则。
- [从命令行或本地 AI 调用](#cli)：各条命令的用途和参数。
- [构建失败时怎么查](#troubleshooting)：日志、常见错误及处理方法。

<a id="first-build"></a>

## 完成第一次构建

### 1. 放好工具，准备项目的编译环境

把蒲元放在一个固定目录，例如 `C:/tools/puyuan`。工程可以放在其他目录，例如 `C:/work/board`，不需要搬进蒲元目录。

需要 Windows PowerShell 5.1，以及工程所需的编译环境：Keil 工程安装对应 MDK 编译器和器件包，ESP-IDF 工程安装对应 SDK 及其工具。运行测试或 Python 打包脚本时还需要 Python 3。蒲元不内置、也不会自动下载安装这些工具；没有环境时先看[本机环境配置](#environment)。

下文的 `C:/work/board` 是示例工程路径，`board` 是给它起的命令行 ID。请按实际情况修改。**所有 `.\puyuan.cmd` 命令都在蒲元目录内的 PowerShell 中执行。** 在资源管理器中打开蒲元目录，在地址栏输入 `powershell` 并回车，即可在正确目录打开终端。下面的命令按步骤分别执行。

### 2. 双击启动，让蒲元检测环境

双击 `puyuan.cmd`。首次启动缺少配置文件时，会创建：

| 文件 | 保存什么 | 何时需要修改 |
|---|---|---|
| `toolchains.local.json` | 这台电脑的工具安装目录、Python 环境和菜单语言 | 没检测到工具、缺组件、需要选择其他版本时 |
| `projects.json` | 你要管理的工程、构建方式及固件名称 | 每次添加工程，或调整打包和命名规则时 |

标题固定为 `Puyuan`，未保存偏好时菜单默认英文。在工程列表按 `L` 可切换中英文，并将偏好保存到 `toolchains.local.json` 的 `language` 字段，下次启动继续使用。也可手工将该字段设为 `en` 或 `zh-CN`。如需临时覆盖已保存的语言，在蒲元目录执行：

```powershell
.\puyuan.cmd --lang zh-CN
```

也可用 `--lang en` 临时使用英文。优先级为命令行 `--lang`、本机配置的 `language`、默认英文；启动参数不覆盖已保存偏好，按 `L` 才保存新选择。重新检测环境会保留语言偏好。配置指南路径随菜单语言切换；本页下方的操作名称使用中文菜单中的文字。

菜单中按 `E` 可重新检测，并查看每套工具的路径、可用状态及缺项。检测会保留已有的手工配置。检测结果只说明找到了相应组件；工程要求的具体编译器版本、器件包和许可证还会在后续检查或编译时验证。

**首次没有工程序号是正常的：需要先在下一步登记工程。** 按 `0` 退出菜单后编辑配置。蒲元不会自动把磁盘上的所有工程加入列表。

### 3. 把一个工程加入配置

下面先以 **Keil 工程**为例。打开蒲元目录下的 `projects.json`，首次配置可将内容改为下面这样，并以 UTF-8 编码保存：

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

这个配置的意思是：把 `C:/work/board` 当作一个 Keil 工程，菜单显示 `Board`，命令行用 `board` 来选中它，构建结果放在蒲元的 `outputs` 目录。

| 字段 | 本例的作用 |
|---|---|
| `schemaVersion` | 配置格式版本，填写 `1` |
| `outputDirectory` | 交付目录，默认 `outputs`；相对于 `projects.json` 所在目录 |
| `projects` | 工程列表；每个 `{ ... }` 是一个工程 |
| `id` | 工程的唯一 ID，后面的命令使用它 |
| `name` | 菜单中的名称；未设置 `projectName` 时也用作固件名前缀 |
| `path` | 实际工程根目录，先把这里改对 |
| `builder` | 构建方式，Keil 工程填写 `keil` |

此最小配置要求工程下只有一个 `.uvprojx` / `.uvproj` 文件，且里面只有一个 Target。多个入口或 Target 的处理见 [Keil 配置](#keil)。

**如果已有工程配置，保留原来的条目，只向 `projects` 数组追加一个工程。** JSON 不支持注释，最后一项后面不能有多余逗号；路径建议写成 `C:/work/board`，使用反斜杠时需写成 `C:\\work\\board`。

ESP-IDF 或其他类型请改用[对应的完整配置](#project-types)，再继续下一步。**后续命令里的 `board` 也要换成该配置的 `id`，例如 ESP-IDF 示例使用 `sensor`。** 需要用编辑器打开文件时，可以在蒲元目录执行这一条命令：

```powershell
notepad .\projects.json
```

### 4. 检查配置，再预览构建内容

先运行配置检查。`--project board` 指定刚才登记的 `id`；这一步会读取工程及工具链信息，不编译固件。

```powershell
.\puyuan.cmd project validate --project board
```

返回 `ok: true`、`code: "OK"` 表示这一步通过。`data` 中可核对工程根目录 `root`、目标 `target`、工具链 `toolchain`。报错时先按[排错表](#troubleshooting)修正。

然后预览一次“全部编译”的计划。`--dry-run` 表示只显示将运行的命令和预期文件，不运行工程构建命令：

```powershell
.\puyuan.cmd build --project board --action all --dry-run
```

检查 `commands` 中的工具和参数、`artifacts` 中的源文件及交付名称，确认选中了预期工程和目标。检查和预览可能查询编译器版本；真正的编译在下一步进行。

### 5. 从菜单选择工程和操作

再次双击 `puyuan.cmd`，输入工程前面的序号，再按提示选择操作。**菜单只显示该工程已配置的操作**，并非每个工程都有三个选项。

| 菜单操作 | 命令行动作 | 含义 |
|---|---|---|
| 全部编译 | `all` | 构建当前选中工程，交付该工程声明的全部固件 |
| 生成首装固件 | `factory` | 交付该工程声明的首装包，通常用于首次烧录 |
| 生成升级固件 | `upgrade` | 交付该工程声明的升级包，供已有设备升级流程使用 |

“全部”指**选中工程的全部交付物**。上面的最小 Keil 配置只生成应用固件，因此菜单只有“全部编译”。首装包中的 Bootloader、分区、初始数据，以及升级包的校验和、签名和协议，需要来自工程本身的构建或打包规则；仅修改文件名不会补齐这些内容。接入方法见[自有打包器](#packager)。

构建成功后，菜单会打印固件路径和日志目录。按 `O` 打开产物目录，按 `L` 查看日志，直接按 Enter 返回工程列表。

### 6. 找到本次固件和日志

每次构建使用独立目录，例如：

```text
outputs/
└─ board/
   └─ 20261109-120000-a1b2c3d4/
      ├─ Board-application.hex
      ├─ step-1.log
      ├─ keil-1.log
      └─ result.json
```

这个例子对应最小 Keil 配置且工程启用了 HEX 输出。具体固件名和日志数量取决于工程配置。工程关闭 HEX 时默认从本次 AXF 导出 BIN。

`result.json` 记录本次结果。成功结果中的 `data.artifacts` 给出固件的完整路径、大小及 SHA256，`data.logs` 给出日志位置。交付时使用本次成功结果列出的文件；构建失败时不要把旧文件当成本次成果。

完成首次配置后，日常使用只需“双击 → 选工程 → 选操作”。

<a id="environment"></a>

## 配置本机环境

### 查看检测结果，判断要补什么

在蒲元目录运行下面这条命令，可以看到完整的环境检测结果；`--save` 会更新 `toolchains.local.json`。

```powershell
.\puyuan.cmd env detect --save
```

重点看 `data.tools` 中每项的 `id`、`root`、`available`、`missing` 和 `components`：

| 结果 | 下一步 |
|---|---|
| 没有候选 | 安装环境，或在配置中填写真实安装路径 |
| 已找到，存在缺项 | 对照组件的预期路径补齐对应工具；再用实际工程检查 |
| 找到多套版本 | 在工程配置中用 `toolchain` 指定本机配置中的某个 `id` |
| 环境看似齐全，工程编译失败 | 看本次编译日志，检查版本、许可证、器件包和 SDK 依赖 |

自动检测读取 `KEIL_ROOT`、`IDF_PATH`、`PATH`、Keil 注册表，以及 C/D 盘上的常见 Keil、ST、Espressif 安装目录及其两级子目录。它不是全盘搜索。显式指定的安装路径失效时，会保留配置并报告问题，方便你修正路径。

### 手工填写安装目录

编辑蒲元目录下的 `toolchains.local.json`。下面是一份同时登记 Keil 和 ESP-IDF 的完整示例；**只保留自己安装的工具，并修改所有相关路径**。

<details>
<summary>展开本机环境配置示例</summary>

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

| 字段 | 含义 |
|---|---|
| `language` | 保存的菜单语言：`en` 或 `zh-CN`，未设置时默认英文；重新检测环境会保留 |
| 顶层 `python` | Python 3 可执行文件，供 `firmware-script` 打包器使用；普通 Keil 编译不依赖它 |
| `toolchains[].id` | 你给这套环境起的唯一 ID，例如 `keil-local` |
| `kind` / `root` | 环境类型与安装根目录；类型可为 `keil`、`esp-idf`、`cubeide` |
| `compilerRoot` | 可选，Keil 自定义 ARMCC 目录，应包含 `bin`；相应编译器还需在 µVision 中注册 |
| `toolsPath` | ESP-IDF 下载工具和 Python 虚拟环境的存放目录 |
| `toolchains[].python` | 可选，显式指定某套 ESP-IDF 虚拟环境的 `Scripts/python.exe` |

例如，工具链 ID 是 `keil-local`，工程中就写 `"toolchain": "keil-local"`。这是两个文件之间的关联；自动生成的 ID 可能叫 `keil-1`，请以实际配置为准。手工增加一套工具不会让 `command` 配置自动使用它，通用命令的工具路径仍由 `commands` 指定。

### 按工程要求准备工具

| 工程 | 应准备的组件 | 配置时核对的位置 |
|---|---|---|
| Keil / ARMCC5 | µVision、工程要求的 ARMCC5、器件包和许可证 | `root/UV4/UV4.exe`、`root/ARM/ARMCC/bin/armcc.exe` |
| Keil / ARMCLANG6 | µVision、工程要求的 ARMCLANG6、器件包和许可证 | `root/ARM/ARMCLANG/bin/armclang.exe`；格式转换还需对应 `fromelf.exe` |
| ESP-IDF | 工程要求的 SDK、目标芯片工具及匹配的 Python 虚拟环境 | `root/export.bat`、`root/tools/idf.py`、`toolsPath/python_env` |
| CubeIDE | 可用的 STM32CubeIDE 安装和工程构建配置 | 安装目录中的 `headless-build.bat` |
| CMake / Make / PlatformIO | 项目构建程序、交叉编译器及项目依赖 | 对应完整配置中的 `executable` 或命令字符串 |

Keil 的编译器和器件包要求来自 `.uvprojx` 中的 `pCCUsed`、`uAC6`、`PackID`，也可在 µVision 工程选项中查看。ARMCC5 工程注明 build 号时，蒲元会参与版本校验。Keil 的命令接口见 [µVision 官方说明](https://www.keil.com/support/man/docs/uv4/uv4_commandline.asp)。

ESP-IDF 可按[官方 Windows 安装说明](https://docs.espressif.com/projects/esp-idf/en/v5.4.3/esp32/get-started/windows-setup.html)安装工程要求的 SDK 和依赖。已有真实构建验收使用 v5.4.3，这不表示所有工程都必须使用这一版本。SDK、工具和工程宜使用较短、无空格的英文路径。蒲元会查找匹配 SDK 主次版本的 Python；有多份候选时，填写工具链条目内的 `python`。

安装或修改环境后，再运行 `env detect --save`，然后对实际工程执行前面的配置检查和构建预览。

<details>
<summary>已准备好 ESP-IDF 源码，需要手工安装目标工具和 Python 环境</summary>

仅当 SDK 已下载、所需子模块已初始化，并且基础 Python 已可用时执行。以下示例为 ESP32 安装工具；路径和目标芯片需按实际工程修改。

```powershell
$env:IDF_TOOLS_PATH = 'C:/Espressif/tools'
$idfRoot = 'C:/Espressif/esp-idf-v5.4.3'
python "$idfRoot/tools/idf_tools.py" install --targets esp32
```

上一条完成后，为同一 SDK 安装 Python 环境：

```powershell
python "$idfRoot/tools/idf_tools.py" install-python-env --features core
```

随后把 SDK 路径和工具目录填入本机配置。SDK 环境在构建子进程中独立初始化。

</details>

<a id="project-types"></a>

## 选择工程类型

先看工程根目录里已有的构建入口，再选 `builder`。芯片品牌本身不能决定构建方式，例如 STM32 工程可能使用 Keil、CubeIDE 或 CMake。

| 看到的入口 | 使用方式 | 本节位置 / 验证状态 |
|---|---|---|
| `.uvprojx` / `.uvproj` | `keil` | [Keil](#keil)，STM32 / GD32 官方示例已真实编译 |
| 根 `CMakeLists.txt` 引用 ESP-IDF 的 `project.cmake` | `esp-idf` | [ESP-IDF](#esp-idf)，5.4.3 官方示例已真实编译 |
| `.project` 与 `.cproject` | `command` 调用 CubeIDE | [CubeIDE](#cubeide)，提供配方，待对应环境实测 |
| 普通 `CMakeLists.txt` | `command` 调用 CMake | [CMake](#cmake)，通用调用流程已测试，项目命令需本机验证 |
| `Makefile` | `command` 调用 Make | [Make](#make)，通用调用流程已测试，项目命令需本机验证 |
| `platformio.ini` | `command` 调用 PlatformIO | [PlatformIO](#platformio)，提供配方，待对应环境实测 |
| 自己的构建或打包脚本 | `command` 或兼容的 `firmware-script` | [自有打包器](#packager)，兼容打包与失败恢复流程已测试 |

只有 `.ioc` 时，需要先用 STM32CubeMX 生成实际可构建工程。`project inspect` 能列出已识别的入口，但通用构建方式仍需你填写真实命令和产物路径。

下面各示例都是完整的 `projects.json`，同样保存在蒲元目录。**加入已有配置时，只合并相应的工程对象；不要用整份示例覆盖已有工程。**

<a id="keil"></a>

### Keil：选中正确的工程文件和 Target

唯一工程、唯一 Target 可使用首次构建中的最小配置。需要明确选择时，先运行这一条识别命令：

```powershell
.\puyuan.cmd project inspect --path "C:/work/board"
```

一个候选时，结果中的 `suggestedConfig` 是工程条目草稿，可放入 `projects` 数组；它不是整个配置文件。多个候选时返回 `AMBIGUOUS_PROJECT`，从 `error.details.candidates` 选择实际入口。按候选填写 `projectFile` 与 `target`，其中 Target 名区分大小写。

<details>
<summary>展开：明确 Target、工具链，并生成带版本的 Board-1.2.hex</summary>

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

本例假设工程文件是 `MDK-ARM/Board.uvprojx`，Target 名为 `Release`；本机已登记 `keil-local`。`include/version.h` 中存在 `#define BOARD_VERSION "1.2"`，正则的第一个捕获组读到 `1.2`。请把这些值改成工程实际内容。

</details>

`outputFormat` 可选 `hex`、`bin` 或 `axf`。不填写时，优先使用工程生成的 HEX；工程关闭 HEX 时，从本次 AXF 导出 BIN。转换使用所选编译器的 `fromelf`。每次调用 Keil 重编指定 Target，检查日志中的 Target 与零错误摘要；仅有警告时可以成功，警告数在结果中返回。

<a id="esp-idf"></a>

### ESP-IDF：应用、首装镜像和升级镜像

先登记可用的 `idf-local` 工具链。工程根目录需有引用 ESP-IDF `project.cmake` 的 `CMakeLists.txt`。`target` 是芯片名，例如 `esp32`；已有 `sdkconfig` 的芯片必须与它一致。

<details>
<summary>展开：ESP32 应用和首装镜像的完整配置</summary>

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

这个配置不写 `artifacts`，使用默认规则：`all` 构建应用、Bootloader 和分区，并通过 SDK 合并镜像，交付 `Sensor-factory.bin` 与 `Sensor-application.bin`；`factory` 只交付合并镜像。Flash 参数和偏移来自工程构建结果。

`outputName` 默认读取根 `CMakeLists.txt` 的 `project(...)` 名称；使用变量命名时需显式填写。`buildDirectory` 默认 `build`，必须位于工程目录内。

升级需要设备侧已经实现匹配的 OTA 流程、分区和校验。确认这些条件后，可改用下面的配置，将应用 BIN 明确作为升级交付物。

<details>
<summary>展开：启用应用升级的完整配置</summary>

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

对该配置执行下面的命令，会运行 `idf.py app`，交付 `Sensor-upgrade.bin`，无需重新生成 Bootloader：

```powershell
.\puyuan.cmd build --project sensor --action upgrade
```

设备侧的 OTA 传输、校验和启动确认由工程实现。蒲元会重新生成本次 ELF/BIN，构建失败时恢复预期旧文件。

<a id="cubeide"></a>

### STM32CubeIDE：调用无界面构建入口

使用 `command` 调用安装目录中的 `headless-build.bat`。先从 `.project` 的 `name` 读取 Eclipse 工程名，从 `.cproject` 确认构建配置；它们可能与磁盘目录名不同。

<details>
<summary>展开：构建 Board/Release 并交付 Release/Board.elf</summary>

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

要修改的地方有三个：`headless-build.bat` 的真实路径、`Board/Release` 中的工程名与构建配置、`artifacts.source` 的输出路径。示例使用独立的 `.builder-workspace`，以免争用日常 IDE workspace。`-import` 导入工程，`-cleanBuild` 构建指定配置。这份配方尚未在真实 CubeIDE 安装环境中验收。

<a id="cmake"></a>

### CMake：使用项目自己的交叉编译配置

准备项目已有的交叉编译工具链文件、CMake、Ninja 及编译器。示例先配置，再执行清理构建，假设输出为 `build/Board.elf`。

<details>
<summary>展开 CMake 完整配置</summary>

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

修改 CMake 路径、生成器、`cmake/arm-gcc.cmake` 和输出 ELF 路径。配置失败时不会继续构建。如果工程使用 CMakePresets，则改用该工程现有的 configure / build preset。

<a id="make"></a>

### Makefile：指定目标和准确的输出文件

示例要求 `make.exe` 和工程的交叉编译器在 `PATH` 中，`all` 目标生成 `build/firmware.bin`。

<details>
<summary>展开 Make 完整配置</summary>

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

`--always-make` 让规则本次重新执行。工程使用其他目标、板型变量或输出位置时，同步修改 `arguments` 与 `artifacts.source`。

<a id="platformio"></a>

### PlatformIO：选中 platformio.ini 中的 environment

安装 [PlatformIO Core](https://docs.platformio.org/en/latest/core/quickstart.html)，确保 `pio` 在 `PATH` 中，或把命令字符串中的 `pio` 改成其可执行文件的完整路径。

<details>
<summary>展开：构建 env:esp32dev 的完整配置</summary>

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

示例对应 `platformio.ini` 中的 `[env:esp32dev]`。先清理该 environment 的构建输出，再重新构建，交付 `.pio/build/esp32dev/firmware.bin`。environment、`build_dir` 或输出格式不同时，修改命令和 `source`；所需 platform、framework 与编译器由 PlatformIO 管理。这份配方尚未在真实 PlatformIO 环境中验收。

<a id="packager"></a>

### 自有打包器：接入首装与升级规则

通常选择 `builder: "command"`，在 `commands.all` 中调用工程现有的完整构建脚本，在 `artifacts` 中列出它生成的准确文件。需要独立的首装或升级动作时，同时配置 `commands.factory` / `commands.upgrade` 和相应 `kind` 的产物。

通用命令以工程 `path` 为工作目录。`executable` 可使用完整路径、工程相对路径或 `PATH` 中的程序；`arguments` 数组中的每项是一个参数。Python 脚本通过 Python 可执行文件启动，PowerShell 脚本通过 `powershell.exe -File` 启动。调用批处理时，使用 `cmd.exe`，参数必须是四项：`/d`、`/s`、`/c`、完整命令字符串，具体写法见上面的 CubeIDE 或 CMake 示例。复杂的初始化和多步打包宜放进工程自己的脚本。

`successCodes` 默认 `[0]`；仅当项目构建程序明确规定其他成功退出码时再调整。即使命令返回成功，蒲元仍会检查本次产物存在、非空且新生成。

<details>
<summary>已有脚本符合 firmware-script 约定：展开兼容配置及完整要求</summary>

`firmware-script` 适配的是一种特定打包约定，使用前逐项核对：

- Keil ARMCC5 工程，Python 脚本支持 `--keil ROOT --rebuild`，返回 `0` 表示成功。
- 完整调用一次生成首装 HEX 和升级 BIN，并输出包含 Target 及零错误摘要的 Keil 日志。
- 脚本公开 `envelope(data, numeric_version)`，返回升级镜像 `bytes`；升级适配会执行脚本顶层代码。
- 软件版本为 `major.minor`。`User_Driver/boot_update.h` 中恰有一个匹配 `*_FW_VERSION_ID` 的十六进制宏，数值为 `(major << 16) | minor`。
- 明确配置 `script`、`keilLog`、版本来源、首装与升级源文件；工具链位于 Keil `root/ARM/ARMCC`，本机配置的顶层 `python` 可用。

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

示例头文件中的宏为 `BOARD_FW_VERSION "HW1,1.2"` 和 `BOARD_FW_VERSION_ID 0x00010002UL`；版本正则取逗号后的 `1.2`。交付名称为 `Board-factory-1.2.hex` 和 `Board-upgrade-1.2.bin`。

`all` 调用一次完整脚本并交付两项文件；`factory` 也执行完整脚本，只交付首装文件；`upgrade` 由蒲元重编应用，用 `fromelf` 提取本次 AXF，再调用 `envelope` 封装，构建升级镜像无需已有 `bootloader.bin`。其他目录布局、版本编码、加密格式或命令接口可使用 `command` 接入。

</details>

<a id="configuration"></a>

## 配置多个工程和固件名称

### 多个工程放在同一个 projects 数组

保留一份顶层配置，将每个工程对象放入 `projects` 数组，条目之间用逗号分隔。例如，一台电脑可同时管理 Keil 和 ESP-IDF 工程：

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

`id` 必须唯一，只使用字母、数字、`_`、`-`，且以字母或数字开头。菜单名称可以更易读；文件名前缀用 `projectName` 单独设置，例如菜单显示 `ESP32 sensor`，文件名以 `Sensor` 开头。

### 设置版本和命名规则

文件名由模板生成，默认是 `{project}-{kind}.{ext}`，例如 `Board-application.hex`。有两处可以改：

| 位置 | 影响范围 | 例子 |
|---|---|---|
| 顶层 `defaultName` | 未单独命名的产物 | `{project}-{kind}-{version}.{ext}` |
| 某项 `artifacts[].name` | 这一项产物，优先级更高 | `{project}-factory-{version}.{ext}` |

例如工程名是 `Board`、版本是 `1.2`，首装 HEX 使用第二个模板后，交付名为 `Board-factory-1.2.hex`。上面的[兼容打包器配置](#packager)包含首装和升级两种完整命名示例。

**源文件与交付名称分开设置。** `artifacts[].source` 指向编译器或打包器实际生成的文件；`name` 是复制到本次交付目录时使用的新名称。改 `name` 不会改变项目编译器的输出文件名。

使用 `{version}` 前，必须给该工程配置 `version`。可选两种来源：

- 固定版本：`"version": {"value": "1.2"}`。
- 从文件读取：配置 `file` 和 `pattern`，正则必须恰好匹配一次，第一个捕获组是版本。完整例子见 [Keil 配置](#keil)。

两种来源互斥。不需要版本时，省略 `version` 并使用不含 `{version}` 的模板。

| 模板变量 | 含义 | 可以用在哪里 |
|---|---|---|
| `{project}` | `projectName`，未设置时为 `name` | 交付名、源路径、命令参数 |
| `{version}` | 读取到的版本 | 交付名、源路径、命令参数 |
| `{target}` / `{date}` | 构建目标 / 本机日期 `yyyyMMdd` | 交付名、源路径、命令参数 |
| `{kind}` / `{ext}` | 当前产物用途 / 扩展名，不含点 | 交付名称 |
| `{root}` | 工程绝对目录 | 源路径、命令参数 |
| `{outputDir}` / `{outputName}` | 原生 Keil / ESP-IDF 的输出目录和主名 | 源路径、命令参数 |
| `{projectFile}` / `{keil}` / `{fromelf}` | Keil 工程文件 / 所选安装根目录 / 转换工具 | Keil 相关命令参数 |

产物的 `kind` 可为 `application`、`factory`、`upgrade`。`source` 必须精确指向工程目录内的文件，不支持通配符。交付名称不能包含 Windows 非法字符，不能重名；`step-`、`keil-` 前缀及 `result.json` 留给日志和结果文件。

### 查字段和相对路径

| 字段 | 使用场景和默认行为 |
|---|---|
| `schemaVersion` / `projects` | 必填，版本固定 `1`；工程数组允许为空 |
| `outputDirectory` / `defaultName` | 顶层可选字段，默认 `outputs` / `{project}-{kind}.{ext}` |
| `id` / `name` / `path` / `builder` | 每个工程必填：ID、显示名称、根目录、构建方式 |
| `projectName` | 可选，交付文件名前缀，默认使用 `name` |
| `projectFile` / `target` | 明确 Keil 入口和 Target；ESP-IDF 的 `target` 是芯片 |
| `toolchain` | 选择本机配置中的工具链 ID；省略时要求唯一兼容候选 |
| `outputFormat` | Keil 交付格式：`hex` / `bin` / `axf` |
| `outputName` / `buildDirectory` | ESP-IDF 输出主名 / 构建目录，默认读取 `project(...)` / 使用 `build` |
| `version` / `artifacts` | 版本来源 / 产物源文件、用途和名称 |
| `commands` | `command` 构建方式中各个动作的程序和参数 |
| `script` / `keilLog` / `upgradeEnvelope` | `firmware-script` 兼容接口的专用字段 |
| `$schema` | 可选的编辑器提示地址；运行时按蒲元自带 Schema 校验 |

相对路径的基准如下：

| 相对路径 | 相对于哪里 |
|---|---|
| `projects[].path`、顶层 `outputDirectory` | `projects.json` 所在目录 |
| `projectFile`、`version.file`、`artifacts.source`、工程脚本 | 该工程的 `path` |
| 本机工具链的 `root`、`compilerRoot`、`toolsPath`、`python` | `toolchains.local.json` 所在目录 |
| 命令行显式传入的 `--config` / `--tools` | 当前 PowerShell 的工作目录 |

精确的字段约束见[项目 Schema](schema/projects.schema.json)与[本机工具 Schema](schema/toolchains.schema.json)。`examples` 中保留了本页完整配置的可复制文件。

<a id="cli"></a>

## 从命令行或本地 AI 调用

命令行适合自动化和排错，交互菜单适合日常手动构建。两种方式使用同一份配置。

| 你要做什么 | 在蒲元目录执行的命令 | 会不会构建 |
|---|---|---|
| 查看用法 | `.\puyuan.cmd help` | 不会 |
| 查找本机工具 | `.\puyuan.cmd env detect` | 不会；加 `--save` 才保存环境配置 |
| 看工程入口和 Target 候选 | `.\puyuan.cmd project inspect --path "C:/work/board"` | 不会，也不会保存工程配置 |
| 查看已登记的工程 | `.\puyuan.cmd project list` | 不会 |
| 检查配置和环境 | `.\puyuan.cmd project validate --project board` | 不会，可能查询工具版本 |
| 预览所选动作 | `.\puyuan.cmd build --project board --action all --dry-run` | 不会，可能查询工具版本 |
| 真正编译并交付 | `.\puyuan.cmd build --project board --action all` | 会 |

`build` 省略 `--action` 时使用 `all`。检查其他动作时，把 `all` 换成该工程支持的 `factory` 或 `upgrade`，并先加 `--dry-run` 预览。

`--lang en` / `--lang zh-CN` 临时覆盖交互语言，不翻译工程名称、编译器日志、JSON 字段或错误码，也不改变非交互命令的返回结果。不支持的语言参数返回 `USAGE`；读取本机配置时发现非法 `language` 则返回 `CONFIG_INVALID`。

命令默认使用蒲元目录中的两份配置；需要另一套配置时加 `--config PATH` 与 `--tools PATH`。从其他目录调用则使用工具完整路径，例如：

```powershell
& "C:/tools/puyuan/puyuan.cmd" build --project board --action all
```

本地 AI 应加 `--json`，解析单个 JSON 对象并检查进程退出码。环境检测、工程识别、配置生成和构建结果处理的完整约定集中在[本地 AI 调用说明](docs/cli-for-agents.md)，可把该文档、工具目录和工程目录一起交给 AI。

### 在 Codex 中启用蒲元

仓库提供通用的 [Puyuan Skill](skills/puyuan/SKILL.md)。应安装为用户级 Skill，使 Codex 在其他固件工程中也能发现它；只把 Skill 留在蒲元仓库中，不会让无关工程自动加载。

1. 安装 Skill。在 Codex 对话中向内置安装技能发出以下请求：

   ```text
   使用 $skill-installer，将 shenk-cn/puyuan 仓库的 skills/puyuan 安装到用户级 ~/.agents/skills 目录。
   ```

   也可首次手工安装。在蒲元目录的 PowerShell 中执行下面的复制操作；目标已存在时会停止，避免覆盖原有 Skill：

   ```powershell
   $skillDestination = Join-Path $env:USERPROFILE '.agents/skills/puyuan'
   if (Test-Path -LiteralPath $skillDestination) { throw 'The Puyuan skill already exists. Review it before updating.' }
   New-Item -ItemType Directory -Path (Split-Path -Parent $skillDestination) -Force | Out-Null
   Copy-Item -LiteralPath '.\skills\puyuan' -Destination $skillDestination -Recurse
   ```

2. 保存本机蒲元安装位置。保持 PowerShell 位于蒲元目录，执行：

   ```powershell
   [Environment]::SetEnvironmentVariable('PUYUAN_HOME', (Get-Location).Path, 'User')
   ```

   Skill 依次检查进程环境变量、Windows 用户级变量、`PATH` 中的 `puyuan.cmd`，任务中明确提供的安装路径优先。Skill 可直接读取已保存的用户级变量，因此不依赖当前应用立即继承新的环境。如果进程里已有变量指向另一份安装，请更新它或重启应用。

3. 在固件工程已有的 `AGENTS.md` 中追加简短指引，保留其他工程说明，并将 `board` 替换成实际登记的工程 ID：

   ```text
   Use the puyuan skill and Puyuan CLI for firmware builds in this project, unless the user explicitly requests another method.
   The registered Puyuan project ID is board; verify its root matches this project before building.
   Use --json and report current artifact paths, SHA256, warnings, and logs. Keep device flashing a separate task.
   ```

安装的 Skill 在下一轮对话可用；如果技能选择器中未出现，重启 Codex。随后可自然描述构建需求，或显式调用 `$puyuan`，例如：“使用 $puyuan 生成当前工程的首装固件，并返回路径和 SHA256。”Skill 会匹配工程、校验和预览所需动作，再通过同一个 CLI 执行已授权的构建。

本机路径和项目登记保留在本地配置中，公共 Skill 不包含私人安装路径或项目 ID。调用需要能访问实际工程及工具链的 Windows 终端。本次接入直接使用 CLI，不安装 MCP 服务。

<a id="troubleshooting"></a>

## 构建失败时怎么查

先看返回的 `code` 和 `error.message`，再找 `error.details` 中的日志路径。编译器原始错误在 `step-*.log` 或 `keil-*.log`，比“构建失败”这句话更具体。

| 错误码或现象 | 怎么处理 |
|---|---|
| `USAGE` | 参数或子命令有误，运行 `help` 对照用法 |
| `CONFIG_MISSING` | 缺少配置，核对默认目录或 `--config` / `--tools` 路径 |
| `CONFIG_INVALID` | 检查 JSON 语法、必填字段、未知字段、重复 ID，以及版本正则 |
| `PROJECT_MISSING` | 工程 ID / 目录不存在，或没有识别到入口；默认扫描根目录及三级子目录，跳过依赖和构建输出目录 |
| `PROJECT_INVALID` | 工程 XML 损坏，或 ESP-IDF 根 CMake 入口不符合要求 |
| `TARGET_MISSING` | 核对 Keil 工程中的实际 `TargetName`，注意大小写 |
| `AMBIGUOUS_PROJECT` / `AMBIGUOUS_TARGET` | 从候选中明确选择，填写 `projectFile` 和 `target` |
| `TOOLCHAIN_MISSING` | 查看缺项的预期路径，安装组件或修正[本机环境配置](#environment) |
| `AMBIGUOUS_TOOLCHAIN` | 在工程中设置 `toolchain` 为实际候选 ID |
| `TOOLCHAIN_VERSION_MISMATCH` | 使用工程注明的编译器版本，核对 ARMCC build 号 |
| `VERSION_MISSING` | 检查版本文件与正则；应仅匹配一次且捕获组 1 非空 |
| `TEMPLATE_INVALID` | 检查未知变量、非法字符、重名和日志保留名称 |
| `ACTION_UNSUPPORTED` | 该工程没有对应动作；检查 `supportedActions`、产物用途及 `command` 的同名动作命令 |
| `PROJECT_BUSY` | 等待同一工程的构建完成；同时让 IDE 对该目录的构建保持空闲 |
| `TOOL_START_FAILED` | 核对可执行文件、工作目录、权限及依赖 |
| `BUILD_FAILED` | 打开本次日志，先解决实际编译错误、许可证或依赖问题 |
| `BUILD_TIMEOUT` | 子进程超时，默认每步 30 分钟；查看终止前保留的输出，检查工具是否在等待输入 |
| `ARTIFACT_MISSING` | 命令没有生成约定文件，核对 `source`、输出主名和扩展名 |
| `ARTIFACT_STALE` | 文件为空或不是本次新生成，检查实际构建目标及打包流程 |
| `INTERNAL_ERROR` | 保存完整错误、配置和复现命令，报告工具问题 |

修正配置后，重新执行“配置检查 → 构建预览 → 真实构建”。

**ESP-IDF 路径与缓存问题：** 头文件明明存在却找不到、无法创建 `.obj.d`，可能是展开后路径过长，缩短 SDK 工具、工程和构建目录。切换 SDK、Python 或路径后，旧 CMake 缓存可能记录原绝对路径，可使用新的 `buildDirectory`；确认旧缓存可丢弃后，再按 SDK 文档清理。切换芯片需同步处理 `sdkconfig`、分区和工具依赖。

**失败恢复：** 构建前会备份预期旧产物，常规失败会恢复。强行结束 PowerShell 或掉电可能留下 `.puyuan-*.bak`；先确认构建已停止，再核对备份与源输出并恢复所需文件。掉电、磁盘写满及设备硬件运行未做破坏性验证。

## 发布与维护

`projects.json`、`toolchains.local.json` 和 `outputs` 属于本地数据，已在忽略规则中列出，公开分享时使用 `examples` 中的通用配置。Git 忽略规则不会自动清除手工 ZIP 或网页上传中的本地数据；发布时只选择源码、文档、Schema、通用示例及许可证，不打包供应商 SDK、编译器、设备固件或个人日志。

使用说明到此完整结束。参与开发或核对验收证据时，再查看：

- [本地 AI 调用说明](docs/cli-for-agents.md)：机器调用和配置生成约定。
- [测试与异常覆盖](docs/testing.md)：运行回归、失败恢复和验证边界。
- [公开工程编译记录](reports/github-acceptance.md)：固定上游提交、实际构建及产物证据。
- [贡献指南](CONTRIBUTING.md)：提交问题、修改代码和维护示例。

## 许可证

蒲元采用 [Apache License 2.0](LICENSE)。外部编译器、SDK 和固件工程继续遵循各自的许可证。
