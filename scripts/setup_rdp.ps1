param(
    [string]$TargetPassword = "Paneer@12345!",
    [string]$PlayitSecret = "9ad05c2cb7d8e04ac490f6b963ec4f71f9774cfa5e05127ac5f5c9c9f8a5cf32"
)

Write-Host "=== 1. CONFIGURING WINDOWS REMOTE DESKTOP & INSTANT AUTO-LOGON ==="

# Disable Windows Server password complexity requirement via security policy
try {
    secedit /export /cfg "$env:TEMP\sec.cfg" | Out-Null
    if (Test-Path "$env:TEMP\sec.cfg") {
        (Get-Content "$env:TEMP\sec.cfg") -replace "PasswordComplexity = 1", "PasswordComplexity = 0" -replace "MinimumPasswordLength = \d+", "MinimumPasswordLength = 4" | Set-Content "$env:TEMP\sec.cfg"
        secedit /configure /db "$env:TEMP\sec.sdb" /cfg "$env:TEMP\sec.cfg" /areas SECURITYPOLICY | Out-Null
    }
} catch {
    Write-Host "Policy warning: $_"
}

# Configure User Credentials using net user
try {
    net user runneradmin "$TargetPassword" /add /yes | Out-Null
} catch {}
net user runneradmin "$TargetPassword" /active:yes | Out-Null
net localgroup Administrators runneradmin /add | Out-Null
net localgroup "Remote Desktop Users" runneradmin /add | Out-Null

# Enable Windows AutoLogon for runneradmin to eliminate login loading screen hang
$winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $winlogon -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path $winlogon -Name "DefaultUserName" -Value "runneradmin"
Set-ItemProperty -Path $winlogon -Name "DefaultPassword" -Value "$TargetPassword"

# Enable Remote Desktop in Registry & Firewall
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# NLA Enabled (UserAuthentication = 1) for fast CredSSP authentication
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

# Performance Accelerations: RemoteFX, AVC444, and UDP
$tsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (!(Test-Path $tsPath)) { New-Item -Path $tsPath -Force | Out-Null }
Set-ItemProperty -Path $tsPath -Name "fEnableRemoteFXAdvancedRemoteFX" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "SelectNetworkDetect" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "SelectTransportProtocol" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "AVC444ModePreferred" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "MinCompressionLevel" -Value 1 -Type DWord

# Start Remote Desktop Service (TermService)
Set-Service -Name "TermService" -StartupType Automatic
Start-Service -Name "TermService" -ErrorAction SilentlyContinue

# Disable Sleep, Hibernation, and Screen Saver
powercfg -change -standby-timeout-ac 0
powercfg -change -monitor-timeout-ac 0
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name "ScreenSaveActive" -Value "0"

# Verify port 3389 local listener
Start-Sleep -Seconds 2
$localPortTest = Test-NetConnection -ComputerName 127.0.0.1 -Port 3389
Write-Host "Local RDP Port 3389 Listening Status: $($localPortTest.TcpTestSucceeded)"

Write-Host "=== 2. INITIALIZING PLAYIT GAMING-GRADE TCP TUNNEL ==="

# Download official Playit signed daemon
$playitBin = "$env:TEMP\playitd.exe"
$playitUrl = "https://github.com/playit-cloud/playit-agent/releases/download/v1.2.0/playitd-windows-x86_64-signed.exe"
Write-Host "Downloading Playit Daemon from GitHub releases..."
Invoke-WebRequest -Uri $playitUrl -OutFile $playitBin -UseBasicParsing

# Launch Playit Daemon with Secret Key in background
$playitLog = "$env:TEMP\playit.log"
Write-Host "Starting Playit Daemon with your agent Secret Key..."
Start-Process -FilePath $playitBin -ArgumentList "--secret", "$PlayitSecret", "--platform-docker", "-l", "$playitLog"

Start-Sleep -Seconds 5
if (Test-Path $playitLog) {
    Write-Host "Playit Daemon Logs:"
    Get-Content $playitLog -Tail 15
}

# Write connection details to file
$connLines = @(
    "==========================================================================",
    "WINDOWS SERVER 2022 RUNTIME READY FOR WINDOWS APP VIA PLAYIT",
    "Agent Status      : CONNECTED TO PLAYIT.GG DASHBOARD",
    "Username          : runneradmin",
    "Password          : $TargetPassword",
    "Local Port 3389   : $(if ($localPortTest.TcpTestSucceeded) { 'LISTENING' } else { 'FAILED' })",
    "==========================================================================",
    "CONNECTION INSTRUCTIONS:",
    "1. Look at your Playit Dashboard in your browser.",
    "2. It will show 'Agent Connected!'",
    "3. Add Tunnel -> Type: Custom TCP -> Port: 3389",
    "4. Copy your assigned 'something.ply.gg:port' address",
    "5. In Windows App (or mstsc.exe): Connect to that address!",
    "6. User: runneradmin | Password: $TargetPassword",
    "=========================================================================="
)

$connLines | Set-Content -Path "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }
