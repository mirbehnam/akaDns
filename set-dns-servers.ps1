# Require administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Break
}

# Read DNS Servers from configuration file
$configPath = Join-Path $PSScriptRoot "dnsConf.txt"
$dnsServers = @()

if (Test-Path $configPath) {
    # Read all DNS servers without filtering
    Get-Content $configPath | ForEach-Object {
        if ($_ -match "(.+)=(.+)") {
            $dnsServers += $matches[2]  # Just add the IP address
        }
    }

    # Limit to first 3 servers for better performance
    $dnsServers = $dnsServers | Select-Object -First 3
} else {
    Write-Host "Configuration file not found: $configPath" -ForegroundColor Red
    exit 1
}

if ($dnsServers.Count -eq 0) {
    Write-Host "No DNS servers found in configuration file" -ForegroundColor Red
    exit 1
}

# Disable IPv6 on all network adapters
Get-NetAdapter | ForEach-Object {
    Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6
}

# Set DNS servers for all network adapters
Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $dnsServers
}

# Disable DNS over HTTPS
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDOH" -Value 0

# Disable Random Name Resolution
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "QueryIpMatching" -Value 0

# Clear DNS cache
ipconfig /flushdns

Write-Host "DNS configuration completed successfully!"
Write-Host "Please test your connection and DNS settings."
