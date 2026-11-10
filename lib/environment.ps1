# Detect local toolchains, invoke processes, and escape Windows command-line arguments.
function Quote-Argument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    # Preserve quotes and trailing backslashes according to Windows argument parsing rules.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-Tool($Executable, $Arguments, $Directory, $LogPath, $TimeoutSeconds = 1800, $Environment = @{}) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = (@($Arguments | ForEach-Object { Quote-Argument ([string]$_) }) -join ' ')
    if ([IO.Path]::GetFileName($Executable) -eq 'cmd.exe') {
        if ($Arguments.Count -ne 4 -or ($Arguments[0..2] -join ' ') -ne '/d /s /c') {
            Fail 'CONFIG_INVALID' 'cmd.exe requires arguments [/d, /s, /c, raw command string]'
        }
        # cmd.exe parses the final command string itself, without ordinary program argument escaping.
        $info.Arguments = '/d /s /c "' + $Arguments[3] + '"'
    }
    $info.WorkingDirectory = $Directory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    foreach ($key in $Environment.Keys) { $info.EnvironmentVariables[$key] = [string]$Environment[$key] }
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        try { $started=$process.Start() }
        catch { Fail 'TOOL_START_FAILED' "Cannot start $Executable. $($_.Exception.Message)" }
        if (!$started) { Fail 'TOOL_START_FAILED' "Cannot start $Executable" }
        # Read both output streams asynchronously so a full buffer cannot block the child process.
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            # Stop the process tree, then drain output and retain diagnostics emitted before termination.
            & "$env:SystemRoot/System32/taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null
            if (!$process.WaitForExit(5000)) { Fail 'BUILD_TIMEOUT' 'Timed-out process could not be stopped' @{executable=$Executable; log=$LogPath} }
        }
        $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        if ($LogPath) { [IO.File]::WriteAllText($LogPath, $text, (New-Object Text.UTF8Encoding($false))) }
        if ($timedOut) { Fail 'BUILD_TIMEOUT' "Process exceeded $TimeoutSeconds seconds" @{executable=$Executable; log=$LogPath} }
        return @{exitCode=$process.ExitCode; text=$text}
    } finally { $process.Dispose() }
}

