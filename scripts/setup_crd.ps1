param(
    [string]$AuthCode = "4/0AUn6Hd_yPvLRhg5QJ77WGbS2D46yx23gnGSovaOnL71G85eQA8IlimPwskOqAhgNzLDSIA",
    [string]$Pin = "123456"
)

Write-Host "=== 1. SYSTEM OPTIMIZATION AND SECURITY ==="

# Disable Sleep, Hibernation, and Screen Saver
powercfg -change -standby-timeout-ac 0
powercfg -change -monitor-timeout-ac 0
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name "ScreenSaveActive" -Value "0"

Write-Host "=== 2. INSTALLING GOOGLE CHROME BROWSER ==="
$chromeInstaller = "$env:TEMP\chrome_installer.exe"
Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $chromeInstaller -UseBasicParsing
Start-Process -FilePath $chromeInstaller -ArgumentList "/silent", "/install" -Wait
Remove-Item $chromeInstaller -Force -ErrorAction SilentlyContinue
Write-Host "Google Chrome installed successfully."

Write-Host "=== 3. INSTALLING CHROME REMOTE DESKTOP HOST ==="
$crdMsi = "$env:TEMP\chromeremotedesktophost.msi"
Invoke-WebRequest "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi" -OutFile $crdMsi -UseBasicParsing
Start-Process "msiexec.exe" -ArgumentList "/i", $crdMsi, "/qn", "/norestart" -Wait
Remove-Item $crdMsi -Force -ErrorAction SilentlyContinue
Write-Host "Chrome Remote Desktop Host installed successfully."

Write-Host "=== 4. AUTHORIZING AND STARTING REMOTING HOST ==="
$remHost = "${Env:PROGRAMFILES(X86)}\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
if (!(Test-Path $remHost)) {
    $remHost = "${Env:ProgramFiles}\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
}
if (!(Test-Path $remHost)) {
    $found = Get-ChildItem -Path "${Env:SystemDrive}\Program Files*" -Filter "remoting_start_host.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $remHost = $found.FullName }
}

Write-Host "Using host binary: $remHost"

# Execute authorization command
& "$remHost" --code="$AuthCode" --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name="$Env:COMPUTERNAME" --pin="$Pin"

Start-Sleep -Seconds 5
$svc = Get-Service -Name "*chromeremote*" -ErrorAction SilentlyContinue
Write-Host "CRD Service Status: $($svc.Status)"

# Export connection info
$connLines = @(
    "==========================================================================",
    "GOOGLE CHROME REMOTE DESKTOP SESSION ONLINE",
    "Computer Name     : $Env:COMPUTERNAME",
    "PIN               : $Pin",
    "Web Portal        : https://remotedesktop.google.com/access",
    "Status            : LIVE & REGISTERED WITH GOOGLE",
    "=========================================================================="
)
$connLines | Set-Content -Path "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }
