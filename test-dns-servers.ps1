Write-Host "DNS Server Test" -ForegroundColor Green

$configPath = Join-Path $PSScriptRoot "dnsConf.txt"
$dnsPairs = @()

if (Test-Path $configPath) {
    $dnsEntries = @()
    Get-Content $configPath | ForEach-Object {
        if ($_ -match "(.+)=(.+)") {
            $dnsEntries += [PSCustomObject]@{
                Name = $matches[1].Trim()
                IP   = $matches[2].Trim()
            }
        }
    }

    $dnsPairs = $dnsEntries |
        Group-Object {
            if ($_.Name -match "^(.*?)(\d+)$") { $matches[1] } else { $_.Name }
        } |
        ForEach-Object {
            $pair = $_.Group | Sort-Object Name
            if ($pair.Count -ge 2) {
                [PSCustomObject]@{
                    Name    = $_.Name
                    Servers = @($pair[0].IP, $pair[1].IP)
                }
            }
        } | Where-Object { $_ -ne $null }
}

$domains = @(
    [PSCustomObject]@{ Label = "ig developer.google.com (for programmer)"; Host = "developer.google.com" },
    [PSCustomObject]@{ Label = "chatgpt.com"; Host = "chatgpt.com" },
    [PSCustomObject]@{ Label = "gemini.google.com"; Host = "gemini.google.com" },
    [PSCustomObject]@{ Label = "aistudio.google.com"; Host = "aistudio.google.com" }
)

Write-Host "`nSelect a domain to test:"
for ($i = 0; $i -lt $domains.Count; $i++) {
    Write-Host ("{0}. {1}" -f ($i + 1), $domains[$i].Label)
}
Write-Host ("{0}. Test all listed domains" -f ($domains.Count + 1))
Write-Host ("{0}. Or enter yourself" -f ($domains.Count + 2))

$domainChoice = Read-Host "Enter your choice"
$domainIndex = 0
$selectedDomains = @()

