"""Validate public documentation links, schemas, entry point identity, and PowerShell example syntax."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

APP = Path(__file__).resolve().parents[1]


class DocumentationTests(unittest.TestCase):
    def test_project_identity_matches_entry_points(self):
        self.assertTrue((APP / 'puyuan.cmd').is_file())
        self.assertTrue((APP / 'puyuan.ps1').is_file())
        self.assertIn('%~dp0puyuan.ps1',(APP / 'puyuan.cmd').read_text(encoding='utf-8'))
        self.assertTrue((APP / 'README.md').read_text(encoding='utf-8').startswith('# Puyuan'))
        english = (APP / 'README.md').read_text(encoding='utf-8')
        chinese = (APP / 'README.zh-CN.md').read_text(encoding='utf-8')
        self.assertTrue(chinese.startswith('# 蒲元（Puyuan）'))
        self.assertIn('](README.zh-CN.md)', english)
        self.assertIn('](README.md)', chinese)
        self.assertEqual(re.findall(r'<a id="([^"]+)"', english), re.findall(r'<a id="([^"]+)"', chinese))
        self.assertEqual([json.loads(v) for v in re.findall(r'```json\s*\n(.*?)```', english, re.S)],
                         [json.loads(v) for v in re.findall(r'```json\s*\n(.*?)```', chinese, re.S)])
        self.assertIn('Version 2.0, January 2004', (APP / 'LICENSE').read_text(encoding='utf-8'))
        for file in (APP / 'schema').glob('*.json'):
            self.assertTrue(json.loads(file.read_text(encoding='utf-8'))['title'].startswith('Puyuan '))

    def documents(self):
        return [*APP.glob("README*.md"), APP / "CONTRIBUTING.md", *(APP / "docs").rglob("*.md"), *(APP / "reports").glob("*.md"), *(APP / "skills").rglob("SKILL.md")]

    def test_relative_links_exist(self):
        for document in self.documents():
            for link in re.findall(r"\]\(([^)]+)\)", document.read_text(encoding="utf-8")):
                if link.startswith(("http://", "https://")): continue
                path, _, fragment = link.partition("#")
                target = document.parent / path if path else document
                self.assertTrue(target.is_file(), (document, link))
                if fragment:
                    contents = target.read_text(encoding="utf-8")
                    anchors = set(re.findall(r'<a\s+id="([^"]+)"', contents))
                    headings = re.findall(r"^#{1,6} (.+)$", contents, re.M)
                    anchors.update(re.sub(r"[^\w -]", "", h.lower()).replace(" ", "-") for h in headings)
                    self.assertIn(fragment, anchors, (document, link))
        for source in [APP / "puyuan.ps1", *(APP / "lib").glob("*.ps1")]:
            for reference in re.findall(r"'(README(?:\.zh-CN)?\.md|docs/[\w/-]+\.md)'", source.read_text(encoding="utf-8-sig")):
                self.assertTrue((APP / reference).is_file(), (source, reference))

    def test_public_docs_have_no_machine_specific_paths(self):
        for document in self.documents():
            self.assertIsNone(re.search(r"[A-Za-z]:[/\\]+(?:Users|workspace)[/\\]", document.read_text(encoding="utf-8"), re.I), document)
            self.assertNotIn("{{", document.read_text(encoding="utf-8"), document)

    def test_examples_and_json_blocks_match_runtime_schema(self):
        samples=[]
        blocks=[]
        for document in self.documents():
            for block in re.findall(r"```json\s*\n(.*?)```", document.read_text(encoding="utf-8"), re.S):
                value=json.loads(block)
                blocks.append(value)
                samples.append(dict(origin=str(document), kind="projects" if "projects" in value else "toolchains", value=value))
        for file in (APP / "examples").glob("*.json"):
            value=json.loads(file.read_text(encoding="utf-8"))
            self.assertIn(value,blocks,f"Example has no matching documented full configuration: {file}")
            samples.append(dict(origin=str(file),kind="projects" if "projects" in value else "toolchains",value=value))
        with tempfile.TemporaryDirectory(prefix="puyuan-doc-check-") as directory:
            directory=Path(directory)
            data=directory / "samples.json"
            data.write_text(json.dumps(samples,ensure_ascii=False),encoding="utf-8")
            probe=directory / "check.ps1"
            probe.write_text(
                "$ErrorActionPreference='Stop'\n"
                f"$script:AppRoot='{str(APP).replace(chr(39), chr(39)*2)}'\n"
                ". \"$script:AppRoot/lib/config.ps1\"\n"
                f"$samples=Read-Json '{data}'\n"
                "foreach($sample in $samples){\n"
                " $schema=Read-Json (Join-Path $script:AppRoot ('schema/'+$sample.kind+'.schema.json'))\n"
                " try {Assert-Schema $sample.value $schema $schema} catch {throw ($sample.origin+': '+$_.Exception.Message)}\n"
                "}\n",encoding="utf-8-sig")
            result=subprocess.run(["powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",str(probe)],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr.decode("utf-8",errors="replace"))

    def test_powershell_snippets_parse(self):
        snippets=[]
        for document in self.documents():
            for block in re.findall(r"```powershell\s*\n(.*?)```",document.read_text(encoding="utf-8"),re.S):
                snippets.append(dict(origin=str(document),text=block))
        with tempfile.TemporaryDirectory(prefix="puyuan-doc-ps-") as directory:
            directory=Path(directory)
            data=directory / "snippets.json"
            data.write_text(json.dumps(snippets,ensure_ascii=False),encoding="utf-8")
            probe=directory / "parse.ps1"
            probe.write_text(
                "$ErrorActionPreference='Stop'\n"
                f"$items=Get-Content -Raw -Encoding UTF8 -LiteralPath '{data}' | ConvertFrom-Json\n"
                "foreach($item in $items){\n"
                " $tokens=$null; $errors=$null\n"
                " $null=[Management.Automation.Language.Parser]::ParseInput($item.text,[ref]$tokens,[ref]$errors)\n"
                " if($errors.Count){throw ($item.origin+': '+($errors.Message -join ', '))}\n"
                "}\n",encoding="utf-8-sig")
            result=subprocess.run(["powershell.exe","-NoProfile","-ExecutionPolicy","Bypass","-File",str(probe)],capture_output=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stderr.decode("utf-8",errors="replace"))

    def test_errors_have_documentation(self):
        for document in APP.glob("README*.md"):
            documented=document.read_text(encoding="utf-8")
            for source in [APP / "puyuan.ps1",*(APP / "lib").glob("*.ps1")]:
                for code in re.findall(r"\bFail\s+'([A-Z_]+)'",source.read_text(encoding="utf-8-sig")):
                    self.assertIn(code,documented,(document,source,code))


if __name__ == "__main__":
    unittest.main(verbosity=2)
