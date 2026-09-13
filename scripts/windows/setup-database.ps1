<#
.SYNOPSIS
    Richtet die MariaDB-Datenbank für den FiveM-Server ein und importiert die SQL-Dateien aus server-data\database.txt.

.DESCRIPTION
    Aktionen (Reihenfolge bei Kombination: -InstallMariaDB, -Create, -Import):
      -InstallMariaDB  installiert MariaDB Server per winget (interaktiver Assistent).
      -Create          legt Datenbank und User an (Anmeldung als root über 127.0.0.1) und schreibt
                       mysql_connection_string in server-data\secrets.cfg.
      -Import          importiert ausstehende SQL-Dateien aus server-data\database.txt (Standard, wenn keine
                       andere Aktion angegeben ist).
      -MarkApplied     trägt ausstehende oder geänderte Dateien als importiert ein, ohne sie auszuführen.
      -DryRun          zeigt nur an, was passieren würde.
      -Check           prüft nur database.txt, ohne Datenbank.

    Jede Datei aus database.txt wird genau einmal importiert. Die Tabelle repo_sql_imports in der Datenbank
    merkt sich Pfad, sha256 und Zeitpunkt. Ändert sich eine importierte Datei, wird sie nur bei Zeilen mit
    'rerun' erneut ausgeführt, sonst gibt es eine Warnung. Der Import stoppt bei der ersten fehlerhaften Datei.
    Die Zugangsdaten stehen nur in einer temporären Optionsdatei (--defaults-file), nie auf der Kommandozeile.
    Anleitung: docs\datenbank.md

.PARAMETER Create
    Datenbank und User anlegen. Fragt einmal das MariaDB-Root-Passwort ab (aus dem Installationsassistenten).

.PARAMETER ResetPassword
    Nur mit -Create: einem vorhandenen User ein neues Passwort geben und den String neu schreiben.

.PARAMETER DbName
    Nur mit -Create: Name der Datenbank. Standard: fivem

.PARAMETER DbUser
    Nur mit -Create: Name des Datenbank-Users. Standard: fivem

.PARAMETER Port
    Nur mit -Create: TCP-Port der lokalen MariaDB. Standard: 3306
    Ohne -Port gilt der Port aus einem vorhandenen mysql_connection_string. Weicht ein angegebener -Port davon ab,
    bricht -Create ab, außer mit -ResetPassword (dann wird ein neuer String geschrieben).

.PARAMETER Import
    Ausstehende SQL-Dateien importieren (Standard ohne andere Aktion).

.PARAMETER MarkApplied
    Ausstehende oder geänderte Dateien als importiert eintragen, ohne sie auszuführen. Ohne -Only betrifft das
    ALLE ausstehenden Dateien, also nur für eine Datenbank verwenden, die wirklich vollständig ist.

.PARAMETER Only
    Beschränkt Import, MarkApplied und DryRun auf diese Pfade aus database.txt (mehrere mit Komma trennen).

.PARAMETER DryRun
    Nur anzeigen, nichts ändern.

.PARAMETER Check
    Nur database.txt prüfen, keine Datenbank. Nur zusammen mit -ManifestPath.

.PARAMETER InstallMariaDB
    MariaDB Server per winget installieren (interaktiver Assistent), falls noch kein mariadb.exe gefunden wird.

.PARAMETER MariaDbBin
    Ordner mit mariadb.exe oder Pfad zu mariadb.exe, falls die automatische Suche nichts findet.

.PARAMETER ManifestPath
    Anderes SQL-Manifest. Standard: <repo>\server-data\database.txt

.PARAMETER SecretsPath
    Andere secrets.cfg. Standard: <repo>\server-data\secrets.cfg

.EXAMPLE
    .\setup-database.ps1 -InstallMariaDB
.EXAMPLE
    .\setup-database.ps1 -Create -Import
.EXAMPLE
    .\setup-database.ps1 -DryRun
.EXAMPLE
    .\setup-database.ps1 -MarkApplied -Only '[vendor]/[npwd]/npwd/import.sql'
.EXAMPLE
    .\setup-database.ps1 -Check

.NOTES
    Exit-Codes: 0 = ok (auch mit Warnungen zu geänderten Dateien), 1 = Abbruch vor bzw. ohne Datenbankarbeit
    (Parameter, database.txt, secrets.cfg, MariaDB-Client fehlt, winget, Namen, Voraussetzungen von -Create),
    2 = Datenbank nicht erreichbar, Anmeldung fehlgeschlagen, MariaDB zu alt oder kein MariaDB (auch bei -DryRun),
    3 = SQL-Fehler (Import oder Eintrag fehlgeschlagen, ausstehende Datei fehlt, CREATE/GRANT fehlgeschlagen).
#>
[CmdletBinding()]
param(
    [switch]$Create,
    [switch]$ResetPassword,
    [string]$DbName = 'fivem',
    [string]$DbUser = 'fivem',
    [int]$Port = 3306,
    [switch]$Import,
    [switch]$MarkApplied,
    [string[]]$Only,
    [switch]$DryRun,
    [switch]$Check,
    [switch]$InstallMariaDB,
    [string]$MariaDbBin,
    [string]$ManifestPath,
    [string]$SecretsPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:BoundParams = $PSBoundParameters
$script:ExitCode = 1
$script:DbTempDir = $null
$script:DefaultsCounter = 0

$MinMajor = 10
$MinMinor = 9
$StatusWidth = 11
$UriPattern = '^(?:([^:/?#.]+):)?(?://(?:([^/?#]*)@)?([\w\d\-\u0100-\uffff.%]*)(?::([0-9]+))?)?([^?#]+)?(?:\?([^#]*))?$'
$SecretsLinePattern = '^\s*set\s+mysql_connection_string\s+("([^"]*)"|(\S+))'
$CfgLinePattern = '^\s*#?\s*(set\s+)?mysql_connection_string(\s|$)'
$TrackingTableDdl = @'
CREATE TABLE IF NOT EXISTS `repo_sql_imports` (
  `file_path` VARCHAR(512) NOT NULL,
  `sha256` CHAR(64) NOT NULL,
  `imported_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `applied_by` VARCHAR(16) NOT NULL DEFAULT 'import',
  PRIMARY KEY (`file_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
'@

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

function New-ExitError([int]$Code, [string]$Message) {
    # Fehler mit Exit-Code (siehe .NOTES). Wird im Hauptprogramm ausgewertet.
    $exception = New-Object System.Exception $Message
    $exception.Data['FxExitCode'] = $Code
    return $exception
}

function Get-ExitErrorCode($Exception) {
    # Exit-Code aus New-ExitError, sonst $null
    if ($null -ne $Exception -and $null -ne $Exception.Data -and $Exception.Data.Contains('FxExitCode')) {
        return [int]$Exception.Data['FxExitCode']
    }
    return $null
}

# ---------------------------------------------------------------------------
# Datei-Helfer (immer literal, Pfade mit [Klammern] sind hier normal)
# ---------------------------------------------------------------------------
function New-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($Path)
    }
}

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
}

function New-TempDirectory([string]$Prefix) {
    $base = [System.IO.Path]::GetTempPath()
    $name = $Prefix + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $base $name
    New-Directory $dir
    return $dir
}

function Resolve-UserPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $PWD.ProviderPath $Path))
}

function Join-ResourcePath([string]$ResourcesDir, [string]$RelativePath) {
    # Manifest-Pfade nutzen immer '/'. Jedes Segment einzeln anhängen (Join-Path mit nur einem Kind).
    $result = $ResourcesDir
    foreach ($segment in $RelativePath.Split('/')) {
        $result = Join-Path $result $segment
    }
    return $result
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FirstLines([string]$Text, [int]$Count) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '(keine Meldung)' }
    $lines = @($Text.Trim() -split "`r?`n" | Select-Object -First $Count)
    return ($lines -join ' | ')
}

function New-RandomHex {
    # 32 Hex-Zeichen (16 Zufallsbytes aus dem Krypto-Zufallsgenerator)
    $bytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Test-ParamGiven([string]$Name) {
    # true, wenn der Parameter angegeben wurde (Schalter nur, wenn sie eingeschaltet sind)
    if (-not $script:BoundParams.ContainsKey($Name)) { return $false }
    $value = $script:BoundParams[$Name]
    if ($value -is [System.Management.Automation.SwitchParameter]) { return $value.IsPresent }
    return $true
}

# ---------------------------------------------------------------------------
# SQL-Manifest database.txt
# ---------------------------------------------------------------------------
function Test-SqlPath([string]$Path) {
    # Rückgabe: $null, wenn der Pfad gültig ist, sonst der Grund
    if (-not ($Path -cmatch '^[A-Za-z0-9._/\[\]-]+$')) { return "erlaubt sind nur A-Z a-z 0-9 . _ - [ ] /" }
    if (-not $Path.EndsWith('.sql', [System.StringComparison]::OrdinalIgnoreCase)) { return "Endung muss .sql sein" }
    if ($Path.StartsWith('/')) { return "muss relativ zu server-data/resources/ sein" }
    foreach ($segment in $Path.Split('/')) {
        if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..') { return "keine leeren, '.'- oder '..'-Segmente" }
    }
    return $null
}

function Read-SqlManifest([string]$Path) {
    # Rückgabe: Objekt mit Entries (Line, Path, Rerun) und Errors (Meldungen)
    $entries = @()
    $errors = @()
    $seen = @{}
    $lines = [System.IO.File]::ReadAllLines($Path)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        $line = $lines[$i].Replace("`r", '').Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $tokens = @($line -split '\s+')
        $sqlPath = $tokens[0]
        $rerun = $false
        if ($tokens.Count -ge 2) {
            if ($tokens.Count -eq 2 -and $tokens[1] -ceq 'rerun') {
                $rerun = $true
            } else {
                $bad = $tokens[1]
                if ($tokens[1] -ceq 'rerun') { $bad = $tokens[2] }
                $errors += "Zeile ${lineNo}: unbekannte Option '$bad' (erlaubt: rerun)"
                continue
            }
        }
        $reason = Test-SqlPath $sqlPath
        if ($reason) {
            $errors += "Zeile ${lineNo}: ungültiger SQL-Pfad '$sqlPath' ($reason)"
            continue
        }
        # Doppelte Pfade ohne Groß-/Kleinschreibung (Dateisystem unter Windows und Collation der Tracking-Tabelle)
        if ($seen.ContainsKey($sqlPath)) {
            $errors += "Zeile ${lineNo}: SQL-Pfad '$sqlPath' steht doppelt in der Datei (zuerst in Zeile $($seen[$sqlPath]))"
            continue
        }
        $seen[$sqlPath] = $lineNo
        $entries += New-Object PSObject -Property @{ Line = $lineNo; Path = $sqlPath; Rerun = $rerun }
    }
    return New-Object PSObject -Property @{ Entries = $entries; Errors = $errors }
}

function ConvertTo-OnlyList([string[]]$Values) {
    # -Only über 'powershell -File' kommt als EIN String an: an ',' und ';' trennen, Anführungszeichen entfernen
    $list = @()
    foreach ($value in @($Values)) {
        if ($null -eq $value) { continue }
        foreach ($part in ($value -split '[,;]')) {
            $item = $part.Trim().Trim("'").Trim('"').Trim().Replace('\', '/')
            if ($item -ne '') { $list += $item }
        }
    }
    return ,$list
}

# ---------------------------------------------------------------------------
# secrets.cfg und mysql_connection_string (Regeln wie oxmysql 2.14.1)
# ---------------------------------------------------------------------------
function Get-SecretsConnectionString([string]$Path) {
    # Rückgabe: Objekt mit Status (ok, none, missing, unreadable), Value und WrongSetter
    $result = New-Object PSObject -Property @{ Status = 'none'; Value = $null; WrongSetter = $false }
    if (-not [System.IO.File]::Exists($Path)) {
        $result.Status = 'missing'
        return $result
    }
    try {
        $lines = [System.IO.File]::ReadAllLines($Path)
    } catch {
        $result.Status = 'unreadable'
        return $result
    }
    foreach ($line in $lines) {
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#') -or $trimmed.StartsWith('//')) { continue }
        $match = [regex]::Match($line, $SecretsLinePattern)
        if ($match.Success) {
            # Die letzte aktive Zeile gewinnt
            $result.Status = 'ok'
            if ($match.Groups[2].Success) { $result.Value = $match.Groups[2].Value } else { $result.Value = $match.Groups[3].Value }
        } elseif ($line -cmatch '^\s*set[rs]\s+mysql_connection_string(\s|$)') {
            $result.WrongSetter = $true
        }
    }
    return $result
}

function ConvertFrom-ConnectionString([string]$Value) {
    # Zerlegt den String genau wie oxmysql 2.14.1 (src/config.ts), OHNE URL-Dekodierung.
    # Rückgabe: Objekt mit Host, Port, User, Password, Database, Socket, Warnings, Error ($null = ok)
    $result = New-Object PSObject -Property @{
        Host = 'localhost'; Port = 3306; User = ''; Password = ''; Database = ''; Socket = ''
        Warnings = @(); Error = $null
    }
    $warnings = @()
    $hostValue = ''
    $portValue = ''

    if ($Value.Contains('mysql://')) {
        # ECMAScript: \w und \d wie in JavaScript nur ASCII
        $match = [regex]::Match($Value, $UriPattern, [System.Text.RegularExpressions.RegexOptions]::ECMAScript)
        if (-not $match.Success) {
            $result.Error = 'mysql_connection_string hat ein ungültiges Format'
            return $result
        }
        if ($match.Groups[2].Success -and $match.Groups[2].Value -ne '') {
            $auth = $match.Groups[2].Value.Split(':')
            $result.User = $auth[0]
            if ($auth.Count -ge 2) { $result.Password = $auth[1] }
        }
        if ($match.Groups[3].Success) { $hostValue = $match.Groups[3].Value }
        if ($match.Groups[4].Success) { $portValue = $match.Groups[4].Value }
        if ($match.Groups[5].Success) { $result.Database = $match.Groups[5].Value -replace '^/+', '' }
        if ($match.Groups[6].Success -and $match.Groups[6].Value -ne '') {
            # Wie oxmysql: jeder Schlüssel aus der Query überschreibt die Angaben davor (ohne '=' ist der Wert leer)
            foreach ($parameter in $match.Groups[6].Value.Split('&')) {
                $pair = $parameter.Split('=')
                $pairValue = ''
                if ($pair.Count -ge 2) { $pairValue = $pair[1] }
                switch -CaseSensitive ($pair[0]) {
                    'socketPath' { $result.Socket = $pairValue }
                    'host' { $hostValue = $pairValue }
                    'port' { $portValue = $pairValue }
                    'user' { $result.User = $pairValue }
                    'password' { $result.Password = $pairValue }
                    'database' { $result.Database = $pairValue }
                }
            }
        }
        if ($result.Password -match '%[0-9A-Fa-f]{2}') {
            $warnings += 'oxmysql dekodiert %XX im Passwort NICHT; das Passwort wird wörtlich verwendet. Besser nur A-Z a-z 0-9 verwenden.'
        }
    } else {
        $options = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
        $rewritten = [regex]::Replace($Value, '(?:host(?:name)|ip|server|data\s?source|addr(?:ess)?)=', 'host=', $options)
        $rewritten = [regex]::Replace($rewritten, '(?:user\s?(?:id|name)?|uid)=', 'user=', $options)
        $rewritten = [regex]::Replace($rewritten, '(?:pwd|pass)=', 'password=', $options)
        $rewritten = [regex]::Replace($rewritten, '(?:db)=', 'database=', $options)
        # Schlüssel mit Groß-/Kleinschreibung (wie JavaScript-Objekte), der letzte doppelte gewinnt
        $pairs = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
        foreach ($parameter in $rewritten.Split(';')) {
            $pair = $parameter.Split('=')
            $key = $pair[0]
            if ($key -eq '') { continue }
            $pairValue = $null
            if ($pair.Count -ge 2) { $pairValue = $pair[1] }
            $pairs[$key] = $pairValue
            if ($key.Trim() -ne '' -and $key -cne $key.Trim()) {
                $warnings += "Schlüssel '$key' im mysql_connection_string hat Leerzeichen am Rand, oxmysql erkennt ihn so nicht."
            }
        }
        if ($pairs.ContainsKey('host') -and $null -ne $pairs['host']) { $hostValue = $pairs['host'] }
        if ($pairs.ContainsKey('port') -and $null -ne $pairs['port']) { $portValue = $pairs['port'] }
        if ($pairs.ContainsKey('user') -and $null -ne $pairs['user']) { $result.User = $pairs['user'] }
        if ($pairs.ContainsKey('password') -and $null -ne $pairs['password']) { $result.Password = $pairs['password'] }
        if ($pairs.ContainsKey('database') -and $null -ne $pairs['database']) { $result.Database = $pairs['database'] }
        if ($pairs.ContainsKey('socketPath') -and $null -ne $pairs['socketPath']) { $result.Socket = $pairs['socketPath'] }
    }

    $result.Warnings = $warnings
    if ($hostValue -ne '') { $result.Host = $hostValue }
    if ($portValue -ne '') {
        $parsedPort = 0
        if (-not ($portValue -match '^[0-9]+$') -or -not [int]::TryParse($portValue, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            $result.Error = "Port '$portValue' im mysql_connection_string ist ungültig"
            return $result
        }
        $result.Port = $parsedPort
    }
    if ($result.User -eq '' -or $result.Database -eq '') {
        $result.Error = 'Benutzer bzw. Datenbankname fehlt im mysql_connection_string'
    }
    return $result
}

function Get-ConnectionLabel($Connection) {
    if ($Connection.Socket -ne '') { return "Socket $($Connection.Socket), User $($Connection.User)" }
    return "$($Connection.Host):$($Connection.Port), User $($Connection.User)"
}

function New-Connection([string]$HostName, [int]$TcpPort, [string]$Account, [string]$Secret, [string]$Database) {
    return New-Object PSObject -Property @{
        Host = $HostName; Port = $TcpPort; User = $Account; Password = $Secret; Database = $Database; Socket = ''
        Warnings = @(); Error = $null
    }
}

function Set-CfgLine([string]$Path, [string]$Pattern, [string]$NewLine) {
    # Gleiche Regeln wie cfg_set_line in lib.sh:
    #   1. letzte aktive (nicht auskommentierte) passende Zeile ersetzen,
    #   2. sonst die erste auskommentierte passende Zeile ersetzen,
    #   3. sonst mit Leerzeile davor anhängen.
    # Liest UTF-8, behält CRLF bzw. LF bei und schreibt UTF-8 ohne BOM.
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $content = [System.IO.File]::ReadAllText($Path, $utf8)
    $eol = "`n"
    if ($content.Contains("`r`n")) { $eol = "`r`n" }
    $endsWithNewline = $content.EndsWith("`n")
    $lines = New-Object System.Collections.Generic.List[string]
    if ($content -ne '') {
        foreach ($line in ($content -split "`r?`n")) { $lines.Add($line) }
        if ($endsWithNewline) { $lines.RemoveAt($lines.Count - 1) }
    }

    $active = -1
    $commented = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not ($lines[$i] -cmatch $Pattern)) { continue }
        if ($lines[$i].TrimStart().StartsWith('#')) {
            if ($commented -lt 0) { $commented = $i }
        } else {
            $active = $i
        }
    }
    if ($active -ge 0) {
        $lines[$active] = $NewLine
    } elseif ($commented -ge 0) {
        $lines[$commented] = $NewLine
    } else {
        if ($endsWithNewline) { $lines.Add('') }
        $lines.Add($NewLine)
        $endsWithNewline = $true
    }

    $output = [string]::Join($eol, $lines.ToArray())
    if ($endsWithNewline) { $output += $eol }
    # Temp-Name wie unter Linux (<datei>.tmp.<PID>), passt zu '/server-data/*.tmp.*' in .gitignore.
    # [NullString]::Value statt $null: PowerShell macht aus $null sonst einen Leerstring,
    # und File.Replace lehnt einen leeren Backup-Pfad ab.
    $tmp = "$Path.tmp.$PID"
    try {
        [System.IO.File]::WriteAllText($tmp, $output, $utf8)
        try {
            [System.IO.File]::Replace($tmp, $Path, [NullString]::Value)
        } catch {
            # Rückfall (z. B. Dateisystem ohne Replace-Unterstützung): direkt überschreiben
            [System.IO.File]::Copy($tmp, $Path, $true)
        }
    } finally {
        if ([System.IO.File]::Exists($tmp)) {
            try { [System.IO.File]::Delete($tmp) } catch { $null = $_ }
        }
    }
}

# ---------------------------------------------------------------------------
# MariaDB-Client
# ---------------------------------------------------------------------------
function Find-MariaDbClient([string]$BinPath) {
    # Rückgabe: Pfad zu mariadb.exe oder $null
    if (-not [string]::IsNullOrWhiteSpace($BinPath)) {
        $candidate = Resolve-UserPath $BinPath
        if ([System.IO.Directory]::Exists($candidate)) { $candidate = Join-Path $candidate 'mariadb.exe' }
        if ([System.IO.File]::Exists($candidate)) { return $candidate }
        throw (New-ExitError 1 "-MariaDbBin: '$candidate' wurde nicht gefunden (erwartet: Ordner mit mariadb.exe oder Pfad zu mariadb.exe).")
    }

    $command = Get-Command 'mariadb.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Path }

    # Standard-Installationsordner "MariaDB <major>.<minor>", die neueste Version gewinnt
    $bases = @()
    foreach ($base in @($env:ProgramW6432, $env:ProgramFiles)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        if (-not [System.IO.Directory]::Exists($base)) { continue }
        if ($bases -contains $base) { continue }
        $bases += $base
    }
    $best = $null
    $bestVersion = $null
    foreach ($base in $bases) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $base -Directory -Filter 'MariaDB *' -ErrorAction SilentlyContinue)) {
            $exe = Join-Path (Join-Path $dir.FullName 'bin') 'mariadb.exe'
            if (-not [System.IO.File]::Exists($exe)) { continue }
            $version = New-Object System.Version 0, 0
            $versionMatch = [regex]::Match($dir.Name, 'MariaDB (\d+)\.(\d+)')
            if ($versionMatch.Success) {
                $version = New-Object System.Version ([int]$versionMatch.Groups[1].Value), ([int]$versionMatch.Groups[2].Value)
            }
            if ($null -eq $best -or $version -gt $bestVersion) {
                $best = $exe
                $bestVersion = $version
            }
        }
    }
    return $best
}

function Get-DbTempDirectory {
    # Ein privater temporärer Ordner pro Lauf, wird im Hauptprogramm (finally) gelöscht
    if ($null -ne $script:DbTempDir) { return $script:DbTempDir }
    $dir = New-TempDirectory 'fivem-db'
    $script:DbTempDir = $dir
    if ($dir.Contains('"')) { throw (New-ExitError 1 "Der temporäre Ordner enthält ein Anführungszeichen: $dir") }
    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        try {
            $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $security = New-Object System.Security.AccessControl.DirectorySecurity
            $security.SetAccessRuleProtection($true, $false)
            $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)
            $security.AddAccessRule($rule)
            (New-Object System.IO.DirectoryInfo $dir).SetAccessControl($security)
        } catch {
            Write-Warn "Zugriffsrechte für '$dir' konnten nicht eingeschränkt werden: $($_.Exception.Message)"
        }
    }
    return $dir
}

function ConvertTo-OptionValue([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Write-DefaultsFile($Connection) {
    # Temporäre Optionsdatei für --defaults-file (UTF-8 ohne BOM). Rückgabe: Pfad
    $dir = Get-DbTempDirectory
    $script:DefaultsCounter++
    $path = Join-Path $dir ("client-{0}.cnf" -f $script:DefaultsCounter)
    $lines = @('[client]', ('user=' + (ConvertTo-OptionValue $Connection.User)), ('password=' + (ConvertTo-OptionValue $Connection.Password)))
    if ($Connection.Database -ne '') { $lines += ('database=' + (ConvertTo-OptionValue $Connection.Database)) }
    $lines += 'default-character-set=utf8mb4'
    if ($Connection.Socket -ne '') {
        # Unter Windows ist ein socketPath eine Named Pipe (\\.\pipe\NAME), der Client erwartet nur NAME
        $pipe = $Connection.Socket
        $pipeMatch = [regex]::Match($pipe, '^[\\/]{2}[^\\/]+[\\/]pipe[\\/](.+)$')
        if ($pipeMatch.Success) { $pipe = $pipeMatch.Groups[1].Value }
        $lines += ('socket=' + (ConvertTo-OptionValue $pipe))
        $lines += 'protocol=PIPE'
    } else {
        $lines += ('host=' + (ConvertTo-OptionValue $Connection.Host))
        $lines += ('port=' + $Connection.Port)
        $lines += 'protocol=TCP'
    }
    $text = ($lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

function Invoke-MariaDbClient([string]$ClientPath, [string]$DefaultsFile, [byte[]]$InputBytes) {
    # Startet mariadb.exe mit --defaults-file als ERSTEM Argument und schreibt die Bytes auf stdin.
    # Rückgabe: Objekt mit ExitCode, StdOut, StdErr
    if ($DefaultsFile.Contains('"')) { throw (New-ExitError 1 "Pfad der Optionsdatei enthält ein Anführungszeichen: $DefaultsFile") }
    $bytes = $InputBytes
    if ($null -eq $bytes) { $bytes = New-Object byte[] 0 }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $withoutBom = New-Object byte[] ($bytes.Length - 3)
        [System.Array]::Copy($bytes, 3, $withoutBom, 0, $withoutBom.Length)
        $bytes = $withoutBom
    }

    $utf8 = New-Object System.Text.UTF8Encoding $false
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ClientPath
    $startInfo.Arguments = '"--defaults-file=' + $DefaultsFile + '" --batch --skip-column-names --default-character-set=utf8mb4'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
    } catch {
        $process.Dispose()
        throw (New-ExitError 1 "MariaDB-Client konnte nicht gestartet werden ($ClientPath): $($_.Exception.Message)")
    }
    try {
        # Lesen VOR dem Schreiben starten, sonst blockieren volle Ausgabepuffer den Client
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        try {
            $stream = $process.StandardInput.BaseStream
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } catch {
            # Client hat sich vorzeitig beendet (z.B. Anmeldung fehlgeschlagen), der Exit-Code sagt mehr
            $null = $_
        }
        try { $process.StandardInput.Close() } catch { $null = $_ }
        $process.WaitForExit()
        return New-Object PSObject -Property @{
            ExitCode = $process.ExitCode
            StdOut   = $stdoutTask.Result
            StdErr   = $stderrTask.Result
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-DbText($Context, [string]$Sql) {
    $bytes = (New-Object System.Text.UTF8Encoding $false).GetBytes($Sql)
    return Invoke-MariaDbClient -ClientPath $Context.Client -DefaultsFile $Context.DefaultsFile -InputBytes $bytes
}

function New-DbContext([string]$Client, $Connection, [string]$Label) {
    $defaults = Write-DefaultsFile $Connection
    if ([string]::IsNullOrEmpty($Label)) { $Label = Get-ConnectionLabel $Connection }
    return New-Object PSObject -Property @{ Client = $Client; DefaultsFile = $defaults; Label = $Label }
}

function Remove-DbContext($Context) {
    if ($null -ne $Context -and [System.IO.File]::Exists($Context.DefaultsFile)) {
        try { [System.IO.File]::Delete($Context.DefaultsFile) } catch { $null = $_ }
    }
}

function Get-OutputLines([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return ,@() }
    return ,@($Text -split "`r?`n" | Where-Object { $_ -ne '' })
}

function Test-MariaDbVersion([string]$Version) {
    # 0 = ok, 1 = zu alt oder kein MariaDB, 2 = nicht lesbar
    if (-not ($Version -cmatch 'MariaDB')) { return 1 }
    $match = [regex]::Match($Version.Trim(), '^(\d+)\.(\d+)')
    if (-not $match.Success) { return 2 }
    $major = [long]$match.Groups[1].Value
    $minor = [long]$match.Groups[2].Value
    if ($major -gt $MinMajor -or ($major -eq $MinMajor -and $minor -ge $MinMinor)) { return 0 }
    return 1
}

function Assert-DbConnection($Context) {
    # Verbindet sich, prüft die Version. Rückgabe: Versionstext. Fehler: Exit-Code 2.
    $result = Invoke-DbText $Context 'SELECT VERSION();'
    if ($result.ExitCode -ne 0) {
        throw (New-ExitError 2 "Datenbank nicht erreichbar oder Anmeldung fehlgeschlagen ($($Context.Label)): $(Get-FirstLines $result.StdErr 5)")
    }
    $version = ''
    $outputLines = Get-OutputLines $result.StdOut
    if ($outputLines.Count -gt 0) { $version = $outputLines[0].Trim() }
    if (-not ($version -cmatch 'MariaDB')) {
        throw (New-ExitError 2 "Der Server meldet '$version', das ist kein MariaDB. Qbox unterstützt MySQL nicht.")
    }
    $check = Test-MariaDbVersion $version
    if ($check -eq 2) {
        throw (New-ExitError 2 "Die MariaDB-Version '$version' konnte nicht gelesen werden.")
    }
    if ($check -ne 0) {
        throw (New-ExitError 2 "MariaDB $version ist zu alt. Qbox braucht mindestens 10.9 (empfohlen: 12.3 LTS). Anleitung: docs/datenbank.md")
    }
    Write-Ok "Verbunden mit MariaDB $version ($($Context.Label))."
    return $version
}

function ConvertTo-SqlString([string]$Value) {
    return $Value.Replace('\', '\\').Replace("'", "\'")
}

# ---------------------------------------------------------------------------
# -InstallMariaDB
# ---------------------------------------------------------------------------
function Install-MariaDbServer([string]$BinPath) {
    $existing = Find-MariaDbClient $BinPath
    if ($existing) {
        Write-Info "MariaDB ist bereits installiert ($existing), die Installation wird übersprungen."
        return
    }
    $winget = Get-Command 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $winget) {
        throw (New-ExitError 1 "winget wurde nicht gefunden. Installiere bzw. aktualisiere den 'App Installer' aus dem Microsoft Store, öffne ein neues Terminal und starte den Befehl erneut.")
    }

    Write-Host ""
    Write-Host " Gleich startet der Installationsassistent von MariaDB. Bitte so ausfüllen:" -ForegroundColor White
    Write-Host "  - Root-Passwort setzen und merken. setup-database.bat -Create fragt es gleich danach ab."
    Write-Host "  - 'Install as service' eingeschaltet lassen, Dienstname MariaDB."
    Write-Host "  - Port 3306 lassen."
    Write-Host "  - Zugriff für root von anderen Rechnern (remote root access) AUS lassen."
    Write-Host "  - Eine UTF8-Option nur anhaken, wenn der Assistent sie anbietet (die Datenbank bekommt ohnehin utf8mb4)."
    Write-Host ""
    Write-Info "winget install --id MariaDB.Server -e --source winget --interactive ..."
    & $winget.Path install --id MariaDB.Server -e --source winget --interactive --accept-package-agreements --accept-source-agreements
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        throw (New-ExitError 1 "winget ist mit Exit-Code $rc beendet worden, MariaDB wurde nicht (vollständig) installiert.")
    }
    $client = Find-MariaDbClient $BinPath
    if (-not $client) {
        throw (New-ExitError 1 "MariaDB wurde installiert, aber mariadb.exe wurde nicht gefunden. Neues Terminal öffnen oder -MariaDbBin angeben.")
    }
    Write-Ok "MariaDB ist installiert ($client)."
}

# ---------------------------------------------------------------------------
# -Create
# ---------------------------------------------------------------------------
function Read-RootPassword {
    # Ohne echte Konsole (umgeleitete Eingabe) kann Read-Host das Skript still mit Exit-Code 0 beenden
    if ([Console]::IsInputRedirected) {
        throw (New-ExitError 1 "-Create fragt das MariaDB-Root-Passwort ab und braucht dafür eine Konsole ohne umgeleitete Eingabe. Bitte setup-database.bat -Create direkt in einem Fenster starten.")
    }
    $secure = Read-Host -AsSecureString 'MariaDB-Root-Passwort'
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Invoke-CreateDatabase {
    param(
        [string]$Client,
        [string]$SecretsFile,
        [string]$SecretsExample,
        [string]$Name,
        [string]$Account,
        [int]$DbPort,
        [bool]$Reset,
        [scriptblock]$ReadRootSecret
    )
    $User = $Account

    # 1. secrets.cfg
    if (-not [System.IO.File]::Exists($SecretsFile)) {
        if (-not [System.IO.File]::Exists($SecretsExample)) {
            throw (New-ExitError 1 "Weder secrets.cfg noch secrets.cfg.example gefunden: $SecretsFile")
        }
        [System.IO.File]::Copy($SecretsExample, $SecretsFile, $false)
        Write-Ok "secrets.cfg aus secrets.cfg.example angelegt (Lizenzschlüssel noch eintragen)."
    }

    # 3. vorhandener mysql_connection_string (vor der Anmeldung als root geprüft, damit nichts umsonst abgefragt wird)
    $existing = $null
    $secrets = Get-SecretsConnectionString $SecretsFile
    if ($secrets.Status -eq 'unreadable') { throw (New-ExitError 1 "secrets.cfg ist nicht lesbar: $SecretsFile") }
    if ($secrets.WrongSetter) { Write-Warn "secrets.cfg: 'setr'/'sets' mysql_connection_string schickt das DB-Passwort an alle Spieler bzw. in die öffentliche Serverinfo. Nur 'set' verwenden, diese Zeile wird hier nicht ausgewertet." }
    if ($secrets.Status -eq 'ok') {
        $parsed = ConvertFrom-ConnectionString $secrets.Value
        if ($parsed.Error) {
            if (-not $Reset) {
                throw (New-ExitError 1 "Der vorhandene mysql_connection_string ist ungültig ($($parsed.Error)). -ResetPassword schreibt einen neuen.")
            }
            Write-Warn "Der vorhandene mysql_connection_string ist ungültig ($($parsed.Error)) und wird ersetzt."
        } else {
            $existing = $parsed
        }
    }
    if ($null -ne $existing) {
        if ($existing.Socket -eq '' -and @('localhost', '127.0.0.1', '::1') -notcontains $existing.Host) {
            throw (New-ExitError 1 "secrets.cfg zeigt auf einen anderen Datenbankserver ($($existing.Host)); -Create richtet nur die lokale MariaDB ein")
        }
        if (($existing.User -cne $User -or $existing.Database -cne $Name) -and -not $Reset) {
            throw (New-ExitError 1 "secrets.cfg nutzt User '$($existing.User)' und Datenbank '$($existing.Database)', angefragt sind '$User' und '$Name'. Passe -DbUser bzw. -DbName an oder schreibe mit -ResetPassword einen neuen String.")
        }
    }
    $existingForUser = ($null -ne $existing -and $existing.User -ceq $User -and $existing.Database -ceq $Name)
    if ($null -ne $existing -and $existing.Socket -eq '' -and -not $script:BoundParams.ContainsKey('Port') -and [int]$existing.Port -ne $DbPort) {
        Write-Info "Übernehme Port $($existing.Port) aus dem vorhandenen mysql_connection_string (-Port überschreibt das)."
        $DbPort = [int]$existing.Port
    }
    if ($null -ne $existing -and $existing.Socket -eq '' -and $script:BoundParams.ContainsKey('Port') -and [int]$existing.Port -ne $DbPort -and -not $Reset) {
        # Ohne neues Passwort bleibt der String unverändert, oxmysql würde weiter den alten Port nutzen
        throw (New-ExitError 1 "secrets.cfg nutzt Port $($existing.Port), -Port ist $DbPort. Entweder -Port $($existing.Port) angeben oder mit -ResetPassword einen neuen String schreiben.")
    }

    # 2. Anmeldung als root über TCP 127.0.0.1, Version prüfen, Datenbank anlegen
    if (Get-Command 'Get-Service' -ErrorAction SilentlyContinue) {
        $service = Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Running') {
            Write-Warn "Der Windows-Dienst MariaDB läuft nicht. Starten: net start MariaDB (als Administrator)"
        }
    }
    $rootPassword = [string](& $ReadRootSecret)
    $rootContext = New-DbContext $Client (New-Connection '127.0.0.1' $DbPort 'root' $rootPassword '') ''
    $rootPassword = $null
    try {
        [void](Assert-DbConnection $rootContext)

        $schema = Invoke-DbText $rootContext "SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$Name';"
        if ($schema.ExitCode -ne 0) {
            throw (New-ExitError 3 "Abfrage der Datenbank $Name fehlgeschlagen (Exit-Code $($schema.ExitCode)): $(Get-FirstLines $schema.StdErr 5)")
        }
        $schemaLines = Get-OutputLines $schema.StdOut
        if ($schemaLines.Count -gt 0) {
            $parts = $schemaLines[0].Split("`t")
            $charset = $parts[0]
            $collation = ''
            if ($parts.Count -ge 2) { $collation = $parts[1] }
            if ($charset -ne 'utf8mb4' -or $collation -ne 'utf8mb4_unicode_ci') {
                Write-Warn "Datenbank $Name existiert bereits mit $charset / $collation statt utf8mb4 / utf8mb4_unicode_ci. Bei Fehlern mit gemischten Collations eine neue, leere Datenbank verwenden."
            }
        }
        $createDb = Invoke-DbText $rootContext "CREATE DATABASE IF NOT EXISTS ``$Name`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        if ($createDb.ExitCode -ne 0) {
            throw (New-ExitError 3 "CREATE DATABASE $Name fehlgeschlagen (Exit-Code $($createDb.ExitCode)): $(Get-FirstLines $createDb.StdErr 5)")
        }
        Write-Ok "Datenbank $Name ist vorhanden (utf8mb4)."

        # 4. vorhandene Accounts
        $accounts = Invoke-DbText $rootContext "SELECT host FROM mysql.user WHERE user='$User' AND host IN ('localhost','127.0.0.1');"
        if ($accounts.ExitCode -ne 0) {
            throw (New-ExitError 3 "Abfrage von mysql.user fehlgeschlagen (Exit-Code $($accounts.ExitCode)): $(Get-FirstLines $accounts.StdErr 5)")
        }
        $accountHosts = Get-OutputLines $accounts.StdOut

        # 5. Passwort wählen
        $passwordIsNew = $false
        $password = ''
        if ($accountHosts.Count -eq 0) {
            if ($existingForUser -and -not $Reset -and $existing.Password -ne '') {
                $password = $existing.Password
                Write-Info "User $User existiert noch nicht, er bekommt das Passwort aus secrets.cfg."
            } else {
                $password = New-RandomHex
                $passwordIsNew = $true
            }
        } elseif ($Reset) {
            $password = New-RandomHex
            $passwordIsNew = $true
            Write-Info "User $User existiert, bekommt ein neues Passwort (-ResetPassword)."
        } elseif ($existingForUser) {
            $testContext = New-DbContext $Client (New-Connection '127.0.0.1' $DbPort $User $existing.Password '') "127.0.0.1:$DbPort, User $User"
            try {
                $test = Invoke-DbText $testContext 'SELECT 1;'
            } finally {
                Remove-DbContext $testContext
            }
            if ($test.ExitCode -ne 0) {
                throw (New-ExitError 1 "Passwort in secrets.cfg passt nicht zum vorhandenen User; -ResetPassword setzt ein neues")
            }
            $password = $existing.Password
            Write-Info "User $User existiert, das Passwort aus secrets.cfg passt."
        } else {
            throw (New-ExitError 1 "User existiert, Passwort unbekannt; -ResetPassword setzt ein neues")
        }

        # 6. User für localhost und 127.0.0.1 anlegen, beide mit demselben Passwort, Rechte vergeben
        $sqlPassword = ConvertTo-SqlString $password
        $grantName = $Name.Replace('_', '\_')
        $sql = New-Object System.Text.StringBuilder
        # ConvertTo-SqlString maskiert mit Backslash, das gilt nur ohne NO_BACKSLASH_ESCAPES im sql_mode
        [void]$sql.AppendLine("SET SESSION sql_mode=REPLACE(@@SESSION.sql_mode,'NO_BACKSLASH_ESCAPES','');")
        foreach ($hostName in @('localhost', '127.0.0.1')) {
            [void]$sql.AppendLine("CREATE USER IF NOT EXISTS '$User'@'$hostName' IDENTIFIED BY '$sqlPassword';")
            [void]$sql.AppendLine("ALTER USER '$User'@'$hostName' IDENTIFIED BY '$sqlPassword';")
            [void]$sql.AppendLine("GRANT ALL PRIVILEGES ON ``$grantName``.* TO '$User'@'$hostName';")
        }
        [void]$sql.AppendLine('FLUSH PRIVILEGES;')
        $grant = Invoke-DbText $rootContext $sql.ToString()
        $sql = $null
        if ($grant.ExitCode -ne 0) {
            throw (New-ExitError 3 "Anlegen des Users $User bzw. der Rechte fehlgeschlagen (Exit-Code $($grant.ExitCode)): $(Get-FirstLines $grant.StdErr 5)")
        }
        Write-Ok "User $User@localhost und $User@127.0.0.1 haben alle Rechte auf $Name."
    } finally {
        Remove-DbContext $rootContext
    }

    # 7. String schreiben (nur bei neuem Passwort oder wenn noch keiner existiert)
    if ($passwordIsNew -or $null -eq $existing) {
        $line = "set mysql_connection_string `"mysql://${User}:${password}@127.0.0.1:${DbPort}/${Name}?charset=utf8mb4`""
        try {
            Set-CfgLine -Path $SecretsFile -Pattern $CfgLinePattern -NewLine $line
        } catch {
            throw (New-ExitError 1 "mysql_connection_string konnte nicht in $SecretsFile geschrieben werden ($($_.Exception.Message)). Das Passwort des Users $User wurde bereits geändert: Ursache beheben (Datei in einem Editor offen?) und danach setup-database.bat -Create -ResetPassword ausführen.")
        }
        Write-Ok "mysql_connection_string in secrets.cfg eingetragen."
    } else {
        Write-Info "mysql_connection_string in secrets.cfg bleibt unverändert."
    }

    # 8. Anmeldung als User prüfen, so wie oxmysql sich verbindet (behaltener String mit socketPath: über die Named Pipe)
    $verifyConnection = New-Connection '127.0.0.1' $DbPort $User $password $Name
    $verifyTarget = "127.0.0.1:$DbPort"
    $verifyHint = 'Prüfe in der my.ini im Datenordner der MariaDB bind-address und skip-name-resolve.'
    if (-not $passwordIsNew -and $null -ne $existing -and $existing.Socket -ne '') {
        $verifyConnection.Socket = $existing.Socket
        $verifyTarget = "Socket $($existing.Socket)"
        $verifyHint = 'Prüfe in der my.ini im Datenordner der MariaDB named-pipe und socket.'
    }
    $verifyContext = New-DbContext $Client $verifyConnection "$verifyTarget, User $User"
    try {
        $verify = Invoke-DbText $verifyContext 'SELECT 1;'
    } finally {
        Remove-DbContext $verifyContext
    }
    if ($verify.ExitCode -ne 0) {
        throw (New-ExitError 2 "Anmeldung als $User über $verifyTarget fehlgeschlagen: $(Get-FirstLines $verify.StdErr 5). $verifyHint")
    }
    Write-Ok "Anmeldung als $User über $verifyTarget funktioniert."

    # 9. neues Passwort einmal anzeigen, aber nicht in eine umgeleitete Ausgabe (Logdatei)
    if ($passwordIsNew) {
        if ([Console]::IsOutputRedirected) {
            Write-Info "Neues MariaDB-Passwort für $User steht in $SecretsFile (Ausgabe ist umgeleitet, daher nicht angezeigt)."
        } else {
            Write-Host "MariaDB-Passwort für $User (steht in secrets.cfg, wird nicht erneut angezeigt): $password" -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# Import, MarkApplied, DryRun
# ---------------------------------------------------------------------------
function Write-FileStatus([string]$Status, [string]$Path) {
    Write-Host ("  {0}  {1}" -f $Status.PadRight($StatusWidth), $Path)
}

function Write-UnknownStatus($Entries, [string]$ResourcesDir) {
    foreach ($entry in $Entries) {
        $status = 'unbekannt'
        if (-not [System.IO.File]::Exists((Join-ResourcePath $ResourcesDir $entry.Path))) { $status = 'fehlt' }
        Write-FileStatus $status $entry.Path
    }
}

function Write-ImportSummary($Counts, [bool]$Dry = $false) {
    $line = "SQL: {0} importiert, {1} erneut ausgeführt, {2} bereits vorhanden, {3} geändert (Warnung), {4} markiert" -f $Counts.Imported, $Counts.Rerun, $Counts.Present, $Counts.Changed, $Counts.Marked
    if ($Dry) { $line = "Probelauf, nichts geändert. Geplant: $line" }
    Write-Host ""
    Write-Host $line
}

function Get-ImportRecord($Context, [bool]$Dry) {
    # Rückgabe: Hashtable Pfad -> Objekt (Hash, ImportedAt). Ohne Groß-/Kleinschreibung wie die Collation der Tabelle.
    $records = @{}
    if ($Dry) {
        $exists = Invoke-DbText $Context "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='repo_sql_imports';"
        if ($exists.ExitCode -ne 0) {
            throw (New-ExitError 3 "Abfrage der Tracking-Tabelle fehlgeschlagen (Exit-Code $($exists.ExitCode)): $(Get-FirstLines $exists.StdErr 5)")
        }
        $countLines = Get-OutputLines $exists.StdOut
        if ($countLines.Count -eq 0 -or $countLines[0].Trim() -eq '0') { return $records }
    } else {
        $ddl = Invoke-DbText $Context $TrackingTableDdl
        if ($ddl.ExitCode -ne 0) {
            throw (New-ExitError 3 "Tracking-Tabelle repo_sql_imports konnte nicht angelegt werden (Exit-Code $($ddl.ExitCode)): $(Get-FirstLines $ddl.StdErr 5)")
        }
    }
    $select = Invoke-DbText $Context 'SELECT file_path, sha256, imported_at FROM repo_sql_imports;'
    if ($select.ExitCode -ne 0) {
        throw (New-ExitError 3 "Lesen von repo_sql_imports fehlgeschlagen (Exit-Code $($select.ExitCode)): $(Get-FirstLines $select.StdErr 5)")
    }
    foreach ($row in (Get-OutputLines $select.StdOut)) {
        $fields = $row.Split("`t")
        if ($fields.Count -lt 2) { continue }
        $importedAt = ''
        if ($fields.Count -ge 3) { $importedAt = $fields[2] }
        $records[$fields[0]] = New-Object PSObject -Property @{ Hash = $fields[1].Trim().ToLowerInvariant(); ImportedAt = $importedAt }
    }
    return $records
}

function Add-ImportRecord($Context, [string]$Path, [string]$Hash, [string]$AppliedBy) {
    $sql = "INSERT INTO repo_sql_imports (file_path, sha256, applied_by) VALUES ('$Path','$Hash','$AppliedBy') ON DUPLICATE KEY UPDATE sha256=VALUES(sha256), applied_by=VALUES(applied_by), imported_at=CURRENT_TIMESTAMP;"
    return Invoke-DbText $Context $sql
}

function Invoke-SqlImport {
    # Rückgabe: Exit-Code (0 oder 3, auch im Probelauf). Verbindungsfehler kommen als New-ExitError 2.
    param(
        $Context,
        $Entries,
        [string]$ResourcesDir,
        [bool]$Mark,
        [bool]$Dry,
        [bool]$OnlyGiven
    )
    $records = Get-ImportRecord $Context $Dry

    # Plan: Zustand jeder Datei
    $plan = @()
    foreach ($entry in $Entries) {
        $fullPath = Join-ResourcePath $ResourcesDir $entry.Path
        $exists = [System.IO.File]::Exists($fullPath)
        $record = $null
        if ($records.ContainsKey($entry.Path)) { $record = $records[$entry.Path] }
        $hash = ''
        if ($exists) { $hash = Get-FileSha256 $fullPath }
        if (-not $exists) {
            $state = 'fehlt'
        } elseif ($null -eq $record) {
            $state = 'ausstehend'
        } elseif ($record.Hash -eq $hash) {
            $state = 'importiert'
        } elseif ($entry.Rerun -and -not $Mark) {
            $state = 'erneut'
        } else {
            $state = 'geändert'
        }
        $plan += New-Object PSObject -Property @{
            Entry = $entry; FullPath = $fullPath; Exists = $exists; Record = $record; Hash = $hash; State = $state
        }
    }

    if ($Dry) {
        Write-Step "Probelauf (nichts wird geändert)"
        # Zählung wie im echten Lauf: mit -MarkApplied zählen ausstehende und geänderte Dateien als markiert
        $dryCounts = New-Object PSObject -Property @{ Imported = 0; Rerun = 0; Present = 0; Changed = 0; Marked = 0 }
        $missing = @()
        foreach ($item in $plan) {
            $state = $item.State
            if ($state -ceq 'fehlt') {
                if ($null -ne $item.Record) {
                    Write-FileStatus $state "$($item.Entry.Path)  (bereits importiert, Datei fehlt)"
                    $dryCounts.Present++
                } else {
                    Write-FileStatus $state "$($item.Entry.Path)  (nicht importiert, Ressource installieren)"
                    $missing += $item
                }
                continue
            }
            Write-FileStatus $state $item.Entry.Path
            if ($state -ceq 'importiert') {
                $dryCounts.Present++
            } elseif ($state -ceq 'erneut') {
                $dryCounts.Rerun++
            } elseif ($Mark) {
                $dryCounts.Marked++
            } elseif ($state -ceq 'ausstehend') {
                $dryCounts.Imported++
            } else {
                $dryCounts.Changed++
            }
        }
        Write-ImportSummary $dryCounts $true
        foreach ($item in $missing) {
            Write-Warn "$($item.Entry.Path) fehlt. Ist die Ressource installiert (install-resources)?"
        }
        if ($missing.Count -gt 0) {
            Write-Fail "$($missing.Count) noch nicht importierte Datei(en) fehlen. Ein echter Lauf würde mit Exit-Code 3 abbrechen. Ressourcen installieren: scripts\windows\install.bat"
            return 3
        }
        return 0
    }

    $counts = New-Object PSObject -Property @{ Imported = 0; Rerun = 0; Present = 0; Changed = 0; Marked = 0 }

    if ($Mark) {
        foreach ($item in $plan) {
            if ($item.State -eq 'fehlt' -and $null -eq $item.Record) {
                Write-Fail "$($item.Entry.Path) fehlt. Ist die Ressource installiert (install-resources)?"
                Write-ImportSummary $counts
                return 3
            }
        }
        $toMark = @($plan | Where-Object { $_.State -eq 'ausstehend' -or $_.State -eq 'geändert' -or $_.State -eq 'erneut' })
        if (-not $OnlyGiven -and $toMark.Count -gt 0) {
            Write-Warn "Diese Dateien werden als importiert eingetragen, OHNE sie auszuführen:"
            foreach ($item in $toMark) { Write-Host "    $($item.Entry.Path)" }
        }
        foreach ($item in $plan) {
            if ($item.State -eq 'importiert' -or $item.State -eq 'fehlt') {
                $counts.Present++
                continue
            }
            $insert = Add-ImportRecord $Context $item.Entry.Path $item.Hash 'mark-applied'
            if ($insert.ExitCode -ne 0) {
                Write-Fail "Eintrag für $($item.Entry.Path) fehlgeschlagen (Exit-Code $($insert.ExitCode)): $(Get-FirstLines $insert.StdErr 5)"
                Write-ImportSummary $counts
                return 3
            }
            Write-Ok "$($item.Entry.Path): als importiert eingetragen"
            $counts.Marked++
        }
        Write-ImportSummary $counts
        return 0
    }

    foreach ($item in $plan) {
        $path = $item.Entry.Path
        # Hinweis: kein switch, 'continue' im switch würde nur den switch verlassen, nicht die Schleife
        if ($item.State -eq 'importiert') {
            $counts.Present++
            continue
        }
        if ($item.State -eq 'fehlt') {
            if ($null -ne $item.Record) {
                Write-Info "${path}: bereits importiert, Datei fehlt"
                $counts.Present++
                continue
            }
            Write-Fail "$path fehlt. Ist die Ressource installiert (install-resources)?"
            Write-ImportSummary $counts
            return 3
        }
        if ($item.State -eq 'geändert') {
            $oldShort = $item.Record.Hash.Substring(0, [Math]::Min(8, $item.Record.Hash.Length))
            $newShort = $item.Hash.Substring(0, 8)
            Write-Warn "$path wurde am $($item.Record.ImportedAt) importiert, die Datei hat sich seitdem geändert (alt $oldShort, neu $newShort). Sie wird NICHT erneut ausgeführt. Prüfe die Änderung und spiele nötige Befehle von Hand ein. Warnung quittieren: setup-database.bat -MarkApplied -Only '$path'"
            $counts.Changed++
            continue
        }

        if ($item.State -eq 'erneut') {
            Write-Info "$path hat sich geändert und ist als rerun markiert, wird erneut ausgeführt"
        } else {
            Write-Info "Importiere $path ..."
        }
        $bytes = [System.IO.File]::ReadAllBytes($item.FullPath)
        $run = Invoke-MariaDbClient -ClientPath $Context.Client -DefaultsFile $Context.DefaultsFile -InputBytes $bytes
        if ($run.ExitCode -ne 0) {
            Write-Fail "FEHLER beim Import von $path (Exit-Code $($run.ExitCode)): $($run.StdErr.Trim())"
            Write-Warn "Achtung: MariaDB führt CREATE/ALTER TABLE ohne Transaktion aus. Befehle vor dem Fehler sind bereits angewendet. Die Datei ist NICHT als importiert eingetragen, folgende Dateien wurden nicht importiert. Ursache beheben und erneut starten, oder nach Handarbeit: -MarkApplied -Only '$path'."
            Write-ImportSummary $counts
            return 3
        }
        $insert = Add-ImportRecord $Context $path $item.Hash 'import'
        if ($insert.ExitCode -ne 0) {
            Write-Fail "Import lief, Eintrag fehlgeschlagen; vor dem nächsten Lauf -MarkApplied -Only '$path' ausführen ($(Get-FirstLines $insert.StdErr 5))"
            Write-ImportSummary $counts
            return 3
        }
        if ($item.State -eq 'erneut') {
            Write-Ok "${path}: erneut ausgeführt"
            $counts.Rerun++
        } else {
            Write-Ok "${path}: importiert"
            $counts.Imported++
        }
    }
    Write-ImportSummary $counts
    return 0
}

# ---------------------------------------------------------------------------
# Hauptprogramm
# ---------------------------------------------------------------------------
function Invoke-Main {
    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $serverDataDir = Join-Path $root 'server-data'
    $resourcesDir = Join-Path $serverDataDir 'resources'
    $secretsExample = Join-Path $serverDataDir 'secrets.cfg.example'
    $manifestFile = Join-Path $serverDataDir 'database.txt'
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $manifestFile = Resolve-UserPath $ManifestPath }
    $secretsFile = Join-Path $serverDataDir 'secrets.cfg'
    if (-not [string]::IsNullOrWhiteSpace($SecretsPath)) { $secretsFile = Resolve-UserPath $SecretsPath }

    Write-Host ""
    Write-Host "FiveM Server - Datenbank (MariaDB)" -ForegroundColor White

    # --- Parameter prüfen ---------------------------------------------------
    if ($Check) {
        $conflicts = @('Create', 'ResetPassword', 'DbName', 'DbUser', 'Port', 'Import', 'MarkApplied', 'Only', 'DryRun', 'InstallMariaDB', 'MariaDbBin', 'SecretsPath') |
            Where-Object { Test-ParamGiven $_ }
        if (@($conflicts).Count -gt 0) {
            throw (New-ExitError 1 "-Check geht nur zusammen mit -ManifestPath (nicht mit: -$(@($conflicts) -join ', -')).")
        }
    }
    if ($Create -and $MarkApplied) { throw (New-ExitError 1 "-Create und -MarkApplied schließen sich aus.") }
    if ($Create -and $DryRun) { throw (New-ExitError 1 "-Create und -DryRun schließen sich aus (-DryRun gilt nur für -Import und -MarkApplied).") }
    if ($Import -and $MarkApplied) { throw (New-ExitError 1 "-Import und -MarkApplied schließen sich aus.") }
    foreach ($name in @('ResetPassword', 'DbName', 'DbUser', 'Port')) {
        if ((Test-ParamGiven $name) -and -not $Create) { throw (New-ExitError 1 "-$name geht nur zusammen mit -Create.") }
    }
    $doImport = $Import -or (-not $Create -and -not $InstallMariaDB -and -not $MarkApplied -and -not $Check)
    $doMark = [bool]$MarkApplied
    $onlyGiven = Test-ParamGiven 'Only'
    $onlyList = ConvertTo-OnlyList $Only
    if ($onlyGiven -and -not ($doImport -or $doMark)) {
        throw (New-ExitError 1 "-Only geht nur zusammen mit -Import, -MarkApplied oder -DryRun.")
    }
    if ($onlyGiven -and $onlyList.Count -eq 0) { throw (New-ExitError 1 "-Only ohne Pfad angegeben.") }
    if ($DryRun -and -not ($doImport -or $doMark)) {
        throw (New-ExitError 1 "-DryRun geht nur zusammen mit -Import oder -MarkApplied.")
    }
    if ($Create) {
        if (-not ($DbName -cmatch '^[A-Za-z0-9_]{1,32}$')) { throw (New-ExitError 1 "-DbName '$DbName' ist ungültig (erlaubt: A-Z a-z 0-9 _, 1 bis 32 Zeichen).") }
        if (-not ($DbUser -cmatch '^[A-Za-z0-9_]{1,32}$')) { throw (New-ExitError 1 "-DbUser '$DbUser' ist ungültig (erlaubt: A-Z a-z 0-9 _, 1 bis 32 Zeichen).") }
        if ($Port -lt 1 -or $Port -gt 65535) { throw (New-ExitError 1 "-Port $Port ist ungültig (1 bis 65535).") }
    }

    # --- Manifest -----------------------------------------------------------
    $entries = @()
    if ($Check -or $doImport -or $doMark) {
        if (-not [System.IO.File]::Exists($manifestFile)) {
            throw (New-ExitError 1 "SQL-Manifest nicht gefunden: $manifestFile")
        }
        $manifest = Read-SqlManifest $manifestFile
        foreach ($problem in @($manifest.Errors)) { Write-Fail $problem }
        if (@($manifest.Errors).Count -gt 0) {
            throw (New-ExitError 1 "$manifestFile ist ungültig ($(@($manifest.Errors).Count) Fehler).")
        }
        $entries = @($manifest.Entries)
        if ($Check) {
            $rerunCount = @($entries | Where-Object { $_.Rerun }).Count
            Write-Ok "$manifestFile ist gültig ($($entries.Count) SQL-Dateien, davon $rerunCount mit rerun)."
            $script:ExitCode = 0
            return
        }
        if ($onlyGiven) {
            $selected = @()
            foreach ($value in $onlyList) {
                $found = @($entries | Where-Object { $_.Path -eq $value })
                if ($found.Count -eq 0) { throw (New-ExitError 1 "-Only '$value' steht nicht in $manifestFile.") }
            }
            foreach ($entry in $entries) {
                if ($onlyList -contains $entry.Path) { $selected += $entry }
            }
            $entries = $selected
        }
    }

    # --- -InstallMariaDB ----------------------------------------------------
    if ($InstallMariaDB) {
        Write-Step "MariaDB installieren (winget)"
        Install-MariaDbServer $MariaDbBin
    }

    # --- -Create ------------------------------------------------------------
    if ($Create) {
        Write-Step "Datenbank und User anlegen ($DbName, $DbUser)"
        $client = Find-MariaDbClient $MariaDbBin
        if (-not $client) { throw (New-ExitError 1 "MariaDB nicht gefunden. Installieren: setup-database.bat -InstallMariaDB") }
        Write-Info "MariaDB-Client: $client"
        Invoke-CreateDatabase -Client $client -SecretsFile $secretsFile -SecretsExample $secretsExample -Name $DbName -Account $DbUser -DbPort $Port -Reset ([bool]$ResetPassword) -ReadRootSecret { Read-RootPassword }
    }

    # --- Import / MarkApplied / DryRun --------------------------------------
    if ($doImport -or $doMark) {
        $action = 'SQL-Dateien importieren'
        if ($doMark) { $action = 'SQL-Dateien als importiert eintragen' }
        if ($DryRun) { $action += ' (Probelauf)' }
        Write-Step "$action ($manifestFile)"

        $connection = $null
        $problem = $null
        $secrets = Get-SecretsConnectionString $secretsFile
        if ($secrets.WrongSetter) { Write-Warn "secrets.cfg: 'setr'/'sets' mysql_connection_string schickt das DB-Passwort an alle Spieler bzw. in die öffentliche Serverinfo. Nur 'set' verwenden, diese Zeile wird hier nicht ausgewertet." }
        switch ($secrets.Status) {
            'missing' { $problem = "secrets.cfg nicht gefunden: $secretsFile" }
            'unreadable' { $problem = "secrets.cfg ist nicht lesbar: $secretsFile" }
            'none' { $problem = "In secrets.cfg fehlt ein aktives 'set mysql_connection_string'. Einrichten: setup-database.bat -Create -Import" }
            default {
                $connection = ConvertFrom-ConnectionString $secrets.Value
                foreach ($warning in @($connection.Warnings)) { Write-Warn $warning }
                if ($connection.Error) { $problem = $connection.Error }
            }
        }
        $client = $null
        if (-not $problem) {
            $client = Find-MariaDbClient $MariaDbBin
            if (-not $client) { $problem = "MariaDB nicht gefunden. Installieren: setup-database.bat -InstallMariaDB" }
        }
        if ($problem) {
            if ($DryRun) {
                Write-Fail $problem
                Write-Warn "Datenbank nicht erreichbar, Status unbekannt"
                Write-UnknownStatus $entries $resourcesDir
                $script:ExitCode = 1
                return
            }
            throw (New-ExitError 1 $problem)
        }

        $context = New-DbContext $client $connection ''
        try {
            try {
                [void](Assert-DbConnection $context)
            } catch {
                $code = Get-ExitErrorCode $_.Exception
                if ($DryRun -and $code -eq 2) {
                    Write-Fail $_.Exception.Message
                    # Nur bei Verbindungsfehlern, nicht bei zu alter Version oder anderem Server (wie unter Linux)
                    if ($_.Exception.Message.StartsWith('Datenbank nicht erreichbar')) {
                        Write-Warn "Datenbank nicht erreichbar, Status unbekannt"
                    }
                    Write-UnknownStatus $entries $resourcesDir
                    $script:ExitCode = 2
                    return
                }
                throw
            }
            $script:ExitCode = Invoke-SqlImport -Context $context -Entries $entries -ResourcesDir $resourcesDir -Mark $doMark -Dry ([bool]$DryRun) -OnlyGiven $onlyGiven
            return
        } finally {
            Remove-DbContext $context
        }
    }

    $script:ExitCode = 0
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-Main
    } catch {
        $code = Get-ExitErrorCode $_.Exception
        Write-Host ""
        if ($null -ne $code) {
            Write-Fail $_.Exception.Message
            $script:ExitCode = $code
        } else {
            Write-Fail "Abbruch: $($_.Exception.Message)"
            if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
                Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
            }
            $script:ExitCode = 1
        }
    } finally {
        if ($null -ne $script:DbTempDir) {
            try { Remove-Tree $script:DbTempDir } catch { Write-Warn "Temporärer Ordner konnte nicht gelöscht werden: $($script:DbTempDir)" }
        }
    }
    exit $script:ExitCode
}
