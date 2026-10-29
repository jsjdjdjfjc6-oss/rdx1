param(
    [string]$AuthCode = "",
    [string]$Pin = "123456"
)

# Extract code safely using robust string methods
if ($AuthCode -like "*--code=*") {
    $idx = $AuthCode.IndexOf("--code=")
    if ($idx -ge 0) {
        $sub = $AuthCode.Substring($idx + 7).TrimStart('"').TrimStart("'")
        $delims = @('"', "'", ' ', "`t")
        $endIdx = $sub.IndexOfAny($delims)
        if ($endIdx -gt 0) {
            $AuthCode = $sub.Substring(0, $endIdx)
        } else {
            $AuthCode = $sub
        }
    }
}
$AuthCode = $AuthCode.Replace('"', "").Replace("'", "").Trim()

if ([string]::IsNullOrWhiteSpace($Pin)) {
    $Pin = "123456"
}

Write-Host ">>> [SUPER-FAST ASYNC] CONFIGURING EXCLUSIVE 'RDP' USER AND ZERO-LOCK LOGIN <<<"

# 1. Create/Configure 'RDP' account as Primary Administrator
$rdpUser = Get-LocalUser -Name "RDP" -ErrorAction SilentlyContinue
if (!$rdpUser) {
    net user RDP "123456" /add /yes | Out-Null
} else {
    net user RDP "123456" | Out-Null
}
net localgroup Administrators RDP /add | Out-Null
net localgroup "Remote Desktop Users" RDP /add | Out-Null

# 2. Hide 'runneradmin' completely from logon screen and show ONLY 'RDP'
$userList = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
if (!(Test-Path $userList)) { New-Item -Path $userList -Force | Out-Null }
Set-ItemProperty -Path $userList -Name "runneradmin" -Value 0 -Type DWord
Set-ItemProperty -Path $userList -Name "RDP" -Value 1 -Type DWord

# 3. Configure 100% Force AutoLogon directly into 'RDP'
$winLogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $winLogon -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path $winLogon -Name "DefaultUserName" -Value "RDP"
Set-ItemProperty -Path $winLogon -Name "DefaultPassword" -Value "123456"
Set-ItemProperty -Path $winLogon -Name "ForceAutoLogon" -Value "1"

# 4. Disable Lock Screen and Screensaver
$lockPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (!(Test-Path $lockPath)) { New-Item -Path $lockPath -Force | Out-Null }
Set-ItemProperty -Path $lockPath -Name "NoLockScreen" -Value 1 -Type DWord

# 5. Background Async Power Settings Optimization
Start-Job -ScriptBlock {
    powercfg -change -standby-timeout-ac 0
    powercfg -change -monitor-timeout-ac 0
    Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name "ScreenSaveActive" -Value "0"
} | Out-Null

# 6. Check Chrome Pre-installation
$chromePath = "${Env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
if (!(Test-Path $chromePath)) {
    $chromePath = "${Env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
}
if (!(Test-Path $chromePath)) {
    Write-Host "[Multiprocessing] Downloading Google Chrome via high-speed curl..."
    & curl.exe -L -s -o "$env:TEMP\chrome.exe" "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
    Start-Process "$env:TEMP\chrome.exe" -ArgumentList "/silent", "/install" -Wait
} else {
    Write-Host "[Optimized] Google Chrome already pre-installed at: $chromePath"
}

# 7. High-Speed Parallel Download and Silent Install of Chrome Remote Desktop Host
$crdMsi = "$env:TEMP\crd.msi"
Write-Host "[High-Speed] Downloading Chrome Remote Desktop Host MSI via curl..."
& curl.exe -L -s -o $crdMsi "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi"

Write-Host "[High-Speed] Installing Chrome Remote Desktop Host MSI..."
Start-Process "msiexec.exe" -ArgumentList "/i", $crdMsi, "/qn", "/norestart" -Wait
Remove-Item $crdMsi -Force -ErrorAction SilentlyContinue

# 8. Instant Host Authorization
$remHost = "${Env:PROGRAMFILES(X86)}\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
if (!(Test-Path $remHost)) {
    $remHost = "${Env:ProgramFiles}\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
}
if (!(Test-Path $remHost)) {
    $found = Get-ChildItem -Path "${Env:SystemDrive}\Program Files*" -Filter "remoting_start_host.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $remHost = $found.FullName }
}

Write-Host "[Instant] Authorizing and Starting Host Binary: $remHost"
Write-Host "[Instant] Using AuthCode: $AuthCode"

& "$remHost" --code="$AuthCode" --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name="$Env:COMPUTERNAME" --pin="$Pin"

Start-Sleep -Seconds 3
$svc = Get-Service -Name "*chromeremote*" -ErrorAction SilentlyContinue
Write-Host "[Status] CRD Service Status: $($svc.Status)"

$connLines = @(
    "==========================================================================",
    "GOOGLE CHROME REMOTE DESKTOP SESSION ONLINE [EXCLUSIVE RDP USER]",
    "Operating System  : Windows Server 2025 (Latest Modern Windows 11 Kernel)",
    "Exclusive User    : RDP (Administrator)",
    "Password          : 123456",
    "PIN               : $Pin",
    "Web Portal        : https://remotedesktop.google.com/access",
    "Status            : LIVE & REGISTERED WITH GOOGLE",
    "=========================================================================="
)
$connLines | Set-Content -Path "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }
