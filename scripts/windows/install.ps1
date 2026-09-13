<#
.SYNOPSIS
    Installiert oder aktualisiert den FiveM-Server (FXServer) lokal unter Windows.

.DESCRIPTION
    Lädt die FXServer-Artifacts über das offizielle Changelog-API herunter, entpackt sie nach
    artifacts\, installiert die Basis-Ressourcen (cfx-server-data) sowie die Einträge aus
    server-data\resources.txt, legt server-data\secrets.cfg aus der Vorlage an, falls sie fehlt,
    und importiert die SQL-Dateien aus server-data\database.txt (setup-database.ps1), sobald ein
    mysql_connection_string in secrets.cfg steht.
    Das Skript ist idempotent und kann gefahrlos mehrfach ausgeführt werden.
    Voraussetzung: Windows PowerShell 5.1 (Standard in Windows 10/11), git (winget install Git.Git).
    Qbox braucht MariaDB ab 10.9: setup-database.bat -InstallMariaDB, danach -Create -Import
    (oder install.bat -SetupDatabase).

.PARAMETER Channel
    Artifact-Kanal: recommended (Standard), latest oder optional.

.PARAMETER ArchiveFormat
    auto (Standard): verwendet die vom API gelieferte Download-URL (derzeit server.zip, wird ohne
    Zusatztools entpackt). zip: erzwingt server.zip. 7z: erzwingt server.7z (kleinerer Download,
    braucht 7-Zip; falls nicht installiert, wird 7zr.exe nach tools\ geladen).

.PARAMETER UpdateArtifacts
    Fragt das API ab und lädt die Artifacts neu, wenn dort eine andere Version steht.

.PARAMETER ForceArtifacts
    Lädt die Artifacts in jedem Fall neu, auch wenn die Version identisch ist.

.PARAMETER UpdateResources
    Aktualisiert Git-Einträge aus resources.txt per 'git pull --ff-only' (entspricht install-resources.ps1 -Update).

.PARAMETER ForceResources
    Installiert Basis-Ressourcen und alle Manifest-Einträge neu, vorhandene Zielordner werden gelöscht
    (entspricht install-resources.ps1 -Force).

.PARAMETER SkipResources
    Überspringt den Ressourcen-Schritt. Nur für reine Artifact-Updates gedacht, wenn die Ressourcen schon
    installiert sind. Die Prüfung der Basis-Ressourcen läuft trotzdem (siehe Exit-Code 2).

.PARAMETER SetupDatabase
    Schritt 4 richtet die Datenbank ein: setup-database.ps1 -Create -Import (fragt das MariaDB-Root-Passwort
    ab, legt Datenbank und User an, schreibt mysql_connection_string und importiert die SQL-Dateien).
    MariaDB muss installiert sein (setup-database.bat -InstallMariaDB).

.PARAMETER SkipDatabase
    Überspringt Schritt 4 (Datenbank) komplett. Nicht zusammen mit -SetupDatabase.

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -SetupDatabase
.EXAMPLE
    .\install.ps1 -Channel latest -UpdateArtifacts
.EXAMPLE
    .\install.ps1 -UpdateResources
.EXAMPLE
    .\install.ps1 -ForceArtifacts -SkipResources -SkipDatabase

.NOTES
    Exit-Codes: 0 = alles ok, 1 = Fehler (Abbruch, auch -SetupDatabase zusammen mit -SkipDatabase),
    2 = fertig, aber Ressourcen oder Datenbank unvollständig (einzelne Manifest-Einträge fehlgeschlagen,
    Basis-Ressourcen mapmanager/spawnmanager/baseevents fehlen oder setup-database.ps1 meldet einen
    Exit-Code ungleich 0). Fehlt nur der mysql_connection_string, bleibt der Exit-Code unverändert.
