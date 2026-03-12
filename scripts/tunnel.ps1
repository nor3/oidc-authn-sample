# authzen tunnel - Script to run as administrator on Windows
# Forwards Windows localhost to WSL2 kubectl port-forward via netsh portproxy
#
# Usage: PowerShell (as admin) .\scripts\tunnel.ps1

# --- Admin privilege check / elevation ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Re-launching with admin privileges..."
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = "Stop"

$hostsFile   = "C:\Windows\System32\drivers\etc\hosts"
$hostnames   = @("authzen.local", "keycloak.local")
$listenAddr  = "127.0.0.1"
$ports       = @(
    @{ listen = 443;   connect = 30443; label = "App (HTTPS)" },
    @{ listen = 80;    connect = 30080; label = "HTTP to HTTPS redirect" }
)

# --- Get WSL2 IP address ---
$wslIp = (wsl hostname -I).Trim().Split(' ')[0]
if (-not $wslIp) {
    Write-Error "Failed to get WSL2 IP address. Please check if WSL2 is running."
    exit 1
}
Write-Host "WSL2 IP: $wslIp"

# --- Add entries to hosts file ---
$hostsContent = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
$missing = $hostnames | Where-Object { $hostsContent -notmatch "\b$_\b" }
if ($missing.Count -gt 0) {
    $entry = "`n$listenAddr " + ($hostnames -join " ")
    Add-Content -Path $hostsFile -Value $entry
    Write-Host "Added to hosts: $($missing -join ', ')"
} else {
    Write-Host "hosts already configured."
}

# --- Launch kubectl port-forward in WSL2 ---
Write-Host ""
Write-Host "Starting kubectl port-forward in WSL2..."
$pfProc = Start-Process wsl -ArgumentList (
    "-- kubectl port-forward svc/ingress-nginx-controller " +
    "-n ingress-nginx --address 0.0.0.0 30443:443 30080:80"
) -PassThru -WindowStyle Hidden

Start-Sleep -Seconds 3

# --- Configure netsh portproxy ---
foreach ($p in $ports) {
    netsh interface portproxy add v4tov4 `
        listenaddress=$listenAddr listenport=$($p.listen) `
        connectaddress=$wslIp    connectport=$($p.connect) | Out-Null
    Write-Host "portproxy: ${listenAddr}:$($p.listen) -> ${wslIp}:$($p.connect)  ($($p.label))"
}

Write-Host ""
Write-Host "=== Tunnel started ==="
Write-Host "  App:             https://authzen.local"
Write-Host "  Keycloak admin:  https://keycloak.local"
Write-Host ""
Write-Host "Press Enter to stop..."

try {
    Read-Host | Out-Null
} finally {
    # --- Cleanup ---
    Write-Host "Cleaning up..."
    foreach ($p in $ports) {
        netsh interface portproxy delete v4tov4 `
            listenaddress=$listenAddr listenport=$($p.listen) 2>$null | Out-Null
    }
    if ($pfProc -and -not $pfProc.HasExited) {
        # Launched via wsl process, so kill kubectl from within wsl
        wsl -- pkill -f "kubectl port-forward" 2>$null
        Stop-Process -Id $pfProc.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Tunnel stopped."
}
