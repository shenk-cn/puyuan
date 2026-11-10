# Inspect project entry points, validate versions and artifacts, and create an unexecuted build plan.
function Find-ProjectFiles($Path) {
    $resolved = Resolve-File (Get-Location).Path $Path
    if (Test-Path -LiteralPath $resolved -PathType Leaf) { return @($resolved) }
    if (!(Test-Path -LiteralPath $resolved -PathType Container)) { Fail 'PROJECT_MISSING' "Directory missing: $resolved" }
    $files = New-Object 'Collections.Generic.List[string]'
    $queue = New-Object Collections.Queue
    $queue.Enqueue(@{path=$resolved; depth=0})
    while ($queue.Count) {
        $item = $queue.Dequeue()
        foreach ($file in Get-ChildItem -LiteralPath $item.path -File) {
            if ($file.Extension -in @('.uvprojx','.uvproj') -or $file.Name -in @('.cproject','CMakeLists.txt','Makefile','platformio.ini')) { $files.Add($file.FullName) }
        }
        if ($item.depth -ge 3) { continue }
        # Skip vendor dependencies, build outputs, and directory links to avoid unrelated or repeated scans.
        foreach ($directory in Get-ChildItem -LiteralPath $item.path -Directory) {
            if ($directory.Name -match '^(?i:Drivers|CMSIS|Middlewares|Libraries|Examples|\.git|\.settings|build|Debug|Release|node_modules|reports|tests|out|dist)$' -or
                ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            $queue.Enqueue(@{path=$directory.FullName; depth=$item.depth + 1})
        }
    }
    return @($files)
}

function Read-Keil($ProjectFile, $Target) {
    try { [xml]$xml = [IO.File]::ReadAllText($ProjectFile) }
    catch { Fail 'PROJECT_INVALID' "Invalid Keil XML: $ProjectFile" }
    $targets = @($xml.SelectNodes('//Targets/Target'))
    if ($Target) { $targets = @($targets | Where-Object { $_.TargetName -ceq $Target }) }
    if (!$targets.Count) { Fail 'TARGET_MISSING' "Target '$Target' missing in $ProjectFile" }
    if ($targets.Count -gt 1) { Fail 'AMBIGUOUS_TARGET' 'Set target in project configuration' @{targets=@($targets.TargetName)} }
    $node = $targets[0]
    # Keil output paths are relative to the project file directory, which may differ from the project root.
    $common = $node.TargetOption.TargetCommonOption
    return @{file=$ProjectFile; target=[string]$node.TargetName; device=[string]$common.Device;
        compiler=[string]$node.pCCUsed; ac6=([string]$node.uAC6 -eq '1'); pack=[string]$common.PackID;
        outputDir=(Resolve-File (Split-Path -Parent $ProjectFile) ([string]$common.OutputDirectory));
        outputName=[string]$common.OutputName; hex=([string]$common.CreateHexFile -eq '1')}
}

function Inspect-Project($Path) {
    $files = @(Find-ProjectFiles $Path)
    $candidates = @()
    foreach ($file in $files) {
        if ([IO.Path]::GetFileName($file) -eq 'CMakeLists.txt') {
            $cmakeText=[IO.File]::ReadAllText($file)
            if ($cmakeText -notmatch '(?m)^\s*project\s*\(') { continue }
            if ($cmakeText -match 'IDF_PATH.*tools/cmake/project\.cmake') {
                $root=Split-Path -Parent $file
                $info=Read-IdfProject $root @{}
                $candidate=@{id=$info.outputName; name=$info.outputName; projectName=$info.outputName; path=$root; builder='esp-idf'; target=$info.target}
                $candidates += @{projectFile=$file; info=$info; suggestedConfig=$candidate; review=@('Declare upgrade artifact only when the product supports application updates.')}
                continue
            }
        }
        # Generic entry points are candidates only; their commands and artifact paths need project-specific configuration.
        if ([IO.Path]::GetExtension($file) -notin @('.uvprojx','.uvproj')) {
            $candidates += @{projectFile=$file; builder='command'; note='Configure a command builder using the project build tool and exact artifact paths.'}
            continue
        }
        try { [xml]$xml = [IO.File]::ReadAllText($file) }
        catch { Fail 'PROJECT_INVALID' "Invalid Keil XML: $file" }
        foreach ($node in $xml.SelectNodes('//Targets/Target')) {
            $info = Read-Keil $file ([string]$node.TargetName)
            $root = Split-Path -Parent $file
            if ((Split-Path -Leaf $root) -eq 'MDK-ARM') { $root = Split-Path -Parent $root }
            $id = [regex]::Replace($info.target, '[^a-zA-Z0-9_-]', '-').Trim('-')
            if (!$id) { $id = 'project' }
            $candidate = @{id=$id; name=$info.target; projectName=$info.target; path=$root; builder='keil'; projectFile=$file; target=$info.target}
            $notes = @('Confirm firmware purpose and version source before adding factory/upgrade artifacts.')
            if ($info.hex) {
                $candidate.artifacts = @(@{kind='application'; source='{outputDir}/{outputName}.hex'; name='{project}.{ext}'})
            } else { $candidate.outputFormat='bin'; $notes += 'HEX output is disabled. Export application BIN from the AXF with fromelf.' }
            if (Test-Path -LiteralPath (Join-Path $root 'tools/firmware.py')) { $notes += 'Existing tools/firmware.py detected. Review its CLI and packaging contract.' }
            $candidates += @{projectFile=$file; target=$info.target; info=$info; suggestedConfig=$candidate; review=$notes}
        }
    }
    if (!$candidates.Count) { Fail 'PROJECT_MISSING' 'No supported build entry found within 3 directory levels; specify projectFile or command builder' }
    if ($candidates.Count -gt 1) { Fail 'AMBIGUOUS_PROJECT' 'Select an exact project file and target' @{candidates=$candidates} }
    return @{candidates=$candidates; suggestedConfig=$candidates[0].suggestedConfig}
}

function Read-Version($Project, $Root) {
    if (!$Project.version) { return '' }
    if ($Project.version.value -and ($Project.version.file -or $Project.version.pattern)) { Fail 'CONFIG_INVALID' 'version.value and version.file/pattern are mutually exclusive' }
    if ($Project.version.value) { return $Project.version.value }
    if (!$Project.version.file -or !$Project.version.pattern) { Fail 'CONFIG_INVALID' 'version needs value or file plus pattern' }
    $file = Resolve-File $Root $Project.version.file
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { Fail 'VERSION_MISSING' "Version source missing: $file" }
    try { $matches = [regex]::Matches([IO.File]::ReadAllText($file), $Project.version.pattern) }
    catch { Fail 'CONFIG_INVALID' 'Invalid version regex' }
    # Require one nonempty version capture to avoid confusing multiple macros or hardware and software versions.
    if ($matches.Count -ne 1 -or $matches[0].Groups.Count -lt 2 -or !$matches[0].Groups[1].Value) { Fail 'VERSION_MISSING' 'Version pattern must match exactly once and capture the version in group 1' }
    return $matches[0].Groups[1].Value
}

function Get-ProjectPlan($ConfigPath, $ToolsPath, $Id, $Action = 'all') {
    $config = Read-Config $ConfigPath 'projects' 'projects'
    $items = @($config.projects | Where-Object { $_.id -eq $Id })
    if (!$items.Count) { Fail 'PROJECT_MISSING' "Unknown project id '$Id'" }
    $project = $items[0]
    $root = Resolve-File (Split-Path -Parent $ConfigPath) $project.path
    if (!(Test-Path -LiteralPath $root -PathType Container)) { Fail 'PROJECT_MISSING' "Project root missing: $root" }
    $version = Read-Version $project $root
    $variables = @{root=$root; project=$project.name; version=$version; target=$project.target; date=(Get-Date -Format 'yyyyMMdd')}
    if ($project.projectName) { $variables.project = $project.projectName }
    $keil = $null
    $tool = $null
    $tools = @{schemaVersion=1; toolchains=@()}
    if (Test-Path -LiteralPath $ToolsPath) { $tools = Read-Config $ToolsPath 'toolchains' 'toolchains' }
    $idf=$null
    if ($project.builder -in @('keil','firmware-script')) {
        $projectFile = $null
        if ($project.projectFile) { $projectFile = Resolve-File $root $project.projectFile }
        else {
            $candidates = @(Find-ProjectFiles $root | Where-Object { [IO.Path]::GetExtension($_) -in @('.uvprojx','.uvproj') })
            if ($candidates.Count -ne 1) { Fail 'AMBIGUOUS_PROJECT' 'Set projectFile explicitly' @{candidates=$candidates} }
            $projectFile = $candidates[0]
        }
        $keil = Read-Keil $projectFile $project.target
        $variables.target=$keil.target
        $variables.outputDir=$keil.outputDir
        $variables.outputName=$keil.outputName
        $variables.projectFile=$keil.file
        $tool = Select-Keil $project $tools (Split-Path -Parent $ToolsPath) $keil
        $variables.keil=$tool.root
        $variables.fromelf=$tool.components.fromelf.path
    }
    if ($project.builder -eq 'esp-idf') {
        $idf=Read-IdfProject $root $project
        $tool=Select-Idf $project $tools (Split-Path -Parent $ToolsPath)
        $variables.outputDir=$idf.outputDir
        $variables.outputName=$idf.outputName
        $variables.target=$idf.target
    }
    $format=$null
    if ($project.builder -eq 'keil') {
        $format='hex'
        if (!$keil.hex) { $format='bin' }
        if ($project.outputFormat) { $format=$project.outputFormat }
    }
    $artifacts = $project.artifacts
    if (!$artifacts) {
        if ($project.builder -eq 'keil') { $artifacts=@(@{kind='application'; source=('{outputDir}/{outputName}.'+$format)}) }
        elseif ($project.builder -eq 'esp-idf') {
            $artifacts=@(@{kind='factory';source='{outputDir}/merged-flash.bin'},@{kind='application';source='{outputDir}/{outputName}.bin'})
        }
        else { Fail 'CONFIG_INVALID' 'Configure artifacts explicitly for this project' }
    }
    # all covers only this project; other actions depend on the declared artifact purposes.
    $supported = @('all') + @($artifacts.kind | Where-Object { $_ -in @('factory','upgrade') } | Sort-Object -Unique)
    if ($Action -notin $supported) { Fail 'ACTION_UNSUPPORTED' "Action '$Action' unavailable" @{supportedActions=$supported} }
    $selected = @($artifacts | Where-Object { $Action -eq 'all' -or $_.kind -eq $Action })
    $outputs = @()
    $names = @{}
    foreach ($artifact in $selected) {
        $source = Resolve-File $root (Expand-Template $artifact.source $variables)
        if (!$source.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { Fail 'CONFIG_INVALID' "Artifact must be inside project root: $source" }
        if ($source -match '[*?]') { Fail 'CONFIG_INVALID' 'Artifact source must be an exact file path' }
        $values = $variables.Clone()
        $values.kind=$artifact.kind
        $values.ext=[IO.Path]::GetExtension($source).TrimStart('.')
        $template = '{project}-{kind}.{ext}'
        if ($config.defaultName) { $template=$config.defaultName }
        if ($artifact.name) { $template=$artifact.name }
        $name = Expand-Template $template $values
        Assert-FileName $name
        if ($name -match '^(?i:step-|keil-|result\.json$)') { Fail 'TEMPLATE_INVALID' "Filename reserved for build logs: $name" }
        if ($names.ContainsKey($name)) { Fail 'TEMPLATE_INVALID' "Two artifacts produce the same filename: $name" }
        $names[$name]=$true
        if ($source -in $outputs.source) { Fail 'CONFIG_INVALID' "Two artifacts use the same source: $source" }
        $outputs += @{kind=$artifact.kind; source=$source; name=$name}
    }
    $commands = @()
    if ($project.builder -eq 'firmware-script') {
        if (!$project.script) { Fail 'CONFIG_INVALID' 'firmware-script requires script' }
        if (@($artifacts | Where-Object { $_.kind -eq 'upgrade' }).Count -ne 1 -or @($artifacts | Where-Object { $_.kind -eq 'factory' }).Count -ne 1 -or $artifacts.Count -ne 2) {
            Fail 'CONFIG_INVALID' 'firmware-script requires exactly one factory and one upgrade artifact'
        }
        foreach ($key in @('armcc','armasm','armlink','fromelf')) {
            if (!$tool.components[$key].exists) { Fail 'TOOLCHAIN_MISSING' "firmware-script needs $key" }
        }
        if ($keil.ac6) { Fail 'CONFIG_INVALID' 'firmware-script envelope-v1 requires ARMCC5' }
        if ($tool.compilerRoot -ne (Resolve-File $tool.root 'ARM/ARMCC')) { Fail 'CONFIG_INVALID' 'firmware-script uses ARM/ARMCC under the Keil root; custom compilerRoot requires command builder' }
        $scriptPath=Resolve-File $root $project.script
        if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) { Fail 'CONFIG_INVALID' "Packager missing: $scriptPath" }
        if (!$tools.python) { Fail 'TOOLCHAIN_MISSING' 'Configure python in toolchains.local.json' }
        $variables.python=Resolve-File (Split-Path -Parent $ToolsPath) $tools.python
        if (!(Test-Path -LiteralPath $variables.python -PathType Leaf)) { Fail 'TOOLCHAIN_MISSING' "Python missing: $($variables.python)" }
        $pythonProbe=Invoke-Tool $variables.python @('--version') $root $null 15
        if ($pythonProbe.exitCode -ne 0 -or $pythonProbe.text -notmatch 'Python 3\.') { Fail 'TOOLCHAIN_MISSING' 'Python 3 is required' }
        # The compatible upgrade path rebuilds and wraps the application; factory and all invoke the full packager.
        if ($Action -eq 'upgrade') {
            if ($project.upgradeEnvelope -ne 'envelope-v1' -or $version -notmatch '^\d+\.\d+$') { Fail 'CONFIG_INVALID' 'Upgrade requires envelope-v1 and a major.minor version' }
            $commands += @{type='keil'; executable=$tool.components.uv4.path; arguments=@('-r',$keil.file,'-t',$keil.target,'-sg'); successCodes=@(0,1)}
            $commands += @{type='process'; executable=$variables.python; arguments=@((Join-Path $script:AppRoot 'lib/envelope.py'),'--script',$scriptPath,'--fromelf',$variables.fromelf,
                '--axf',(Join-Path $keil.outputDir ($keil.outputName + '.axf')),'--output',$outputs[0].source,'--version',$version); successCodes=@(0); freshInput=(Join-Path $keil.outputDir ($keil.outputName + '.axf'))}
        } else {
            if (!$project.keilLog) { Fail 'CONFIG_INVALID' 'firmware-script requires keilLog written by its --rebuild command' }
            $commands += @{type='packager'; executable=$variables.python; arguments=@($scriptPath,'--keil',$tool.root,'--rebuild'); successCodes=@(0)}
        }
    } elseif ($project.builder -eq 'keil') {
        $commands += @{type='keil'; executable=$tool.components.uv4.path; arguments=@('-r',$keil.file,'-t',$keil.target,'-sg','-j0'); successCodes=@(0,1)}
        # Conversion must use the current build AXF, checked through freshInput during execution.
        if ($format -eq 'bin' -or ($format -eq 'hex' -and !$keil.hex)) {
            if (!$tool.components.fromelf.exists) { Fail 'TOOLCHAIN_MISSING' "fromelf required for $format conversion" }
            $option='--bin'
            if ($format -eq 'hex') { $option='--i32combined' }
            $commands += @{type='process'; executable=$tool.components.fromelf.path;
                arguments=@($option,'--output',(Join-Path $keil.outputDir ($keil.outputName+".$format")),(Join-Path $keil.outputDir ($keil.outputName+'.axf')));successCodes=@(0);freshInput=(Join-Path $keil.outputDir ($keil.outputName+'.axf'))}
        }
    } elseif ($project.builder -eq 'esp-idf') {
        $commands=@(Get-IdfCommands $tool $idf $root $Action)
    } else {
        if (!$project.commands) { Fail 'CONFIG_INVALID' 'command builder requires commands' }
        $command = $project.commands[$Action]
        if (!$command) { Fail 'ACTION_UNSUPPORTED' "No command configured for '$Action'" }
        $executable = Expand-Template $command.executable $variables
        if (!(Test-Path -LiteralPath $executable -PathType Leaf)) {
            $found=Get-Command $executable -CommandType Application -ErrorAction SilentlyContinue
            if ($found) { $executable=$found.Source } else { $executable=Resolve-File $root $executable }
        }
        if (!(Test-Path -LiteralPath $executable -PathType Leaf)) { Fail 'TOOLCHAIN_MISSING' "Command executable missing: $executable" }
        if ([IO.Path]::GetExtension($executable) -in @('.cmd','.bat')) { Fail 'CONFIG_INVALID' 'For batch scripts configure cmd.exe with /d /s /c and a quoted command argument' }
        $codes=@(0)
        if ($command.successCodes) { $codes=$command.successCodes }
        $commands += @{type='process'; executable=$executable; arguments=@($command.arguments | ForEach-Object { Expand-Template $_ $variables }); successCodes=$codes}
    }
    $out='outputs'
    if ($config.outputDirectory) { $out=$config.outputDirectory }
    return @{projectId=$Id; projectName=$variables.project; target=$variables.target; root=$root; action=$Action; supportedActions=$supported; version=$version;
        builder=$project.builder; toolchain=$tool; keil=$keil; commands=$commands; artifacts=$outputs;
        outputDirectory=(Resolve-File (Split-Path -Parent $ConfigPath) $out); packagerLog=$project.keilLog}
}
