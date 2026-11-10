"""Accept real builds of official GitHub examples using prepared temporary checkouts and toolchains."""
import argparse
from datetime import datetime
import hashlib
import json
import os
import shutil
from pathlib import Path
import struct
import subprocess

APP = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", required=True, help="Directory containing stm32, gd32, esp-idf checkouts")
    parser.add_argument("--tools", required=True)
    args = parser.parse_args()
    # Keep the explicit short drive alias instead of resolving it back to a long Windows GCC path.
    workspace = Path(os.path.abspath(args.workspace))
    config_path = workspace / "github-projects.json"
    output = workspace / "github-results"
    report = {"testedAt": datetime.now().astimezone().isoformat(), "builds": [], "checks": [], "repositories": []}
    for example, destination in [("examples/get-started/hello_world", "hello"), ("examples/system/ota/native_ota_example", "ota")]:
        original = workspace / "esp-idf" / example
        copied = workspace / destination
        if not copied.exists():
            shutil.copytree(original, copied, ignore=shutil.ignore_patterns("build*", "sdkconfig", "sdkconfig.old", "managed_components", "dependencies.lock", "__pycache__"))
        for source in original.rglob("*"):
            if source.is_file() and source.suffix in (".c", ".h") and not any(part.startswith("build") for part in source.relative_to(original).parts):
                assert source.read_bytes() == (copied / source.relative_to(original)).read_bytes()
    report["checks"].append("ESP-IDF examples copied with identical C/H sources into short temporary directories for Windows GCC")
    for name, url in [("stm32", "https://github.com/STMicroelectronics/STM32CubeF4"),
                      ("gd32", "https://github.com/GigaDevice-GD32-MCU/GD32F4xx_Firmware_Library"),
                      ("esp-idf", "https://github.com/espressif/esp-idf")]:
        commit = subprocess.check_output(["git", "-C", str(workspace / name), "rev-parse", "HEAD"], text=True).strip()
        report["repositories"].append({"name": name, "url": url, "commit": commit})
    projects = [
        {"id": "stm32-gpio", "name": "STM32-GPIO", "path": str(workspace / "stm32/Projects/STM32F429ZI-Nucleo/Examples/GPIO/GPIO_IOToggle"),
         "builder": "keil", "projectFile": "MDK-ARM/Project.uvprojx"},
        {"id": "gd32-template", "name": "GD32-Template", "path": str(workspace / "gd32/Template"),
         "builder": "keil", "projectFile": "Keil5_project/Project.uvprojx"},
        {"id": "esp32-hello", "name": "ESP32-Hello", "path": str(workspace / "hello"),
         "builder": "esp-idf", "target": "esp32", "buildDirectory": "build-short"},
        {"id": "esp32-ota", "name": "ESP32-OTA", "path": str(workspace / "ota"),
         "builder": "esp-idf", "target": "esp32", "buildDirectory": "build-short", "artifacts": [
             {"kind": "factory", "source": "{outputDir}/merged-flash.bin"},
             {"kind": "upgrade", "source": "{outputDir}/{outputName}.bin"}]},
    ]

    def save_config():
        config_path.write_text(json.dumps({"schemaVersion": 1, "outputDirectory": str(output), "projects": projects}), encoding="utf-8")

    def call(*arguments, expected="OK"):
        result = subprocess.run([str(APP / "puyuan.cmd"), *map(str, arguments), "--config", str(config_path),
                                 "--tools", args.tools, "--json"], capture_output=True, encoding="utf-8", timeout=900, cwd=workspace)
        reply = json.loads(result.stdout)
        assert reply["code"] == expected, reply
        assert (result.returncode == 0) == (expected == "OK"), reply
        assert not result.stderr, result.stderr
        return reply

    def verify_image(project, data):
        for artifact in data["artifacts"]:
            path = Path(artifact["path"])
            payload = path.read_bytes()
            assert len(payload) == artifact["bytes"]
            assert hashlib.sha256(payload).hexdigest() == artifact["sha256"]
            if path.suffix == ".hex":
                lines = payload.decode("ascii").splitlines()
                assert lines[-1] == ":00000001FF"
                for line in lines:
                    record = bytes.fromhex(line[1:])
                    assert len(record) == record[0] + 5 and sum(record) % 256 == 0
            if project["builder"] == "esp-idf":
                if artifact["kind"] == "factory":
                    build = Path(project["path"]) / project["buildDirectory"]
                    flash = json.loads((build / "flasher_args.json").read_text(encoding="utf-8"))
                    for offset, source in flash["flash_files"].items():
                        part = (build / source).read_bytes()
                        start = int(offset, 0)
                        assert payload[start:start + len(part)] == part, source
                else:
                    assert payload[0] == 0xE9
        if project["builder"] == "keil":
            # Validate the linked Arm ELF independently of the exported HEX/BIN images.
            if project["id"] == "stm32-gpio":
                axf = Path(project["path"]) / "MDK-ARM/STM32F429ZI_NUCLEO_144/STM32F429ZI_NUCLEO_144.axf"
            else:
                axf = Path(project["path"]) / "Keil5_project/output/Project.axf"
            elf = axf.read_bytes()
            assert elf[:4] == b"\x7fELF" and struct.unpack_from("<H", elf, 18)[0] == 40

    save_config()
    for project in projects:
        entry = Path(project["path"])
        if project["builder"] == "keil": entry /= project["projectFile"]
        call("project", "inspect", "--path", entry)
        call("project", "validate", "--project", project["id"])
    matrix = [(0, "bin", "all"), (0, "hex", "all"), (0, "axf", "all"),
              (1, "hex", "all"), (1, "bin", "all"), (2, None, "all"), (2, None, "factory"),
              (3, None, "upgrade"), (3, None, "all"), (3, None, "factory")]
    for index, fmt, action in matrix:
        project = projects[index]
        if fmt: project["outputFormat"] = fmt
        save_config()
        plan = call("build", "--project", project["id"], "--action", action, "--dry-run")["data"]
        assert len(plan["commands"]) > 0
        boot = None
        backup = None
        if action == "upgrade":
            boot = Path(project["path"]) / project["buildDirectory"] / "bootloader/bootloader.bin"
            if boot.exists():
                backup = boot.with_name("bootloader.bin.acceptance-backup")
                assert not backup.exists()
                boot.rename(backup)
        try:
            print(f"Building {project['id']} {fmt or ''} {action}", flush=True)
            data = call("build", "--project", project["id"], "--action", action)["data"]
            verify_image(project, data)
            report["builds"].append(dict(data, outputFormat=fmt))
            if boot is not None:
                assert not boot.exists(), "Application-only action generated a Bootloader"
                report["checks"].append("ESP-IDF OTA application builds with bootloader.bin absent")
            print(f"Passed {project['id']} {action}", flush=True)
        finally:
            if backup is not None and backup.exists(): backup.rename(boot)
    ota = projects[3]
    source = Path(ota["path"]) / "main/native_ota_example.c"
    original = source.read_bytes()
    stat = source.stat()
    upgrade_plan = call("build", "--project", ota["id"], "--action", "upgrade", "--dry-run")["data"]
    app = Path(upgrade_plan["artifacts"][0]["source"])
    old_image = app.read_bytes()
    # Inject a real compiler error only into the temporary example; finally restores source bytes and timestamps.
    try:
        source.write_bytes(original + b"\n#error puyuan_acceptance_failure\n")
        failure = call("build", "--project", ota["id"], "--action", "upgrade", expected="BUILD_FAILED")
        assert app.read_bytes() == old_image
        assert not list(Path(failure["error"]["details"]["runDirectory"]).glob("*.bin"))
        report["failure"] = failure
    finally:
        source.write_bytes(original)
        os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    report["checks"].extend(["Actual ESP-IDF #error failure restores previous app and exports no BIN",
                             "All HEX records have correct byte count, checksum and EOF",
                             "All factory images match every partition offset from flasher_args.json",
                             "Keil outputs are linked Arm ELF images; all delivered SHA256 values match"])
    for repository in report["repositories"]:
        diff = subprocess.check_output(["git", "-C", str(workspace / repository["name"]), "diff", "--name-only"], text=True)
        assert not diff.strip(), diff
    report["checks"].append("Downloaded repository tracked sources match the selected commits")
    (workspace / "github-acceptance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("GitHub acceptance passed", flush=True)


if __name__ == "__main__":
    main()
