param(
    [string]$TargetPassword = "Paneer@12345!",
    [string]$NgrokToken = "3LNPUZ3mB16z0o1VpkcjzrYckG2_7aYVrFd3YinNFFXHdgiXP"
)

Write-Host "=== 1. CONFIGURING WINDOWS REMOTE DESKTOP AND SECURITY ==="

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

# Enable Remote Desktop in Registry
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# Disable NLA for 100% client compatibility with Microsoft Windows App
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0

# Enable Low-Latency RemoteFX, AVC444, and UDP Accelerated Transport
$tsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (!(Test-Path $tsPath)) { New-Item -Path $tsPath -Force | Out-Null }
Set-ItemProperty -Path $tsPath -Name "fEnableRemoteFXAdvancedRemoteFX" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "SelectNetworkDetect" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "SelectTransportProtocol" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "AVC444ModePreferred" -Value 1 -Type DWord
Set-ItemProperty -Path $tsPath -Name "MinCompressionLevel" -Value 1 -Type DWord

# Configure User Credentials using net user
try {
    net user runneradmin "$TargetPassword" /add /yes | Out-Null
} catch {}
net user runneradmin "$TargetPassword" /active:yes | Out-Null
net localgroup Administrators runneradmin /add | Out-Null
net localgroup "Remote Desktop Users" runneradmin /add | Out-Null

# Explicitly Enable and Start Remote Desktop Service (TermService)
Write-Host "Ensuring TermService is running and listening on port 3389..."
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

Write-Host "=== 2. INITIALIZING HIGH-PERFORMANCE TCP TUNNELS ==="

# Initialize Pinggy TCP Tunnel (Fast, zero card required)
Write-Host "Installing and starting Pinggy TCP tunnel..."
$pinggyHost = ""
try {
    npm install -g pinggy | Out-Null
    pinggy --type tcp -l 3389 --b
    Start-Sleep -Seconds 4
    $psOut = pinggy ps | Out-String
    Write-Host "Pinggy PS Status:"
    Write-Host $psOut
    if ($psOut -match 'tcp://([^\s]+)') {
        $pinggyHost = $matches[1]
        Write-Host "SUCCESS: Pinggy Live Host: $pinggyHost"
    }
} catch {
    Write-Host "Pinggy error: $_"
}

# Also Initialize Ngrok (If account verified)
$ngrokHost = ""
if (-not [string]::IsNullOrWhiteSpace($NgrokToken)) {
    try {
        $ngrokZip = "$env:TEMP\ngrok.zip"
        Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip" -OutFile $ngrokZip
        Expand-Archive -Path $ngrokZip -DestinationPath "$env:TEMP\ngrok" -Force
        & "$env:TEMP\ngrok\ngrok.exe" config add-authtoken "$NgrokToken"
        Start-Process -FilePath "$env:TEMP\ngrok\ngrok.exe" -ArgumentList "tcp", "3389", "--log=stdout" -RedirectStandardOutput "$env:TEMP\ngrok.log"
        Start-Sleep -Seconds 4
        for ($i = 0; $i -lt 10; $i++) {
            try {
                $tunnels = (Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -ErrorAction Stop).tunnels
                if ($tunnels -and $tunnels[0].public_url) {
                    $ngrokHost = $tunnels[0].public_url -replace 'tcp://', ''
                    Write-Host "SUCCESS: Ngrok Live Host: $ngrokHost"
                    break
                }
            } catch {}
            Start-Sleep -Seconds 1
        }
    } catch {
        Write-Host "Ngrok error: $_"
    }
}

# Determine Primary Address
$PRIMARY_CONNECTION = ""
if (-not [string]::IsNullOrWhiteSpace($pinggyHost)) {
    $PRIMARY_CONNECTION = $pinggyHost
} elseif (-not [string]::IsNullOrWhiteSpace($ngrokHost)) {
    $PRIMARY_CONNECTION = $ngrokHost
}

# Write connection details to file
$connLines = @(
    "==========================================================================",
    "WINDOWS SERVER 2022 RUNTIME READY FOR WINDOWS APP",
    "Primary PC Address: $PRIMARY_CONNECTION",
    "Pinggy Address    : $pinggyHost",
    "Ngrok Address     : $ngrokHost",
    "Username          : runneradmin",
    "Password          : $TargetPassword",
    "Local Port 3389   : $(if ($localPortTest.TcpTestSucceeded) { 'LISTENING' } else { 'FAILED' })",
    "==========================================================================",
    "CONNECTION INSTRUCTIONS:",
    "1. Open official Microsoft Windows App (or Remote Desktop Connection / mstsc)",
    "2. Click '+' -> Add PC",
    "3. PC Name: $PRIMARY_CONNECTION",
    "4. User Account: runneradmin",
    "5. Password: $TargetPassword",
    "=========================================================================="
)

$connLines | Set-Content -Path "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }
