[CmdletBinding()]
param(
    [string] $Site,
    [string] $LaragonRoot,
    [switch] $NoReload,
    [switch] $ForceReload
)

$ErrorActionPreference = 'Stop'

$worktreeRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($worktreeRoot)) {
    throw 'Run stage from a Git worktree.'
}

$gitCommonDirectory = (& git rev-parse --path-format=absolute --git-common-dir 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommonDirectory)) {
    throw 'Git could not find the common repository directory.'
}

$repositoryRoot = Split-Path $gitCommonDirectory
$repositoryName = Split-Path $repositoryRoot -Leaf
$publicPath = Join-Path $worktreeRoot 'public'

$appHost = $null
if ([string]::IsNullOrWhiteSpace($Site)) {
    foreach ($environmentFileName in @('.env', '.env.example')) {
        $environmentFile = Join-Path $worktreeRoot $environmentFileName
        if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
            continue
        }

        $appUrlLine = Get-Content -LiteralPath $environmentFile |
            Where-Object { $_ -match '^\s*APP_URL\s*=' } |
            Select-Object -First 1

        if ($null -eq $appUrlLine) {
            continue
        }

        $appUrl = ($appUrlLine -replace '^\s*APP_URL\s*=\s*', '').Trim().Trim('"', "'")
        $parsedAppUrl = $null
        if ([Uri]::TryCreate($appUrl, [UriKind]::Absolute, [ref]$parsedAppUrl)) {
            $appHost = $parsedAppUrl.Host
            break
        }
    }
}

$siteName = if (-not [string]::IsNullOrWhiteSpace($Site)) {
    $Site -replace '(?i)\.test$', ''
} elseif (-not [string]::IsNullOrWhiteSpace($appHost) -and $appHost -match '(?i)\.test$') {
    $appHost -replace '(?i)\.test$', ''
} else {
    $repositoryName
}

if ($siteName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
    $siteName -in @('.', '..')) {
    throw "The site name is not valid for a directory: $siteName"
}

if (-not (Test-Path -LiteralPath $publicPath -PathType Container)) {
    throw "The current worktree does not have a public directory: $publicPath"
}

if ([string]::IsNullOrWhiteSpace($LaragonRoot)) {
    $runningLaragon = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -ieq 'laragon.exe' -and -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) } |
        Select-Object -First 1

    if ($null -eq $runningLaragon) {
        throw 'Laragon is not running. Start Laragon or use -LaragonRoot.'
    }

    $LaragonRoot = Split-Path $runningLaragon.ExecutablePath
}

$candidateSiteNames = @($siteName)

$siteDirectories = @(
    [pscustomobject]@{ Type = 'apache'; Path = Join-Path $LaragonRoot 'etc\apache2\sites-enabled' }
    [pscustomobject]@{ Type = 'nginx'; Path = Join-Path $LaragonRoot 'etc\nginx\sites-enabled' }
)

$virtualHost = @(foreach ($candidateSiteName in $candidateSiteNames) {
    $candidateNames = @(
        "$candidateSiteName.test.conf"
        "auto.$candidateSiteName.test.conf"
    )

    foreach ($siteDirectory in $siteDirectories) {
        if (-not (Test-Path -LiteralPath $siteDirectory.Path -PathType Container)) {
            continue
        }

        Get-ChildItem -LiteralPath $siteDirectory.Path -File |
            Where-Object { $candidateNames -contains $_.Name } |
            ForEach-Object {
                [pscustomobject]@{
                    Type = $siteDirectory.Type
                    File = $_
                    SiteName = $candidateSiteName
                }
            }
    }
}) | Select-Object -First 1

if ($null -eq $virtualHost) {
    $apacheSiteDirectory = $siteDirectories |
        Where-Object { $_.Type -eq 'apache' -and (Test-Path -LiteralPath $_.Path -PathType Container) } |
        Select-Object -First 1

    if ($null -eq $apacheSiteDirectory) {
        throw "No Laragon virtual host was found for $siteName.test, and no Apache site directory is available under $LaragonRoot."
    }

    $newVirtualHostFile = Join-Path $apacheSiteDirectory.Path "$siteName.test.conf"
    $initialPublicPath = $publicPath.Replace('\', '/')
    $certificateFile = (Join-Path $LaragonRoot 'etc\ssl\laragon.crt').Replace('\', '/')
    $certificateKeyFile = (Join-Path $LaragonRoot 'etc\ssl\laragon.key').Replace('\', '/')
    $newVirtualHostConfiguration = @"
define ROOT "$initialPublicPath"
define SITE "$siteName.test"

<VirtualHost *:80>
    DocumentRoot "`${ROOT}"
    ServerName `${SITE}
    ServerAlias *.`${SITE}
    <Directory "`${ROOT}">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    DocumentRoot "`${ROOT}"
    ServerName `${SITE}
    ServerAlias *.`${SITE}
    <Directory "`${ROOT}">
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile "$certificateFile"
    SSLCertificateKeyFile "$certificateKeyFile"
</VirtualHost>
"@
    Set-Content -LiteralPath $newVirtualHostFile -Value $newVirtualHostConfiguration -NoNewline

    $virtualHost = [pscustomobject]@{
        Type = 'apache'
        File = Get-Item -LiteralPath $newVirtualHostFile
        SiteName = $siteName
    }
}

$siteName = $virtualHost.SiteName

# Apache and Nginx keep this path for the life of the virtual host. Staging a
# worktree changes only the junction target, so the web server does not need to
# reload after the initial configuration change.
$stageDirectory = Join-Path $LaragonRoot "data\stage\$siteName"
$stagedPublicPath = Join-Path $stageDirectory 'public'
$temporaryJunction = Join-Path $stageDirectory "public.new.$PID"
$oldJunction = Join-Path $stageDirectory "public.old.$PID"

New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null

foreach ($stalePath in @($temporaryJunction, $oldJunction)) {
    if (Test-Path -LiteralPath $stalePath) {
        Remove-Item -LiteralPath $stalePath -Force
    }
}

New-Item -ItemType Junction -Path $temporaryJunction -Target $publicPath | Out-Null

$hadExistingJunction = Test-Path -LiteralPath $stagedPublicPath
if ($hadExistingJunction) {
    $existingItem = Get-Item -LiteralPath $stagedPublicPath -Force
    if ($existingItem.LinkType -ne 'Junction') {
        Remove-Item -LiteralPath $temporaryJunction -Force
        throw "The staging path exists but is not a junction: $stagedPublicPath"
    }

    Move-Item -LiteralPath $stagedPublicPath -Destination $oldJunction
}

try {
    Move-Item -LiteralPath $temporaryJunction -Destination $stagedPublicPath
} catch {
    if ($hadExistingJunction -and (Test-Path -LiteralPath $oldJunction)) {
        Move-Item -LiteralPath $oldJunction -Destination $stagedPublicPath
    }
    throw
}

if (Test-Path -LiteralPath $oldJunction) {
    Remove-Item -LiteralPath $oldJunction -Force
}

$configuration = Get-Content -LiteralPath $virtualHost.File.FullName -Raw
$rootPattern = if ($virtualHost.Type -eq 'apache') {
    '(?m)^\s*define\s+ROOT\s+"[^"]*"\s*$'
} else {
    '(?m)^(\s*)root\s+[^;]+;\s*$'
}
$rootMatches = [regex]::Matches($configuration, $rootPattern)

if ($rootMatches.Count -ne 1) {
    throw "Expected one document-root definition in $($virtualHost.File.FullName), but found $($rootMatches.Count)."
}

$serverPublicPath = $stagedPublicPath.Replace('\', '/')
$replacement = if ($virtualHost.Type -eq 'apache') {
    "define ROOT `"$serverPublicPath`""
} else {
    "`$1root `"$serverPublicPath`";"
}
$updatedConfiguration = [regex]::Replace($configuration, $rootPattern, $replacement)
$configurationChanged = $updatedConfiguration -ne $configuration

if ($configurationChanged) {
    Copy-Item -LiteralPath $virtualHost.File.FullName -Destination "$($virtualHost.File.FullName).bak" -Force
    Set-Content -LiteralPath $virtualHost.File.FullName -Value $updatedConfiguration -NoNewline
}

if (-not $NoReload -and ($configurationChanged -or $ForceReload)) {
    if ($virtualHost.Type -eq 'apache') {
        $apacheProcesses = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -ieq 'httpd.exe' -and
            $_.ExecutablePath -like "$LaragonRoot*"
        })

        if ($apacheProcesses.Count -gt 0) {
            $apacheProcessIds = @($apacheProcesses.ProcessId)
            $apacheParent = $apacheProcesses |
                Where-Object { $_.ParentProcessId -notin $apacheProcessIds } |
                Select-Object -First 1

            if ($null -eq $apacheParent) {
                throw 'The main Apache process could not be identified.'
            }

            $apacheExecutable = $apacheParent.ExecutablePath
        } else {
            $apacheExecutable = Get-ChildItem -LiteralPath (Join-Path $LaragonRoot 'bin\apache') `
                -Filter 'httpd.exe' -File -Recurse |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 -ExpandProperty FullName

            if ([string]::IsNullOrWhiteSpace($apacheExecutable)) {
                throw "No Apache executable was found under $LaragonRoot\bin\apache."
            }
        }

        $apacheBinDirectory = Split-Path $apacheExecutable
        $apacheServerRoot = Split-Path $apacheBinDirectory

        Write-Output 'Restarting Apache...'
        if ($null -ne $apacheParent) {
            Stop-Process -Id $apacheParent.ProcessId -Force
        }

        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 100
            $remainingApache = @(Get-CimInstance Win32_Process | Where-Object {
                $_.Name -ieq 'httpd.exe' -and
                $_.ExecutablePath -ieq $apacheExecutable
            })
        } while ($remainingApache.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

        foreach ($process in $remainingApache) {
            Stop-Process -Id $process.ProcessId -Force
        }

        Start-Process `
            -FilePath $apacheExecutable `
            -ArgumentList @('-d', "`"$apacheServerRoot`"") `
            -WorkingDirectory $apacheBinDirectory `
            -WindowStyle Hidden

        Start-Sleep -Milliseconds 750

        $restartedApache = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -ieq 'httpd.exe' -and
            $_.ExecutablePath -ieq $apacheExecutable
        })

        if ($restartedApache.Count -eq 0) {
            throw 'Apache stopped but did not start again. Start it from Laragon and check the Apache error log.'
        }

        Write-Output "Apache restarted with $($restartedApache.Count) process(es)."
    } else {
        $nginxProcess = Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -ieq 'nginx.exe' -and
                $_.ExecutablePath -like "$LaragonRoot*"
            } |
            Select-Object -First 1

        if ($null -eq $nginxProcess) {
            throw 'Nginx is not running. Start it from Laragon, then run stage again.'
        }

        $nginxPrefix = Split-Path $nginxProcess.ExecutablePath
        & $nginxProcess.ExecutablePath -p "$nginxPrefix\" -s reload
        if ($LASTEXITCODE -ne 0) {
            throw "Nginx could not reload. Exit code: $LASTEXITCODE"
        }

        Write-Output 'Nginx reloaded.'
    }
} elseif ($configurationChanged) {
    Write-Warning 'The virtual-host configuration changed, but -NoReload prevented the required reload.'
}

if (-not ($NoReload -and $configurationChanged)) {
    if (-not $configurationChanged -and $virtualHost.Type -eq 'apache') {
        $apacheIsRunning = @(Get-CimInstance Win32_Process | Where-Object {
            $_.Name -ieq 'httpd.exe' -and
            $_.ExecutablePath -like "$LaragonRoot*"
        }).Count -gt 0

        if (-not $apacheIsRunning) {
            Write-Output 'Apache is stopped; no PHP OPcache reset is needed.'
            Write-Output "Staged $siteName.test successfully."
            return
        }

        $serverHostMatch = [regex]::Match($configuration, '(?m)^\s*define\s+SITE\s+"([^"]+)"\s*$')
        if (-not $serverHostMatch.Success) {
            throw "The Apache host name could not be read from $($virtualHost.File.FullName)."
        }

        $resetToken = [Guid]::NewGuid().ToString('N')
        $resetFileName = "stage-opcache-$([Guid]::NewGuid().ToString('N')).php"
        # Write through the same junction path that Apache uses. PHP-FCGI can
        # briefly retain the old resolved target after an atomic junction swap.
        $resetFilePath = Join-Path $stagedPublicPath $resetFileName
        $resetScript = @"
<?php

`$providedToken = `$_GET['token'] ?? '';

if (! hash_equals('$resetToken', `$providedToken)) {
    http_response_code(404);
    exit;
}

header('Content-Type: application/json');

echo json_encode([
    'available' => function_exists('opcache_reset'),
    'reset' => function_exists('opcache_reset') ? opcache_reset() : null,
]);
"@

        try {
            Set-Content -LiteralPath $resetFilePath -Value $resetScript -Encoding utf8NoBOM

            $resetUri = "http://$($serverHostMatch.Groups[1].Value)/${resetFileName}?token=$resetToken"
            $resetResponse = $null

            for ($resetAttempt = 1; $resetAttempt -le 5; $resetAttempt++) {
                try {
                    $resetResponse = Invoke-RestMethod -Uri $resetUri -TimeoutSec 5
                    break
                } catch {
                    if ($resetAttempt -eq 5) {
                        throw
                    }

                    Start-Sleep -Milliseconds 100
                }
            }

            if ($resetResponse.available -and -not $resetResponse.reset) {
                throw 'PHP OPcache was available but could not be reset.'
            }

            if ($resetResponse.available) {
                Write-Output 'PHP OPcache reset.'
            }
        } finally {
            if (Test-Path -LiteralPath $resetFilePath) {
                Remove-Item -LiteralPath $resetFilePath -Force
            }
        }
    }

    Write-Output "Staged $siteName.test successfully."
}
