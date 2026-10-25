param(
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'
$script:CleanOSName = 'CleanOS'
$script:CleanOSVersion = '0.1.0'
# Before publishing, replace OWNER/REPO with the real GitHub repository.
$script:CleanOSRepository = 'https://github.com/OWNER/CleanOS'
$script:CleanOSRawScriptUrl = 'https://raw.githubusercontent.com/OWNER/CleanOS/main/CleanOS.ps1'
$script:CleanOSLocalScriptPath = $null
if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Split-Path -Leaf $PSCommandPath) -ieq 'CleanOS.ps1') { $script:CleanOSLocalScriptPath = $PSCommandPath }
$script:CleanOSNoColor = [bool]$NoColor
$script:CleanOSIsWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$script:CleanOSIsAdmin = $false
$script:CurrentTransaction = $null
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'CleanOS'
$script:HistoryDir = Join-Path $script:DataRoot 'history'
$script:LogDir = Join-Path $script:DataRoot 'logs'
$script:LogPath = Join-Path $script:LogDir 'cleanos.jsonl'

$script:OptionalAppAllowList = @(
    'Clipchamp.Clipchamp',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.People',
    'Microsoft.Todos',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.YourPhone'
)

# Protected Windows security, update, networking, core, search and package services.
# CleanOS will not change startup settings for these services.
$script:ProtectedServiceNames = @(
    'AppInfo', 'AppXSvc', 'BFE', 'BITS', 'BrokerInfrastructure', 'CDPSvc',
    'ClipSVC', 'CryptSvc', 'DcomLaunch', 'Dhcp', 'DiagTrack', 'Dnscache',
    'DoSvc', 'EventLog', 'gpsvc', 'IKEEXT', 'InstallService', 'LanmanServer',
    'LanmanWorkstation', 'LicenseManager', 'LSM', 'MpsSvc', 'MSDTC', 'msiserver',
    'NlaSvc', 'netprofm', 'Netman', 'nsi', 'PlugPlay', 'Power', 'ProfSvc',
    'RpcEptMapper', 'RpcSs', 'SamSs', 'Schedule', 'SecurityHealthService',
    'SENS', 'StateRepository', 'StorSvc', 'TrustedInstaller', 'UsoSvc',
    'W32Time', 'WaaSMedicSvc', 'Wcmsvc', 'WdNisSvc', 'WebClient', 'WlanSvc',
    'WinDefend', 'WinHttpAutoProxySvc', 'Winmgmt', 'WinRM', 'WSearch',
    'wuauserv', 'WdFilter', 'WdBoot', 'Sense', 'TermService', 'UserManager',
    'ShellHWDetection', 'Themes', 'AudioEndpointBuilder', 'Audiosrv'
)

function Write-CleanText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    if ($script:CleanOSNoColor) { Write-Host $Text } else { Write-Host $Text -ForegroundColor $Color }
}

function Write-CleanHeader {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Host ''
    Write-CleanText ('--- ' + $Title + ' ---') Cyan
}

function Write-CleanLog {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [string]$Target = '',
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')][string]$Status = 'INFO',
        [string]$Detail = ''
    )
    try {
        $record = [ordered]@{
            timestamp = [DateTimeOffset]::Now.ToString('o')
            version   = $script:CleanOSVersion
            action    = $Action
            target    = $Target
            status    = $Status
            detail    = $Detail
        }
        $line = $record | ConvertTo-Json -Compress -Depth 5
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    } catch {
        # Logging failures must never be hidden if a system change is attempted.
        Write-CleanText ('Günlük yazılamadı: ' + $_.Exception.Message) Yellow
    }
}

