#requires -Version 5.1
# Share one entry point for the menu and CLI, with stable JSON results and errors.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$script:AppRoot=$PSScriptRoot
$script:MenuLanguage='en'
$script:LanguageOverride=$false
foreach ($module in @('config','environment','espidf','projects','build','menu')) { . "$PSScriptRoot/lib/$module.ps1" }

function Read-Options($Arguments) {
    $options=@{positionals=@(); json=$false; 'dry-run'=$false; save=$false}
    for ($i=0; $i -lt $Arguments.Count; $i++) {
        $argument=$Arguments[$i]
        if ($argument -in @('--json','--dry-run','--save')) { $options[$argument.Substring(2)]=$true; continue }
        if ($argument -in @('--config','--tools','--path','--project','--action','--lang')) {
            if ($i+1 -ge $Arguments.Count -or $Arguments[$i+1] -like '--*') { Fail 'USAGE' "Value missing for $argument" }
            $i++
            $options[$argument.Substring(2)]=$Arguments[$i]
            continue
        }
        if ($argument -like '--*') { Fail 'USAGE' "Unknown option $argument" }
        $options.positionals += $argument
    }
    if ($options.ContainsKey('lang') -and $options.lang -cnotin @('en','zh-CN')) { Fail 'USAGE' 'Language must be en or zh-CN' }
    return $options
}

