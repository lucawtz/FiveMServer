<#
.SYNOPSIS
    Installiert die Basis-Ressourcen (cfx-server-data) und die Einträge aus server-data\resources.txt.

.DESCRIPTION
    1. Klont https://github.com/citizenfx/cfx-server-data.git (--depth 1) in einen temporären Ordner und
       kopiert dessen resources\* nach server-data\resources\[cfx-default]\ (übersprungen, wenn dort schon
       etwas liegt, außer mit -Force).
    2. Verarbeitet das Manifest server-data\resources.txt:
         # Kommentar- und Leerzeilen werden ignoriert (auch ' # Kommentar' am Zeilenende)
         git <ziel> <url> [ref]   -> git clone --depth 1 [--branch ref] nach server-data\resources\<ziel>
         zip <ziel> <url>         -> Download + Entpacken nach server-data\resources\<ziel>
                                     (hat das Archiv genau EINEN Oberordner, wird dessen Inhalt zu <ziel>)
       <ziel> ist relativ zu server-data\resources\ und darf Klammer-Ordner enthalten, z.B. [vendor]/oxmysql.
       Vorhandene Ziele werden übersprungen, außer mit -Update (git pull --ff-only bei Git-Zielen)
       oder -Force (Ziel löschen und neu klonen bzw. neu herunterladen).
    Voraussetzung: git im PATH (winget install Git.Git).

.PARAMETER Update
    Führt bei vorhandenen Git-Zielen 'git pull --ff-only' aus. Zip-Ziele bleiben unverändert.

.PARAMETER Force
    Installiert [cfx-default] neu und löscht vorhandene Manifest-Ziele vor dem erneuten Klonen/Entpacken.

.PARAMETER ManifestPath
    Alternativer Pfad zum Manifest. Standard: <repo>\server-data\resources.txt

.EXAMPLE
    .\install-resources.ps1
.EXAMPLE
    .\install-resources.ps1 -Update
.EXAMPLE
    .\install-resources.ps1 -Force -ManifestPath C:\temp\meine-resources.txt

.NOTES
    Exit-Codes: 0 = ok, 1 = Abbruch (z.B. git fehlt, Klonen von cfx-server-data fehlgeschlagen),
    2 = fertig, aber mindestens ein Manifest-Eintrag ist fehlgeschlagen.
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Force,
    [string]$ManifestPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BaseRepoUrl = 'https://github.com/citizenfx/cfx-server-data.git'
$BaseTargetName = '[cfx-default]'

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
# Datei-Helfer (immer literal: Klammern und Leerzeichen in Pfaden sind hier normal)
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
        # Schreibgeschützte Dateien (typisch für .git\objects) freigeben und erneut versuchen
        if (Test-Path -LiteralPath $Path) {
            Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object {
                try { $_.Attributes = ($_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)) } catch { }
            }
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    }
}

function Copy-Tree([string]$Source, [string]$Destination) {
    New-Directory $Destination
    foreach ($file in [System.IO.Directory]::GetFiles($Source)) {
        $name = [System.IO.Path]::GetFileName($file)
        [System.IO.File]::Copy($file, (Join-Path $Destination $name), $true)
    }
    foreach ($dir in [System.IO.Directory]::GetDirectories($Source)) {
        $name = [System.IO.Path]::GetFileName($dir)
        Copy-Tree -Source $dir -Destination (Join-Path $Destination $name)
    }
}

function New-TempDirectory([string]$Prefix) {
    $base = [System.IO.Path]::GetTempPath()
    $name = $Prefix + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $base $name
    New-Directory $dir
    return $dir
}