#>
[CmdletBinding()]
param(
    [ValidateSet('recommended', 'latest', 'optional')]
    [string]$Channel = 'recommended',

    [ValidateSet('auto', 'zip', '7z')]
    [string]$ArchiveFormat = 'auto',

    [switch]$UpdateArtifacts,
    [switch]$ForceArtifacts,
    [switch]$UpdateResources,
    [switch]$ForceResources,
    [switch]$SkipResources,
    [switch]$SetupDatabase,
    [switch]$SkipDatabase
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------------
$ApiUrl = 'https://changelogs-live.fivem.net/api/changelog/versions/win32/server'
$SevenZrUrl = 'https://www.7-zip.org/a/7zr.exe'

# ---------------------------------------------------------------------------
# Ausgabe-Helfer
# ---------------------------------------------------------------------------
function Write-Info([string]$Message) { Write-Host "[i] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Fail([string]$Message) { Write-Host "[x] $Message" -ForegroundColor Red }
function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor White
}

# ---------------------------------------------------------------------------
# Datei-Helfer (arbeiten immer literal, damit Pfade mit [Klammern] und Leerzeichen funktionieren)
# ---------------------------------------------------------------------------
function New-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($Path)
    }
}

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    } catch {
        # Schreibgeschützte Dateien (z.B. aus .git) freigeben und erneut versuchen
        if (Test-Path -LiteralPath $Path) {
            Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object {
                try { $_.Attributes = ($_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)) } catch { }
            }
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    }
}

function New-TempDirectory([string]$Prefix) {
    $base = [System.IO.Path]::GetTempPath()
    $name = $Prefix + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $base $name
    New-Directory $dir
    return $dir
}

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warn "TLS 1.2 konnte nicht aktiviert werden: $($_.Exception.Message)"
    }
}

function Invoke-Download([string]$Url, [string]$OutFile) {
    # -TimeoutSec begrenzt in PS 5.1 die Wartezeit bis zu den Antwort-Headern (nicht den Transfer),
    # damit eine stumm blockierende Firewall das Skript nicht endlos hängen lässt.
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile -TimeoutSec 60
    } catch {
        throw "Download von '$Url' fehlgeschlagen: $($_.Exception.Message) (Internetverbindung, Proxy oder Firewall prüfen)"
    }
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Download von '$Url' hat keine Datei erzeugt."
    }
}

function Expand-ZipArchive([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Directory $Destination
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}

# ---------------------------------------------------------------------------
# Artifact-Logik
# ---------------------------------------------------------------------------
function Get-ArtifactInfo([string]$ChannelName, [string]$Format) {
    Write-Info "Frage Artifact-Versionen ab: $ApiUrl"
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $ApiUrl -TimeoutSec 30
    } catch {
        throw "Abfrage von '$ApiUrl' fehlgeschlagen: $($_.Exception.Message) (Internetverbindung, Proxy oder Firewall prüfen)"
    }
    $json = $response.Content | ConvertFrom-Json

    $versionKey = $ChannelName
    $urlKey = "${ChannelName}_download"
    $props = $json.PSObject.Properties
    if (-not $props[$urlKey] -or -not $props[$versionKey]) {
        throw "Die API-Antwort enthält die Schlüssel '$versionKey' / '$urlKey' nicht. Hat sich das API geändert?"
    }

    $url = [string]$props[$urlKey].Value
    $version = [string]$props[$versionKey].Value
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($version)) {
        throw "Das API hat für den Kanal '$ChannelName' keine Version oder URL geliefert."
    }

    switch ($Format) {
        'zip' { $url = $url -replace '\.7z$', '.zip' }
        '7z'  { $url = $url -replace '\.zip$', '.7z' }
    }

    $fileName = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
    if (-not ($fileName -match '\.(zip|7z)$')) {
        throw "Unerwarteter Archivname '$fileName' in der URL '$url' (erwartet .zip oder .7z)."
    }

    return New-Object PSObject -Property @{
        Channel  = $ChannelName
        Version  = $version
        Url      = $url
        FileName = $fileName
    }
}

function Get-InstalledVersion([string]$VersionFile) {
    if (-not (Test-Path -LiteralPath $VersionFile)) { return $null }
    foreach ($line in [System.IO.File]::ReadAllLines($VersionFile)) {
        if ($line -match '^\s*version\s*=\s*(.+?)\s*$') { return $Matches[1] }
    }
    return $null
}

