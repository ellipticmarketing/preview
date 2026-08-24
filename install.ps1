[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repository = 'ellipticmarketing/preview'
$repositoryUrl = "https://github.com/$repository.git"
$installDirectory = if ([string]::IsNullOrWhiteSpace($env:ELLIPTIC_PREVIEW_HOME)) {
    Join-Path $env:LOCALAPPDATA 'Elliptic\preview'
} else {
    $env:ELLIPTIC_PREVIEW_HOME
}
$commandDirectory = Join-Path $env:LOCALAPPDATA 'Elliptic\bin'

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [string] $Id,
        [Parameter(Mandatory)]
        [string] $Name
    )

    & winget list --id $Id --exact --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-Output "Installing $Name..."
    & winget install `
        --id $Id `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "$Name could not be installed. winget exit code: $LASTEXITCODE"
    }

    Refresh-ProcessPath
}

function Test-PythonVersion {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $launcher) {
        & $launcher.Source -3 -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' *> $null
        return $LASTEXITCODE -eq 0
    }

    $launcher = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $launcher) {
        return $false
    }

    & $launcher.Source -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' *> $null
    return $LASTEXITCODE -eq 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This installer is for Windows. Use install.sh on Ubuntu.'
}

if ($null -eq (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'Windows Package Manager is required. Install App Installer from Microsoft Store, then run this command again.'
}

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    Install-WingetPackage -Id 'Git.Git' -Name 'Git'
}
if (-not (Test-PythonVersion)) {
    Install-WingetPackage -Id 'Python.Python.3.13' -Name 'Python'
}
if ($null -eq (Get-Command tailscale -ErrorAction SilentlyContinue)) {
    Install-WingetPackage -Id 'Tailscale.Tailscale' -Name 'Tailscale'
}
Install-WingetPackage -Id 'LeNgocKhoa.Laragon' -Name 'Laragon'

Refresh-ProcessPath

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was installed but the git command was not found. Open a new PowerShell window and run the installer again.'
}

if (-not (Test-PythonVersion)) {
    throw 'Python 3.10 or newer was installed, but its command was not found. Open a new PowerShell window and run the installer again.'
}

if (Test-Path -LiteralPath $installDirectory) {
    if (-not (Test-Path -LiteralPath (Join-Path $installDirectory '.git') -PathType Container)) {
        throw "$installDirectory exists but is not a Git clone."
    }

    $originUrl = (& git -C $installDirectory remote get-url origin 2>$null).Trim()
    if ($originUrl -notin @(
        'https://github.com/ellipticmarketing/stage',
        'https://github.com/ellipticmarketing/stage.git',
        'git@github.com:ellipticmarketing/stage.git',
        'https://github.com/ellipticmarketing/preview',
        'https://github.com/ellipticmarketing/preview.git',
        'git@github.com:ellipticmarketing/preview.git'
    )) {
        throw "$installDirectory is not a clone of $repository."
    }

    if (-not [string]::IsNullOrWhiteSpace((& git -C $installDirectory status --porcelain))) {
        throw "$installDirectory has local changes. Commit or remove them before installation."
    }

    $branch = (& git -C $installDirectory branch --show-current).Trim()
    if ($branch -ne 'main') {
        $branchDescription = if ([string]::IsNullOrWhiteSpace($branch)) { 'a detached commit' } else { $branch }
        throw "$installDirectory is on $branchDescription, not main."
    }

    Write-Output "Updating $installDirectory..."
    & git -C $installDirectory pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) {
        throw "The repository could not be updated. Git exit code: $LASTEXITCODE"
    }
} else {
    New-Item -ItemType Directory -Path (Split-Path $installDirectory -Parent) -Force | Out-Null
    Write-Output "Cloning $repository into $installDirectory..."
    & git clone $repositoryUrl $installDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "The repository could not be cloned. Git exit code: $LASTEXITCODE"
    }
}

& (Join-Path $installDirectory 'install-windows.ps1') `
    -Destination (Join-Path $commandDirectory 'preview.ps1') `
    -StageDestination (Join-Path $commandDirectory 'stage.ps1')

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$userPathEntries = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if (-not ($userPathEntries | Where-Object { $_.TrimEnd('\') -ieq $commandDirectory.TrimEnd('\') })) {
    $updatedUserPath = (@($userPathEntries) + $commandDirectory) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
    Write-Output "Added $commandDirectory to your user PATH."
}

$env:Path = "$commandDirectory;$env:Path"

Write-Output ''
& (Join-Path $commandDirectory 'preview.ps1') version
Write-Output 'Installation complete.'

$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if ($null -eq $tailscale) {
    Write-Output 'Open Tailscale from the Start menu and sign in.'
} else {
    & $tailscale.Source status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'Open Tailscale from the Start menu and sign in.'
    }
}

Write-Output 'Start Laragon before you run preview.'
Write-Output 'Open a new PowerShell window before you use preview or stage.'
