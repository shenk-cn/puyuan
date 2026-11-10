# Read configuration, validate the supported schema subset, and resolve paths and artifact names.
function Fail($Code, $Message, $Details = @{}) {
    $exception = New-Object System.Exception($Message)
    $exception.Data['code'] = $Code
    $exception.Data['details'] = $Details
    throw $exception
}

function ConvertTo-Map($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = @{}
        foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = ConvertTo-Map $property.Value }
        return $map
    }
    # Preserve empty and single-item arrays instead of letting the PowerShell pipeline unwrap them.
    if ($Value -is [Array]) { return ,@($Value | ForEach-Object { ConvertTo-Map $_ }) }
    return $Value
}

function Read-Json($Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { Fail 'CONFIG_MISSING' "File missing: $Path" @{path=$Path} }
    try { return ConvertTo-Map (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Fail 'CONFIG_INVALID' "Invalid JSON in $Path. $($_.Exception.Message)" }
}

function Write-Json($Path, $Value) {
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    # Write a temporary file in the same directory before replacing the existing configuration.
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Resolve-File($Base, $Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Base $Path))
}

function Assert-Schema($Value, $Schema, $Root, $At = '$') {
    # Support only keywords used by the bundled schemas; this is not a general JSON Schema engine.
    if ($Schema.ContainsKey('$ref')) {
        $node = $Root
        foreach ($part in $Schema['$ref'].Substring(2).Split('/')) { $node = $node[$part] }
        Assert-Schema $Value $node $Root $At
        return
    }
    $valid = switch ($Schema.type) {
        'object' { $Value -is [hashtable] }
        'array' { $Value -is [Array] }
        'string' { $Value -is [string] }
        'integer' { $Value -is [int] -or $Value -is [long] }
        default { $true }
    }
    if (!$valid) { Fail 'CONFIG_INVALID' "$At must have type $($Schema.type)" }
    if ($Schema.ContainsKey('enum') -and $Value -cnotin $Schema.enum) { Fail 'CONFIG_INVALID' "$At has unsupported value '$Value'" }
    if ($Schema.type -eq 'object') {
        foreach ($key in $Schema.required) { if (!$Value.ContainsKey($key)) { Fail 'CONFIG_INVALID' "$At.$key is required" } }
        foreach ($key in $Value.Keys) {
            if ($Schema.properties.ContainsKey($key)) { Assert-Schema $Value[$key] $Schema.properties[$key] $Root "$At.$key" }
            elseif ($Schema.additionalProperties -eq $false) { Fail 'CONFIG_INVALID' "$At.$key is unknown" }
        }
    }
    if ($Schema.type -eq 'array') {
        if ($Schema.ContainsKey('minItems') -and $Value.Count -lt $Schema.minItems) { Fail 'CONFIG_INVALID' "$At has too few items" }
        for ($i = 0; $i -lt $Value.Count; $i++) { Assert-Schema $Value[$i] $Schema.items $Root "$At[$i]" }
    }
    if ($Schema.type -eq 'string') {
        if ($Schema.ContainsKey('minLength') -and $Value.Length -lt $Schema.minLength) { Fail 'CONFIG_INVALID' "$At is empty" }
        if ($Schema.pattern -and $Value -cnotmatch $Schema.pattern) { Fail 'CONFIG_INVALID' "$At has an invalid format" }
    }
}

function Read-Config($Path, $SchemaName, $Collection) {
    $value = Read-Json $Path
    $schema = Read-Json (Join-Path $script:AppRoot "schema/$SchemaName.schema.json")
    Assert-Schema $value $schema $schema
    $ids = @{}
    foreach ($item in $value[$Collection]) {
        if ($ids.ContainsKey($item.id)) { Fail 'CONFIG_INVALID' "Duplicate id: $($item.id)" }
        $ids[$item.id] = $true
    }
    return $value
}

function Expand-Template($Template, $Variables) {
    foreach ($match in [regex]::Matches($Template, '\{([a-zA-Z][a-zA-Z0-9]*)\}')) {
        $key=$match.Groups[1].Value
        if (!$Variables.ContainsKey($key) -or [string]::IsNullOrEmpty([string]$Variables[$key])) {
            Fail 'TEMPLATE_INVALID' "Template variable {$key} is unknown or empty" @{template=$Template}
        }
    }
    # Return literal values from a callback so dollar signs in paths are not replacement syntax.
    $result = [regex]::Replace($Template, '\{([a-zA-Z][a-zA-Z0-9]*)\}', {
        param($match)
        $key = $match.Groups[1].Value
        return [string]$Variables[$key]
    })
    if ($result -match '[{}]') { Fail 'TEMPLATE_INVALID' "Unresolved braces: $Template" }
    return $result
}

function Assert-FileName($Name) {
    if ($Name.Length -gt 180 -or $Name -match '[<>:"/\\|?*\x00-\x1f]' -or $Name -match '[. ]$' -or
        $Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or !$Name) {
        Fail 'TEMPLATE_INVALID' "Invalid Windows filename: $Name"
    }
}