function Get-SevenZip([string]$ToolsDir) {
    # 1. 7z.exe im PATH (nur echte Programme, keine Aliase, Funktionen oder .cmd-Shims)
    $cmd = Get-Command '7z.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Path }

    # 2. Standard-Installationspfade
    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe') }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    # 3. 7zr.exe (Konsolen-Version nur für .7z) nach tools\ laden; eine unvollständige Datei wird verworfen
    $sevenZr = Join-Path $ToolsDir '7zr.exe'
    if (Test-Path -LiteralPath $sevenZr) {
        if ((Get-Item -LiteralPath $sevenZr).Length -lt 100KB) {
            Write-Warn "'$sevenZr' ist unvollständig (abgebrochener Download?), wird neu geladen."
            Remove-Item -LiteralPath $sevenZr -Force
        }
    }
    if (-not (Test-Path -LiteralPath $sevenZr)) {
        New-Directory $ToolsDir
        Write-Info "Kein 7-Zip gefunden, lade 7zr.exe von $SevenZrUrl nach '$sevenZr' ..."
        Invoke-Download -Url $SevenZrUrl -OutFile $sevenZr
    }
    return $sevenZr
}

function Install-Artifacts($Info, [string]$ArtifactsDir, [string]$ToolsDir, [string]$Root) {
    $running = @(Get-Process -Name 'FXServer' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $pids = ($running | ForEach-Object { $_.Id }) -join ', '
        throw "FXServer.exe läuft gerade (PID $pids). Bitte den Server beenden und das Skript erneut starten."
    }

    $tmp = New-TempDirectory 'fivem-artifacts'
    $strayTxData = Join-Path $ArtifactsDir 'txData'
    $parkedTxData = Join-Path $Root 'artifacts.txData.tmp'
    try {
        $archive = Join-Path $tmp $Info.FileName
        Write-Info "Lade $($Info.Url) ..."
        Invoke-Download -Url $Info.Url -OutFile $archive
        $size = (Get-Item -LiteralPath $archive).Length
        if ($size -lt 1MB) {
            throw "Der Download ist verdächtig klein ($size Bytes). Bitte URL und Internetverbindung prüfen."
        }
        Write-Ok ("Download abgeschlossen ({0:N1} MB)." -f ($size / 1MB))

        $is7z = $Info.FileName.ToLowerInvariant().EndsWith('.7z')
        $sevenZip = $null
        if ($is7z) {
            $sevenZip = Get-SevenZip -ToolsDir $ToolsDir
            Write-Info "Verwende 7-Zip: $sevenZip"
        }

        # Alten Artifact-Ordner leeren. txData wird NIE gelöscht: ein artifacts\txData (unter Windows unüblich,
        # txAdmin legt standardmäßig <repo>\txData an; Schutz für abweichende Layouts) wird beiseite gelegt
        # und danach zurückgeholt.
        if (Test-Path -LiteralPath $ArtifactsDir) {
            if (Test-Path -LiteralPath $strayTxData) {
                if (Test-Path -LiteralPath $parkedTxData) {
                    throw "Es existiert bereits '$parkedTxData' (Rest eines abgebrochenen Laufs). Bitte manuell prüfen und entfernen bzw. zurückschieben."
                }
                Write-Warn "Gefunden: '$strayTxData' (abweichendes Layout, txAdmin nutzt normalerweise <repo>\txData). Wird gesichert und nach dem Entpacken zurückgelegt."
                # .NET-Move statt Move-Item: -Destination wertet in PS 5.1 Wildcards aus ([ ] im Repo-Pfad)
                [System.IO.Directory]::Move($strayTxData, $parkedTxData)
            }
            # VERSION.txt zuerst löschen: bricht das Leeren oder Entpacken ab, gilt der Ordner danach als unvollständig.
            $oldVersionFile = Join-Path $ArtifactsDir 'VERSION.txt'
            if (Test-Path -LiteralPath $oldVersionFile) { Remove-Item -LiteralPath $oldVersionFile -Force -ErrorAction Stop }
            Write-Info "Leere '$ArtifactsDir' ..."
            Get-ChildItem -LiteralPath $ArtifactsDir -Force | ForEach-Object { Remove-Tree $_.FullName }
        } else {
            New-Directory $ArtifactsDir
        }

        Write-Info "Entpacke $($Info.FileName) nach '$ArtifactsDir' ..."
        if ($is7z) {
            & $sevenZip x $archive "-o$ArtifactsDir" -y
            $rc = $LASTEXITCODE
            if ($rc -eq 1) {
                Write-Warn "7-Zip hat Warnungen gemeldet (Exit-Code 1). Bitte Ausgabe oben prüfen."
            } elseif ($rc -ne 0) {
                throw "7-Zip ist mit Exit-Code $rc fehlgeschlagen."
            }
        } else {
            Expand-ZipArchive -Archive $archive -Destination $ArtifactsDir
        }

        # Falls das Archiv doch einen Wrapper-Ordner hat: Inhalt eine Ebene nach oben ziehen
        $fxExe = Join-Path $ArtifactsDir 'FXServer.exe'
        if (-not (Test-Path -LiteralPath $fxExe)) {
            $subDirs = @(Get-ChildItem -LiteralPath $ArtifactsDir -Force | Where-Object { $_.PSIsContainer })
            if ($subDirs.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $subDirs[0].FullName 'FXServer.exe'))) {
                Write-Info "Das Archiv enthielt einen Wrapper-Ordner '$($subDirs[0].Name)', verschiebe den Inhalt nach oben."
                Get-ChildItem -LiteralPath $subDirs[0].FullName -Force | ForEach-Object {
                    $dest = Join-Path $ArtifactsDir $_.Name
                    if ($_.PSIsContainer) { [System.IO.Directory]::Move($_.FullName, $dest) }
                    else { [System.IO.File]::Move($_.FullName, $dest) }
                }
                Remove-Tree $subDirs[0].FullName
            }
        }
        if (-not (Test-Path -LiteralPath $fxExe)) {
            throw "Nach dem Entpacken wurde keine FXServer.exe in '$ArtifactsDir' gefunden."
        }

        $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        # Gleiche Schlüssel wie lib.sh / Dockerfile, damit VERSION.txt auf beiden Plattformen identisch aufgebaut ist
        $versionContent = "channel=$($Info.Channel)`nversion=$($Info.Version)`nurl=$($Info.Url)`ndownloaded_at=$stamp`nplatform=windows`n"
        [System.IO.File]::WriteAllText((Join-Path $ArtifactsDir 'VERSION.txt'), $versionContent)
        Write-Ok "FXServer $($Info.Version) (Kanal '$($Info.Channel)') installiert."
    } finally {
        if (Test-Path -LiteralPath $parkedTxData) {
            if (Test-Path -LiteralPath $strayTxData) {
                Write-Warn "Konnte '$parkedTxData' nicht zurücklegen, weil '$strayTxData' inzwischen existiert. Bitte manuell zusammenführen."
            } else {
                New-Directory $ArtifactsDir
                [System.IO.Directory]::Move($parkedTxData, $strayTxData)
                Write-Info "txData wurde nach '$strayTxData' zurückgelegt."
            }
        }
        try { Remove-Tree $tmp } catch { Write-Warn "Temporärer Ordner konnte nicht gelöscht werden: $tmp" }
    }
}

