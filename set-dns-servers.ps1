# Require administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Break
}

# Read DNS Servers from configuration file
$configPath = Join-Path $PSScriptRoot "dnsConf.txt"

if (-not (Test-Path $configPath)) {
    Write-Host "Configuration file not found: $configPath" -ForegroundColor Red
    exit 1
}

$dnsEntries = @()
Get-Content $configPath | ForEach-Object {
    if ($_ -match "(.+)=(.+)") {
        $dnsEntries += [PSCustomObject]@{
            Name = $matches[1].Trim()
            IP   = $matches[2].Trim()
        }
    }
}

if ($dnsEntries.Count -eq 0) {
    Write-Host "No DNS servers found in configuration file" -ForegroundColor Red
    exit 1
}

$dnsPairs = $dnsEntries |
    Group-Object {
        if ($_.Name -match "^(.*?)(\d+)$") { $matches[1] } else { $_.Name }
    } |
    ForEach-Object {
        $pair = $_.Group | Sort-Object Name
        if ($pair.Count -ge 2) {
            [PSCustomObject]@{
                Name      = $_.Name
                Servers   = @($pair | ForEach-Object { $_.IP })
                RawNames  = @($pair | ForEach-Object { $_.Name })
            }
        }
    } | Where-Object { $_ -ne $null }

if ($dnsPairs.Count -eq 0) {
    Write-Host "No DNS pairs found in configuration file" -ForegroundColor Red
    exit 1
}

Write-Host "Select a DNS configuration pair:"
for ($i = 0; $i -lt $dnsPairs.Count; $i++) {
    $pair = $dnsPairs[$i]
    Write-Host ("{0}. {1} ({2})" -f ($i + 1), $pair.Name, ($pair.Servers -join ", "))
}

$selection = Read-Host "Enter the DNS pair number"
$selectedIndex = 0
if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

$selectedIndex = $selectedIndex - 1
if ($selectedIndex -lt 0 -or $selectedIndex -ge $dnsPairs.Count) {
    Write-Host "Selection out of range." -ForegroundColor Red
    exit 1
}

$dnsServers = $dnsPairs[$selectedIndex].Servers

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
