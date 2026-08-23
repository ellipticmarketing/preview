[CmdletBinding()]
param(
    [string] $Destination = 'C:\Rolando Apps\scripts\preview.ps1'
)

$ErrorActionPreference = 'Stop'

$launcher = (Resolve-Path (Join-Path $PSScriptRoot 'bin\preview.ps1')).Path
$destinationDirectory = Split-Path $Destination -Parent
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

if (Test-Path -LiteralPath $Destination) {
    $existing = Get-Item -LiteralPath $Destination -Force
    if ($existing.LinkType -eq 'SymbolicLink' -and
        [IO.Path]::GetFullPath([string] $existing.Target) -eq $launcher) {
        Write-Output "preview already links to $launcher"
        exit
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Destination.$timestamp.bak"
    Move-Item -LiteralPath $Destination -Destination $backup
    Write-Output "Saved the old launcher at $backup"
}

try {
    New-Item -ItemType SymbolicLink -Path $Destination -Target $launcher -ErrorAction Stop | Out-Null
    Write-Output "Linked $Destination to $launcher"
} catch {
    $content = @"
& '$($launcher.Replace("'", "''"))' @args
exit `$LASTEXITCODE
"@
    Set-Content -LiteralPath $Destination -Value $content -Encoding utf8NoBOM
    Write-Warning 'Windows blocked the symbolic link. Installed a forwarding script instead.'
}