function Show-Menu($ConfigPath, $ToolsPath) {
    if (Test-Path -LiteralPath $ToolsPath) {
        $localSettings=Read-Config $ToolsPath 'toolchains' 'toolchains'
        if (!$script:LanguageOverride -and $localSettings.language) { $script:MenuLanguage=$localSettings.language }
    }
    $text=$script:MenuStrings[$script:MenuLanguage]
    if (!(Test-Path -LiteralPath $ToolsPath)) {
        Write-Host $text.FirstLaunch
        $detected=Find-Environments $ToolsPath
        Write-Json $ToolsPath $detected.configuration
        Write-Host ($text.Detected -f $detected.tools.Count, $ToolsPath)
        Write-Host ($text.EnvironmentGuide -f (Join-Path $script:AppRoot $text.GuideFile))
    }
    while ($true) {
        $text=$script:MenuStrings[$script:MenuLanguage]
        Write-Host "`nPuyuan"
        if (!(Test-Path -LiteralPath $ConfigPath)) {
            Write-Json $ConfigPath @{schemaVersion=1; projects=@()}
        }
        $config=Read-Config $ConfigPath 'projects' 'projects'
        for ($i=0; $i -lt $config.projects.Count; $i++) { Write-Host "[$($i+1)] $($config.projects[$i].name)" }
        Write-Host $text.Options
        $choice=Read-Host $text.SelectProject
        if ($choice -eq '0') { return @{closed=$true} }
        if ($choice -eq 'L') {
            $nextLanguage='en'
            if ($script:MenuLanguage -eq 'en') { $nextLanguage='zh-CN' }
            $localSettings=Read-Config $ToolsPath 'toolchains' 'toolchains'
            $localSettings.language=$nextLanguage
            Write-Json $ToolsPath $localSettings
            $script:MenuLanguage=$nextLanguage
            continue
        }
        if ($choice -eq 'D') { Write-Host ($text.ConfigurationGuide -f (Join-Path $script:AppRoot $text.GuideFile)); continue }
        if ($choice -eq 'E') {
            $detected=Find-Environments $ToolsPath
            Write-Json $ToolsPath $detected.configuration
            foreach ($tool in $detected.tools) { Write-Host ($text.ToolStatus -f $tool.id, $tool.root, $tool.available, ($tool.missing -join ',')) }
            continue
        }
        $number=0
        if (![int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $config.projects.Count) { continue }
        $project=$config.projects[$number-1]
        $plan=$null
        try { $plan=Get-ProjectPlan $ConfigPath $ToolsPath $project.id }
        catch {
            if ($_.Exception.Data['code'] -eq 'AMBIGUOUS_TOOLCHAIN') {
                $candidates=$_.Exception.Data['details'].candidates
                for ($i=0; $i -lt $candidates.Count; $i++) { Write-Host "[$($i+1)] $($candidates[$i].root) $($candidates[$i].compilerVersion)" }
                $selection=Read-Host $text.SelectToolchain
                $toolNumber=0
                if ([int]::TryParse($selection,[ref]$toolNumber) -and $toolNumber -gt 0 -and $toolNumber -le $candidates.Count) {
                    $project.toolchain=$candidates[$toolNumber-1].id
                    Write-Json $ConfigPath $config
                }
            } else { Write-Host "$($_.Exception.Data['code']) $($_.Exception.Message)"; Write-Host ($_.Exception.Data['details'] | ConvertTo-Json -Depth 10) }
            continue
        }
        Write-Host ($text.CurrentProject -f $plan.projectName, $plan.target)
        if ($plan.toolchain) { Write-Host ($text.Toolchain -f $plan.toolchain.root, $plan.toolchain.compilerVersion) }
        $actions=@($plan.supportedActions)
        for ($i=0; $i -lt $actions.Count; $i++) { Write-Host "[$($i+1)] $($text[$actions[$i]])" }
        Write-Host $text.Back
        $actionNumber=0
        $choice=Read-Host $text.SelectAction
        if (![int]::TryParse($choice,[ref]$actionNumber) -or $actionNumber -lt 1 -or $actionNumber -gt $actions.Count) { continue }
        try {
            $plan=Get-ProjectPlan $ConfigPath $ToolsPath $project.id $actions[$actionNumber-1]
            Write-Host $text.Building
            $result=Invoke-Build $plan
            Write-Host ($text.Success -f $result.warnings, $result.elapsedSeconds)
            foreach ($artifact in $result.artifacts) { Write-Host $artifact.path }
            Write-Host ($text.LogDirectory -f $result.runDirectory)
            $open=Read-Host $text.OpenResult
            if ($open -eq 'O') { Start-Process explorer.exe -ArgumentList (Quote-Argument $result.runDirectory) | Out-Null }
            if ($open -eq 'L') { foreach ($log in $result.logs) { Start-Process notepad.exe -ArgumentList (Quote-Argument $log) | Out-Null } }
        } catch {
            Write-Host "$($_.Exception.Data['code']) $($_.Exception.Message)"
            Write-Host ($_.Exception.Data['details'] | ConvertTo-Json -Depth 10)
            Read-Host $text.ReturnPrompt | Out-Null
        }
    }
}

# Detect JSON mode before parsing options so usage errors follow the same response contract.
$jsonMode = '--json' -in $args
try {
    $options=Read-Options $args
    $script:LanguageOverride=$options.ContainsKey('lang')
    if ($script:LanguageOverride) { $script:MenuLanguage=$options.lang }
    $configPath=Join-Path $PSScriptRoot 'projects.json'
    $toolsPath=Join-Path $PSScriptRoot 'toolchains.local.json'
    if ($options.config) { $configPath=Resolve-File (Get-Location).Path $options.config }
    if ($options.tools) { $toolsPath=Resolve-File (Get-Location).Path $options.tools }
    $operation=$options.positionals -join ' '
    $data=switch ($operation) {
        '' {
            if ($jsonMode) { Fail 'USAGE' 'Specify a command in JSON mode' }
            Show-Menu $configPath $toolsPath
        }
        'help' { @{commands=@('env detect [--save]','project inspect --path PATH','project list','project validate --project ID','build --project ID [--action all|factory|upgrade] [--dry-run]'); options=@('--json','--config PATH','--tools PATH','--lang en|zh-CN'); docs=(Join-Path $PSScriptRoot 'docs/cli-for-agents.md')} }
        'env detect' {
            $detection=Find-Environments $toolsPath
            if ($options.save) { Write-Json $toolsPath $detection.configuration }
            $detection
        }
        'project inspect' {
            if (!$options.path) { Fail 'USAGE' '--path is required' }
            Inspect-Project $options.path
        }
        'project list' { @{projects=@((Read-Config $configPath 'projects' 'projects').projects)} }
        'project validate' {
            if (!$options.project) { Fail 'USAGE' '--project is required' }
            Get-ProjectPlan $configPath $toolsPath $options.project
        }
        'build' {
            if (!$options.project) { Fail 'USAGE' '--project is required' }
            $action='all'
            if ($options.action) { $action=$options.action }
            if ($action -notin @('all','factory','upgrade')) { Fail 'USAGE' 'Action must be all, factory, or upgrade' }
            $plan=Get-ProjectPlan $configPath $toolsPath $options.project $action
            if ($options['dry-run']) { $plan } else { Invoke-Build $plan }
        }
        default { Fail 'USAGE' "Unknown command '$operation'; run help" }
    }
    $reply=@{ok=$true; code='OK'; data=$data}
    if ($jsonMode) { [Console]::Out.WriteLine(($reply | ConvertTo-Json -Depth 30 -Compress)) }
    elseif ($operation) { $reply | ConvertTo-Json -Depth 30 }
    exit 0
} catch {
    $code=$_.Exception.Data['code']
    if (!$code) { $code='INTERNAL_ERROR' }
    $reply=@{ok=$false; code=$code; error=@{message=$_.Exception.Message; details=$_.Exception.Data['details']}}
    if ($jsonMode) { [Console]::Out.WriteLine(($reply | ConvertTo-Json -Depth 30 -Compress)) }
    else {
        $reply | ConvertTo-Json -Depth 30
        if (!$args.Count) { Read-Host ($script:MenuStrings[$script:MenuLanguage].ExitPrompt) | Out-Null }
    }
    $exitCode=2
    if ($code -in @('BUILD_FAILED','BUILD_TIMEOUT','ARTIFACT_MISSING','ARTIFACT_STALE')) { $exitCode=3 }
    elseif ($code -eq 'INTERNAL_ERROR') { $exitCode=4 }
    exit $exitCode
}
