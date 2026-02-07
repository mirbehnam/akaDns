# Check current DNS settings
Write-Host "Current DNS Settings:" -ForegroundColor Green
Get-DnsClientServerAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, ServerAddresses

# Test DNS resolution
Write-Host "`nTesting DNS Resolution:" -ForegroundColor Green
Resolve-DnsName www.google.com | Format-Table Name, IPAddress

# Check for IPv6
Write-Host "`nChecking IPv6 Status:" -ForegroundColor Green
Get-NetAdapterBinding -ComponentID ms_tcpip6 | Format-Table Name, Enabled

# Check DoH Status
Write-Host "`nChecking DoH Status:" -ForegroundColor Green
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDOH" | Format-Table EnableAutoDOH
