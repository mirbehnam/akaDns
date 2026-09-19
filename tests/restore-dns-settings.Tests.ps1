# Run with powershell -NoProfile -File .\tests\restore-dns-settings.Tests.ps1
# Extract only the function under test; never run the administrator/network reset code.
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$source = Join-Path $PSScriptRoot '..\restore-dns-settings.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Restore-AdapterDns'
}, $true)
if (-not $functionAst) { throw 'Restore-AdapterDns not found.' }
. ([scriptblock]::Create($functionAst.Extent.Text))

function Get-DnsClientServerAddress {
    [CmdletBinding()] param()
    if ($script:discoveryFailure) { throw 'Discovery failed' }
    $script:clients
}
function Set-DnsClientServerAddress {
    [CmdletBinding()] param($InputObject, [switch]$ResetServerAddresses)
    if ($script:resetFailure) { throw 'Reset denied' }
    if (-not $ResetServerAddresses) { throw 'Expected automatic DNS reset.' }
    $script:changed.Add($InputObject)
}

$script:clients = @(
    [pscustomobject]@{ InterfaceIndex = 7; AddressFamily = 2 },
    [pscustomobject]@{ InterfaceIndex = 7; AddressFamily = 23 },
    [pscustomobject]@{ InterfaceIndex = 8; AddressFamily = 2 }
)
$script:changed = New-Object 'System.Collections.Generic.List[object]'
$missing = [pscustomobject]@{ Name = 'VPN'; ifIndex = 23 }
$present = [pscustomobject]@{ Name = 'Disconnected Ethernet'; ifIndex = 7 }
$output = Restore-AdapterDns $missing 6>&1 | Out-String
if ($script:changed.Count -ne 0 -or $output -notmatch '\[SKIP\]' -or $output -match '\[OK\]') {
    throw 'Missing DNS instances must be skipped without claiming success.'
}
Restore-AdapterDns $present
if ($script:changed.Count -ne 2 -or @($script:changed | Where-Object InterfaceIndex -ne 7).Count) {
    throw 'Only both DNS families of the requested adapter should be reset.'
}
foreach ($failureType in @('discovery', 'reset')) {
    $script:discoveryFailure = $failureType -eq 'discovery'
    $script:resetFailure = $failureType -eq 'reset'
    $caught = $false
    try { Restore-AdapterDns $present } catch { $caught = $true }
    if (-not $caught) { throw "$failureType error was hidden." }
}
Write-Host 'PASS: absent DNS instances, disconnected adapter, both DNS families, unrelated adapter exclusion, discovery/reset failures.'
