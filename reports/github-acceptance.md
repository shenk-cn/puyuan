# 官方 GitHub 示例验收

2026-11-06 在 Windows 上使用可下载的上游工程完成了 10 项真实构建，并注入一次实际编译错误。[机器可读结果](github-acceptance.json)

| 来源 | 固定提交 | 通过的构建 |
|---|---|---|
| [STM32CubeF4](https://github.com/STMicroelectronics/STM32CubeF4) v1.28.3 | `94cae6e83f00e276a11957e7833c01ac3d0bd7af` | STM32F429ZI-Nucleo GPIO_IOToggle，BIN / HEX / AXF |
| [GD32F4xx Firmware Library](https://github.com/GigaDevice-GD32-MCU/GD32F4xx_Firmware_Library) | `10d02f4c8a7e1d79da8b2a9ad67b534f187ec936` | GD32F450IK Keil5 模板，HEX / BIN |
| [ESP-IDF](https://github.com/espressif/esp-idf) v5.4.3 | `ea1c174c1cbb7348bd8ba0ff1eb306246938dd80` | `hello_world` 的 `all` / `factory`，`native_ota_example` 的 `upgrade` / `all` / `factory` |

Arm 示例使用 ARMCC 5.06 update 7 build 960，ESP32 使用 ESP-IDF 5.4.3、Xtensa GCC 14.2 和 Python 3.13。STM32 / GD32 日志零错误、零警告；ESP-IDF 日志中的路径别名提示计入 `warnings`。

## 检查内容

- 交付尺寸与 SHA256 一致，HEX 字节数、校验和和 EOF 正确，AXF 是已链接的 Arm ELF。
- 首装镜像逐项匹配 `flasher_args.json` 的 Bootloader、分区表、应用及其他分区偏移。
- OTA 应用在没有 `bootloader.bin` 时成功生成，`upgrade` 没有生成 Bootloader。
- 在真实 OTA 示例中加入 `#error` 后，构建失败，旧应用恢复，失败目录没有导出 BIN；测试结束恢复源码。
- 初次及重复构建通过，下载仓库的受版本控制源码与固定提交一致。

Windows GCC 对较长路径存在限制，验收使用短工具路径和原样复制的短目录示例。测试结束清理下载副本、SDK、固件及临时盘符。公开记录保留来源、操作、尺寸及哈希，原始本机日志单独归档。

## 重复验收

在专用临时工作区准备 `stm32`、`gd32`、`esp-idf` 三个目录，分别检出上表提交。ESP-IDF 递归初始化子模块，STM32 至少初始化以下依赖。

```powershell
git -C stm32 submodule update --init --depth 1 Drivers/STM32F4xx_HAL_Driver Drivers/CMSIS/Device/ST/STM32F4xx Drivers/BSP/STM32F4xx_Nucleo_144
```

依照[README 的环境配置](../README.zh-CN.md#environment)安装 Keil 和临时 ESP-IDF 工具，写入本机 `tools.json`。然后运行以下命令。

```powershell
python tests/accept_github_projects.py --workspace "C:/Temp/puyuan-test" --tools "C:/Temp/puyuan-test/tools.json"
```

脚本在工作区创建 `hello`、`ota` 短路径副本，生成配置，执行 10 项构建并注入编译失败。较长临时目录可以自行使用空闲短盘符，并在归档后移除自己的映射。

## 验证范围

本记录覆盖主机构建、打包及交付。自动化异常覆盖和当前运行方法见[测试指南](../docs/testing.md)。CubeIDE / PlatformIO 的配置配方仍需对应环境验证，设备烧录及板上运行需要硬件验收。