if (-not [int]::TryParse($domainChoice, [ref]$domainIndex)) {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

if ($domainIndex -ge 1 -and $domainIndex -le $domains.Count) {
    $selectedDomains = @($domains[$domainIndex - 1].Host)
} elseif ($domainIndex -eq ($domains.Count + 1)) {
    $selectedDomains = $domains | ForEach-Object { $_.Host }
} elseif ($domainIndex -eq ($domains.Count + 2)) {
    $inputUrl = Read-Host "Enter a URL or domain"
    if ([string]::IsNullOrWhiteSpace($inputUrl)) {
        Write-Host "No input provided." -ForegroundColor Red
        exit 1
    }

    try {
        if ($inputUrl -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
            $uri = [Uri]$inputUrl
            $selectedDomains = @($uri.Host)
        } else {
            $selectedDomains = @($inputUrl.Trim())
        }
    } catch {
        Write-Host "Invalid input. Please enter a valid URL or domain." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Selection out of range." -ForegroundColor Red
    exit 1
}

Write-Host "`nTest scope:"
Write-Host "1. Test current DNS settings"
Write-Host "2. Test all DNS pairs from dnsConf.txt"
$scopeChoice = Read-Host "Enter your choice"
$scopeIndex = 0

if (-not [int]::TryParse($scopeChoice, [ref]$scopeIndex)) {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

$currentServers = @()
if ($scopeIndex -eq 1) {
    $currentServers = (Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses | Where-Object { $_ }
    if ($currentServers.Count -eq 0) {
        Write-Host "No current DNS servers found." -ForegroundColor Red
        exit 1
    }
}

function Assert-Administrator {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator"
    )
    if (-not $isAdmin) {
        Write-Warning "Please run this script as Administrator!"
        exit 1
    }
}

function Set-CustomDnsServers {
    param (
        [string[]]$Servers
    )

    Get-NetAdapter | ForEach-Object {
        Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    }

    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $Servers
    }

    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDOH" -Value 0
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "QueryIpMatching" -Value 0
    ipconfig /flushdns | Out-Null
}

function Restore-DnsServers {
    param (
        [hashtable]$OriginalServers
    )

    foreach ($entry in $OriginalServers.GetEnumerator()) {
        if ($entry.Value.Reset) {
            Set-DnsClientServerAddress -InterfaceIndex $entry.Key -ResetServerAddresses
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $entry.Key -ServerAddresses $entry.Value.Servers
        }
    }

    ipconfig /flushdns | Out-Null
}

function Get-DnsPairName {
    param (
        [string[]]$Servers,
        [object[]]$Pairs
    )

    foreach ($pair in $Pairs) {
        $intersection = $Servers | Where-Object { $pair.Servers -contains $_ }
        if ($intersection.Count -gt 0) {
            return $pair.Name
        }
    }

    return "Unknown"
}

function Test-DomainWithServers {
    param (
        [string]$Domain,
        [string[]]$Servers,
        [string]$DnsName,
        [switch]$UseSystemDns
    )

    Write-Host "`nResolving DNS for: $Domain" -ForegroundColor Green
    $success = $false
    $results = @()
    $elapsed = 0
    $titleStatus = "Not Checked"
    $tcpStatus = "Failed"

    if ($UseSystemDns) {
        $resolveTime = Measure-Command {
            $results = Resolve-DnsName -Name $Domain -ErrorAction SilentlyContinue
        }
        if ($results) {
            $success = $true
            $elapsed = $resolveTime.TotalMilliseconds
        }
    } else {
        foreach ($server in $Servers) {
            $resolveTime = Measure-Command {
                $results = Resolve-DnsName -Name $Domain -Server $server -ErrorAction SilentlyContinue
            }
            if ($results) {
                $success = $true
                $elapsed = $resolveTime.TotalMilliseconds
                break
            }
        }
    }

    if (-not $success) {
        Write-Host "DNS resolution failed for $Domain" -ForegroundColor Red
        return
    }

    Write-Host ("DNS resolution successful via {0}." -f $DnsName) -ForegroundColor Green
    $resultText = $results |
        Where-Object { $_.IPAddress } |
        Select-Object Name, IPAddress |
        Format-Table -AutoSize |
        Out-String
    Write-Host $resultText.Trim()
    Write-Host ("DNS lookup completed in {0} ms" -f [math]::Round($elapsed, 2))

    Write-Host "`nTesting TCP connectivity on port 443..." -ForegroundColor Green
    $connection = Test-NetConnection -ComputerName $Domain -Port 443 -WarningAction SilentlyContinue

    if ($connection.TcpTestSucceeded) {
        Write-Host "TCP connectivity successful." -ForegroundColor Green
        $tcpStatus = "Success"
    } else {
        Write-Host "TCP connectivity failed." -ForegroundColor Yellow
    }

    Write-Host "`nChecking page title for 403..." -ForegroundColor Green
    try {
        $response = Invoke-WebRequest -Uri ("https://{0}" -f $Domain) -UseBasicParsing -TimeoutSec 10 -Headers @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            "Accept-Language" = "en-US,en;q=0.9"
        }
        $finalHost = $response.BaseResponse.ResponseUri.Host
        if ($finalHost -and $finalHost -ne $Domain) {
            Write-Host ("Request redirected to {0}." -f $finalHost) -ForegroundColor Yellow
            $titleStatus = ("Redirected: {0}" -f $finalHost)
            return [PSCustomObject]@{
                Domain       = $Domain
                DnsName      = $DnsName
                ResolveTime  = [math]::Round($elapsed, 2)
                TcpStatus    = $tcpStatus
                TitleStatus  = $titleStatus
            }
        }
        if ($response.Content -match "<title>\s*Error 403") {
            Write-Host "Title indicates 403 Forbidden." -ForegroundColor Red
            $titleStatus = "403 Forbidden"
        } else {
            $titleMatch = [regex]::Match($response.Content, "<title>\s*(.*?)\s*</title>", "IgnoreCase")
            if ($titleMatch.Success) {
                $titleText = $titleMatch.Groups[1].Value.Trim()
                if ($titleText -match "Before you continue") {
                    Write-Host "Title indicates consent/verification page." -ForegroundColor Yellow
                    $titleStatus = "Consent page"
                } else {
                    Write-Host ("Title check passed. Title: {0}" -f $titleText) -ForegroundColor Green
                    $titleStatus = $titleText
                }
            } else {
                Write-Host "Title check passed." -ForegroundColor Green
                $titleStatus = "OK"
            }
        }
    } catch {
        Write-Host "Unable to fetch page title." -ForegroundColor Yellow
        $titleStatus = "Unavailable"
    }

    return [PSCustomObject]@{
        Domain       = $Domain
        DnsName      = $DnsName
        ResolveTime  = [math]::Round($elapsed, 2)
        TcpStatus    = $tcpStatus
        TitleStatus  = $titleStatus
    }
}

$summary = @()
foreach ($domain in $selectedDomains) {
    if ($scopeIndex -eq 1) {
        $dnsName = Get-DnsPairName -Servers $currentServers -Pairs $dnsPairs
        $summary += Test-DomainWithServers -Domain $domain -Servers $currentServers -DnsName $dnsName
    } elseif ($scopeIndex -eq 2) {
        if ($dnsPairs.Count -eq 0) {
            Write-Host "No DNS pairs found in configuration file." -ForegroundColor Red
            exit 1
        }

        Assert-Administrator

        $activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        $originalDnsMap = @{}
        foreach ($adapter in $activeAdapters) {
            $current = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses
            $originalDnsMap[$adapter.ifIndex] = [PSCustomObject]@{
                Servers = $current
                Reset   = ($current.Count -eq 0)
            }
        }

        foreach ($pair in $dnsPairs) {
            Write-Host ("`nApplying DNS pair {0} before testing..." -f $pair.Name) -ForegroundColor Cyan
            Set-CustomDnsServers -Servers $pair.Servers
            $summary += Test-DomainWithServers -Domain $domain -Servers $pair.Servers -DnsName $pair.Name -UseSystemDns
        }

        Restore-DnsServers -OriginalServers $originalDnsMap
    } else {
        Write-Host "Selection out of range." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nTest Summary" -ForegroundColor Green
$summaryText = $summary |
    Format-Table Domain, DnsName, ResolveTime, TcpStatus, TitleStatus -AutoSize |
    Out-String
Write-Host $summaryText.Trim()