function Get-ToolStatus($Entry, $Base) {
    $root = Resolve-File $Base $Entry.root
    $status = @{id=$Entry.id; kind=$Entry.kind; root=$root; available=$false; missing=@(); components=@{}}
    $files = @{}
    switch ($Entry.kind) {
        'keil' {
            $compiler = [IO.Path]::GetFullPath([IO.Path]::Combine($root, 'ARM/ARMCC'))
            if ($Entry.compilerRoot) { $compiler = Resolve-File $Base $Entry.compilerRoot }
            $status.compilerRoot = $compiler
            $files = @{uv4=([IO.Path]::Combine($root, 'UV4/UV4.exe')); armcc=([IO.Path]::Combine($compiler, 'bin/armcc.exe'));
                fromelf=([IO.Path]::Combine($compiler, 'bin/fromelf.exe')); armasm=([IO.Path]::Combine($compiler, 'bin/armasm.exe'));
                armlink=([IO.Path]::Combine($compiler, 'bin/armlink.exe')); armclang=([IO.Path]::Combine($root, 'ARM/ARMCLANG/bin/armclang.exe'))}
        }
        'cubeide' { $files = @{headless=([IO.Path]::Combine($root, 'headless-build.bat'))} }
        'esp-idf' { $files = @{export=([IO.Path]::Combine($root, 'export.bat')); idf=([IO.Path]::Combine($root, 'tools/idf.py'))} }
    }
    foreach ($key in $files.Keys) {
        $exists = [IO.File]::Exists($files[$key])
        $status.components[$key] = @{path=$files[$key]; exists=$exists}
        if (!$exists -and $key -ne 'armclang') { $status.missing += $key }
    }
    if ($Entry.kind -eq 'keil') {
        $status.available = $status.components.uv4.exists -and ($status.components.armcc.exists -or $status.components.armclang.exists)
        if ($status.components.armcc.exists) {
            $probe = Invoke-Tool $files.armcc @('--vsn') $root $null 15
            $status.compilerVersion = $probe.text.Trim()
        }
    } else { $status.available = $status.missing.Count -eq 0 }
    if ($Entry.kind -eq 'esp-idf') {
        $toolsPath=$env:IDF_TOOLS_PATH
        if (!$toolsPath) { $toolsPath=Join-Path $env:USERPROFILE '.espressif' }
        if ($Entry.toolsPath) { $toolsPath=Resolve-File $Base $Entry.toolsPath }
        $status.toolsPath=$toolsPath
        $python=$null
        if ($Entry.python) { $python=Resolve-File $Base $Entry.python }
        else {
            $envs=@(Get-ChildItem -LiteralPath ([IO.Path]::Combine($toolsPath,'python_env')) -Directory -ErrorAction SilentlyContinue)
            if ($env:IDF_PYTHON_ENV_PATH) { $envs=@(Get-Item -LiteralPath $env:IDF_PYTHON_ENV_PATH -ErrorAction SilentlyContinue) }
            # Match the SDK major/minor version to avoid mixing dependencies from another Python environment.
            $versionFile=[IO.Path]::Combine($root,'tools/cmake/version.cmake')
            if ([IO.File]::Exists($versionFile) -and !$env:IDF_PYTHON_ENV_PATH) {
                $versionText=[IO.File]::ReadAllText($versionFile)
                $major=[regex]::Match($versionText,'set\(IDF_VERSION_MAJOR\s+(\d+)\)').Groups[1].Value
                $minor=[regex]::Match($versionText,'set\(IDF_VERSION_MINOR\s+(\d+)\)').Groups[1].Value
                $envs=@($envs | Where-Object { $_.Name -like "idf$major.$($minor)_*" })
            }
            $pythonCandidates=@($envs | ForEach-Object { [IO.Path]::Combine($_.FullName,'Scripts/python.exe') } | Where-Object { [IO.File]::Exists($_) })
            if ($pythonCandidates.Count -eq 1) { $python=$pythonCandidates[0] }
            $status.pythonCandidates=$pythonCandidates
        }
        $status.python=$python
        if (!$python -or ![IO.File]::Exists($python)) { $status.missing += 'ESP-IDF Python environment'; $status.available=$false }
    }
    return $status
}

function Find-Environments($ToolsPath) {
    $existing = @{schemaVersion=1; toolchains=@()}
    if (Test-Path -LiteralPath $ToolsPath) { $existing = Read-Config $ToolsPath 'toolchains' 'toolchains' }
    # Preserve manual entries and IDs; append only installations that are not already registered.
    $entries = @($existing.toolchains)
    $roots = New-Object 'Collections.Generic.List[string]'
    foreach ($path in @($env:KEIL_ROOT, $env:IDF_PATH)) { if ($path) { $roots.Add($path) } }
    foreach ($commandName in @('UV4.exe','stm32cubeide.exe','idf.py')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            $parent = Split-Path -Parent $command.Source
            if ($commandName -in @('UV4.exe','idf.py')) { $parent = Split-Path -Parent $parent }
            $roots.Add($parent)
        }
    }
    foreach ($key in @('HKLM:\SOFTWARE\Keil\MDK','HKLM:\SOFTWARE\WOW6432Node\Keil\MDK')) {
        $registry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($registry.Path) { $roots.Add([string]$registry.Path) }
    }
    $search = @('C:\Keil_v5','D:\Keil_v5','C:\Keil','D:\Keil','C:\ST','D:\ST','C:\Espressif','D:\Espressif',
        'C:\software\Keil','D:\software\Keil',"${env:ProgramFiles}\Keil", "${env:ProgramFiles(x86)}\Keil_v5")
    foreach ($base in $search) {
        if (Test-Path -LiteralPath $base -PathType Container) {
            $roots.Add($base)
            foreach ($child in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue) {
                $roots.Add($child.FullName)
                foreach ($sub in Get-ChildItem -LiteralPath $child.FullName -Directory -ErrorAction SilentlyContinue) { $roots.Add($sub.FullName) }
            }
        }
    }
    foreach ($root in @($roots | Sort-Object -Unique)) {
        $kind = $null
        if (Test-Path -LiteralPath (Join-Path $root 'UV4/UV4.exe')) { $kind='keil' }
        elseif (Test-Path -LiteralPath (Join-Path $root 'headless-build.bat')) { $kind='cubeide' }
        elseif (Test-Path -LiteralPath (Join-Path $root 'tools/idf.py')) { $kind='esp-idf' }
        if (!$kind) { continue }
        $present = @($entries | Where-Object { (Resolve-File (Split-Path -Parent $ToolsPath) $_.root) -eq [IO.Path]::GetFullPath($root) })
        if ($present.Count) { continue }
        $id = "$kind-$($entries.Count + 1)"
        while ($id -in $entries.id) { $id += '-new' }
        $entries += @{id=$id; kind=$kind; root=$root}
    }
    $config = @{schemaVersion=1; toolchains=@($entries); language='en'}
    if ($existing.language) { $config.language=$existing.language }
    if ($existing.python) { $config.python = $existing.python }
    else {
        $python = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($python -and $python.Source -notmatch 'WindowsApps') { $config.python = $python.Source }
    }
    $statuses = @($entries | ForEach-Object { Get-ToolStatus $_ (Split-Path -Parent $ToolsPath) })
    return @{configuration=$config; tools=$statuses; searched=@($search); guidance=(Join-Path $script:AppRoot 'README.md')}
}

