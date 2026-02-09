# uninstall.ps1 - Adobe Acrobat/Reader
$ErrorActionPreference = "Stop"

$AppName   = "AdobeReader"
$LogDir    = "C:\ProgramData\FNBA\$AppName"
$ScriptLog = Join-Path $LogDir "uninstall.log"
$MsiLog    = Join-Path $LogDir ("{0}verbose.log" -f $AppName)

New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path $ScriptLog -Append | Out-Null

function Try-ParseVersion([string]$v) { try { [version]$v } catch { [version]"0.0.0.0" } }

try {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $rawApps = foreach ($p in $paths) {
        Get-ItemProperty $p -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and (
                    $_.DisplayName -like "Adobe Acrobat*" -or
                    $_.DisplayName -like "Adobe Acrobat Reader*" -or
                    $_.DisplayName -like "Adobe Reader*"
                )
            } |
            Select-Object DisplayName, DisplayVersion, PSChildName, UninstallString
    }

    if (-not $rawApps) { Write-Output "Adobe Acrobat/Reader not found. Nothing to uninstall."; exit 0 }

    $apps = $rawApps | Where-Object { $_.DisplayName -notmatch 'Refresh Manager|Genuine|Update|Updater|ARM|Acrobat.com|CEF|MUI' }
    if (-not $apps) { Write-Output "Only non-target Adobe components were found. Nothing to uninstall."; exit 0 }

    # Build candidates + extract ProductCode + de-dupe by ProductCode
    $candidates = $apps | ForEach-Object {
        $productCode = $null
        if ($_.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') { $productCode = $_.PSChildName }
        elseif ($_.UninstallString -match '\{[0-9A-Fa-f-]+\}') { $productCode = $Matches[0] }

        $name  = $_.DisplayName
        $ver   = Try-ParseVersion $_.DisplayVersion
        $score = 0
        if ($name -match 'Acrobat Reader|Adobe Reader') { $score += 200 }
        if ($name -match 'Acrobat(?! Reader)')          { $score += 150 }
        if ($name -match '64-bit')                      { $score += 10 }

        [pscustomobject]@{
            DisplayName    = $_.DisplayName
            DisplayVersion = $_.DisplayVersion
            VersionObj     = $ver
            ProductCode    = $productCode
            Score          = $score
        }
    } |
    Where-Object { $_.ProductCode } |
    Sort-Object -Property ProductCode -Unique |
    Sort-Object -Property @{Expression="Score";Descending=$true}, @{Expression="VersionObj";Descending=$true}

    Write-Output "Candidates (in order):"
    $candidates | ForEach-Object { Write-Output " - $($_.DisplayName)  Version: $($_.DisplayVersion)  ProductCode: $($_.ProductCode)" }

    foreach ($c in $candidates) {
        Write-Output "Attempting uninstall: $($c.DisplayName) ($($c.DisplayVersion)) ProductCode: $($c.ProductCode)"

        $args = "/x $($c.ProductCode) /qn /norestart /L*v `"$MsiLog`""
        Write-Output "Running: msiexec.exe $args"

        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        $exit = $p.ExitCode
        Write-Output "Exit Code: $exit"

        switch ($exit) {
            0    { exit 0 }
            3010 { exit 3010 }
            1641 { exit 1641 }
            1605 { Write-Output "Not installed (1605). Trying next candidate..."; continue }
            1622 { Write-Output "Invalid command line (1622). Check MSI log path/quoting."; exit 1 }
            default { Write-Output "Uninstall failed with exit code $exit."; exit 1 }
        }
    }

    Write-Output "No installed Adobe Acrobat/Reader MSI products were successfully uninstalled."
    exit 0
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
