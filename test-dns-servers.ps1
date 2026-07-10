$ErrorActionPreference = "Stop"

Write-Host "Smart DNS Server Test" -ForegroundColor Green

$configPath = Join-Path $PSScriptRoot "dnsConf.txt"
$referenceDnsServers = @("1.1.1.1", "8.8.8.8")
$httpsTimeoutSeconds = 15
$dnsQueryAttempts = 2
$backToMainMenuExitCode = 10

$domains = @(
    [PSCustomObject]@{ Label = "developer.google.com (Programming)"; Host = "developer.google.com" },
    [PSCustomObject]@{ Label = "chatgpt.com"; Host = "chatgpt.com" },
    [PSCustomObject]@{ Label = "gemini.google.com"; Host = "gemini.google.com" },
    [PSCustomObject]@{ Label = "aistudio.google.com"; Host = "aistudio.google.com" }
)

function Get-DnsEntries {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }

    $entries = @()
    foreach ($line in Get-Content $Path) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#")) {
            continue
        }

        if ($trimmedLine -notmatch "^([^=]+)=(.+)$") {
            Write-Warning "Ignoring invalid configuration line: $line"
            continue
        }

        $name = $matches[1].Trim()
        $address = $matches[2].Trim()
        $parsedAddress = $null

        if (-not [System.Net.IPAddress]::TryParse($address, [ref]$parsedAddress)) {
            Write-Warning "Ignoring invalid DNS address for ${name}: $address"
            continue
        }

        $entries += [PSCustomObject]@{
            Name = $name
            IP   = $parsedAddress.ToString()
        }
    }

    return @($entries)
}

function Exit-ToMainMenu {
    exit $backToMainMenuExitCode
}

function Get-DnsPairs {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Entries
    )

    $pairs = @()
    $groups = $Entries | Group-Object {
        if ($_.Name -match "^(.*?)(\d+)$") {
            $matches[1]
        } else {
            $_.Name
        }
    }

    foreach ($group in $groups) {
        $servers = @($group.Group | Sort-Object Name)
        if ($servers.Count -lt 2) {
            Write-Warning "DNS group '$($group.Name)' has fewer than two servers and will be skipped."
            continue
        }

        $pairs += [PSCustomObject]@{
            Name    = $group.Name
            Servers = $servers
        }
    }

    return @($pairs)
}

function Get-NormalizedDomain {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputValue
    )

    $value = $InputValue.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "No domain or URL was provided."
    }

    if ($value -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        $uri = [Uri]$value
        $hostName = $uri.DnsSafeHost
    } else {
        $hostName = $value.TrimEnd(".")
    }

    if ([string]::IsNullOrWhiteSpace($hostName) -or
        $hostName.Contains("/") -or
        $hostName.Contains("\") -or
        $hostName.Contains(":") -or
        $hostName -notmatch "^[a-zA-Z0-9.-]+$") {
        throw "Invalid domain or URL: $InputValue"
    }

    return $hostName.ToLowerInvariant()
}

function Invoke-DnsQuery {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [int]$Attempts = 2
    )

    $allAddresses = @()
    $successfulAttempts = 0
    $attemptTimes = @()
    $errors = @()

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $records = @()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $records = @(
                Resolve-DnsName `
                    -Name $Domain `
                    -Server $Server `
                    -Type A `
                    -DnsOnly `
                    -NoHostsFile `
                    -QuickTimeout `
                    -ErrorAction Stop |
                    Where-Object { $_.IPAddress }
            )
        } catch {
            $errors += $_.Exception.Message
        } finally {
            $stopwatch.Stop()
        }

        $addresses = @(
            $records |
            ForEach-Object { $_.IPAddress.ToString() } |
            Sort-Object -Unique
        )

        if ($addresses.Count -gt 0) {
            $successfulAttempts++
            $allAddresses += $addresses
            $attemptTimes += $stopwatch.Elapsed.TotalMilliseconds
        }
    }

    $uniqueAddresses = @($allAddresses | Sort-Object -Unique)
    $averageTime = $null
    if ($attemptTimes.Count -gt 0) {
        $averageTime = [math]::Round(
            ($attemptTimes | Measure-Object -Average).Average,
            2
        )
    }

    return [PSCustomObject]@{
        Domain             = $Domain
        Server             = $Server
        Addresses          = $uniqueAddresses
        SuccessfulAttempts = $successfulAttempts
        TotalAttempts      = $Attempts
        AverageTimeMs      = $averageTime
        Error              = ($errors | Select-Object -Last 1)
    }
}

function Get-ReferenceDnsResult {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string[]]$Servers
    )

    $queries = @()
    $addresses = @()

    foreach ($server in $Servers) {
        $query = Invoke-DnsQuery `
            -Domain $Domain `
            -Server $server `
            -Attempts $dnsQueryAttempts

        $queries += $query
        $addresses += $query.Addresses
    }

    return [PSCustomObject]@{
        Queries   = $queries
        Addresses = @($addresses | Sort-Object -Unique)
    }
}

