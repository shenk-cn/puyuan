"""Drive the real CLI with temporary projects to verify build results and failure recovery."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

APP = Path(__file__).resolve().parents[1]
PS = APP / "puyuan.ps1"


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="puyuan 中文 空格 ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "projects.json"
        self.tools = self.root / "tools.json"
        self.tools.write_text(json.dumps({"schemaVersion": 1, "toolchains": []}), encoding="utf-8")
        # Simulate success, failure, and timeouts in temporary processes without modifying user projects.
        self.worker = self.root / "worker.py"
        self.worker.write_text(
            "import pathlib,sys,time,os,subprocess\n"
            "mode,output,*args=sys.argv[1:]\n"
            "print('worker started',flush=True)\n"
            "if mode=='sleep': time.sleep(5)\n"
            "if mode=='tree':\n"
            " subprocess.Popen([sys.executable,str(pathlib.Path(__file__).with_name('child.py'))]); time.sleep(10)\n"
            "if mode not in ('empty','fail'): pathlib.Path(output).write_text(repr(args),encoding='utf-8')\n"
            "if mode=='zero': pathlib.Path(output).write_bytes(b'')\n"
            "if mode=='stale': os.utime(output,(1,1))\n"
            "sys.exit(5 if mode=='fail' else 0)\n", encoding="utf-8")
        self.project = {
            "id": "test", "name": "中文 test", "projectName": "Board", "path": str(self.root),
            "builder": "command", "version": {"value": "1.2"},
            "commands": {"all": {"executable": __import__('sys').executable,
                                     "arguments": [str(self.worker), "write", str(self.root / "fresh.bin"), 'quote"value', 'C:\\tail\\']}},
            "artifacts": [{"kind": "application", "source": "fresh.bin", "name": "{project}-{version}.{ext}"}],
        }
        self.document = {"schemaVersion": 1, "outputDirectory": "delivery", "projects": [self.project]}
        self.save()

    def save(self):
        self.config.write_text(json.dumps(self.document, ensure_ascii=False), encoding="utf-8")

    def local_keil_tools(self, armclang=False):
        file = APP / "toolchains.local.json"
        if not file.exists(): self.skipTest("Configure local Keil to run this toolchain-plan check")
        tools = json.loads(file.read_text(encoding="utf-8"))
        candidates = [entry for entry in tools["toolchains"] if entry["kind"] == "keil"]
        if not candidates: self.skipTest("Local Keil needed for this check")
        if armclang and not (Path(candidates[0]["root"]) / "ARM/ARMCLANG/bin/armclang.exe").exists():
            self.skipTest("Local ARMCLANG needed for this check")
        return tools

    def command(self, *arguments):
        return ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(PS),
                *arguments, "--config", str(self.config), "--tools", str(self.tools), "--json"]

    def call(self, *arguments, expected="OK"):
        result = subprocess.run(self.command(*arguments), capture_output=True, encoding="utf-8", cwd=self.root, timeout=30)
        self.assertEqual(result.stderr, "", result.stderr)
        response = json.loads(result.stdout)
        self.assertEqual(response["code"], expected, response)
        self.assertEqual(result.returncode == 0, expected == "OK", response)
        return response

    def test_schema_and_names(self):
        for key, value, code in [("typo", True, "CONFIG_INVALID"), ("projectName", "CON", "TEMPLATE_INVALID")]:
            with self.subTest(key=key):
                self.project[key] = value
                if key == "projectName": self.project["artifacts"][0]["name"] = "{project}.{ext}"
                self.save()
                self.call("project", "validate", "--project", "test", expected=code)
                del self.project[key]

    def test_duplicate_id_and_unknown_variable(self):
        self.document["projects"].append(self.project.copy())
        self.save()
        self.call("project", "validate", "--project", "test", expected="CONFIG_INVALID")
        self.document["projects"].pop()
        self.project["artifacts"][0]["name"] = "{oops}.bin"
        self.save()
        self.call("project", "validate", "--project", "test", expected="TEMPLATE_INVALID")

    def test_dry_run_no_writes(self):
        self.call("build", "--project", "test", "--dry-run")
        self.assertFalse((self.root / "fresh.bin").exists())
        self.assertFalse((self.root / "delivery").exists())

    def test_build_arguments_and_manifest(self):
        response = self.call("build", "--project", "test")
        result = response["data"]
        artifact = Path(result["artifacts"][0]["path"])
        self.assertEqual(artifact.name, "Board-1.2.bin")
        self.assertEqual(artifact.read_text(encoding="utf-8"), repr(['quote"value', 'C:\\tail\\']))
        self.assertEqual(json.loads((artifact.parent / "result.json").read_text(encoding="utf-8"))["ok"], True)

    def test_old_output_never_counts_as_success(self):
        old = self.root / "fresh.bin"
        old.write_bytes(b"historical output")
        self.project["commands"]["all"]["arguments"][1] = "empty"
        self.save()
        self.call("build", "--project", "test", expected="ARTIFACT_MISSING")
        self.assertEqual(old.read_bytes(), b"historical output")
        self.assertEqual(list((self.root / "delivery").rglob("Board-1.2.bin")), [])

    def test_failure_restores_old_output(self):
        old = self.root / "fresh.bin"
        old.write_bytes(b"old")
        self.project["commands"]["all"]["arguments"][1] = "fail"
        self.save()
        self.call("build", "--project", "test", expected="BUILD_FAILED")
        self.assertEqual(old.read_bytes(), b"old")
        self.assertEqual(list(self.root.rglob("*.bak")), [])

    def test_missing_version_and_collision(self):
        del self.project["version"]
        self.save()
        self.call("project", "validate", "--project", "test", expected="TEMPLATE_INVALID")
        self.project["version"] = {"value": "1.2"}
        self.project["artifacts"].append(self.project["artifacts"][0].copy())
        self.save()
        self.call("project", "validate", "--project", "test", expected="TEMPLATE_INVALID")

    def test_unavailable_action_and_bad_option(self):
        self.call("build", "--project", "test", "--action", "upgrade", expected="ACTION_UNSUPPORTED")
        self.call("build", "--unknown", expected="USAGE")

    def test_invalid_json_and_missing_configuration(self):
        self.config.write_text('{"schemaVersion":', encoding="utf-8")
        self.call("project", "list", expected="CONFIG_INVALID")
        self.config.unlink()
        self.call("project", "list", expected="CONFIG_MISSING")

    def test_empty_and_stale_outputs_restore_previous_file(self):
        for mode in ("zero", "stale"):
            with self.subTest(mode=mode):
                old=self.root / "fresh.bin"
                old.write_bytes(b"previous valid image")
                self.project["commands"]["all"]["arguments"][1]=mode
                self.save()
                self.call("build", "--project", "test", expected="ARTIFACT_STALE")
                self.assertEqual(old.read_bytes(),b"previous valid image")
                self.assertEqual(list((self.root / "delivery").rglob("Board-1.2.bin")),[])

    def test_invalid_version_regex(self):
        (self.root / "version.h").write_text('#define BOARD_VERSION "1.2"',encoding="utf-8")
        self.project["version"]={"file":"version.h","pattern":"("}
        self.save()
        self.call("project","validate","--project","test",expected="CONFIG_INVALID")

    def test_timeout_keeps_output_and_stops_process(self):
        import sys
        log=self.root / "timeout.log"
        probe=self.root / "timeout.ps1"
        child=self.root / "child.py"
        child.write_text("import pathlib,time\nprint('child started',flush=True)\ntime.sleep(10)\npathlib.Path(__file__).with_name('late-child.bin').write_bytes(b'late')\n",encoding="utf-8")
        def quote(value): return "'"+str(value).replace("'","''")+"'"
        probe.write_text(
            "$ErrorActionPreference='Stop'\n"
            f". {quote(APP / 'lib/config.ps1')}\n"
            f". {quote(APP / 'lib/environment.ps1')}\n"
            "try {\n"
            f" $null=Invoke-Tool {quote(sys.executable)} @({quote(self.worker)},'tree',{quote(self.root / 'never.bin')}) {quote(self.root)} {quote(log)} 1\n"
            " exit 90\n"
            "} catch {\n"
            " if ($_.Exception.Data['code'] -eq 'BUILD_TIMEOUT') { exit 0 }; throw\n"
            "}\n",encoding="utf-8-sig")
        result=subprocess.run(["powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",str(probe)],capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("worker started",log.read_text(encoding="utf-8"))
        self.assertIn("child started",log.read_text(encoding="utf-8"))
        import time
        time.sleep(.2)
        self.assertFalse((self.root / "never.bin").exists())
        self.assertFalse((self.root / "late-child.bin").exists())

    def test_concurrent_build_rejected(self):
        self.project["commands"]["all"]["arguments"][1] = "sleep"
        self.save()
        first = subprocess.Popen(self.command("build", "--project", "test"), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            import time
            deadline = time.monotonic() + 10
            while not (self.root / "delivery").exists() and time.monotonic() < deadline:
                time.sleep(.05)
            self.call("build", "--project", "test", expected="PROJECT_BUSY")
            stdout, stderr = first.communicate(timeout=15)
            self.assertEqual(json.loads(stdout)["code"], "OK", stderr)
        finally:
            if first.poll() is None: first.kill()

    def test_explicit_missing_environment_is_preserved(self):
        self.tools.write_text(json.dumps({"schemaVersion": 1, "python": "X:/missing/python.exe", "toolchains": [
            {"id": "manual", "kind": "keil", "root": "X:/missing/keil"}]}), encoding="utf-8")
        response = self.call("env", "detect", "--save")
        configuration = response["data"]["configuration"]
        self.assertEqual(configuration["python"], "X:/missing/python.exe")
        self.assertEqual(configuration["toolchains"][0]["root"], "X:/missing/keil")
        self.assertFalse(response["data"]["tools"][0]["available"])

    def make_keil(self, targets=("Board",)):
        folder = self.root / "MDK-ARM"
        folder.mkdir()
        file = folder / "Board.uvprojx"
        nodes = ''.join(
            f'<Target><TargetName>{name}</TargetName><pCCUsed></pCCUsed>'
            '<TargetOption><TargetCommonOption><OutputDirectory>Board</OutputDirectory>'
            '<OutputName>Board</OutputName><CreateHexFile>1</CreateHexFile></TargetCommonOption></TargetOption></Target>'
            for name in targets)
        file.write_text('<Project><Targets>' + nodes + '</Targets></Project>', encoding="utf-8")
        self.project["builder"] = "keil"
        self.project["projectFile"] = str(file)
        self.save()
        return file

    def test_inspect_suggestion_is_valid_schema(self):
        self.make_keil()
        drivers = self.root / "Drivers/CMSIS"
        drivers.mkdir(parents=True)
        (drivers / "CMakeLists.txt").write_text("project(irrelevant)", encoding="utf-8")
        response = self.call("project", "inspect", "--path", str(self.root))
        suggestion = response["data"]["suggestedConfig"]
        self.assertIsInstance(suggestion["projectFile"], str)
        self.assertEqual(len(response["data"]["candidates"]), 1)

    def test_no_environment_and_target_ambiguity(self):
        self.make_keil(("Board", "Other"))
        self.call("project", "validate", "--project", "test", expected="AMBIGUOUS_TARGET")
        self.project["target"] = "Board"
        self.save()
        self.call("project", "validate", "--project", "test", expected="TOOLCHAIN_MISSING")

    def test_corrupt_keil_project(self):
        file=self.make_keil()
        file.write_text('<Project><broken>',encoding="utf-8")
        self.call("project","inspect","--path",str(file),expected="PROJECT_INVALID")
        self.call("project","validate","--project","test",expected="PROJECT_INVALID")

    def test_target_does_not_exist(self):
        self.make_keil()
        self.project["target"]="Missing"
        self.save()
        self.call("project","validate","--project","test",expected="TARGET_MISSING")

    def test_multiple_environment_selection(self):
        self.make_keil()
        tools = self.local_keil_tools()
        candidates = [entry for entry in tools["toolchains"] if entry["kind"] == "keil"]
        if not candidates:
            self.skipTest("Local Keil needed for multi-install selection check")
        first = dict(candidates[0], id="first")
        second = dict(candidates[0], id="second")
        tools["toolchains"] = [first, second]
        self.tools.write_text(json.dumps(tools), encoding="utf-8")
        self.call("project", "validate", "--project", "test", expected="AMBIGUOUS_TOOLCHAIN")
        self.project["toolchain"] = "first"
        self.save()
        self.call("project", "validate", "--project", "test")
        first["root"] = "X:/unmounted/Keil"
        self.tools.write_text(json.dumps(tools), encoding="utf-8")
        self.call("project", "validate", "--project", "test", expected="TOOLCHAIN_MISSING")

    def menu(self, input_text, *arguments):
        # Read-Host hides prompts with redirected stdin, so this test host echoes its prompt argument.
        def quote(value):
            return "'" + str(value).replace("'", "''") + "'"
        wrapper = self.root / 'menu-host.ps1'
        invocation = [PS, '--config', self.config, '--tools', self.tools, *arguments]
        wrapper.write_text(
            'function Read-Host([string]$Prompt) { Write-Host $Prompt; [Console]::ReadLine() }\n'
            + '& ' + ' '.join(quote(value) for value in invocation) + '\n', encoding='utf-8-sig')
        return subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(wrapper)],
                              input=input_text, capture_output=True, encoding="utf-8", timeout=30)

    def test_first_launch_creates_config(self):
        for arguments, prompt, guide in [((), 'First launch: detecting local tools', 'README.md'),
                                         (('--lang', 'zh-CN'), '首次启动，正在检测本机环境', 'README.zh-CN.md')]:
            with self.subTest(arguments=arguments):
                self.tools.unlink()
                self.config.unlink()
                result = self.menu("D\n0\n", *arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Puyuan', result.stdout)
                self.assertNotIn('蒲元（Puyuan）', result.stdout)
                self.assertIn(prompt, result.stdout)
                self.assertGreaterEqual(result.stdout.count(str(APP / guide)), 2)
                self.assertEqual(json.loads(self.config.read_text(encoding="utf-8"))["projects"], [])
                self.assertEqual(json.loads(self.tools.read_text(encoding="utf-8"))["schemaVersion"], 1)
                self.assertFalse((self.root / "fresh.bin").exists())

    def test_menu_language_switch_changes_guidance(self):
        project_before = self.config.read_bytes()
        tools_before = json.loads(self.tools.read_text(encoding='utf-8'))
        result = self.menu("L\nD\n0\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Select a project number', result.stdout)
        self.assertIn('选择工程序号', result.stdout)
        self.assertIn(str(APP / 'README.zh-CN.md'), result.stdout)
        self.assertIn('[L] 中文', result.stdout)
        self.assertIn('[L] English', result.stdout)
        self.assertEqual(project_before, self.config.read_bytes())
        tools_before['language'] = 'zh-CN'
        self.assertEqual(tools_before, json.loads(self.tools.read_text(encoding='utf-8')))
        restarted = self.menu("D\n0\n")
        self.assertIn('选择工程序号', restarted.stdout)
        self.assertNotIn('Select a project number', restarted.stdout)
        detected = self.call('env', 'detect', '--save')
        self.assertEqual(detected['data']['configuration']['language'], 'zh-CN')
        saved = self.tools.read_bytes()
        overridden = self.menu("D\n0\n", '--lang', 'en')
        self.assertIn('Select a project number', overridden.stdout)
        self.assertIn(str(APP / 'README.md'), overridden.stdout)
        self.assertEqual(saved, self.tools.read_bytes())
        switched_back = self.menu("L\nD\n0\n")
        self.assertIn(str(APP / 'README.md'), switched_back.stdout)
        self.assertEqual(json.loads(self.tools.read_text(encoding='utf-8'))['language'], 'en')

    def test_menu_actions_in_both_languages(self):
        messages = {'en': ('Build all artifacts', 'Generate factory firmware', 'Generate upgrade firmware', 'Build succeeded.'),
                    'zh-CN': ('全部编译', '生成首装固件', '生成升级固件', '构建成功')}
        for language in messages:
            for action in ('all', 'factory', 'upgrade'):
                with self.subTest(language=language, action=action):
                    self.project['artifacts'][0]['kind'] = 'application' if action == 'all' else action
                    self.project['commands'][action] = dict(self.project['commands']['all'])
                    self.save()
                    number = '1' if action == 'all' else '2'
                    result = self.menu('1\n' + number + '\n\n0\n', '--lang', language)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn(messages[language][('all', 'factory', 'upgrade').index(action)], result.stdout)
                    self.assertIn(messages[language][3], result.stdout)
                    manifests = list((self.root / 'delivery').rglob('result.json'))
                    latest = max(manifests, key=lambda p: p.stat().st_mtime_ns)
                    response = json.loads(latest.read_text(encoding='utf-8'))
                    self.assertTrue(response['ok'])
                    self.assertEqual(response['data']['action'], action)
                    self.assertEqual(len(response['data']['artifacts']), 1)
                    self.assertTrue(Path(response['data']['artifacts'][0]['path']).is_file())

    def test_menu_failure_prompts_in_both_languages(self):
        self.project['commands']['all']['arguments'][1] = 'fail'
        self.save()
        for language, prompt in [('en', 'Press Enter to return'), ('zh-CN', '按 Enter 返回')]:
            with self.subTest(language=language):
                result = self.menu('1\n1\n\n0\n', '--lang', language)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('BUILD_FAILED', result.stdout)
                self.assertIn(prompt, result.stdout)
                self.assertFalse(list((self.root / 'delivery').rglob('Board-1.2.bin')))

    def test_language_option_validation_and_json_stability(self):
        baseline = self.call('help')
        self.assertIn('--lang en|zh-CN', baseline['data']['options'])
        for language in ('en', 'zh-CN'):
            self.assertEqual(self.call('help', '--lang', language), baseline)
        for arguments in [('--lang',), ('--lang', ''), ('--lang', 'fr'), ('--lang', 'EN')]:
            with self.subTest(arguments=arguments):
                self.call('help', *arguments, expected='USAGE')
        document = json.loads(self.tools.read_text(encoding='utf-8'))
        document['language'] = 'fr'
        self.tools.write_text(json.dumps(document), encoding='utf-8')
        self.call('env', 'detect', expected='CONFIG_INVALID')

    def test_project_list_shape(self):
        response = self.call("project", "list")
        self.assertIsInstance(response["data"]["projects"], list)

    def test_custom_batch_command_with_spaces(self):
        import os
        batch = self.root / "build script.cmd"
        batch.write_text('@echo off\n>"%~1" echo firmware\n', encoding="ascii")
        self.project["commands"]["all"] = {
            "executable": str(Path(os.environ["SystemRoot"]) / "System32/cmd.exe"),
            "arguments": ["/d", "/s", "/c", f'"{batch}" "{self.root / "fresh.bin"}"'],
        }
        self.save()
        self.call("build", "--project", "test")

    def test_upgrade_rejects_numeric_version_drift(self):
        import runpy
        import sys
        from unittest.mock import patch
        (self.root / "tools").mkdir()
        (self.root / "User_Driver").mkdir()
        script = self.root / "tools/firmware.py"
        script.write_text('def envelope(data, version): return data\n', encoding="utf-8")
        (self.root / "User_Driver/boot_update.h").write_text('#define TEST_FW_VERSION_ID 0x00010003UL\n', encoding="utf-8")
        adapter = runpy.run_path(str(APP / "lib/envelope.py"))
        args = ["envelope.py", "--script", str(script), "--fromelf", "missing.exe", "--axf", "missing.axf",
                "--output", str(self.root / "upgrade.bin"), "--version", "1.2"]
        with patch.object(sys, "argv", args), self.assertRaisesRegex(ValueError, "versions disagree"):
            adapter["main"]()
        self.assertFalse((self.root / "upgrade.bin").exists())

    def make_idf(self):
        import sys
        sdk = self.root / "sdk"
        (sdk / "tools").mkdir(parents=True)
        (sdk / "export.bat").write_text('@echo off\nexit /b 0\n', encoding="ascii")
        (sdk / "tools/idf.py").write_text(
            'import pathlib,sys,os\n'
            'out=pathlib.Path(sys.argv[sys.argv.index("-B")+1]); out.mkdir(parents=True,exist_ok=True)\n'
            'assert os.environ["IDF_TARGET"]=="esp32"\n'
            'if "merge-bin" in sys.argv: (out/"merged-flash.bin").write_bytes(b"factory")\n'
            'elif not (out/"demo.elf").exists():\n'
            ' (out/"demo.elf").write_bytes(b"linked ELF"); (out/"demo.bin").write_bytes(b"application")\n'
            'elif not (out/"demo.bin").exists(): raise RuntimeError("post-link BIN was not regenerated")\n', encoding="utf-8")
        (self.root / "CMakeLists.txt").write_text('include($ENV{IDF_PATH}/tools/cmake/project.cmake)\nproject(demo)\n', encoding="utf-8")
        (self.root / "main").mkdir()
        (self.root / "main/CMakeLists.txt").write_text('idf_component_register(SRCS "main.c")\n', encoding="utf-8")
        self.project = {"id": "test", "name": "ESP32", "path": str(self.root), "builder": "esp-idf", "target": "esp32"}
        self.document["projects"] = [self.project]
        self.save()
        self.tools.write_text(json.dumps({"schemaVersion": 1, "toolchains": [
            {"id": "idf", "kind": "esp-idf", "root": str(sdk), "toolsPath": str(self.root / "tools-store"), "python": sys.executable}]}), encoding="utf-8")

    def test_idf_inspection_and_full_build(self):
        self.make_idf()
        response = self.call("project", "inspect", "--path", str(self.root))
        self.assertEqual(response["data"]["suggestedConfig"]["builder"], "esp-idf")
        self.assertEqual(len(response["data"]["candidates"]), 1)
        response = self.call("build", "--project", "test")
        self.assertEqual({a["kind"] for a in response["data"]["artifacts"]}, {"factory", "application"})
        self.call("build", "--project", "test")

    def test_idf_upgrade_and_chip_mismatch(self):
        self.make_idf()
        self.project["artifacts"] = [{"kind": "upgrade", "source": "{outputDir}/{outputName}.bin"}]
        self.save()
        plan = self.call("build", "--project", "test", "--action", "upgrade", "--dry-run")["data"]
        self.assertEqual(len(plan["commands"]), 1)
        self.assertTrue(plan["commands"][0]["arguments"][-1].endswith(" app"))
        self.call("build", "--project", "test", "--action", "upgrade")
        (self.root / "sdkconfig").write_text('CONFIG_IDF_TARGET="esp32c3"\n', encoding="utf-8")
        self.call("project", "validate", "--project", "test", expected="CONFIG_INVALID")

    def test_keil_no_hex_infers_binary_conversion(self):
        file = self.make_keil()
        file.write_text(file.read_text(encoding="utf-8").replace('<CreateHexFile>1', '<CreateHexFile>0'), encoding="utf-8")
        del self.project["artifacts"]
        self.save()
        self.tools.write_text(json.dumps(self.local_keil_tools()), encoding="utf-8")
        plan = self.call("build", "--project", "test", "--dry-run")["data"]
        self.assertEqual(len(plan["commands"]), 2)
        self.assertIn("--bin", plan["commands"][1]["arguments"])
        self.assertTrue(plan["artifacts"][0]["source"].endswith("Board.bin"))

    def test_armclang_uses_its_own_fromelf(self):
        file = self.make_keil()
        file.write_text(file.read_text(encoding="utf-8").replace('<pCCUsed>', '<uAC6>1</uAC6><pCCUsed>'), encoding="utf-8")
        self.project["outputFormat"] = "bin"
        self.save()
        self.tools.write_text(json.dumps(self.local_keil_tools(armclang=True)), encoding="utf-8")
        plan = self.call("build", "--project", "test", "--dry-run")["data"]
        self.assertIn("ARMCLANG", plan["commands"][1]["executable"].upper())
        self.assertIn("clang", plan["toolchain"]["compilerVersion"].lower())

    def test_idf_failure_restores_previous_firmware(self):
        self.make_idf()
        build = self.root / "build"
        build.mkdir()
        old = build / "demo.bin"
        old.write_bytes(b"old firmware")
        (self.root / "sdk/tools/idf.py").write_text('raise RuntimeError("compiler failure")\n', encoding="utf-8")
        self.call("build", "--project", "test", expected="BUILD_FAILED")
        self.assertEqual(old.read_bytes(), b"old firmware")

    def test_idf_python_environment_missing(self):
        self.make_idf()
        tools=json.loads(self.tools.read_text(encoding="utf-8"))
        tools["toolchains"][0]["python"]=str(self.root / "missing/python.exe")
        self.tools.write_text(json.dumps(tools),encoding="utf-8")
        self.call("project","validate","--project","test",expected="TOOLCHAIN_MISSING")


if __name__ == "__main__":
    unittest.main(verbosity=2)
