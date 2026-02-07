Write-Host "DNS Server Test" -ForegroundColor Green

$inputUrl = Read-Host "Enter a URL or domain to test (default: https://www.google.com)"
if ([string]::IsNullOrWhiteSpace($inputUrl)) {
    $inputUrl = "https://www.google.com"
}

try {
    if ($inputUrl -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        $uri = [Uri]$inputUrl
        $hostName = $uri.Host
    } else {
        $hostName = $inputUrl.Trim()
    }
} catch {
    Write-Host "Invalid input. Please enter a valid URL or domain." -ForegroundColor Red
    exit 1
}

Write-Host "`nResolving DNS for: $hostName" -ForegroundColor Green
$resolveTime = Measure-Command {
    $dnsResults = Resolve-DnsName -Name $hostName -ErrorAction SilentlyContinue
}

if (-not $dnsResults) {
    Write-Host "DNS resolution failed for $hostName" -ForegroundColor Red
    exit 1
}

$dnsResults | Where-Object { $_.IPAddress } | Select-Object Name, IPAddress | Format-Table -AutoSize
Write-Host ("DNS lookup completed in {0} ms" -f [math]::Round($resolveTime.TotalMilliseconds, 2))

Write-Host "`nTesting TCP connectivity on port 443..." -ForegroundColor Green
$connection = Test-NetConnection -ComputerName $hostName -Port 443 -WarningAction SilentlyContinue

if ($connection.TcpTestSucceeded) {
    Write-Host "TCP connectivity successful." -ForegroundColor Green
} else {
    Write-Host "TCP connectivity failed." -ForegroundColor Yellow
}