function Test-DirectoryHasContent([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $first = @(Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)
    return ($first.Count -gt 0)
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
# git-Helfer
# ---------------------------------------------------------------------------
function Test-GitAvailable {
    return [bool](Get-Command 'git' -ErrorAction SilentlyContinue)
}

function Assert-Git {
    if (-not (Test-GitAvailable)) {
        throw "git wurde nicht gefunden. Bitte installieren: winget install Git.Git  (danach ein neues Terminal öffnen)."
    }
}

function Invoke-Git([string[]]$GitArgs, [switch]$Quiet) {
    # git schreibt Fortschritt auf stderr; damit das unter $ErrorActionPreference='Stop' nicht als Fehler
    # zählt, wird die Einstellung nur für den Aufruf gelockert. Rückgabe: Exit-Code von git.
    # -Quiet unterdrückt die Ausgabe (für reine Prüfaufrufe).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) { & git @GitArgs 2>&1 | Out-Null } else { & git @GitArgs | Out-Host }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

# ---------------------------------------------------------------------------
# Basis-Ressourcen (cfx-server-data)
# ---------------------------------------------------------------------------
function Install-BaseResources([string]$ResourcesDir, [bool]$ForceInstall) {
    $target = Join-Path $ResourcesDir $BaseTargetName
    New-Directory $target

    $hasContent = Test-DirectoryHasContent $target
    if ($hasContent -and -not $ForceInstall) {
        Write-Ok "$BaseTargetName ist bereits befüllt, wird übersprungen (mit -Force neu installieren)."
        return 'übersprungen (vorhanden)'
    }

    Assert-Git
    $tmp = New-TempDirectory 'fivem-cfx-default'
    try {
        $clone = Join-Path $tmp 'cfx-server-data'
        Write-Info "Klone $BaseRepoUrl (--depth 1) ..."
        $rc = Invoke-Git @('clone', '--depth', '1', '--', $BaseRepoUrl, $clone)
        if ($rc -ne 0) { throw "git clone von cfx-server-data ist fehlgeschlagen (Exit-Code $rc)." }

        $sourceResources = Join-Path $clone 'resources'
        if (-not (Test-Path -LiteralPath $sourceResources -PathType Container)) {
            throw "Im geklonten Repository fehlt der Ordner 'resources'."
        }

        if ($hasContent) {
            Write-Info "Leere '$target' (-Force) ..."
            Get-ChildItem -LiteralPath $target -Force | ForEach-Object { Remove-Tree $_.FullName }
        }

        $count = 0
        foreach ($item in Get-ChildItem -LiteralPath $sourceResources -Force) {
            # Der leere [local]-Ordner aus cfx-server-data wird nicht übernommen, wir haben unser eigenes [local]
            if ($item.Name -eq '[local]') { continue }
            if ($item.PSIsContainer) {
                Copy-Tree -Source $item.FullName -Destination (Join-Path $target $item.Name)
            } else {
                [System.IO.File]::Copy($item.FullName, (Join-Path $target $item.Name), $true)
            }
            $count++
        }
        Write-Ok "$count Einträge aus cfx-server-data nach $BaseTargetName kopiert."
        return 'installiert'
    } finally {
        try { Remove-Tree $tmp } catch { Write-Warn "Temporärer Ordner konnte nicht gelöscht werden: $tmp" }
    }
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------
function ConvertTo-SafeTarget([string]$Target) {
    # Gibt den normalisierten relativen Zielpfad zurück oder $null, wenn er unzulässig ist.
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
    $normalized = $Target.Trim().Replace('/', '\').TrimEnd('\')
    if ($normalized -eq '') { return $null }
    if ([System.IO.Path]::IsPathRooted($normalized)) { return $null }
    if ($normalized.Contains(':')) { return $null }
    foreach ($segment in ($normalized -split '\\')) {
        if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..') { return $null }
    }
    return $normalized
}

function Read-Manifest([string]$Path) {
    $entries = @()
    $lines = [System.IO.File]::ReadAllLines($Path)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        $line = $lines[$i].Trim()
        # Wie lib.sh: Kommentar am Zeilenende entfernen (nur '#' nach Leerzeichen, damit URLs mit '#' heil bleiben)
        $line = ($line -replace '\s+#.*$', '').Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }

        $tokens = @($line -split '\s+')
        $type = $tokens[0].ToLowerInvariant()
        $entry = New-Object PSObject -Property @{
            Line    = $lineNo
            Type    = $type
            Target  = $null
            Url     = $null
            Ref     = $null
            Error   = $null
        }

        if ($type -eq 'git') {
            if ($tokens.Count -lt 3) {
                $entry.Error = "Erwartet: git <ziel> <url> [ref]"
            } else {
                # Wie lib.sh: überzählige Felder nur mit Warnung ignorieren
                if ($tokens.Count -gt 4) { Write-Warn "Zeile ${lineNo}: zu viele Felder, ignoriere Rest '$($tokens[4..($tokens.Count - 1)] -join ' ')'" }
                $entry.Target = ConvertTo-SafeTarget $tokens[1]
                $entry.Url = $tokens[2]
                if ($tokens.Count -ge 4) { $entry.Ref = $tokens[3] }
            }
        } elseif ($type -eq 'zip') {
            if ($tokens.Count -lt 3) {
                $entry.Error = "Erwartet: zip <ziel> <url>"
            } else {
                if ($tokens.Count -gt 3) { Write-Warn "Zeile ${lineNo}: zu viele Felder, ignoriere Rest '$($tokens[3..($tokens.Count - 1)] -join ' ')'" }
                $entry.Target = ConvertTo-SafeTarget $tokens[1]
                $entry.Url = $tokens[2]
            }
        } else {
            $entry.Error = "Unbekannter Typ '$($tokens[0])' (erlaubt: git, zip)"
        }

        if (-not $entry.Error -and -not $entry.Target) {
            $entry.Error = "Unzulässiges Ziel '$($tokens[1])' (muss relativ sein, ohne '..' und ohne Laufwerk)"
        }
        if (-not $entry.Error -and -not ($entry.Url -match '^https?://')) {
            $entry.Error = "URL muss mit http:// oder https:// beginnen: '$($entry.Url)'"
        }
        $entries += $entry
    }
    return ,$entries
}

function Install-GitEntry($Entry, [string]$TargetPath, [bool]$DoUpdate, [bool]$DoForce) {
    if (Test-Path -LiteralPath $TargetPath) {
        if ($DoForce) {
            Write-Info "Entferne '$TargetPath' (-Force) ..."
            Remove-Tree $TargetPath
        } elseif ($DoUpdate) {
            if (Test-Path -LiteralPath (Join-Path $TargetPath '.git')) {
                Assert-Git
                # Auf ein Tag geklonte Ziele stehen auf einem detached HEAD, dort ist 'git pull' nicht möglich
                $rcHead = Invoke-Git @('-C', $TargetPath, 'symbolic-ref', '-q', 'HEAD') -Quiet
                if ($rcHead -ne 0) {
                    Write-Info "'$TargetPath' steht auf einem Tag bzw. Commit (detached HEAD), 'git pull' ist hier nicht möglich. Übersprungen (für ein neueres Tag: Ref im Manifest ändern und -Force verwenden)."
                    return 'übersprungen'
                }
                Write-Info "git pull --ff-only in '$TargetPath' ..."
                $rc = Invoke-Git @('-C', $TargetPath, 'pull', '--ff-only')
                if ($rc -ne 0) { throw "git pull --ff-only fehlgeschlagen (Exit-Code $rc). Lokale Änderungen? Mit -Force neu klonen." }
                return 'aktualisiert'
            } else {
                Write-Warn "'$TargetPath' existiert, ist aber kein Git-Repository. Übersprungen (mit -Force neu klonen)."
                return 'übersprungen'
            }
        } else {
            Write-Info "Ziel existiert bereits, übersprungen (-Update aktualisiert, -Force klont neu)."
            return 'übersprungen'
        }
    }

    Assert-Git
    New-Directory ([System.IO.Path]::GetDirectoryName($TargetPath))
    $gitArgs = @('clone', '--depth', '1')
    if ($Entry.Ref) { $gitArgs += @('--branch', $Entry.Ref) }
    $gitArgs += @('--', $Entry.Url, $TargetPath)
    Write-Info "git $($gitArgs -join ' ')"
    $rc = Invoke-Git $gitArgs
    if ($rc -ne 0) {
        if (Test-Path -LiteralPath $TargetPath) { try { Remove-Tree $TargetPath } catch { } }
        throw "git clone fehlgeschlagen (Exit-Code $rc). Hinweis: [ref] muss ein Branch oder Tag sein, kein Commit-Hash."
    }
    return 'installiert'
}

function Install-ZipEntry($Entry, [string]$TargetPath, [bool]$DoForce) {
    if ((Test-Path -LiteralPath $TargetPath) -and -not $DoForce) {
        Write-Info "Ziel existiert bereits, übersprungen (-Force lädt neu herunter)."
        return 'übersprungen'
    }

    $tmp = New-TempDirectory 'fivem-zip'
    try {
        $archive = Join-Path $tmp 'archive.zip'
        Write-Info "Lade $($Entry.Url) ..."
        Invoke-Download -Url $Entry.Url -OutFile $archive

        $extractDir = Join-Path $tmp 'extract'
        Expand-ZipArchive -Archive $archive -Destination $extractDir

        $top = @(Get-ChildItem -LiteralPath $extractDir -Force)
        if ($top.Count -eq 0) { throw "Das Archiv ist leer." }
        $source = $extractDir
        if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
            $source = $top[0].FullName
            Write-Info "Archiv hat genau einen Oberordner '$($top[0].Name)', dessen Inhalt wird zu '$($Entry.Target)'."
        }

        if (Test-Path -LiteralPath $TargetPath) {
            Write-Info "Entferne '$TargetPath' (-Force) ..."
            Remove-Tree $TargetPath
        }
        Copy-Tree -Source $source -Destination $TargetPath
        return 'installiert'
    } finally {
        try { Remove-Tree $tmp } catch { Write-Warn "Temporärer Ordner konnte nicht gelöscht werden: $tmp" }
    }
}

# ---------------------------------------------------------------------------
# Hauptprogramm
# ---------------------------------------------------------------------------
$exitCode = 0
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$resourcesDir = Join-Path $root 'server-data\resources'
$manifestExplicit = -not [string]::IsNullOrWhiteSpace($ManifestPath)
if (-not $manifestExplicit) {
    $ManifestPath = Join-Path $root 'server-data\resources.txt'
} elseif (-not [System.IO.Path]::IsPathRooted($ManifestPath)) {
    $ManifestPath = [System.IO.Path]::GetFullPath((Join-Path $PWD.ProviderPath $ManifestPath))
}

$env:GIT_TERMINAL_PROMPT = '0'
# Git Credential Manager (Git for Windows): keinen GUI-Dialog öffnen, private Repos schlagen sofort fehl
$env:GCM_INTERACTIVE = 'Never'
$baseSummary = 'nicht ausgeführt'
$results = @()

try {
    Write-Host ""
    Write-Host "FiveM Server - Ressourcen installieren" -ForegroundColor White
    Write-Host "Ressourcen-Ordner: $resourcesDir"
    if (-not (Test-Path -LiteralPath (Join-Path $root 'server-data') -PathType Container)) {
        throw "Ordner 'server-data' nicht gefunden unter '$root'. Liegt das Skript unter scripts\windows\ im Repo?"
    }
    New-Directory $resourcesDir
    Enable-Tls12

    Write-Step "Basis-Ressourcen (cfx-server-data -> $BaseTargetName)"
    $baseSummary = Install-BaseResources -ResourcesDir $resourcesDir -ForceInstall ([bool]$Force)

    Write-Step "Manifest: $ManifestPath"
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        if ($manifestExplicit) { throw "Das angegebene Manifest wurde nicht gefunden: $ManifestPath" }
        Write-Warn "Kein Manifest gefunden (server-data\resources.txt fehlt), Schritt wird übersprungen."
    } else {
        $entries = Read-Manifest $ManifestPath
        if ($entries.Count -eq 0) {
            Write-Info "Das Manifest enthält keine aktiven Einträge (nur Kommentare). Nichts zu tun."
        }
        foreach ($entry in $entries) {
            $status = 'fehlgeschlagen'
            $message = ''
            $label = "Zeile $($entry.Line)"
            if ($entry.Target) { $label = "$($entry.Target) (Zeile $($entry.Line))" }
            Write-Host ""
            if ($entry.Error) {
                Write-Fail "${label}: $($entry.Error)"
                $message = $entry.Error
            } else {
                $refText = ''
                if ($entry.Ref) { $refText = " @ $($entry.Ref)" }
                Write-Info "[$($entry.Type)] $($entry.Target)  <-  $($entry.Url)$refText"
                $targetPath = Join-Path $resourcesDir $entry.Target
                try {
                    if ($entry.Type -eq 'git') {
                        $status = Install-GitEntry -Entry $entry -TargetPath $targetPath -DoUpdate ([bool]$Update) -DoForce ([bool]$Force)
                    } else {
                        $status = Install-ZipEntry -Entry $entry -TargetPath $targetPath -DoForce ([bool]$Force)
                    }
                    Write-Ok "$($entry.Target): $status"
                } catch {
                    $status = 'fehlgeschlagen'
                    $message = $_.Exception.Message
                    Write-Fail "$($entry.Target): $message"
                }
            }
            $results += New-Object PSObject -Property @{
                Label   = $label
                Type    = $entry.Type
                Status  = $status
                Message = $message
            }
        }
    }
} catch {
    Write-Host ""
    Write-Fail "Ressourcen-Installation abgebrochen: $($_.Exception.Message)"
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
    }
    exit 1
}