# ---------------------------------------------------------------------------
# Basis-Ressourcen
# ---------------------------------------------------------------------------
# server.cfg startet diese Ressourcen aus [cfx-default]. Fehlen sie, fährt der Server hoch, aber niemand spawnt.
$BaseResources = @(
    @{ Name = 'mapmanager';   Path = '[managers]\mapmanager' },
    @{ Name = 'spawnmanager'; Path = '[managers]\spawnmanager' },
    @{ Name = 'baseevents';   Path = '[system]\baseevents' }
)

function Get-MissingBaseResource([string]$ResourcesDir) {
    # .NET statt Test-Path: die Ordnernamen enthalten [Klammern], die PowerShell sonst als Wildcards liest
    $missing = @()
    foreach ($resource in $BaseResources) {
        $manifest = [System.IO.Path]::Combine($ResourcesDir, '[cfx-default]', $resource.Path, 'fxmanifest.lua')
        if (-not [System.IO.File]::Exists($manifest)) { $missing += $resource.Name }
    }
    return $missing
}

# ---------------------------------------------------------------------------
# secrets.cfg
# ---------------------------------------------------------------------------
function Test-LicenseKeyMissing([string]$SecretsFile) {
    # true, wenn kein sv_licenseKey gesetzt ist oder noch der Platzhalter 'changeme' drinsteht
    foreach ($line in [System.IO.File]::ReadAllLines($SecretsFile)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('//')) { continue }
        if ($trimmed -match '^(set\s+)?sv_licenseKey\s+(.*)$') {
            $value = $Matches[2].Trim().Trim('"').Trim("'").Trim()
            if ($value -eq '' -or $value -eq 'changeme') { return $true }
            return $false
        }
    }
    return $true
}

