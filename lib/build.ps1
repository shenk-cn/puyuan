# Execute build plans, validate fresh artifacts, and restore expected previous files on ordinary failures.
function Assert-KeilLog($Path, $Target) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { Fail 'BUILD_FAILED' "Keil did not write its build log: $Path" }
    $text = [IO.File]::ReadAllText($Path)
    if ($Target -and $text -notmatch ([regex]::Escape("Rebuild target '$Target'"))) { Fail 'BUILD_FAILED' "Keil log does not match requested target '$Target'" @{log=$Path} }
    if ($text -notmatch ' - 0 Error\(s\)') { Fail 'BUILD_FAILED' 'Keil did not report zero errors' @{log=$Path} }
    $warnings = 0
    if ($text -match ' - 0 Error\(s\),\s+(\d+) Warning\(s\)') { $warnings=[int]$Matches[1] }
    return $warnings
}

function Invoke-Build($Plan) {
    # Lock by absolute project directory so separate configurations for the same project share a mutex.
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Plan.root.ToLowerInvariant())))).Replace('-','') }
    finally { $hash.Dispose() }
    $mutex = New-Object Threading.Mutex($false, "Local\puyuan-$key")
    $locked = $false
    $backups = @()
    $committed = $false
    $run = $null
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
        if (!$locked) { Fail 'PROJECT_BUSY' 'Another Puyuan process is building this project' }
        $run = Join-Path $Plan.outputDirectory ($Plan.projectId + '/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        [IO.Directory]::CreateDirectory($run) | Out-Null
        $logs = @()
        $warnings=0
        $watch = [Diagnostics.Stopwatch]::StartNew()
        # Back up only expected artifacts and required intermediates, restoring them on ordinary failures.
        $sources = @($Plan.artifacts.source)
        $sources += @($Plan.commands | Where-Object { $_.freshInput } | ForEach-Object { $_.freshInput })
        # ESP-IDF generates BIN after linking ELF; moving the old ELF forces fresh output.
        $sources += @($Plan.commands | Where-Object { $_.freshOutput } | ForEach-Object { $_.freshOutput })
        if ($Plan.packagerLog -and $Plan.action -ne 'upgrade') { $sources += (Resolve-File $Plan.root $Plan.packagerLog) }
        foreach ($source in @($sources | Sort-Object -Unique)) {
            $rootPrefix = $Plan.root.TrimEnd('\') + '\'
            if (!$source.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { Fail 'CONFIG_INVALID' "Artifact/log must be inside project root: $source" }
            $backup = "$source.puyuan-$([guid]::NewGuid().ToString('N')).bak"
            $existed = Test-Path -LiteralPath $source -PathType Leaf
            if ($existed) { [IO.File]::Move($source,$backup) }
            $backups += @{source=$source; backup=$backup; existed=$existed}
        }
        $started = [DateTime]::UtcNow.AddSeconds(-2)
        $index=0
        foreach ($command in $Plan.commands) {
            $index++
            $log=Join-Path $run "step-$index.log"
            $arguments=@($command.arguments)
            if ($command.freshInput) {
                if (![IO.File]::Exists($command.freshInput)) { Fail 'ARTIFACT_MISSING' "Fresh conversion input missing: $($command.freshInput)" }
                $inputFile=Get-Item -LiteralPath $command.freshInput
                if ($inputFile.Length -eq 0 -or $inputFile.LastWriteTimeUtc -lt $started) { Fail 'ARTIFACT_STALE' "Conversion input is stale: $($command.freshInput)" }
            }
            if ($command.type -eq 'keil') {
                $keilLog=Join-Path $run "keil-$index.log"
                $arguments += @('-o',$keilLog)
            }
            $environment=@{}
            if ($command.environment) { $environment=$command.environment }
            $result=Invoke-Tool $command.executable $arguments $Plan.root $log 1800 $environment
            $logs += $log
            if ($result.exitCode -notin $command.successCodes) { Fail 'BUILD_FAILED' "Build step $index exited with $($result.exitCode)" @{log=$log; exitCode=$result.exitCode} }
            if ($command.freshOutput) {
                if (![IO.File]::Exists($command.freshOutput)) { Fail 'ARTIFACT_MISSING' "Linker output missing: $($command.freshOutput)" }
                $linked=Get-Item -LiteralPath $command.freshOutput
                if ($linked.Length -eq 0 -or $linked.LastWriteTimeUtc -lt $started) { Fail 'ARTIFACT_STALE' "Linker output is stale: $($command.freshOutput)" }
            }
            if ($command.type -eq 'idf') { $warnings += [regex]::Matches($result.text,'(?im)^.*\bwarning:').Count }
            if ($command.type -eq 'keil') {
                # Keil exit code 1 may mean warnings only; still verify the Target and zero-error summary.
                $warnings += Assert-KeilLog $keilLog $Plan.keil.target
                $logs += $keilLog
            }
            if ($command.type -eq 'packager') {
                $packagerLog=Resolve-File $Plan.root $Plan.packagerLog
                $warnings += Assert-KeilLog $packagerLog $Plan.keil.target
                $copy=Join-Path $run 'keil-packager.log'
                [IO.File]::Copy($packagerLog,$copy)
                $logs += $copy
            }
        }
        $artifacts=@()
        foreach ($artifact in $Plan.artifacts) {
            if (!(Test-Path -LiteralPath $artifact.source -PathType Leaf)) { Fail 'ARTIFACT_MISSING' "Expected output missing: $($artifact.source)" }
            $file=Get-Item -LiteralPath $artifact.source
            if ($file.Length -eq 0 -or $file.LastWriteTimeUtc -lt $started) { Fail 'ARTIFACT_STALE' "Output is empty or older than this build: $($artifact.source)" }
            $destination=Join-Path $run $artifact.name
            if (Test-Path -LiteralPath $destination) { Fail 'TEMPLATE_INVALID' "Artifact collides with log: $destination" }
            [IO.File]::Copy($artifact.source,$destination)
            $hasher=[Security.Cryptography.SHA256]::Create()
            $stream=[IO.File]::OpenRead($destination)
            try { $digest=([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
            finally { $stream.Dispose(); $hasher.Dispose() }
            $artifacts += @{kind=$artifact.kind; path=$destination; bytes=$file.Length; sha256=$digest}
        }
        $report=@{projectId=$Plan.projectId; action=$Plan.action; version=$Plan.version; artifacts=$artifacts;
            warnings=$warnings; elapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2); logs=$logs; runDirectory=$run}
        # Record success only after every artifact is validated, copied, and hashed.
        Write-Json (Join-Path $run 'result.json') @{ok=$true; code='OK'; data=$report}
        $committed=$true
        return $report
    } catch {
        if ($run) {
            $_.Exception.Data['details'] = @{runDirectory=$run; cause=$_.Exception.Data['details']; message=$_.Exception.Message}
            # Copies are incomplete until success is recorded; remove partial deliverables after failure.
            foreach ($artifact in $Plan.artifacts) {
                $partial=Join-Path $run $artifact.name
                if ([IO.File]::Exists($partial) -and $artifact.name -notmatch '^(step-|keil-|result\.json)') { [IO.File]::Delete($partial) }
            }
            Write-Json (Join-Path $run 'result.json') @{ok=$false; code=$_.Exception.Data['code']; error=@{message=$_.Exception.Message; details=$_.Exception.Data['details']}}
        }
        throw
    } finally {
        # Delete old backups on success; on failure, remove new files and restore expected previous files.
        foreach ($backup in $backups) {
            if (!$committed -and [IO.File]::Exists($backup.source)) { [IO.File]::Delete($backup.source) }
            if ([IO.File]::Exists($backup.backup)) {
                if ($committed) { [IO.File]::Delete($backup.backup) }
                else { [IO.File]::Move($backup.backup,$backup.source) }
            }
        }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