function Select-Keil($Project, $ToolConfig, $Base, $Keil) {
    $entries = @($ToolConfig.toolchains | Where-Object { $_.kind -eq 'keil' })
    if ($Project.toolchain) {
        $entries = @($entries | Where-Object { $_.id -eq $Project.toolchain })
        if (!$entries.Count) { Fail 'TOOLCHAIN_MISSING' "Configured toolchain '$($Project.toolchain)' is missing" }
    }
    $statuses = @($entries | ForEach-Object { Get-ToolStatus $_ $Base })
    $required = 'armcc'
    if ($Keil.ac6) { $required = 'armclang' }
    $compatible = @($statuses | Where-Object { $_.components.uv4.exists -and $_.components[$required].exists })
    # Fail when an explicit toolchain lacks components instead of silently selecting another compiler.
    if ($Project.toolchain -and !$compatible.Count) {
        Fail 'TOOLCHAIN_MISSING' "Explicit toolchain '$($Project.toolchain)' needs UV4 and $required" @{candidates=$statuses}
    }
    if ($compatible.Count -eq 1) {
        $selected = $compatible[0]
        if ($Keil.ac6) {
            $selected.compilerRoot=Split-Path -Parent (Split-Path -Parent $selected.components.armclang.path)
            $probe=Invoke-Tool $selected.components.armclang.path @('--version') $selected.root $null 15
            $selected.compilerVersion=$probe.text.Trim()
            # Use the fromelf executable belonging to the selected ARMCLANG installation.
            $fromelf=[IO.Path]::Combine($selected.compilerRoot,'bin/fromelf.exe')
            $selected.components.fromelf=@{path=$fromelf;exists=[IO.File]::Exists($fromelf)}
        }
        if (!$Keil.ac6 -and $Keil.compiler -match 'build (\d+)' -and $selected.compilerVersion -notmatch "build $($Matches[1])\b") {
            Fail 'TOOLCHAIN_VERSION_MISMATCH' "Project requires $($Keil.compiler)" @{candidate=$selected}
        }
        return $selected
    }
    if (!$compatible.Count) { Fail 'TOOLCHAIN_MISSING' "Install or configure Keil with $required" @{candidates=$statuses; guidance=(Join-Path $script:AppRoot 'README.md')} }
    Fail 'AMBIGUOUS_TOOLCHAIN' 'Set project.toolchain to one candidate id' @{candidates=$compatible}
}
