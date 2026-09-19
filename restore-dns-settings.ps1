# Windows PowerShell 5.1 compatible.
[CmdletBinding()]
param([switch]$FullNetworkReset)

$ErrorActionPreference = 'Stop'
# Require administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    exit 1
}

$failures = New-Object 'System.Collections.Generic.List[string]'
function Invoke-ResetStep {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action | Out-Host
        Write-Host "[OK] $Name" -ForegroundColor Green
    } catch {
        $message = "${Name}: $($_.Exception.Message)"
        $failures.Add($message)
        Write-Warning $message
    }
}

function Invoke-Netsh {
    param([string[]]$Arguments)
    & "$env:SystemRoot\System32\netsh.exe" @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "netsh $($Arguments -join ' ') failed (exit code $LASTEXITCODE)."
    }
}

function Restore-AdapterDns {
    param($Adapter)
    # Enumerate first: a network adapter need not expose DNS client instances.
    # Do not suppress discovery errors (for example access denied or CIM failure).
    $dnsClients = @(Get-DnsClientServerAddress -ErrorAction Stop |
        Where-Object { $_.InterfaceIndex -eq $Adapter.ifIndex })
    if ($dnsClients.Count -eq 0) {
        Write-Host "[SKIP] DNS on $($Adapter.Name): no DNS client settings exposed by Windows." -ForegroundColor Yellow
        return
    }
    foreach ($dnsClient in $dnsClients) {
        Set-DnsClientServerAddress -InputObject $dnsClient -ResetServerAddresses -ErrorAction Stop
    }
    Write-Host "[OK] Automatic DNS on $($Adapter.Name)" -ForegroundColor Green
}

try {
    # Include disconnected adapters with saved manual DNS settings.
    $adapters = @(Get-NetAdapter -ErrorAction Stop)
    if ($adapters.Count -eq 0) { throw 'No network adapters were found.' }
    if ($FullNetworkReset) {
        Write-Warning 'Network reset may disconnect you. Static IP settings will be replaced by DHCP on physical adapters. Restart Windows afterwards.'
        # Diagnostic snapshot, not automatic rollback. Abort if it cannot be saved.
        $backupPath = Join-Path $env:LOCALAPPDATA ('akaDns\Backups\' + [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Get-NetIPConfiguration -All | Export-Clixml (Join-Path $backupPath 'ip-configuration.xml')
        Get-NetIPAddress | Export-Clixml (Join-Path $backupPath 'ip-addresses.xml')
        Get-NetRoute | Export-Clixml (Join-Path $backupPath 'routes.xml')
        Get-DnsClientServerAddress | Export-Clixml (Join-Path $backupPath 'dns.xml')
        Get-NetAdapterBinding -Name '*' | Export-Clixml (Join-Path $backupPath 'bindings.xml')
        Write-Host "Settings snapshot: $backupPath"
    }
} catch {
    Write-Warning "Reset did not start: $($_.Exception.Message)"
    exit 1
}

foreach ($adapter in $adapters) {
    Invoke-ResetStep "Enable IPv6 on $($adapter.Name)" {
        $binding = Get-NetAdapterBinding -InterfaceDescription $adapter.InterfaceDescription -ComponentID ms_tcpip6
        if (-not $binding) { throw 'IPv6 binding was not found.' }
        if (-not $binding.Enabled) {
            $binding | Enable-NetAdapterBinding -Confirm:$false
        }
    }
    try {
        Restore-AdapterDns -Adapter $adapter
    } catch {
        $message = "Automatic DNS on $($adapter.Name): $($_.Exception.Message)"
        $failures.Add($message)
        Write-Warning $message
    }
}

# Remove only overrides written by this app. OS/policy chooses DoH behavior.
foreach ($valueName in @('EnableAutoDOH', 'QueryIpMatching')) {
    Invoke-ResetStep "Remove $valueName override" {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
        if (Test-Path -LiteralPath $path) {
            $key = Get-Item -LiteralPath $path
            if ($key.GetValueNames() -contains $valueName) {
                Remove-ItemProperty -LiteralPath $path -Name $valueName
            }
        }
    }
}

if ($FullNetworkReset) {
    Invoke-ResetStep 'Reset Winsock catalog' { Invoke-Netsh @('winsock', 'reset') }
    Invoke-ResetStep 'Reset TCP/IP' {
        Invoke-Netsh @('int', 'ip', 'reset', (Join-Path $backupPath 'tcp-ip-reset.log'))
    }
    Invoke-ResetStep 'Reset IPv6 stack' { Invoke-Netsh @('int', 'ipv6', 'reset') }
    # Explicit DHCP on physical adapters; virtual/VPN addressing belongs to its owner.
    foreach ($adapter in @($adapters | Where-Object { $_.HardwareInterface })) {
        Invoke-ResetStep "Automatic IPv4 address on $($adapter.Name)" {
            Invoke-Netsh @('interface', 'ipv4', 'set', 'address', "name=$($adapter.ifIndex)", 'source=dhcp')
        }
    }
}

# Always flush, even after a failed step. No restart of the protected DNS service.
Invoke-ResetStep 'Clear Windows DNS cache' { Clear-DnsClientCache }

if ($failures.Count -gt 0) {
    Write-Warning "Reset completed with $($failures.Count) failed step(s). Review the warnings above."
    if ($FullNetworkReset) {
        Write-Warning 'Restart Windows if network changes were applied, then retry failed steps.'
    } else {
        Write-Warning 'Review and retry the failed steps. A full network reset was not performed.'
    }
    exit 1
}
Write-Host 'All applicable reset steps completed successfully. Any skipped adapters are listed above.' -ForegroundColor Green
if ($FullNetworkReset) {
    Write-Host 'Restart Windows to finish TCP/IP and Winsock reset and acquire a fresh DHCP lease.' -ForegroundColor Yellow
} else {
    Write-Host 'Automatic DNS restored and Windows DNS cache cleared. A Windows restart is normally unnecessary.' -ForegroundColor Green
    Write-Host 'If an app still uses old DNS results, close and reopen it. Some registry changes may take effect after a future restart.'
}
exit 0
