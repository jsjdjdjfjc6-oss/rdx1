param(
    [string]$TargetPassword = "Paneer@12345!",
    [string]$NgrokToken = "3LNPUZ3mB16z0o1VpkcjzrYckG2_7aYVrFd3YinNFFXHdgiXP"
)

Write-Host "=== 1. CONFIGURING WINDOWS REMOTE DESKTOP & SECURITY ==="

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

Write-Host "=== 2. INITIALIZING HIGH-SPEED NGROK TCP TUNNEL ==="

# Download and initialize Ngrok v3
$ngrokZip = "$env:TEMP\ngrok.zip"
Write-Host "Downloading official Ngrok agent..."
Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip" -OutFile $ngrokZip
Expand-Archive -Path $ngrokZip -DestinationPath "$env:TEMP\ngrok" -Force

# Authenticate Ngrok
& "$env:TEMP\ngrok\ngrok.exe" config add-authtoken "$NgrokToken"

# Launch Ngrok TCP tunnel to port 3389
Write-Host "Launching Ngrok TCP tunnel on port 3389..."
Start-Process -FilePath "$env:TEMP\ngrok\ngrok.exe" -ArgumentList "tcp", "3389", "--log=stdout" -RedirectStandardOutput "$env:TEMP\ngrok.log" -RedirectStandardError "$env:TEMP\ngrok_err.log"

Start-Sleep -Seconds 4
$ngrokHost = ""
for ($i = 0; $i -lt 25; $i++) {
    try {
        $tunnels = (Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -ErrorAction Stop).tunnels
        if ($tunnels -and $tunnels[0].public_url) {
            $ngrokHost = $tunnels[0].public_url -replace 'tcp://', ''
            Write-Host "SUCCESS! Ngrok Live Host: $ngrokHost"
            break
        }
    } catch {}
    Start-Sleep -Seconds 1
}

# Fallback: Also launch Serveo in case of backup
$serveoHost = ""
if ([string]::IsNullOrWhiteSpace($ngrokHost)) {
    Write-Host "Ngrok waiting, launching Serveo fallback..."
    $serveoLog = "$env:TEMP\serveo.log"
    Start-Process -FilePath "ssh" -ArgumentList "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-o", "ServerAliveInterval=15", "-R", "0:localhost:3389", "serveo.net" -RedirectStandardOutput $serveoLog
    Start-Sleep -Seconds 3
    if (Test-Path $serveoLog) {
        $sContent = Get-Content $serveoLog -Raw
        if ($sContent -match 'serveousercontent\.com:([0-9]+)') {
            $serveoHost = "serveousercontent.com:$($matches[1])"
        }
    }
}

$PRIMARY_CONNECTION = ""
if (-not [string]::IsNullOrWhiteSpace($ngrokHost)) {
    $PRIMARY_CONNECTION = $ngrokHost
} else {
    $PRIMARY_CONNECTION = $serveoHost
}

# Write connection details to file
$connLines = @(
    "==========================================================================",
    "WINDOWS SERVER 2022 RUNTIME READY FOR WINDOWS APP",
    "Primary PC Address: $PRIMARY_CONNECTION",
    "Ngrok Address     : $ngrokHost",
    "Serveo Address    : $serveoHost",
    "Username          : runneradmin",
    "Password          : $TargetPassword",
    "=========================================================================="
)
$connLines | Out-File -FilePath "connection_info.txt" -Encoding utf8
$connLines | ForEach-Object { Write-Host $_ }

# Write GitHub Step Summary
$summaryLines = @(
    "## Windows Server 2022 Remote PC Ready",
    "",
    "### Connection Details for Windows App:",
    "| Setting | Value |",
    "|---|---|",
    "| PC name (Host:Port) | $PRIMARY_CONNECTION |",
    "| User account | runneradmin |",
    "| Password | $TargetPassword |",
    "",
    "---",
    "### How to Connect in Windows App (Microsoft Official):",
    "1. Open Windows App.",
    "2. Click Add a remote PC (or + button).",
    "3. In PC name, paste: $PRIMARY_CONNECTION",
    "4. In User account, choose Add user account:",
    "   - Username: runneradmin",
    "   - Password: $TargetPassword",
    "5. Click Connect!"
)
if ($env:GITHUB_STEP_SUMMARY) {
    $summaryLines | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

Write-Host "Setup completed successfully."