# ---------------------------------------------------------------------------
# Zusammenfassung
# ---------------------------------------------------------------------------
$failed = @($results | Where-Object { $_.Status -eq 'fehlgeschlagen' })
$installed = @($results | Where-Object { $_.Status -eq 'installiert' }).Count
$updated = @($results | Where-Object { $_.Status -eq 'aktualisiert' }).Count
$skipped = @($results | Where-Object { $_.Status -eq 'übersprungen' }).Count

Write-Host ""
Write-Host "-------------------------------------------------------------" -ForegroundColor White
Write-Host " Ressourcen-Zusammenfassung" -ForegroundColor White
Write-Host "-------------------------------------------------------------" -ForegroundColor White
Write-Host "  $BaseTargetName : $baseSummary"
Write-Host "  Manifest-Einträge: $($results.Count) gesamt, $installed installiert, $updated aktualisiert, $skipped übersprungen, $($failed.Count) fehlgeschlagen"
foreach ($f in $failed) {
    Write-Host "    - $($f.Label): $($f.Message)" -ForegroundColor Red
}
Write-Host "  Eigene Ressourcen gehören nach server-data\resources\[local]\ und werden per 'ensure <name>' in server.cfg gestartet."

if ($failed.Count -gt 0) {
    Write-Warn "Mindestens ein Manifest-Eintrag ist fehlgeschlagen (Exit-Code 2)."
    $exitCode = 2
} else {
    Write-Ok "Ressourcen sind bereit."
}
exit $exitCode
