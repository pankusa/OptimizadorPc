# Compatible with PowerShell 5.1 and the PC Claro 0.1 report format.
function Read-DiagnosticReport([string]$Path) {
    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($data.schemaVersion -ne 1 -or -not $data.checks) {
        throw 'El archivo no contiene un diagnóstico compatible.'
    }
    foreach ($check in $data.checks) {
        if (-not $check.id -or -not $check.title -or $check.status -notin @('critical','warn','unknown','ok','info','na')) {
            throw 'El archivo contiene un resultado inválido.'
        }
    }
    $null = Get-ReportDate $data
    return $data
}

function Get-ReportDate($Report) {
    if ($Report.finishedAt -is [datetime]) { return $Report.finishedAt.ToLocalTime() }
    return [DateTimeOffset]::Parse([string]$Report.finishedAt, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime
}

function Get-FilteredChecks($Report, [string]$Category, [int]$Status, [string]$Query) {
    if (-not $Report) { return }
    $rank = @('critical','warn','unknown','ok','info','na')
    $Query = $Query.Trim()
    $compare = [Globalization.CultureInfo]::GetCultureInfo('es-AR').CompareInfo
    $options = [Globalization.CompareOptions]::IgnoreCase -bor [Globalization.CompareOptions]::IgnoreNonSpace
    foreach ($key in $rank) {
        if ($Status -eq 1 -and $key -notin @('critical','warn','unknown')) { continue }
        if ($Status -ge 2 -and $key -ne $rank[$Status - 2]) { continue }
        foreach ($check in $Report.checks) {
            if ($check.status -ne $key) { continue }
            if ($Category -and $Category -ne 'Todas las áreas' -and $Category -ne $check.category) { continue }
            if ($Query) {
                $text = @($check.title, $check.category, $check.summary, $check.next) -join ' '
                if ($compare.IndexOf($text, $Query, $options) -lt 0) { continue }
            }
            $check
        }
    }
}

function Get-SavedReports([string[]]$Roots) {
    $records = foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $html = Join-Path $directory.FullName 'Informe.html'
            $json = Join-Path $directory.FullName 'diagnostico.json'
            if (-not (Test-Path -LiteralPath $html -PathType Leaf) -or -not (Test-Path -LiteralPath $json -PathType Leaf)) { continue }
            try {
                $data = Read-DiagnosticReport $json
                if ($data.demo) { continue }
                if ($data.appVersion -ne '0.1.0') {
                    $progress = Get-Content -LiteralPath (Join-Path $directory.FullName 'progress.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($progress.done -ne $true) { continue }
                }
                [pscustomobject]@{
                    path = $directory.FullName
                    machine = [string]$data.machine
                    date = Get-ReportDate $data
                    alerts = @($data.checks | Where-Object {$_.status -in @('critical','warn')}).Count
                    version = [string]$data.appVersion
                }
            } catch {
                # Leave an incompatible or unfinished report on disk for recovery.
            }
        }
    }
    $records | Sort-Object date -Descending
}
