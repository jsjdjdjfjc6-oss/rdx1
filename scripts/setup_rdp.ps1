param(
    [string]$TargetPassword = "Paneer@12345!",
    [string]$NgrokToken = ""
)

Write-Host "=== 1. CONFIGURING WINDOWS REMOTE DESKTOP ==="

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

# Enable Remote Desktop
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

# Disable Sleep, Hibernation, and Screen Saver
powercfg -change -standby-timeout-ac 0
powercfg -change -monitor-timeout-ac 0
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name "ScreenSaveActive" -Value "0"

Write-Host "=== 2. INITIALIZING SECURE LOW-LATENCY MULTI-TUNNEL ==="

$serveoLog = "$env:TEMP\serveo.log"
Remove-Item $serveoLog -ErrorAction SilentlyContinue

$pinggyLog = "$env:TEMP\pinggy.log"
Remove-Item $pinggyLog -ErrorAction SilentlyContinue

# Launch 1: Serveo TCP tunnel (direct, instant, no token needed)
Write-Host "Launching Serveo TCP tunnel on port 3389..."
Start-Process -FilePath "ssh" -ArgumentList "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-o", "ServerAliveInterval=15", "-R", "0:localhost:3389", "serveo.net" -RedirectStandardOutput $serveoLog -RedirectStandardError "$env:TEMP\serveo_err.log"

# Launch 2: Pinggy TCP tunnel
Write-Host "Launching Pinggy TCP tunnel..."
Start-Process -FilePath "ssh" -ArgumentList "-T", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-o", "ServerAliveInterval=15", "-p", "443", "-R", "0:localhost:3389", "tcp@free.pinggy.io" -RedirectStandardOutput $pinggyLog -RedirectStandardError "$env:TEMP\pinggy_err.log"

# Launch 3: Ngrok TCP if token provided
$ngrokHost = ""
if (-not [string]::IsNullOrWhiteSpace($NgrokToken)) {
    Write-Host "Launching Ngrok TCP tunnel..."
    $ngrokZip = "$env:TEMP\ngrok.zip"
    Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip" -OutFile $ngrokZip
    Expand-Archive -Path $ngrokZip -DestinationPath "$env:TEMP\ngrok" -Force
    & "$env:TEMP\ngrok\ngrok.exe" config add-authtoken $NgrokToken
    Start-Process -FilePath "$env:TEMP\ngrok\ngrok.exe" -ArgumentList "tcp", "3389", "--log=stdout" -RedirectStandardOutput "$env:TEMP\ngrok.log"
}

# Poll tunnels for live host and port
$serveoHost = ""
$pinggyHost = ""

for ($i = 0; $i -lt 30; $i++) {
    # Check Serveo
    if ([string]::IsNullOrWhiteSpace($serveoHost) -and (Test-Path $serveoLog)) {
        $sContent = Get-Content $serveoLog -Raw
        if ($sContent -match 'serveousercontent\.com:([0-9]+)') {
            $serveoHost = "serveousercontent.com:$($matches[1])"
            Write-Host "Found Serveo Address: $serveoHost"
        }
    }

    # Check Pinggy
    if ([string]::IsNullOrWhiteSpace($pinggyHost) -and (Test-Path $pinggyLog)) {
        $pContent = Get-Content $pinggyLog -Raw
        if ($pContent -match 'tcp://([a-zA-Z0-9\.\-]+):([0-9]+)') {
            $pinggyHost = "$($matches[1]):$($matches[2])"
            Write-Host "Found Pinggy Address: $pinggyHost"
        }
    }

    # Check Ngrok
    if (-not [string]::IsNullOrWhiteSpace($NgrokToken) -and [string]::IsNullOrWhiteSpace($ngrokHost)) {
        try {
            $tunnels = (Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -ErrorAction Stop).tunnels
            if ($tunnels -and $tunnels[0].public_url) {
                $ngrokHost = $tunnels[0].public_url -replace 'tcp://', ''
                Write-Host "Found Ngrok Address: $ngrokHost"
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($serveoHost) -or -not [string]::IsNullOrWhiteSpace($pinggyHost) -or -not [string]::IsNullOrWhiteSpace($ngrokHost)) {
        Write-Host "At least one tunnel address acquired!"
        break
    }
    Start-Sleep -Seconds 1
}

$PRIMARY_CONNECTION = ""
if (-not [string]::IsNullOrWhiteSpace($ngrokHost)) {
    $PRIMARY_CONNECTION = $ngrokHost
} elseif (-not [string]::IsNullOrWhiteSpace($serveoHost)) {
    $PRIMARY_CONNECTION = $serveoHost
} elseif (-not [string]::IsNullOrWhiteSpace($pinggyHost)) {
    $PRIMARY_CONNECTION = $pinggyHost
}

# Write connection details to file
$connLines = @(
    "==========================================================================",
    "WINDOWS SERVER 2022 RUNTIME READY FOR WINDOWS APP",
    "Primary PC Address: $PRIMARY_CONNECTION",
    "Serveo Address    : $serveoHost",
    "Pinggy Address    : $pinggyHost",
    "Ngrok Address     : $ngrokHost",
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
