# Require administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Break
}

# Enable IPv6 on all network adapters
Get-NetAdapter | ForEach-Object {
    Enable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6
}

# Reset DNS servers to DHCP for all network adapters
Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses
}

# Enable DNS over HTTPS (restore to default)
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDOH" -ErrorAction SilentlyContinue

# Reset Random Name Resolution (restore to default)
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "QueryIpMatching" -ErrorAction SilentlyContinue

# Clear DNS cache
ipconfig /flushdns

# Restart DNS Client service
Restart-Service -Name Dnscache -Force

Write-Host "DNS settings have been restored to default configuration!" -ForegroundColor Green
Write-Host "Please restart your computer to ensure all changes take effect." -ForegroundColor Yellow