function Test-ConnectionStringConfigured([string]$SecretsFile) {
    # true, wenn secrets.cfg eine aktive Zeile 'set mysql_connection_string ...' enthält
    # (gleiche Regel wie setup-database.ps1: Zeilen mit '#' oder '//' am Anfang zählen nicht)
    if (-not (Test-Path -LiteralPath $SecretsFile -PathType Leaf)) { return $false }
    foreach ($line in [System.IO.File]::ReadAllLines($SecretsFile)) {
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#') -or $trimmed.StartsWith('//')) { continue }
        if ($line -cmatch '^\s*set\s+mysql_connection_string\s+("([^"]*)"|(\S+))') { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Hauptprogramm
# ---------------------------------------------------------------------------
$exitCode = 0
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$artifactsDir = Join-Path $root 'artifacts'
$toolsDir = Join-Path $root 'tools'
$serverDataDir = Join-Path $root 'server-data'
$secretsFile = Join-Path $serverDataDir 'secrets.cfg'
$secretsExample = Join-Path $serverDataDir 'secrets.cfg.example'
$versionFile = Join-Path $artifactsDir 'VERSION.txt'
$fxServerExe = Join-Path $artifactsDir 'FXServer.exe'

$artifactSummary = 'unverändert'
$resourceSummary = 'übersprungen'
$secretsSummary = 'vorhanden'
$databaseSummary = 'nicht ausgeführt'
$dbNextSteps = $false
$licenseMissing = $false

try {
    Write-Host ""
    Write-Host "FiveM Server - Installation (Windows)" -ForegroundColor White
    Write-Host "Repo: $root"

    if ($SetupDatabase -and $SkipDatabase) {
        throw "-SetupDatabase und -SkipDatabase schließen sich aus. Bitte nur einen der beiden Parameter angeben."
    }

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "Es wird mindestens Windows PowerShell 5.1 benötigt (gefunden: $($PSVersionTable.PSVersion))."
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Warn "FXServer benötigt ein 64-Bit-Windows. Dieses System ist 32-Bit, der Server wird vermutlich nicht starten."
    }
    if ($root -match '[^\x20-\x7E]') {
        Write-Warn "Der Repo-Pfad enthält Sonderzeichen oder Umlaute. txAdmin verlangt reine ASCII-Pfade für artifacts\ und txData\ und startet sonst nicht. Bitte das Repo z.B. nach C:\FiveMServer verschieben."
    }
    if (-not (Test-Path -LiteralPath $serverDataDir -PathType Container)) {
        throw "Ordner '$serverDataDir' nicht gefunden. Liegt das Skript unter scripts\windows\ im Repo?"
    }

    Enable-Tls12

    # Vorab prüfen, damit der Hinweis nicht erst nach dem Artifact-Download kommt.
    if (-not $SkipResources -and -not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        throw "git wurde nicht gefunden, wird aber für die Ressourcen benötigt. Bitte installieren: winget install --id Git.Git -e  (danach ein neues Terminal öffnen und install.bat erneut starten). Ohne die Ressourcen aus cfx-server-data spawnt im Spiel niemand."
    }

    # -----------------------------------------------------------------------
    Write-Step "Schritt 1/4: FXServer-Artifacts (Kanal: $Channel)"
    # Installiert heißt: FXServer.exe UND VERSION.txt. VERSION.txt entsteht erst nach dem vollständigen Entpacken,
    # FXServer.exe steht im Archiv dagegen vor libnode22.dll und der VC-Runtime und läge nach einem Abbruch schon da.
    $hasBinary = (Test-Path -LiteralPath $fxServerExe) -and (Test-Path -LiteralPath $versionFile)
    if ((Test-Path -LiteralPath $fxServerExe) -and -not $hasBinary) {
        Write-Warn "artifacts\FXServer.exe ist vorhanden, aber artifacts\VERSION.txt fehlt. Die Artifacts sind vermutlich unvollständig (z. B. abgebrochenes Entpacken) und werden neu geladen."
    }
    $installedVersion = Get-InstalledVersion $versionFile
    $installedText = 'unbekannt'
    if ($installedVersion) { $installedText = $installedVersion }

    if ($hasBinary -and -not $UpdateArtifacts -and -not $ForceArtifacts) {
        Write-Ok "FXServer.exe ist bereits vorhanden (Version: $installedText). Download wird übersprungen."
        Write-Info "Zum Aktualisieren: install.bat -UpdateArtifacts  (oder -ForceArtifacts für einen Neudownload)"
        $artifactSummary = "vorhanden (Version $installedText)"
    } else {
        $info = Get-ArtifactInfo -ChannelName $Channel -Format $ArchiveFormat
        Write-Info "Kanal '$($info.Channel)' liefert Version $($info.Version) ($($info.FileName))."
        if ($hasBinary -and -not $ForceArtifacts -and $installedVersion -eq $info.Version) {
            Write-Ok "Installierte Version $installedVersion ist bereits aktuell. Nichts zu tun (-ForceArtifacts erzwingt den Download)."
            $artifactSummary = "aktuell (Version $installedVersion)"
        } else {
            if ($hasBinary) {
                Write-Info "Aktualisiere von Version $installedText auf $($info.Version) ..."
            }
            Install-Artifacts -Info $info -ArtifactsDir $artifactsDir -ToolsDir $toolsDir -Root $root
            $artifactSummary = "installiert (Version $($info.Version), Kanal $($info.Channel))"
        }
    }

    # -----------------------------------------------------------------------
    Write-Step "Schritt 2/4: Ressourcen (cfx-server-data + resources.txt)"
    if ($SkipResources) {
        Write-Info "Übersprungen (-SkipResources)."
    } else {
        $resourceScript = Join-Path $PSScriptRoot 'install-resources.ps1'
        if (-not (Test-Path -LiteralPath $resourceScript)) {
            throw "install-resources.ps1 wurde nicht gefunden: $resourceScript"
        }
        & $resourceScript -Update:$UpdateResources -Force:$ForceResources
        $rc = $LASTEXITCODE
        if ($rc -eq 0) {
            $resourceSummary = 'ok'
        } elseif ($rc -eq 2) {
            Write-Warn "Einzelne Ressourcen-Einträge konnten nicht installiert werden (siehe oben)."
            $resourceSummary = 'mit Fehlern (siehe oben)'
            $exitCode = 2
        } else {
            throw "install-resources.ps1 ist mit Exit-Code $rc fehlgeschlagen."
        }
    }
    $missingBase = @(Get-MissingBaseResource (Join-Path $serverDataDir 'resources'))
    if ($missingBase.Count -gt 0) {
        $missingText = $missingBase -join ', '
        Write-Warn "Basis-Ressourcen fehlen in server-data\resources\[cfx-default]: $missingText. Der Server startet, aber im Spiel spawnt niemand."
        Write-Warn "Abhilfe: install.bat ohne -SkipResources ausführen (ist [cfx-default] nicht leer, aber kaputt: install.bat -ForceResources)."
        $resourceSummary = "unvollständig, es fehlen: $missingText"
        $exitCode = 2
    }

    # -----------------------------------------------------------------------
    Write-Step "Schritt 3/4: server-data\secrets.cfg"
    if (-not (Test-Path -LiteralPath $secretsFile)) {
        if (Test-Path -LiteralPath $secretsExample) {
            [System.IO.File]::Copy($secretsExample, $secretsFile, $false)
            Write-Ok "secrets.cfg aus secrets.cfg.example angelegt."
            $secretsSummary = 'neu angelegt, bitte ausfüllen'
        } else {
            Write-Warn "Weder secrets.cfg noch secrets.cfg.example gefunden. Bitte secrets.cfg manuell anlegen (sv_licenseKey ...)."
            $secretsSummary = 'fehlt'
        }
    } else {
        Write-Ok "secrets.cfg ist vorhanden und bleibt unverändert."
    }
    if (Test-Path -LiteralPath $secretsFile) {
        $licenseMissing = Test-LicenseKeyMissing $secretsFile
        if ($licenseMissing) {
            Write-Warn "In secrets.cfg fehlt noch der Lizenzschlüssel (sv_licenseKey steht auf 'changeme' oder ist leer)."
        } else {
            Write-Ok "sv_licenseKey ist in secrets.cfg gesetzt."
        }
    } else {
        $licenseMissing = $true
    }

    # -----------------------------------------------------------------------
    Write-Step "Schritt 4/4: Datenbank (MariaDB)"
    $dbScript = Join-Path $PSScriptRoot 'setup-database.ps1'
    $dbRc = $null
    if ($SkipDatabase) {
        Write-Info "Übersprungen (-SkipDatabase)."
        $databaseSummary = 'übersprungen'
    } elseif (-not (Test-Path -LiteralPath $dbScript)) {
        throw "setup-database.ps1 wurde nicht gefunden: $dbScript"
    } elseif ($SetupDatabase) {
        Write-Info "Richte Datenbank ein und importiere SQL-Dateien (setup-database.ps1 -Create -Import) ..."
        $global:LASTEXITCODE = 0
        & $dbScript -Create -Import
        $dbRc = $global:LASTEXITCODE
    } elseif (Test-ConnectionStringConfigured $secretsFile) {
        Write-Info "mysql_connection_string ist gesetzt, importiere ausstehende SQL-Dateien (setup-database.ps1 -Import) ..."
        $global:LASTEXITCODE = 0
        & $dbScript -Import
        $dbRc = $global:LASTEXITCODE
    } else {
        Write-Warn "In secrets.cfg fehlt mysql_connection_string. Qbox startet ohne Datenbank nicht."
        $databaseSummary = 'nicht eingerichtet'
        $dbNextSteps = $true
    }
    if ($null -ne $dbRc) {
        if ($dbRc -eq 0) {
            $databaseSummary = 'ok'
        } else {
            Write-Warn "setup-database.ps1 ist mit Exit-Code $dbRc beendet worden (siehe Meldungen oben)."
            $databaseSummary = "unvollständig (setup-database.ps1 Exit-Code $dbRc)"
            $exitCode = 2
        }
    }
} catch {
    Write-Host ""
    Write-Fail "Installation abgebrochen: $($_.Exception.Message)"
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Zusammenfassung und nächste Schritte
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================================" -ForegroundColor White
Write-Host " Zusammenfassung" -ForegroundColor White
Write-Host "=============================================================" -ForegroundColor White
Write-Host "  Repo:         $root"
Write-Host "  Artifacts:    $artifactSummary"
Write-Host "  Ressourcen:   $resourceSummary"
Write-Host "  secrets.cfg:  $secretsSummary"
Write-Host "  Datenbank:    $databaseSummary"
if ($licenseMissing) {
    Write-Host ""
    Write-Warn "WICHTIG: Ohne Lizenzschlüssel startet der Spielserver nicht. Trage in server-data\secrets.cfg"
    Write-Warn "         sv_licenseKey ein. Einen kostenlosen Key bekommst du unter https://portal.cfx.re/"
}
if ($dbNextSteps) {
    Write-Host ""
    Write-Host " Datenbank einrichten (Pflicht für Qbox)" -ForegroundColor White
    Write-Host "  1. scripts\windows\setup-database.bat -InstallMariaDB"
    Write-Host "  2. scripts\windows\setup-database.bat -Create -Import"
    Write-Host "  Anleitung: docs\datenbank.md"
}
Write-Host ""
Write-Host " Nächste Schritte" -ForegroundColor White
Write-Host "  1. server-data\secrets.cfg öffnen und sv_licenseKey eintragen (https://portal.cfx.re/)."
Write-Host "  2. scripts\windows\start.bat doppelklicken (Start mit txAdmin)"
Write-Host "     oder scripts\windows\start-direct.bat (Direktstart ohne txAdmin, nutzt server.cfg direkt)."
Write-Host "  3. txAdmin im Browser öffnen: http://localhost:40120  (PIN steht in der Server-Konsole)."
Write-Host "     Beim ersten Mal in txAdmin 'Existing Server Data' wählen: Ordner $serverDataDir, CFG server.cfg."
Write-Host "  4. Im Spiel F8 drücken und eingeben: connect localhost:30120"
Write-Host "  Hinweis: Nicht mit der Maus ins Serverfenster klicken. Eine Markierung hält den Server an, Esc hebt sie auf."
Write-Host "  Freunde verbinden: docs\windows-lokal.md, Abschnitt 'Freunde verbinden'."
Write-Host "  Nur Freunde zulassen: docs\linux-server.md, Abschnitt 'Nur Freunde zulassen (License Allowlist)'."
Write-Host ""
if ($exitCode -eq 2) {
    Write-Warn "Fertig, aber Ressourcen oder Datenbank sind unvollständig (Exit-Code 2). Bitte die Warnungen oben lesen."
} else {
    Write-Ok "Fertig."
}
exit $exitCode