function Test-CleanOSAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Initialize-CleanOS {
    if (-not $script:CleanOSIsWindows) {
        throw 'CleanOS yalnızca Windows 10/11 üzerinde çalışır.'
    }
    foreach ($dir in @($script:DataRoot, $script:HistoryDir, $script:LogDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    # Verify that the local journal directory is writable before offering changes.
    $probe = Join-Path $script:DataRoot ('.write-test-' + [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($probe, 'ok')
    Remove-Item -LiteralPath $probe -Force
    $script:CleanOSIsAdmin = Test-CleanOSAdmin
    Write-CleanLog -Action 'Startup' -Status 'INFO' -Detail ('CleanOS ' + $script:CleanOSVersion + ' started; admin=' + $script:CleanOSIsAdmin)
}

function Test-IsMachineRegistryPath {
    param([string]$Path)
    return ($Path -match '^HKLM:\\')
}

function Get-RegistryValueSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $hive = $null
    $subPath = $null
    if ($Path -match '^HKCU:\\(.*)$') {
        $hive = [Microsoft.Win32.Registry]::CurrentUser
        $subPath = $Matches[1]
    } elseif ($Path -match '^HKLM:\\(.*)$') {
        $hive = [Microsoft.Win32.Registry]::LocalMachine
        $subPath = $Matches[1]
    } else {
        throw ('Desteklenmeyen kayıt defteri yolu: ' + $Path)
    }

    $key = $null
    try {
        $key = $hive.OpenSubKey($subPath, $false)
        if ($null -eq $key -or -not ($key.GetValueNames() -contains $Name)) {
            return [ordered]@{ Exists = $false; Kind = $null; Value = $null }
        }
        $kind = $key.GetValueKind($Name).ToString()
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [ordered]@{ Exists = $true; Kind = $kind; Value = $value }
    } finally {
        if ($null -ne $key) { $key.Dispose() }
    }
}

function ConvertTo-CleanComparable {
    param($Value)
    return (ConvertTo-Json -InputObject $Value -Compress -Depth 8)
}

function Test-CleanValueEqual {
    param($Left, $Right)
    if ($null -eq $Left -and $null -eq $Right) { return $true }
    return ((ConvertTo-CleanComparable $Left) -ceq (ConvertTo-CleanComparable $Right))
}

function Test-SnapshotEquals {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$ExpectedPrefix
    )
    $expectedExistsProperty = $ExpectedPrefix + 'Exists'
    $expectedKindProperty = $ExpectedPrefix + 'Kind'
    $expectedValueProperty = $ExpectedPrefix + 'Value'
    if ([bool]$Snapshot.Exists -ne [bool]$Expected.$expectedExistsProperty) { return $false }
    if (-not $Snapshot.Exists) { return $true }
    if ([string]$Snapshot.Kind -ne [string]$Expected.$expectedKindProperty) { return $false }
    return (Test-CleanValueEqual $Snapshot.Value $Expected.$expectedValueProperty)
}

function Start-CleanTransaction {
    param([Parameter(Mandatory = $true)][string]$Name)
    $id = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $script:CurrentTransaction = [ordered]@{
        Id            = $id
        Name          = $Name
        Version       = $script:CleanOSVersion
        StartedAt     = [DateTimeOffset]::Now.ToString('o')
        ComputerBuild = [Environment]::OSVersion.Version.ToString()
        Changes       = @()
    }
}

function Save-CleanTransaction {
    if ($null -eq $script:CurrentTransaction -or @($script:CurrentTransaction.Changes).Count -eq 0) { return }
    $path = Join-Path $script:HistoryDir ($script:CurrentTransaction.Id + '.json')
    $temp = $path + '.tmp'
    $json = $script:CurrentTransaction | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $path -Force
}

function Register-CleanChange {
    param(
        [Parameter(Mandatory = $true)]$Change,
        [switch]$Pending
    )
    if ($null -eq $script:CurrentTransaction) {
        Start-CleanTransaction -Name 'Yapılandırma değişikliği'
    }
    $script:CurrentTransaction.Changes += ,$Change
    Save-CleanTransaction
    if ($Pending) {
        Write-CleanLog -Action ([string]$Change.Type) -Target ([string]$Change.Target) -Status 'INFO' -Detail 'Geri alma kaydı işlemden önce yazıldı.'
    } else {
        Write-CleanLog -Action ([string]$Change.Type) -Target ([string]$Change.Target) -Status 'SUCCESS' -Detail 'İşlem geçmişe kaydedildi.'
    }
}

function Complete-CleanTransaction {
    if ($null -eq $script:CurrentTransaction) { return }
    $count = @($script:CurrentTransaction.Changes).Count
    if ($count -gt 0) {
        Save-CleanTransaction
        Write-CleanText ('İşlem kaydedildi. Kimlik: ' + $script:CurrentTransaction.Id + ' | Değişiklik: ' + $count) Green
        Write-CleanText ('Geri alma geçmişi: ' + $script:HistoryDir) DarkGray
    } else {
        Write-CleanText 'Değişiklik yapılmadı.' DarkGray
    }
    $script:CurrentTransaction = $null
}

function Test-RegistrySnapshotsEqual {
    param([Parameter(Mandatory = $true)]$Left, [Parameter(Mandatory = $true)]$Right)
    if ([bool]$Left.Exists -ne [bool]$Right.Exists) { return $false }
    if (-not $Left.Exists) { return $true }
    if ([string]$Left.Kind -ne [string]$Right.Kind) { return $false }
    return (Test-CleanValueEqual $Left.Value $Right.Value)
}

function Set-CleanRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')][string]$Kind,
        [string]$Reason = 'Kullanıcı isteği'
    )
    if ((Test-IsMachineRegistryPath $Path) -and -not (Test-CleanOSAdmin)) {
        throw 'Bu kayıt defteri değişikliği için yönetici izni gerekir. CleanOS''u yönetici olarak yeniden başlatın.'
    }
    $before = Get-RegistryValueSnapshot -Path $Path -Name $Name
    if ($before.Exists -and $before.Kind -eq $Kind -and (Test-CleanValueEqual $before.Value $Value)) {
        return $false
    }
    $latestBefore = Get-RegistryValueSnapshot -Path $Path -Name $Name
    if (-not (Test-RegistrySnapshotsEqual -Left $before -Right $latestBefore)) {
        throw ('Kayıt defteri değeri işlem sırasında değişti; güvenlik için atlandı: ' + $Path + '\' + $Name)
    }
    if ($null -eq $script:CurrentTransaction) { Start-CleanTransaction -Name 'Kayıt defteri ayarı' }
    $change = [ordered]@{
        Type = 'RegistryValue'
        Target = ($Path + '\' + $Name)
        Path = $Path
        Name = $Name
        BeforeExists = [bool]$before.Exists
        BeforeKind = $before.Kind
        BeforeValue = $before.Value
        AfterExists = $true
        AfterKind = $Kind
        AfterValue = $Value
        Reversible = $true
        Reason = $Reason
    }
    Register-CleanChange -Change $change -Pending
    try {
        New-Item -Path $Path -Force | Out-Null
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
        $after = Get-RegistryValueSnapshot -Path $Path -Name $Name
        if (-not (Test-SnapshotEquals -Snapshot $after -Expected $change -ExpectedPrefix 'After')) {
            throw ('Yazılan değer doğrulanamadı: ' + $Path + '\' + $Name)
        }
        Write-CleanLog -Action 'RegistryValueApplied' -Target ($Path + '\' + $Name) -Status 'SUCCESS' -Detail $Reason
    } catch {
        Write-CleanLog -Action 'RegistryValueApplied' -Target ($Path + '\' + $Name) -Status 'ERROR' -Detail $_.Exception.Message
        throw
    }
    return $true
}

function Remove-CleanRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Reason = 'Başlangıç girdisi devre dışı bırakıldı'
    )
    if ((Test-IsMachineRegistryPath $Path) -and -not (Test-CleanOSAdmin)) {
        throw 'Bu kayıt defteri değişikliği için yönetici izni gerekir.'
    }
    $before = Get-RegistryValueSnapshot -Path $Path -Name $Name
    if (-not $before.Exists) { return $false }
    $latestBefore = Get-RegistryValueSnapshot -Path $Path -Name $Name
    if (-not (Test-RegistrySnapshotsEqual -Left $before -Right $latestBefore)) {
        throw ('Kayıt defteri değeri işlem sırasında değişti; güvenlik için atlandı: ' + $Path + '\' + $Name)
    }
    if ($null -eq $script:CurrentTransaction) { Start-CleanTransaction -Name 'Kayıt defteri girdisini kaldır' }
    $change = [ordered]@{
        Type = 'RegistryValue'
        Target = ($Path + '\' + $Name)
        Path = $Path
        Name = $Name
        BeforeExists = $true
        BeforeKind = $before.Kind
        BeforeValue = $before.Value
        AfterExists = $false
        AfterKind = $null
        AfterValue = $null
        Reversible = $true
        Reason = $Reason
    }
    Register-CleanChange -Change $change -Pending
    try {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $after = Get-RegistryValueSnapshot -Path $Path -Name $Name
        if ($after.Exists) { throw ('Kayıt defteri girdisi silinemedi: ' + $Path + '\' + $Name) }
        Write-CleanLog -Action 'RegistryValueRemoved' -Target ($Path + '\' + $Name) -Status 'SUCCESS' -Detail $Reason
    } catch {
        Write-CleanLog -Action 'RegistryValueRemoved' -Target ($Path + '\' + $Name) -Status 'ERROR' -Detail $_.Exception.Message
        throw
    }
    return $true
}

function ConvertTo-RegistryRestoreValue {
    param([string]$Kind, $Value)
    switch ($Kind) {
        'DWord' { return [int]$Value }
        'QWord' { return [long]$Value }
        'String' { return [string]$Value }
        'ExpandString' { return [string]$Value }
        'MultiString' { return [string[]]@($Value) }
        'Binary' { return [byte[]]@($Value) }
        default { return $Value }
    }
}

function Restore-RegistryChange {
    param([Parameter(Mandatory = $true)]$Change)
    $current = Get-RegistryValueSnapshot -Path ([string]$Change.Path) -Name ([string]$Change.Name)
    if (-not (Test-SnapshotEquals -Snapshot $current -Expected $Change -ExpectedPrefix 'After')) {
        return 'Atlandı: bu değer işlemden sonra tekrar değiştirilmiş.'
    }
    if ([bool]$Change.BeforeExists) {
        $value = ConvertTo-RegistryRestoreValue -Kind ([string]$Change.BeforeKind) -Value $Change.BeforeValue
        New-Item -Path ([string]$Change.Path) -Force | Out-Null
        New-ItemProperty -LiteralPath ([string]$Change.Path) -Name ([string]$Change.Name) -Value $value -PropertyType ([string]$Change.BeforeKind) -Force | Out-Null
    } else {
        Remove-ItemProperty -LiteralPath ([string]$Change.Path) -Name ([string]$Change.Name) -ErrorAction SilentlyContinue
    }
    return 'Geri alındı.'
}

function Get-StartupRegistryEntries {
    $paths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        try {
            $hive = $null; $subPath = $null
            if ($path -match '^HKCU:\\(.*)$') { $hive = [Microsoft.Win32.Registry]::CurrentUser; $subPath = $Matches[1] }
            else { $hive = [Microsoft.Win32.Registry]::LocalMachine; $subPath = $path -replace '^HKLM:\\', '' }
            $key = $hive.OpenSubKey($subPath, $false)
            if ($null -eq $key) { continue }
            try {
                foreach ($name in $key.GetValueNames()) {
                    $snapshot = Get-RegistryValueSnapshot -Path $path -Name $name
                    if ($snapshot.Exists) {
                        $items.Add([pscustomobject]@{
                            Path = $path
                            Name = $name
                            Command = [string]$snapshot.Value
                            Kind = [string]$snapshot.Kind
                            Scope = if ($path -like 'HKCU:*') { 'Kullanıcı' } else { 'Tüm kullanıcılar' }
                        })
                    }
                }
            } finally { $key.Dispose() }
        } catch {
            Write-CleanLog -Action 'ReadStartupEntries' -Target $path -Status 'WARNING' -Detail $_.Exception.Message
        }
    }
    return @($items)
}

function Read-CleanSelection {
    param([Parameter(Mandatory = $true)][string]$Prompt, [int]$Maximum = 0, [switch]$AllowMany)
    $raw = (Read-Host $Prompt).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    if ($AllowMany) {
        $parts = $raw -split '[,; ]+' | Where-Object { $_ -match '^\d+$' }
        $numbers = @()
        foreach ($part in $parts) {
            $num = [int]$part
            if ($num -ge 1 -and ($Maximum -le 0 -or $num -le $Maximum) -and $numbers -notcontains $num) { $numbers += $num }
        }
        return @($numbers)
    }
    if ($raw -match '^\d+$') {
        $num = [int]$raw
        if ($num -ge 1 -and ($Maximum -le 0 -or $num -le $Maximum)) { return @($num) }
    }
    return @()
}

function Start-CleanOSAsAdmin {
    Write-CleanText 'Bu işlem yönetici izni gerektiriyor.' Yellow
    $choice = Read-Host 'CleanOS''u yeni bir yönetici PowerShell penceresinde açmak ister misiniz? (E/H)'
    if ($choice -notmatch '^(E|EVET|Y|YES)$') { return $false }
    try {
        $exe = (Get-Process -Id $PID).Path
        if ([string]::IsNullOrWhiteSpace($exe)) { throw 'PowerShell çalıştırılabilir dosyası bulunamadı.' }
        if (-not [string]::IsNullOrWhiteSpace($script:CleanOSLocalScriptPath) -and (Test-Path -LiteralPath $script:CleanOSLocalScriptPath)) {
            $escapedScriptPath = $script:CleanOSLocalScriptPath.Replace("'", "''")
            $cmd = "& '$escapedScriptPath'"
        } else {
            if ($script:CleanOSRawScriptUrl -match '/OWNER/') {
                throw 'Önce README.md içindeki dağıtım adımlarını tamamlayıp CleanOSRawScriptUrl değerini gerçek GitHub adresiyle değiştirin.'
            }
            $cmd = "irm '$script:CleanOSRawScriptUrl' | iex"
        }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath $exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -EncodedCommand " + $encoded) | Out-Null
        Write-CleanText 'Yönetici penceresi açılıyor. Yeni pencerede istediğiniz işlemi yeniden seçin.' Green
        return $true
    } catch {
        Write-CleanText ('Yönetici penceresi açılamadı: ' + $_.Exception.Message) Red
        return $false
    }
}

function Show-PerformanceMenu {
    while ($true) {
        Write-CleanHeader 'Performans'
        Write-Host '1. CPU/RAM kullanan işlemleri göster (salt okunur)'
        Write-Host '2. Başlangıç uygulamalarını görüntüle / seçerek devre dışı bırak'
        Write-Host '3. Görsel efektleri performans odaklı ayarla (geri alınabilir)'
        Write-Host '0. Geri'
        $choice = Read-Host 'Seçim'
        switch ($choice) {
            '1' {
                Get-Process -ErrorAction SilentlyContinue |
                    Sort-Object -Property WorkingSet64 -Descending |
                    Select-Object -First 15 @{N='İşlem';E={$_.ProcessName}}, Id,
                        @{N='RAM (MB)';E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
                        @{N='CPU saniye';E={if ($null -eq $_.CPU) { 0 } else { [math]::Round($_.CPU, 1) }}} |
                    Format-Table -AutoSize
                Read-Host 'Devam etmek için Enter'
            }
            '2' { Show-StartupManager }
            '3' {
                Write-Host 'Bu ayar mevcut kullanıcı için VisualFXSetting=2 (performans odaklı) değerini yazar.'
                Write-Host 'Animasyon ve görsel efektler azalabilir. Ayar geri alınabilir.'
                if ((Read-Host 'Uygulamak için APPLY yazın') -ceq 'APPLY') {
                    Start-CleanTransaction -Name 'Görsel efektleri performans odaklı ayarla'
                    try {
                        [void](Set-CleanRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Kind DWord -Reason 'Kullanıcı performans tercihi')
                        Complete-CleanTransaction
                    } catch { Write-CleanText $_.Exception.Message Red; Write-CleanLog -Action 'SetVisualEffects' -Status 'ERROR' -Detail $_.Exception.Message }
                }
            }
            '0' { return }
            default { Write-CleanText 'Geçersiz seçim.' Yellow }
        }
    }
}

function Show-StartupManager {
    Write-CleanHeader 'Başlangıç uygulamaları'
    $items = @(Get-StartupRegistryEntries)
    if ($items.Count -eq 0) {
        Write-CleanText 'Desteklenen Run kayıtlarında başlangıç girdisi bulunamadı.' Yellow
        Read-Host 'Devam etmek için Enter' | Out-Null
        return
    }
    for ($i = 0; $i -lt $items.Count; $i++) {
        $cmd = [string]$items[$i].Command
        if ($cmd.Length -gt 105) { $cmd = $cmd.Substring(0, 102) + '...' }
        Write-Host ('{0,2}. [{1}] {2} :: {3}' -f ($i + 1), $items[$i].Scope, $items[$i].Name, $cmd)
    }
    Write-Host ''
    Write-Host 'Not: Yalnızca bu üç Run kayıt defteri konumu yönetilir; görev zamanlayıcıları ve başlangıç klasörleri değiştirilmez.'
    $selected = @(Read-CleanSelection -Prompt 'Devre dışı bırakılacak numaralar (örn. 1,3) veya Enter ile dön' -Maximum $items.Count -AllowMany)
    if ($selected.Count -eq 0) { return }
    $chosen = @($selected | ForEach-Object { $items[$_ - 1] })
    if (($chosen | Where-Object { $_.Path -like 'HKLM:*' }).Count -gt 0 -and -not (Test-CleanOSAdmin)) {
        [void](Start-CleanOSAsAdmin)
        return
    }
    Write-CleanText 'Seçilen girdiler sonraki oturum açılışlarında ilgili uygulamaların başlamasını engelleyebilir:' Yellow
    foreach ($item in $chosen) {
        Write-Host ('- ' + $item.Name + ' [' + $item.Scope + ']')
        Write-Host ('  ' + $item.Command)
    }
    if ((Read-Host 'Toplu devre dışı bırakmak için DISABLE yazın') -cne 'DISABLE') { return }
    Start-CleanTransaction -Name 'Başlangıç girdilerini devre dışı bırak'
    try {
        foreach ($item in $chosen) {
            [void](Remove-CleanRegistryValue -Path $item.Path -Name $item.Name -Reason 'CleanOS başlangıç yöneticisi; geri alınabilir')
        }
        Complete-CleanTransaction
    } catch {
        Write-CleanText ('İşlem sırasında hata: ' + $_.Exception.Message) Red
        Write-CleanLog -Action 'DisableStartupEntries' -Status 'ERROR' -Detail $_.Exception.Message
        Complete-CleanTransaction
    }
    Read-Host 'Devam etmek için Enter' | Out-Null
}

function Show-DebloatMenu {
    Write-CleanHeader 'Debloat - isteğe bağlı uygulamalar'
    Write-CleanText 'Yalnızca mevcut kullanıcı profilindeki aşağıdaki izinli uygulama paketleri listelenir.' Yellow
    Write-CleanText 'Windows Güvenliği, Microsoft Store, Edge, WebView, Başlat, Fotoğraflar, Not Defteri, Terminal ve Xbox bileşenleri hedef listeye dahil değildir.' Yellow
    Write-CleanText 'ÖNEMLİ: Bir uygulama kaldırıldıktan sonra CleanOS onu otomatik geri yükleyemez; Microsoft Store/üretici kaynağından yeniden kurmanız gerekebilir.' Red

    $installed = New-Object System.Collections.Generic.List[object]
    foreach ($appName in $script:OptionalAppAllowList) {
        try {
            foreach ($pkg in @(Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue)) {
                if ($null -ne $pkg -and -not $pkg.NonRemovable) {
                    $installed.Add([pscustomobject]@{ Name = $pkg.Name; PackageFullName = $pkg.PackageFullName; Version = [string]$pkg.Version })
                }
            }
        } catch { }
    }
    $unique = @($installed | Sort-Object PackageFullName -Unique)
    if ($unique.Count -eq 0) {
        Write-CleanText 'İzin verilen listede kaldırılabilir uygulama bulunamadı.' Green
        Read-Host 'Devam etmek için Enter' | Out-Null
        return
    }
    for ($i = 0; $i -lt $unique.Count; $i++) {
        Write-Host ('{0,2}. {1}  ({2})' -f ($i + 1), $unique[$i].Name, $unique[$i].Version)
    }
    $selected = @(Read-CleanSelection -Prompt 'Kaldırılacak numaralar (örn. 1,3) veya Enter ile dön' -Maximum $unique.Count -AllowMany)
    if ($selected.Count -eq 0) { return }
    $chosen = @($selected | ForEach-Object { $unique[$_ - 1] })
    Write-CleanText 'Bu işlem yalnızca mevcut kullanıcıdaki seçili Appx paketlerini kaldırır; provisioned paketlere dokunulmaz.' Yellow
    foreach ($app in $chosen) { Write-Host ('- ' + $app.Name) }
    if ((Read-Host 'Kaldırmayı onaylamak için REMOVE yazın') -cne 'REMOVE') { return }

    Start-CleanTransaction -Name 'Seçilen isteğe bağlı Appx uygulamalarını kaldır'
    foreach ($app in $chosen) {
        try {
            Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
            Register-CleanChange -Change ([ordered]@{
                Type = 'AppxPackageRemoved'
                Target = $app.PackageFullName
                Name = $app.Name
                PackageFullName = $app.PackageFullName
                Reversible = $false
                Reason = 'Kullanıcı onayıyla mevcut profilden kaldırıldı; otomatik geri yükleme garanti edilemez.'
            })
            Write-CleanText ('Kaldırıldı: ' + $app.Name) Green
        } catch {
            Write-CleanText ('Kaldırılamadı: ' + $app.Name + ' — ' + $_.Exception.Message) Yellow
            Write-CleanLog -Action 'RemoveAppxPackage' -Target $app.Name -Status 'ERROR' -Detail $_.Exception.Message
        }
    }
    Complete-CleanTransaction
    Read-Host 'Devam etmek için Enter' | Out-Null
}

function Show-PrivacyMenu {
    while ($true) {
        Write-CleanHeader 'Gizlilik ve öneriler'
        Write-Host '1. Reklam kimliğini kapat (mevcut kullanıcı)'
        Write-Host '2. Başlat/Windows içerik önerilerini azalt (mevcut kullanıcı)'
        Write-Host '3. Tanılama verilerine dayalı kişiselleştirilmiş deneyimleri kapat'
        Write-Host '4. Dosya Gezgini eşitleme sağlayıcısı bildirimlerini kapat'
        Write-Host '5. Önerilen gizlilik ayarlarını topluca uygula'
        Write-Host '6. Windows gizlilik ayarlarını aç'
        Write-Host '0. Geri'
        $choice = Read-Host 'Seçim'
        if ($choice -eq '0') { return }
        if ($choice -eq '6') { Start-Process 'ms-settings:privacy'; continue }
        if ($choice -notin @('1', '2', '3', '4', '5')) { Write-CleanText 'Geçersiz seçim.' Yellow; continue }
        if ((Read-Host 'Yalnızca mevcut kullanıcıya uygulanacak bu ayarlar için APPLY yazın') -cne 'APPLY') { continue }

        Start-CleanTransaction -Name 'Gizlilik ayarları'
        try {
            if ($choice -in @('1', '5')) {
                [void](Set-CleanRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0 -Kind DWord -Reason 'Reklam kimliğini kapat')
            }
            if ($choice -in @('2', '5')) {
                $contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                foreach ($name in @('ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SoftLandingEnabled')) {
                    [void](Set-CleanRegistryValue -Path $contentPath -Name $name -Value 0 -Kind DWord -Reason 'Kişisel öneri ve tanıtımları azalt')
                }
            }
            if ($choice -in @('3', '5')) {
                [void](Set-CleanRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 -Kind DWord -Reason 'Tanılama verilerine dayalı kişiselleştirmeyi kapat')
                [void](Set-CleanRegistryValue -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Value 0 -Kind DWord -Reason 'Geri bildirim bildirim sıklığını azalt')
            }
            if ($choice -in @('4', '5')) {
                [void](Set-CleanRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Value 0 -Kind DWord -Reason 'Dosya Gezgini eşitleme sağlayıcısı bildirimlerini kapat')
            }
            Complete-CleanTransaction
            Write-CleanText 'Not: Bu ayarlar tüm tanılama verilerini kapatmaz. CleanOS gerekli tanılama verilerini, Defender''ı, güvenlik duvarını veya ağ bileşenlerini devre dışı bırakmaz.' Cyan
        } catch {
            Write-CleanText ('Gizlilik ayarı uygulanamadı: ' + $_.Exception.Message) Red
            Write-CleanLog -Action 'PrivacySettings' -Status 'ERROR' -Detail $_.Exception.Message
            Complete-CleanTransaction
        }
        Read-Host 'Devam etmek için Enter' | Out-Null
    }
}

function Show-WindowsUpdateMenu {
    while ($true) {
        Write-CleanHeader 'Windows Update'
        Write-CleanText 'CleanOS Windows Update hizmetlerini devre dışı bırakmaz veya güncellemeleri gizlice engellemez.' Cyan
        Write-Host '1. Windows Update ayarlarını aç'
        Write-Host '2. Güncelleme geçmişini aç'
        Write-Host '3. Gelişmiş güncelleme seçeneklerini aç'
        Write-Host '4. Temel güncelleme hizmetlerinin durumunu göster (salt okunur)'
        Write-Host '0. Geri'
        $choice = Read-Host 'Seçim'
        switch ($choice) {
            '1' { Start-Process 'ms-settings:windowsupdate' }
            '2' { Start-Process 'ms-settings:windowsupdate-history' }
            '3' { Start-Process 'ms-settings:windowsupdate-options' }
            '4' {
                $names = @('wuauserv', 'UsoSvc', 'BITS', 'DoSvc', 'WaaSMedicSvc')
                Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -in $names } |
                    Select-Object Name, DisplayName, State, StartMode |
                    Format-Table -AutoSize
                Read-Host 'Devam etmek için Enter' | Out-Null
            }
            '0' { return }
            default { Write-CleanText 'Geçersiz seçim.' Yellow }
        }
    }
}

function Test-ProtectedService {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ($script:ProtectedServiceNames -contains $Name)
}

function Get-ServiceExecutablePath {
    param([Parameter(Mandatory = $true)]$Service)
    $raw = [Environment]::ExpandEnvironmentVariables([string]$Service.PathName).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    if ($raw -match '^"([^"]+\.exe)"') { return $Matches[1] }
    if ($raw -match '^(.+?\.exe)(?:\s|$)') { return $Matches[1].Trim('"') }
    return $null
}

function Test-EditableThirdPartyService {
    param([Parameter(Mandatory = $true)]$Service)
    if (Test-ProtectedService -Name ([string]$Service.Name)) { return $false }
    if ([string]$Service.StartMode -notin @('Auto', 'Manual', 'Disabled')) { return $false }
    $exePath = Get-ServiceExecutablePath -Service $Service
    if ([string]::IsNullOrWhiteSpace($exePath) -or -not (Test-Path -LiteralPath $exePath -PathType Leaf)) { return $false }
    $resolved = [System.IO.Path]::GetFullPath($exePath)
    if ($resolved -match '(?i)\\Windows\\' -or $resolved -match '(?i)\\SystemRoot\\') { return $false }
    if ([System.IO.Path]::GetFileName($resolved) -ieq 'svchost.exe') { return $false }
    try {
        $signature = Get-AuthenticodeSignature -FilePath $resolved -ErrorAction Stop
        if ($signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate -and $signature.SignerCertificate.Subject -match '(?i)Microsoft Corporation') {
            return $false
        }
    } catch { }
    $programFilesRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $programFilesRoots) {
        if ($resolved.StartsWith([System.IO.Path]::GetFullPath($root), [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    # Only permit known third-party program locations; block ambiguous service binaries.
    return $false
}

function Get-StartupTypeName {
    param([string]$StartMode)
    switch ($StartMode) {
        'Auto' { return 'Automatic' }
        'Manual' { return 'Manual' }
        'Disabled' { return 'Disabled' }
        default { return $null }
    }
}

function Show-ServiceManager {
    while ($true) {
        Write-CleanHeader 'Servis yöneticisi'
        Write-CleanText 'Windows güvenlik, güncelleme, ağ, arama ve çekirdek servisleri korumalıdır.' Cyan
        Write-Host '1. Kritik ve Windows servislerinin durumunu göster (salt okunur)'
        Write-Host '2. Güvenli kontrol filtresinden geçen üçüncü taraf servislerin başlangıç türünü değiştir'
        Write-Host '3. services.msc aç'
        Write-Host '0. Geri'
        $choice = Read-Host 'Seçim'
        switch ($choice) {
            '1' {
                Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
                    Where-Object { (Test-ProtectedService -Name $_.Name) -or $_.Name -in @('WinDefend', 'wuauserv', 'BITS', 'Dnscache', 'Dhcp', 'WSearch', 'MpsSvc', 'BFE') } |
                    Select-Object Name, State, StartMode, DisplayName |
                    Sort-Object Name | Format-Table -AutoSize
                Read-Host 'Devam etmek için Enter' | Out-Null
            }
            '2' { Set-ThirdPartyServiceStartup }
            '3' { Start-Process 'services.msc' }
            '0' { return }
            default { Write-CleanText 'Geçersiz seçim.' Yellow }
        }
    }
}

function Set-ThirdPartyServiceStartup {
    if (-not (Test-CleanOSAdmin)) { [void](Start-CleanOSAsAdmin); return }
    Write-CleanText 'Servis adayları filtrelenir: Windows klasöründeki ikililer, svchost ve Microsoft imzalı dosyalar değiştirilemez.' Yellow
    $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop | Where-Object { Test-EditableThirdPartyService -Service $_ } | Sort-Object Name)
    if ($services.Count -eq 0) {
        Write-CleanText 'Güvenli filtreyi geçen üçüncü taraf servisi bulunamadı.' Green
        Read-Host 'Devam etmek için Enter' | Out-Null
        return
    }
    $limit = [Math]::Min(80, $services.Count)
    for ($i = 0; $i -lt $limit; $i++) {
        Write-Host ('{0,2}. {1} | {2} | Durum: {3} | Başlangıç: {4}' -f ($i + 1), $services[$i].Name, $services[$i].DisplayName, $services[$i].State, $services[$i].StartMode)
    }
    if ($services.Count -gt $limit) { Write-CleanText ('İlk ' + $limit + ' servis gösteriliyor.') DarkGray }
    $selected = @(Read-CleanSelection -Prompt 'Bir servis numarası seçin veya Enter ile dön' -Maximum $limit)
    if ($selected.Count -eq 0) { return }
    $service = $services[$selected[0] - 1]
    if (Test-ProtectedService -Name $service.Name) { Write-CleanText 'Bu servis korumalıdır; işlem reddedildi.' Red; return }
    Write-Host ('Seçilen servis: ' + $service.Name + ' — ' + $service.DisplayName)
    Write-Host ('Çalıştırılabilir dosya: ' + (Get-ServiceExecutablePath -Service $service))
    Write-CleanText 'Disabled seçimi ilgili uygulamanın/cihazın çalışmasını bozabilir. Windows servisleri bu araçla toplu kapatılmaz.' Yellow
    Write-Host 'Başlangıç türü: 1=Automatic, 2=Manual, 3=Disabled, 0=Vazgeç'
    $typeChoice = Read-Host 'Seçim'
    $newType = switch ($typeChoice) { '1' { 'Automatic' } '2' { 'Manual' } '3' { 'Disabled' } default { $null } }
    if ($null -eq $newType) { return }
    if ((Read-Host ('Uygulamak için servis adını aynen yazın: ' + $service.Name)) -cne [string]$service.Name) { return }
    if ((Read-Host 'Değişikliği onaylamak için SET yazın') -cne 'SET') { return }
    try {
        $fresh = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f ([string]$service.Name.Replace("'", "''")))
        if ($null -eq $fresh -or -not (Test-EditableThirdPartyService -Service $fresh)) { throw 'Servis güvenli kontrol filtresinden tekrar geçemedi; işlem iptal edildi.' }
        $before = Get-StartupTypeName -StartMode ([string]$fresh.StartMode)
        if ($null -eq $before) { throw 'Mevcut başlangıç türü güvenli biçimde geri alınamıyor; işlem iptal edildi.' }
        if ($before -eq $newType) {
            Write-CleanText ('Servis zaten ' + $newType + ' başlangıç türünde; değişiklik yapılmadı.') DarkGray
            return
        }
        Start-CleanTransaction -Name ('Servis başlangıç türü: ' + $service.Name)
        $serviceChange = [ordered]@{
            Type = 'ServiceStartup'
            Target = [string]$service.Name
            Name = [string]$service.Name
            BeforeStartupType = $before
            AfterStartupType = $newType
            Reversible = $true
            Reason = 'Kullanıcının açık onayıyla üçüncü taraf servis başlangıcı değiştirildi.'
        }
        Register-CleanChange -Change $serviceChange -Pending
        Set-Service -Name $service.Name -StartupType $newType -ErrorAction Stop | Out-Null
        $afterService = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f ([string]$service.Name.Replace("'", "''")))
        $after = Get-StartupTypeName -StartMode ([string]$afterService.StartMode)
        if ($after -ne $newType) { throw 'Servisin yeni başlangıç türü doğrulanamadı.' }
        Write-CleanLog -Action 'ServiceStartupApplied' -Target ([string]$service.Name) -Status 'SUCCESS' -Detail ('New startup type: ' + $newType)
        Complete-CleanTransaction
    } catch {
        Write-CleanText ('Servis değiştirilemedi: ' + $_.Exception.Message) Red
        Write-CleanLog -Action 'SetServiceStartup' -Target ([string]$service.Name) -Status 'ERROR' -Detail $_.Exception.Message
        Complete-CleanTransaction
    }
    Read-Host 'Devam etmek için Enter' | Out-Null
}

function Restore-ServiceStartupChange {
    param([Parameter(Mandatory = $true)]$Change)
    if (Test-ProtectedService -Name ([string]$Change.Name)) { return 'Atlandı: servis artık korumalı listede.' }
    $fresh = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f ([string]$Change.Name.Replace("'", "''"))) -ErrorAction SilentlyContinue
    if ($null -eq $fresh) { return 'Atlandı: servis bulunamadı.' }
    $current = Get-StartupTypeName -StartMode ([string]$fresh.StartMode)
    if ($current -ne [string]$Change.AfterStartupType) { return 'Atlandı: servis başlangıcı işlemden sonra tekrar değiştirilmiş.' }
    if ([string]$Change.BeforeStartupType -notin @('Automatic', 'Manual', 'Disabled')) { return 'Atlandı: önceki başlangıç türü güvenli biçimde geri alınamıyor.' }
    Set-Service -Name ([string]$Change.Name) -StartupType ([string]$Change.BeforeStartupType) -ErrorAction Stop | Out-Null
    return 'Geri alındı.'
}

function Get-CleanHistory {
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $script:HistoryDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (@($record.Changes).Count -gt 0) { $records.Add($record) }
        } catch {
            Write-CleanLog -Action 'ReadHistory' -Target $file.Name -Status 'WARNING' -Detail $_.Exception.Message
        }
    }
    return @($records)
}

function Restore-CleanTransaction {
    param([Parameter(Mandatory = $true)]$Transaction)
    $summary = New-Object System.Collections.Generic.List[string]
    $changes = @($Transaction.Changes)
    [array]::Reverse($changes)
    foreach ($change in $changes) {
        try {
            switch ([string]$change.Type) {
                'RegistryValue' {
                    $result = Restore-RegistryChange -Change $change
                }
                'ServiceStartup' {
                    if (-not (Test-CleanOSAdmin)) { throw 'Servis ayarlarını geri almak için yönetici izni gerekir.' }
                    $result = Restore-ServiceStartupChange -Change $change
                }
                'AppxPackageRemoved' {
                    $result = 'Otomatik geri alınamaz: uygulamayı Microsoft Store veya üretici kaynağından yeniden yükleyin.'
                }
                default { $result = 'Atlandı: tanınmayan değişiklik türü.' }
            }
            $summary.Add(([string]$change.Target + ': ' + $result))
            Add-Member -InputObject $change -MemberType NoteProperty -Name 'RollbackResult' -Value $result -Force
            Write-CleanLog -Action 'RollbackItem' -Target ([string]$change.Target) -Status $(if ($result -like 'Geri alındı*') { 'SUCCESS' } else { 'WARNING' }) -Detail $result
        } catch {
            $result = 'Hata: ' + $_.Exception.Message
            $summary.Add(([string]$change.Target + ': ' + $result))
            Add-Member -InputObject $change -MemberType NoteProperty -Name 'RollbackResult' -Value $result -Force
            Write-CleanLog -Action 'RollbackItem' -Target ([string]$change.Target) -Status 'ERROR' -Detail $_.Exception.Message
        }
    }
    $Transaction | Add-Member -MemberType NoteProperty -Name 'RollbackAttemptedAt' -Value ([DateTimeOffset]::Now.ToString('o')) -Force
    $Transaction | Add-Member -MemberType NoteProperty -Name 'RollbackSummary' -Value @($summary) -Force
    $historyPath = Join-Path $script:HistoryDir ([string]$Transaction.Id + '.json')
    try {
        $temp = $historyPath + '.tmp'
        [System.IO.File]::WriteAllText($temp, ($Transaction | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $historyPath -Force
    } catch { Write-CleanText ('Geri alma sonucu geçmişe yazılamadı: ' + $_.Exception.Message) Yellow }
    Write-CleanHeader 'Geri alma sonucu'
    foreach ($line in $summary) { Write-Host ('- ' + $line) }
    Write-CleanText 'Not: Appx uygulama kaldırmaları otomatik geri alınamaz. Sonradan değiştirilen ayarlar, daha yeni kullanıcı tercihlerini ezmemek için atlanır.' Yellow
}

function Show-RollbackMenu {
    Write-CleanHeader 'Geri alma geçmişi'
    $records = @(Get-CleanHistory)
    if ($records.Count -eq 0) {
        Write-CleanText 'Geri alınabilir işlem geçmişi bulunamadı.' Yellow
        Read-Host 'Devam etmek için Enter' | Out-Null
        return
    }
    for ($i = 0; $i -lt $records.Count; $i++) {
        $count = @($records[$i].Changes).Count
        $when = [string]$records[$i].StartedAt
        $status = if ($records[$i].RollbackAttemptedAt) { ' | Geri alma denenmiş' } else { '' }
        Write-Host ('{0,2}. {1} | {2} değişiklik | {3}{4}' -f ($i + 1), $records[$i].Name, $count, $when, $status)
    }
    $selected = @(Read-CleanSelection -Prompt 'Geri alınacak işlem numarası veya Enter ile dön' -Maximum $records.Count)
    if ($selected.Count -eq 0) { return }
    $record = $records[$selected[0] - 1]
    Write-CleanText ('Seçilen işlem: ' + $record.Name) Yellow
    Write-CleanText 'Geri alma, işlemden sonra aynı ayar elle değiştirilmişse o değeri korumak için atlayabilir.' Yellow
    if ((Read-Host 'Geri almak için RESTORE yazın') -cne 'RESTORE') { return }
    $needsAdmin = (@($record.Changes | Where-Object { $_.Type -eq 'ServiceStartup' -or ($_.Type -eq 'RegistryValue' -and $_.Path -like 'HKLM:*') }).Count -gt 0)
    if ($needsAdmin -and -not (Test-CleanOSAdmin)) {
        [void](Start-CleanOSAsAdmin)
        return
    }
    Restore-CleanTransaction -Transaction $record
    Read-Host 'Devam etmek için Enter' | Out-Null
}

function Show-UpdateCheck {
    Write-CleanHeader 'Sürüm denetimi'
    if ($script:CleanOSRepository -match '/OWNER/') {
        Write-CleanText 'GitHub deposu henüz yapılandırılmamış. README.md içindeki OWNER/CleanOS adresini gerçek depo ile değiştirin.' Yellow
        Read-Host 'Devam etmek için Enter' | Out-Null
        return
    }
    try {
        $repo = $script:CleanOSRepository.TrimEnd('/') -replace '^https://github\.com/', ''
        $latest = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/releases/latest') -Headers @{ 'User-Agent' = 'CleanOS/' + $script:CleanOSVersion } -TimeoutSec 10
        $latestTag = ([string]$latest.tag_name) -replace '^[vV]', ''
        Write-Host ('Kurulu sürüm: ' + $script:CleanOSVersion)
        Write-Host ('Son yayımlanan sürüm: ' + $latest.tag_name)
        try {
            if ([version]$latestTag -gt [version]$script:CleanOSVersion) {
                Write-CleanText 'Yeni bir sürüm var. Sürüm sayfası açılıyor; otomatik kod güncellemesi yapılmaz.' Green
                Start-Process ([string]$latest.html_url)
            } else { Write-CleanText 'Yeni sürüm görünmüyor.' Green }
        } catch {
            Start-Process ([string]$latest.html_url)
            Write-CleanText 'Sürüm etiketi karşılaştırılamadı; yayımlama sayfası açıldı.' Yellow
        }
    } catch {
        Write-CleanText ('Sürüm denetlenemedi: ' + $_.Exception.Message) Yellow
        Write-CleanText 'Ağ bağlantınızı ve GitHub deposunun herkese açık olduğunu kontrol edin.' DarkGray
    }
    Read-Host 'Devam etmek için Enter' | Out-Null
}

function Show-CleanOSBanner {
    Clear-Host
    Write-CleanText '   ____ _                     ___  ____' Cyan
    Write-CleanText '  / ___| | ___  __ _ _ __     / _ \/ ___|' Cyan
    Write-CleanText ' | |   | |/ _ \/ _` |  _ \   | | | \___ \' Cyan
    Write-CleanText ' | |___| |  __/ (_| | | | |  | |_| |___) |' Cyan
    Write-CleanText '  \____|_|\___|\__,_|_| |_|   \___/|____/' Cyan
    Write-Host ('Version ' + $script:CleanOSVersion + ' | Windows 10/11 | PowerShell menu')
    $adminText = if (Test-CleanOSAdmin) { 'Yönetici: Evet' } else { 'Yönetici: Hayır (bazı sistem değişiklikleri için yeniden başlatma gerekir)' }
    if (Test-CleanOSAdmin) { Write-CleanText $adminText Green } else { Write-CleanText $adminText Yellow }
    Write-Host ('Yerel günlük: ' + $script:DataRoot)
    Write-Host 'Defender, güvenlik duvarı, Windows Update ve ağ servisleri toplu kapatılmaz.'
}

try {
    Initialize-CleanOS
} catch {
    Write-Host ('CleanOS başlatılamadı: ' + $_.Exception.Message) -ForegroundColor Red
    return
}

$script:CleanOSExit = $false
while (-not $script:CleanOSExit) {
    Show-CleanOSBanner
    Write-Host ''
    Write-Host '1. Performans'
    Write-Host '2. Debloat - isteğe bağlı uygulamalar'
    Write-Host '3. Gizlilik'
    Write-Host '4. Windows Update'
    Write-Host '5. Servis yöneticisi'
    Write-Host '6. Geri alma geçmişi'
    Write-Host '7. Güncellemeleri denetle'
    Write-Host '0. Çıkış'
    $mainChoice = Read-Host 'Seçim'
    switch ($mainChoice) {
        '1' { Show-PerformanceMenu }
        '2' { Show-DebloatMenu }
        '3' { Show-PrivacyMenu }
        '4' { Show-WindowsUpdateMenu }
        '5' { Show-ServiceManager }
        '6' { Show-RollbackMenu }
        '7' { Show-UpdateCheck }
        '0' {
            Write-CleanLog -Action 'Exit' -Status 'INFO' -Detail 'CleanOS closed by user.'
            Write-CleanText 'CleanOS kapatıldı.' Green
            $script:CleanOSExit = $true
        }
        default { Write-CleanText 'Geçersiz seçim.' Yellow; Start-Sleep -Milliseconds 700 }
    }
}