function Test-HttpsEndpoint {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$Address,

        [int]$TimeoutSeconds = 15
    )

    $curlCommand = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if (-not $curlCommand) {
        return [PSCustomObject]@{
            Success      = $false
            HttpCode     = 0
            RemoteIP     = ""
            RedirectUrl  = ""
            SslVerify    = -1
            ExitCode     = -1
            Error        = "curl.exe was not found."
        }
    }

    $outputFormat = "code=%{http_code}`nremote=%{remote_ip}`nredirect=%{redirect_url}`nssl=%{ssl_verify_result}`nerror=%{errormsg}"
    $arguments = @(
        "--silent",
        "--show-error",
        "--output", "NUL",
        "--noproxy", "*",
        "--connect-timeout", [string][math]::Min(8, $TimeoutSeconds),
        "--max-time", [string]$TimeoutSeconds,
        "--resolve", ("{0}:443:{1}" -f $Domain, $Address),
        "--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36",
        "--header", "Accept-Language: en-US,en;q=0.9",
        "--write-out", $outputFormat,
        ("https://{0}/" -f $Domain)
    )

    $output = @(& $curlCommand.Source @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $values = @{}

    foreach ($line in $output) {
        $lineText = $line.ToString()
        if ($lineText -match "^([^=]+)=(.*)$") {
            $values[$matches[1]] = $matches[2]
        }
    }

    $httpCode = 0
    [void][int]::TryParse([string]$values["code"], [ref]$httpCode)

    $sslVerify = -1
    [void][int]::TryParse([string]$values["ssl"], [ref]$sslVerify)

    $errorText = [string]$values["error"]
    if ([string]::IsNullOrWhiteSpace($errorText) -and $exitCode -ne 0) {
        $firstOutputLine = $output | Select-Object -First 1
        if ($null -ne $firstOutputLine) {
            $errorText = $firstOutputLine.ToString()
        } else {
            $errorText = "HTTPS request timed out or curl.exe returned no output."
        }
    }

    return [PSCustomObject]@{
        Success      = ($exitCode -eq 0 -and $sslVerify -eq 0 -and $httpCode -gt 0)
        HttpCode     = $httpCode
        RemoteIP     = [string]$values["remote"]
        RedirectUrl  = [string]$values["redirect"]
        SslVerify    = $sslVerify
        ExitCode     = $exitCode
        Error        = $errorText
    }
}

function Get-TestClassification {
    param (
        [Parameter(Mandatory = $true)]
        [object]$DnsQuery,

        [Parameter(Mandatory = $true)]
        [string[]]$ReferenceAddresses,

        [AllowNull()]
        [object]$HttpsResult
    )

    if ($DnsQuery.Addresses.Count -eq 0) {
        return "DNS Failed"
    }

    $differentAddresses = @(
        $DnsQuery.Addresses |
        Where-Object { $ReferenceAddresses -notcontains $_ }
    )

    if ($differentAddresses.Count -eq 0) {
        return "Same as Global DNS"
    }

    if (-not $HttpsResult -or -not $HttpsResult.Success) {
        return "Different IP, HTTPS Failed"
    }

    if ($HttpsResult.HttpCode -eq 451) {
        return "Restricted"
    }

    if ($HttpsResult.HttpCode -eq 403) {
        return "Smart DNS Detected (HTTP 403)"
    }

    if ($HttpsResult.HttpCode -ge 200 -and $HttpsResult.HttpCode -lt 400) {
        return "Working"
    }

    if ($HttpsResult.HttpCode -ge 400 -and $HttpsResult.HttpCode -lt 500) {
        return "Reachable, Needs Review"
    }

    if ($HttpsResult.HttpCode -ge 500) {
        return "Service Error"
    }

    return "Uncertain"
}

