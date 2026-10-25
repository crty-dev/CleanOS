param(
    [Parameter(Mandatory = $true)][string]$Owner,
    [string]$Repository = 'CleanOS'
)
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'CleanOS.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw
$content = $content.Replace('https://github.com/OWNER/CleanOS', "https://github.com/$Owner/$Repository")
$content = $content.Replace('https://raw.githubusercontent.com/OWNER/CleanOS/main/CleanOS.ps1', "https://raw.githubusercontent.com/$Owner/$Repository/main/CleanOS.ps1")
Set-Content -LiteralPath $scriptPath -Value $content -Encoding UTF8
Write-Host "Repository URLs updated in $scriptPath. Review the diff before committing." -ForegroundColor Green
