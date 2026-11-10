# Parse ESP-IDF projects, select SDK environments, and plan application or factory image commands.
function Read-IdfProject($Root, $Project) {
    $cmake=Join-Path $Root 'CMakeLists.txt'
    if (![IO.File]::Exists($cmake)) { Fail 'PROJECT_INVALID' 'ESP-IDF requires root CMakeLists.txt' }
    $text=[IO.File]::ReadAllText($cmake)
    if ($text -notmatch 'IDF_PATH.*tools/cmake/project\.cmake') { Fail 'PROJECT_INVALID' 'CMakeLists.txt does not include ESP-IDF project.cmake' }
    $name=[regex]::Match($text,'(?m)^\s*project\(\s*([a-zA-Z0-9_-]+)\s*\)').Groups[1].Value
    if ($Project.outputName) { $name=$Project.outputName }
    if (!$name) { Fail 'CONFIG_INVALID' 'Set outputName when CMake project name uses variables' }
    Assert-FileName "$name.bin"
    $target='esp32'
    $sdkconfig=Join-Path $Root 'sdkconfig'
    if ([IO.File]::Exists($sdkconfig)) {
        $value=[regex]::Match([IO.File]::ReadAllText($sdkconfig),'(?m)^CONFIG_IDF_TARGET="([a-z0-9]+)"').Groups[1].Value
        if ($value) { $target=$value }
    }
    # Do not rewrite an existing sdkconfig chip selection and inadvertently change the board or partitions.
    if ($Project.target) {
        if ([IO.File]::Exists($sdkconfig) -and $target -ne $Project.target) { Fail 'CONFIG_INVALID' "sdkconfig targets $target, requested $($Project.target). Select the intended sdkconfig before building." }
        $target=$Project.target
    }
    if ($target -notmatch '^esp32[a-z0-9]*$') { Fail 'CONFIG_INVALID' 'Invalid ESP-IDF chip target' }
    $buildDirectory='build'
    if ($Project.buildDirectory) { $buildDirectory=$Project.buildDirectory }
    $output=Resolve-File $Root $buildDirectory
    if (!$output.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { Fail 'CONFIG_INVALID' 'buildDirectory must be inside project root' }
    return @{file=$cmake; outputName=$name; outputDir=$output; target=$target}
}

function Select-Idf($Project, $Config, $Base) {
    $entries=@($Config.toolchains | Where-Object { $_.kind -eq 'esp-idf' })
    if ($Project.toolchain) { $entries=@($entries | Where-Object { $_.id -eq $Project.toolchain }) }
    $statuses=@($entries | ForEach-Object { Get-ToolStatus $_ $Base })
    $available=@($statuses | Where-Object { $_.available })
    if (!$available.Count) { Fail 'TOOLCHAIN_MISSING' 'Configure an ESP-IDF root, toolsPath and its Python environment' @{candidates=$statuses} }
    if ($available.Count -gt 1) { Fail 'AMBIGUOUS_TOOLCHAIN' 'Set toolchain to an ESP-IDF candidate id' @{candidates=$available} }
    return $available[0]
}

function Get-IdfCommands($Tool, $Info, $Root, $Action) {
    $envs=@{IDF_PATH=$Tool.root; IDF_TOOLS_PATH=$Tool.toolsPath; IDF_TARGET=$Info.target;
        IDF_PYTHON_ENV_PATH=(Split-Path -Parent (Split-Path -Parent $Tool.python))}
    # Reject expansion and command-structure characters in paths embedded in a cmd.exe command string.
    foreach ($path in @($Tool.root,$Tool.python,$Root,$Info.outputDir)) {
        if ($path -match '["%\r\n!]') { Fail 'CONFIG_INVALID' 'ESP-IDF command paths cannot contain quotes, percent, exclamation or newlines' }
    }
    $base='call "' + $Tool.components.export.path + '" && "' + $Tool.python + '" "' + $Tool.components.idf.path +
        '" -C "' + $Root + '" -B "' + $Info.outputDir + '"'
    # Upgrade builds only the application; other actions also merge a factory image.
    $target='build'
    if ($Action -eq 'upgrade') { $target='app' }
    $commands=@(@{type='idf'; executable=(Join-Path $env:SystemRoot 'System32/cmd.exe');
        arguments=@('/d','/s','/c',"$base $target"); successCodes=@(0); environment=$envs;
        freshOutput=(Join-Path $Info.outputDir ($Info.outputName+'.elf'))})
    if ($Action -ne 'upgrade') {
        $commands += @{type='idf'; executable=(Join-Path $env:SystemRoot 'System32/cmd.exe');
            arguments=@('/d','/s','/c',"$base merge-bin -o merged-flash.bin"); successCodes=@(0); environment=$envs}
    }
    return $commands
}