function Test-SmartDnsServer {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$PairName,

        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$ServerAddress,

        [Parameter(Mandatory = $true)]
        [string[]]$ReferenceAddresses
    )

    Write-Host ("  Querying {0} ({1})..." -f $ServerName, $ServerAddress) -ForegroundColor Cyan

    $dnsQuery = Invoke-DnsQuery `
        -Domain $Domain `
        -Server $ServerAddress `
        -Attempts $dnsQueryAttempts

    $differentAddresses = @(
        $dnsQuery.Addresses |
        Where-Object { $ReferenceAddresses -notcontains $_ }
    )

    $httpsResult = $null
    $testedAddress = ""

    if ($differentAddresses.Count -gt 0) {
        foreach ($address in $differentAddresses) {
            try {
                $currentHttpsResult = Test-HttpsEndpoint `
                    -Domain $Domain `
                    -Address $address `
                    -TimeoutSeconds $httpsTimeoutSeconds
            } catch {
                $currentHttpsResult = [PSCustomObject]@{
                    Success      = $false
                    HttpCode     = 0
                    RemoteIP     = ""
                    RedirectUrl  = ""
                    SslVerify    = -1
                    ExitCode     = -1
                    Error        = $_.Exception.Message
                }
            }

            if (-not $httpsResult -or $currentHttpsResult.Success) {
                $httpsResult = $currentHttpsResult
                $testedAddress = $address
            }

            if ($currentHttpsResult.Success) {
                break
            }
        }
    }

    $classification = Get-TestClassification `
        -DnsQuery $dnsQuery `
        -ReferenceAddresses $ReferenceAddresses `
        -HttpsResult $httpsResult

    $httpCode = ""
    $httpsError = ""
    if ($httpsResult) {
        if ($httpsResult.HttpCode -gt 0) {
            $httpCode = [string]$httpsResult.HttpCode
        }
        $httpsError = $httpsResult.Error
    }

    return [PSCustomObject]@{
        Domain          = $Domain
        Pair            = $PairName
        Server          = $ServerName
        DnsAddress      = $ServerAddress
        ResolvedIPs     = ($dnsQuery.Addresses -join ", ")
        DifferentIPs    = ($differentAddresses -join ", ")
        TestedIP        = $testedAddress
        Attempts        = ("{0}/{1}" -f $dnsQuery.SuccessfulAttempts, $dnsQuery.TotalAttempts)
        AverageTimeMs   = $dnsQuery.AverageTimeMs
        HttpCode        = $httpCode
        Status          = $classification
        DnsError        = $dnsQuery.Error
        HttpsError      = $httpsError
    }
}

function Get-StatusScore {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    switch ($Status) {
        "Working" { return 100 }
        "Reachable, Needs Review" { return 70 }
        "Smart DNS Detected (HTTP 403)" { return 85 }
        "Service Error" { return 45 }
        "Uncertain" { return 35 }
        "Different IP, HTTPS Failed" { return 20 }
        "Restricted" { return 10 }
        "Same as Global DNS" { return 5 }
        "DNS Failed" { return 0 }
        default { return 0 }
    }
}

try {
    $dnsEntries = Get-DnsEntries -Path $configPath
    $dnsPairs = Get-DnsPairs -Entries $dnsEntries

    if ($dnsPairs.Count -eq 0) {
        throw "No valid DNS pairs were found in dnsConf.txt."
    }

    Write-Host "`nSelect a domain to test:"
    for ($index = 0; $index -lt $domains.Count; $index++) {
        Write-Host ("{0}. {1}" -f ($index + 1), $domains[$index].Label)
    }
    Write-Host ("{0}. Test all listed domains" -f ($domains.Count + 1))
    Write-Host ("{0}. Enter a URL or domain" -f ($domains.Count + 2))
    Write-Host "0. Back to main menu"

    $domainChoice = Read-Host "Enter your choice"
    $domainIndex = 0

    if (-not [int]::TryParse($domainChoice, [ref]$domainIndex)) {
        throw "Invalid selection."
    }

    if ($domainIndex -eq 0) {
        Exit-ToMainMenu
    } elseif ($domainIndex -ge 1 -and $domainIndex -le $domains.Count) {
        $selectedDomains = @($domains[$domainIndex - 1].Host)
    } elseif ($domainIndex -eq ($domains.Count + 1)) {
        $selectedDomains = @($domains | ForEach-Object { $_.Host })
    } elseif ($domainIndex -eq ($domains.Count + 2)) {
        $customDomain = Read-Host "Enter a URL or domain (0 = Back to main menu)"
        if ($customDomain.Trim() -eq "0") {
            Exit-ToMainMenu
        }
        $selectedDomains = @(Get-NormalizedDomain -InputValue $customDomain)
    } else {
        throw "Selection out of range."
    }

    Write-Host "`nTest scope:"
    Write-Host "1. Test DNS servers currently configured in Windows"
    Write-Host "2. Test every DNS server from dnsConf.txt"
    Write-Host "3. Test one DNS pair from dnsConf.txt"
    Write-Host "0. Back to main menu"
    $scopeChoice = Read-Host "Enter your choice"
    $scopeIndex = 0

    if (-not [int]::TryParse($scopeChoice, [ref]$scopeIndex)) {
        throw "Invalid selection."
    }

    if ($scopeIndex -eq 0) {
        Exit-ToMainMenu
    } elseif ($scopeIndex -eq 1) {
        $currentAddresses = @(
            Get-DnsClientServerAddress -AddressFamily IPv4 |
            Where-Object { $_.ServerAddresses } |
            ForEach-Object { $_.ServerAddresses } |
            Sort-Object -Unique
        )

        if ($currentAddresses.Count -eq 0) {
            throw "No IPv4 DNS servers are currently configured in Windows."
        }

        $testPairs = @(
            [PSCustomObject]@{
                Name    = "Current"
                Servers = @(
                    for ($index = 0; $index -lt $currentAddresses.Count; $index++) {
                        [PSCustomObject]@{
                            Name = "Current$($index + 1)"
                            IP   = $currentAddresses[$index]
                        }
                    }
                )
            }
        )
    } elseif ($scopeIndex -eq 2) {
        $testPairs = $dnsPairs
    } elseif ($scopeIndex -eq 3) {
        Write-Host "`nSelect a DNS pair:"
        for ($index = 0; $index -lt $dnsPairs.Count; $index++) {
            $serverText = @($dnsPairs[$index].Servers | ForEach-Object { $_.IP }) -join ", "
            Write-Host ("{0}. {1} ({2})" -f ($index + 1), $dnsPairs[$index].Name, $serverText)
        }
        Write-Host "0. Back to main menu"

        $pairChoice = Read-Host "Enter your choice"
        $pairIndex = 0
        if (-not [int]::TryParse($pairChoice, [ref]$pairIndex)) {
            throw "Invalid DNS pair selection."
        }

        if ($pairIndex -eq 0) {
            Exit-ToMainMenu
        }

        $pairIndex--
        if ($pairIndex -lt 0 -or $pairIndex -ge $dnsPairs.Count) {
            throw "DNS pair selection out of range."
        }

        $testPairs = @($dnsPairs[$pairIndex])
    } else {
        throw "Selection out of range."
    }

    $summary = @()

    foreach ($domain in $selectedDomains) {
        Write-Host ("`nTesting domain: {0}" -f $domain) -ForegroundColor Green
        Write-Host ("Reference DNS servers: {0}" -f ($referenceDnsServers -join ", "))

        $referenceResult = Get-ReferenceDnsResult `
            -Domain $domain `
            -Servers $referenceDnsServers

        foreach ($query in $referenceResult.Queries) {
            $referenceText = if ($query.Addresses.Count -gt 0) {
                $query.Addresses -join ", "
            } else {
                "No response"
            }

            Write-Host ("  {0}: {1}" -f $query.Server, $referenceText)
        }

        if ($referenceResult.Addresses.Count -eq 0) {
            Write-Warning "Both global reference DNS servers failed for $domain. This domain is skipped."
            continue
        }

        Write-Host ("Global reference IP set: {0}" -f ($referenceResult.Addresses -join ", ")) -ForegroundColor Yellow

        foreach ($pair in $testPairs) {
            Write-Host ("`nTesting DNS pair: {0}" -f $pair.Name) -ForegroundColor Magenta

            foreach ($server in $pair.Servers) {
                try {
                    $result = Test-SmartDnsServer `
                        -Domain $domain `
                        -PairName $pair.Name `
                        -ServerName $server.Name `
                        -ServerAddress $server.IP `
                        -ReferenceAddresses $referenceResult.Addresses
                } catch {
                    $result = [PSCustomObject]@{
                        Domain          = $domain
                        Pair            = $pair.Name
                        Server          = $server.Name
                        DnsAddress      = $server.IP
                        ResolvedIPs     = ""
                        DifferentIPs    = ""
                        TestedIP        = ""
                        Attempts        = "0/$dnsQueryAttempts"
                        AverageTimeMs   = $null
                        HttpCode        = ""
                        Status          = "Test Error"
                        DnsError        = $_.Exception.Message
                        HttpsError      = ""
                    }
                }

                $summary += $result

                $statusColor = switch ($result.Status) {
                    "Working" { "Green" }
                    "Same as Global DNS" { "Yellow" }
                    "DNS Failed" { "Red" }
                    "Different IP, HTTPS Failed" { "Red" }
                    default { "Yellow" }
                }

                Write-Host ("  Result: {0}" -f $result.Status) -ForegroundColor $statusColor
            }
        }
    }

    if ($summary.Count -eq 0) {
        throw "No DNS test results were produced."
    }

    Write-Host "`nDetailed Test Summary" -ForegroundColor Green
    $detailText = $summary |
        Select-Object Domain, Pair, Server, DnsAddress, Attempts, AverageTimeMs, HttpCode, Status |
        Format-Table -AutoSize |
        Out-String
    Write-Host $detailText.Trim()

    $ranking = @(
        $summary |
        Group-Object Pair |
        ForEach-Object {
            $items = @($_.Group)
            $scores = @($items | ForEach-Object { Get-StatusScore -Status $_.Status })
            $workingCount = @($items | Where-Object { $_.Status -eq "Working" }).Count
            $detectedCount = @(
                $items |
                Where-Object {
                    $_.Status -eq "Working" -or
                    $_.Status -eq "Smart DNS Detected (HTTP 403)"
                }
            ).Count
            $sameAsGlobalCount = @($items | Where-Object { $_.Status -eq "Same as Global DNS" }).Count
            $dnsFailureCount = @($items | Where-Object { $_.Status -eq "DNS Failed" }).Count
            $timings = @($items | Where-Object { $null -ne $_.AverageTimeMs } | ForEach-Object { $_.AverageTimeMs })
            $averageTime = $null

            if ($timings.Count -gt 0) {
                $averageTime = [math]::Round(
                    ($timings | Measure-Object -Average).Average,
                    2
                )
            }

            [PSCustomObject]@{
                Pair              = $_.Name
                Score             = [math]::Round(($scores | Measure-Object -Average).Average, 1)
                Detected          = ("{0}/{1}" -f $detectedCount, $items.Count)
                FullHttpSuccess   = $workingCount
                SameAsGlobal      = $sameAsGlobalCount
                DnsFailures       = $dnsFailureCount
                AverageDnsTimeMs  = $averageTime
            }
        } |
        Sort-Object `
            @{ Expression = "Score"; Descending = $true },
            @{ Expression = "AverageDnsTimeMs"; Descending = $false }
    )

    Write-Host "`nDNS Pair Ranking" -ForegroundColor Green
    $rankingText = $ranking |
        Format-Table Pair, Score, Detected, FullHttpSuccess, SameAsGlobal, DnsFailures, AverageDnsTimeMs -AutoSize |
        Out-String
    Write-Host $rankingText.Trim()

    Write-Host "`nMeaning of important statuses:" -ForegroundColor Cyan
    Write-Host "  Working: IP differs from global DNS and HTTPS succeeds with the original host/SNI."
    Write-Host "  Same as Global DNS: All returned IPs match 1.1.1.1/8.8.8.8; this DNS probably does not bypass the restriction."
    Write-Host "  Smart DNS Detected (HTTP 403): IP differs and HTTPS/TLS succeeds; HTTP 403 may be an anti-bot response."
    Write-Host "  Different IP, HTTPS Failed: The DNS returned a different IP, but direct HTTPS validation failed."
} catch {
    Write-Host ("Test failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
