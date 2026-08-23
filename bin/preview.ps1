$ErrorActionPreference = 'Stop'
$scriptPath = $PSCommandPath
$scriptItem = Get-Item -LiteralPath $scriptPath -Force
if ($scriptItem.LinkType -eq 'SymbolicLink') {
    $linkTarget = [string] $scriptItem.Target
    $scriptPath = if ([IO.Path]::IsPathRooted($linkTarget)) {
        $linkTarget
    } else {
        Join-Path $scriptItem.DirectoryName $linkTarget
    }
}

$projectRoot = Split-Path (Split-Path $scriptPath -Parent) -Parent
$sourcePath = Join-Path $projectRoot 'src'
$env:PYTHONPATH = if ([string]::IsNullOrWhiteSpace($env:PYTHONPATH)) {
    $sourcePath
} else {
    "$sourcePath$([IO.Path]::PathSeparator)$env:PYTHONPATH"
}

$normalizedArguments = @(foreach ($argument in $args) {
    switch -CaseSensitive ($argument) {
        '-Stop' { '--stop' }
        '-Status' { '--status' }
        '-Site' { '--site' }
        '-Backend' { '--backend' }
        '-NoStage' { '--no-stage' }
        '-LaragonRoot' { '--laragon-root' }
        default { $argument }
    }
})

$python = Get-Command py -ErrorAction SilentlyContinue
if ($null -ne $python) {
    & $python.Source -3 -m preview_tool @normalizedArguments
} else {
    $python = Get-Command python -ErrorAction Stop
    & $python.Source -m preview_tool @normalizedArguments
}

exit $LASTEXITCODE
