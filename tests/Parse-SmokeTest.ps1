$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'CleanOS.ps1'
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error ($_.ToString()) }
    exit 1
}
$source = Get-Content -LiteralPath $scriptPath -Raw
$required = @(
    '$script:CleanOSVersion',
    'function Show-PerformanceMenu',
    'function Show-DebloatMenu',
    'function Show-PrivacyMenu',
    'function Show-WindowsUpdateMenu',
    'function Show-ServiceManager',
    'function Show-RollbackMenu',
    'WinDefend',
    'wuauserv',
    'MpsSvc',
    'Dhcp'
)
foreach ($needle in $required) {
    if ($source -notlike ('*' + $needle + '*')) { throw "Required source marker missing: $needle" }
}
Write-Host 'CleanOS parse smoke test passed.' -ForegroundColor Green
