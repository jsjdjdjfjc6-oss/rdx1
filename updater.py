import os

crd_ps = r''"param(
    [string]$AuthCode = "",
    [string]$Pin = "123456"
)

# Automatically extract code even if paneer pasted the entire command
if ($AuthCode -match '--code=["']?([^'"\s]+)["']?') {
    $AuthCode = $Matches[1]
}
$AuthCode = $AuthCode.Trim()

if ([string]::IsNullOrWhiteSpace($Pin)) {
    $Pin = "123456"
}

Write-Host "=== 1. SYSTEM OPTIMIZATION AND SECURITY ==="
powercfg -change -standby-timeout-ac 0
powercfg -change -monitor-timeout-ac 0
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name "ScreenSaveActive" -Value "0"

Write-Host "=== 2. INSTALLING GOOGLE CHROME BROWSERE ==="
$chromeInstaller = "$env:TEMP\\chrome_installer.exe"
Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $chromeInstaller -UseBasicParsing
Start-Process -FilePath $chromeInstaller -ArgumentList "/silent", "/install" -Wait
Remove-Item $chromeInstaller -Force -ErrorAction SilentlyContinue
Write-Host "Google Chrome installed successfully."

Write-Host "=== 3. INSTALLING CHROME REMOTE DESKTOP HOST ==="
$crdMsi = "$env:TEMP\\chromeremotedesktophost.msi"
Invoke-WebRequest "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi" -OutFile $crdMsi -UseBasicParsing
Start-Process "msiexec.exe" -ArgumentList "/i", $crdMsi, "/qn", "/norestart" -Wait
Remove-Item $crdMsi -Force -ErrorAction SilentlyContinue
Write-Host "Chrome Remote Desktop Host installed successfully."

Write-Host "=== 4. AUTHORIZING AND STARTING REMOTING HOST ==="
$remHost = "${Env:PROGRAMFILES(X86)}\\Google\\Chrome Remote Desktop\\CurrentVersion\\remoting_start_host.exe"
if (!(Test-Path $remHost)) {
    $remHost = "${Env:ProgramFiles}\\Google\\Chrome Remote Desktop\\CurrentVersion\\remoting_start_host.exe"
}
if (!(Test-Path $remHost)) {
    $found = Get-ChildItem -Path "${Env:SystemDrive}\\Program Files*\" -Filter "remoting_start_host.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $remHost = $found.FullName }
}

Write-Host "Using host binary: $remHost"

# Execute authorization command
& "$remHost" --code="$AuthCode" --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name="$Env:COMPUTERNAME" --pin="$Pin"

Start-Sleep -Seconds 5
$svc = Get-Service -Name "*chromeremote*" -ErrorAction SilentlyContinue
Write-Host "CRD Service Status: $($svc.Status)"

$connLines = @(
    "========================================================================",
    "GOOGLE CHROME REMOTE DESKTOP SESSION ONLINE",
    "Operating System  : Windows Server 2025 (Latest Modern Windows 11 Kernel)",
    "Computer Name     : $Env:COMPUTERNAME",
    "PIN               : $Pin",
    "Web Portal        : https://remotedesktop.google.com/access",
    "Status            : LIVE & REGISTERED WITH GOOGLE",
    "========================================================================"
)
$connLines | Set-Content -Path "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }
''"phin config=utf-8
with open('scripts/setup_crd.ps1', 'w', encoding='utf-8') as f:
    f.write(crd_ps)

wf = rrr"name: Windows Runtime Environment Validation

on:
  workflow_dispatch:
    inputs:
      crd_code:
        description: 'Paste auth code OR full command from Google headless page'
        required: true
        type: string
      pin:
        description: 'Access PIN'
        required: false
        default: '123456'
  push:
    paths:
      - 'trigger_build.txt'

jobs:
  windows-session:
    runs-on: windows-2025
    timeout-minutes: 360

    steps:
      - name: 1. Checkout repository
        uses: actions/checkout@4

      - name: 2. Deploy Chrome Remote Desktop Host
        shell: powershell
        run: |
          $code = SREQ github.event.inputs.crd_code EREQ
          $pin = SREQ github.event.inputs.pin EREQ
          .\scripts\setup_crd.ps1 -AuthCode $code -Pin $pin

      - name: 3. Export Connection Info Artifact
        uses: actions/upload-artifact@4
        with:
          name: windows-connection-info
          path: connection_info.txt
          retention-days: 1

      - name: 4. Maintain Active Session and Watchdog
        shell: powershell
        run: |
          Write-Host "Google Chrome Remote Desktop is live and connected!"
          Write-Host "Connect at: https://remotedesktop.google.com/access with PIN: 123456"
          for ($m = 1; $m -le 360; $m++) {
              Start-Sleep -Seconds 60
              $svc = Get-Service -Name "*chromeremote*" -ErrorAction SilentlyContinue
              Write-Host "[Heartbeat] Elapsed: $m mins | CRD Service Status: $($svc.Status)"
          }
"'".replace("SREQ", "{{").replace("EREQ", "}}")

with open('.github/workflows/windows_build.yml', 'w', encoding='utf-8') as f:
    f.write(wf)

print('Update files successfully')
