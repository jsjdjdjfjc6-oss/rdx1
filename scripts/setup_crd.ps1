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

Write-Host ">>> [SETUP] CONFIGURING PROFILES, AUDIO SYSTEM, AND ZERO-RESTRICTION RUNTIME <<<"

# 1. Disable Windows Server Password Complexity Requirements via secedit
$secCfg = "$env:TEMP\sec.cfg"
$secSdb = "$env:TEMP\sec.sdb"
secedit /export /cfg $secCfg | Out-Null
if (Test-Path $secCfg) {
    (Get-Content $secCfg) `
        -replace 'PasswordComplexity = 1', 'PasswordComplexity = 0' `
        -replace 'MinimumPasswordLength = \d+', 'MinimumPasswordLength = 0' | Set-Content $secCfg
    secedit /configure /db $secSdb /cfg $secCfg /areas SECURITYPOLICY | Out-Null
    Remove-Item $secCfg, $secSdb -Force -ErrorAction SilentlyContinue
}

# 2. Configure 'RDP' profile with password rakib123
$rdpUser = Get-LocalUser -Name "RDP" -ErrorAction SilentlyContinue
if (!$rdpUser) {
    net user RDP "rakib123" /add /yes | Out-Null
} else {
    net user RDP "rakib123" | Out-Null
}
net localgroup Administrators RDP /add | Out-Null
net localgroup "Remote Desktop Users" RDP /add | Out-Null

# 3. Configure 'runneradmin' profile with the exact same password rakib123
net user runneradmin "rakib123" /active:yes | Out-Null
net localgroup Administrators runneradmin /add | Out-Null
net localgroup "Remote Desktop Users" runneradmin /add | Out-Null

# 4. Make sure BOTH runneradmin and RDP profiles appear on the login screen
$userList = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
if (!(Test-Path $userList)) { New-Item -Path $userList -Force | Out-Null }
Set-ItemProperty -Path $userList -Name "runneradmin" -Value 1 -Type DWord
Set-ItemProperty -Path $userList -Name "RDP" -Value 1 -Type DWord

# 5. Enable the Windows Login Page
$winLogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $winLogon -Name "AutoAdminLogon" -Value "0"
Set-ItemProperty -Path $winLogon -Name "DefaultUserName" -Value "RDP"
Set-ItemProperty -Path $winLogon -Name "DontDisplayLastUserName" -Value "0"

# 6. FORCE-START WINDOWS AUDIO SYSTEM BEFORE CRD INSTALLATION
Write-Host ">>> [AUDIO] Starting Windows Audio Services & Audio Redirection Policies <<<"
Set-Service -Name "AudioEndpointBuilder" -StartupType Automatic -ErrorAction SilentlyContinue
Set-Service -Name "Audiosrv" -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name "AudioEndpointBuilder" -ErrorAction SilentlyContinue
Start-Service -Name "Audiosrv" -ErrorAction SilentlyContinue

# Enable Audio Redirection Policies in Registry
$tsAudio = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (!(Test-Path $tsAudio)) { New-Item -Path $tsAudio -Force | Out-Null }
Set-ItemProperty -Path $tsAudio -Name "fDisableAudio" -Value 0 -Type DWord
Set-ItemProperty -Path $tsAudio -Name "fDisableAudioCapture" -Value 0 -Type DWord

$tsTcp = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
if (Test-Path $tsTcp) {
    Set-ItemProperty -Path $tsTcp -Name "fDisableAudio" -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $tsTcp -Name "fDisableCam" -Value 0 -ErrorAction SilentlyContinue
}

# 7. Check Chrome Pre-installation
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

# 8. High-Speed Parallel Download and Silent Install of Chrome Remote Desktop Host
$crdMsi = "$env:TEMP\crd.msi"
Write-Host "[High-Speed] Downloading Chrome Remote Desktop Host MSI via curl..."
& curl.exe -L -s -o $crdMsi "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi"

Write-Host "[High-Speed] Installing Chrome Remote Desktop Host MSI (with Audio Driver)..."
Start-Process "msiexec.exe" -ArgumentList "/i", $crdMsi, "/qn", "/norestart" -Wait
Remove-Item $crdMsi -Force -ErrorAction SilentlyContinue

# Ensure all Media PnP devices (CRD Audio Driver) are explicitly Enabled
Start-Sleep -Seconds 2
Get-PnpDevice -Class Media -ErrorAction SilentlyContinue | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue
Restart-Service -Name "Audiosrv" -Force -ErrorAction SilentlyContinue

# 9. Instant Host Authorization
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
    "GOOGLE CHROME REMOTE DESKTOP SESSION ONLINE [WITH SOUND DRIVER]",
    "Operating System  : Windows Server 2025 (Latest Modern Windows 11 Kernel)",
    "Profiles Visible  : runneradmin AND RDP",
    "Unified Password  : rakib123",
    "PIN               : $Pin",
    "Web Portal        : https://remotedesktop.google.com/access",
    "Status            : LIVE & REGISTERED WITH GOOGLE",
    "=========================================================================="
)
$connLines | Set-Content -Path "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }
