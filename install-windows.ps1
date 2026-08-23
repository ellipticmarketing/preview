[CmdletBinding()]
param(
    [string] $Destination = 'C:\Rolando Apps\scripts\preview.ps1',
    [string] $StageDestination = 'C:\Rolando Apps\scripts\stage.ps1'
)

$ErrorActionPreference = 'Stop'

function Install-CommandLink {
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [string] $Source,
        [Parameter(Mandatory)]
        [string] $Destination
    )

    $launcher = (Resolve-Path $Source).Path
    $destinationDirectory = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination -Force
        if ($existing.LinkType -eq 'SymbolicLink' -and
            [IO.Path]::GetFullPath([string] $existing.Target) -eq $launcher) {
            Write-Output "$Name already links to $launcher"
            return
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$Destination.$timestamp.bak"
        Move-Item -LiteralPath $Destination -Destination $backup
        Write-Output "Saved the old $Name launcher at $backup"
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
        Write-Warning "Windows blocked the $Name symbolic link. Installed a forwarding script instead."
    }
}

Install-CommandLink `
    -Name 'preview' `
    -Source (Join-Path $PSScriptRoot 'bin\preview.ps1') `
    -Destination $Destination

Install-CommandLink `
    -Name 'stage' `
    -Source (Join-Path $PSScriptRoot 'bin\stage.ps1') `
    -Destination $StageDestination
