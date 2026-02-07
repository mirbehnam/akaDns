# Require administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Break
}

# Install HttpListener if not already available
if (-not (Get-Module -ListAvailable -Name HttpListener)) {
    Install-Module -Name HttpListener -Force -Scope CurrentUser
}

$port = 8080
$url = "http://localhost:$port/"
$htmlPath = Join-Path $PSScriptRoot "dns-gui.html"

# Create HTTP Server
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()

Write-Host "DNS Configuration GUI is running at $url"
Start-Process $url

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        if ($request.HttpMethod -eq 'GET') {
            if ($request.Url.LocalPath -eq '/current-dns') {
                $allDNSServers = Get-DnsClientServerAddress -AddressFamily IPv4 | 
                    Where-Object {$_.AddressFamily -eq 2 -and $_.ServerAddresses} |
                    Select-Object -ExpandProperty ServerAddresses

                # Get all unique DNS servers across all interfaces
                $uniqueDNSServers = $allDNSServers | Select-Object -Unique

                # Take up to 3 servers
                $dnsArray = @($uniqueDNSServers | Select-Object -First 3)
                
                $jsonResponse = @{
                    dns = $dnsArray
                } | ConvertTo-Json
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.LocalPath -eq '/dns-config') {
                $configPath = Join-Path $PSScriptRoot "dnsConf.txt"
                $dnsServers = @()
                
                if (Test-Path $configPath) {
                    Get-Content $configPath | ForEach-Object {
                        if ($_ -match "(.+)=(.+)") {
                            $dnsServers += @{
                                name = $matches[1]
                                ip = $matches[2]
                            }
                        }
                    }
                }
                
                $jsonResponse = $dnsServers | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.ContentType = "text/html; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
        }
        elseif ($request.HttpMethod -eq 'POST' -and $request.Url.LocalPath -eq '/set-dns') {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $dnsServers = ($body | ConvertFrom-Json).dns

            try {
                Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
                    Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $dnsServers
                }
                
                ipconfig /flushdns
                
                $jsonResponse = @{
                    success = $true
                    message = "DNS settings updated successfully!"
                } | ConvertTo-Json
                
            } catch {
                $jsonResponse = @{
                    success = $false
                    message = "Error: $($_.Exception.Message)"
                } | ConvertTo-Json
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($request.HttpMethod -eq 'POST' -and $request.Url.LocalPath -eq '/restore-dns') {
            try {
                Get-NetAdapter | ForEach-Object {
                    Enable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6
                }
                Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
                    Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses
                }
                Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDOH" -ErrorAction SilentlyContinue
                ipconfig /flushdns
                
                $jsonResponse = @{
                    success = $true
                    message = "DNS settings have been restored to default configuration!"
                } | ConvertTo-Json
                
            } catch {
                $jsonResponse = @{
                    success = $false
                    message = "Error: $($_.Exception.Message)"
                } | ConvertTo-Json
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        $response.Close()
    }
}
finally {
    $listener.Stop()
}
