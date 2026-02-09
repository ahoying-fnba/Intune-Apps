# install.ps1 - Adobe Acrobat Reader DC (offline EXE) for Intune Win32
$ErrorActionPreference = 'Stop'

$appName   = 'AdobeReader'
$logDir    = Join-Path $env:ProgramData "FNBA\$appName"
$scriptLog = Join-Path $logDir "install.log"
$msiLog    = Join-Path $logDir "${appName}verbose.log"

New-Item -Path $logDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path $scriptLog -Append | Out-Null

try {
    $installer = Join-Path $PSScriptRoot "AcroRdrDC2500121111_en_US.exe"
    if (-not (Test-Path $installer)) { throw "Installer not found: $installer" }

    # Silent install + suppress reboot + pass MSI logging
    $args = "/sAll /rs /msi EULA_ACCEPT=YES /L*v+ `"$msiLog`""
    Write-Output "Running: $installer $args"

    $p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    $exitCode = $p.ExitCode
    Write-Output "Exit code: $exitCode"

    switch ($exitCode) {
        0    { exit 0 }
        3010 { exit 3010 }  # reboot required
        1641 { exit 1641 }  # reboot initiated/required
        default { throw "Install failed with exit code $exitCode. See $scriptLog and $msiLog" }
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
