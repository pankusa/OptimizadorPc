# Runs on Windows PowerShell 5.1 or PowerShell 7.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'app/ReportData.ps1')
$fixture = Join-Path $root 'docs/Ejemplo_datos.json'
$report = Read-DiagnosticReport $fixture
if (-not $report.demo -or $report.checks.Count -ne 21) { throw 'Ejemplo inválido.' }
$all = @(Get-FilteredChecks $report 'Todas las áreas' 0 '')
if ($all.Count -ne 21 -or $all[0].status -ne 'warn') { throw 'Resultados u orden incorrectos.' }
$match = @(Get-FilteredChecks $report 'Almacenamiento' 3 'VOLÚMENES')
if ($match.Count -ne 1 -or $match[0].id -ne 'volumes') { throw 'Falló el cruce de categoría, estado y búsqueda sin tildes.' }
$alerts = @(Get-FilteredChecks $report 'Todas las áreas' 1 '')
if ($alerts.Count -eq 0 -or @($alerts | Where-Object status -notin @('critical','warn','unknown')).Count) {
    throw 'El filtro de alertas y pendientes devolvió un estado incorrecto.'
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('OptimizadorPc-tests-' + [guid]::NewGuid())
try {
    foreach ($folder in @('anterior', 'actual', 'incompleto')) {
        $path = Join-Path $temp $folder
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $report.demo = $false
        $report.appVersion = if ($folder -eq 'anterior') {'0.1.0'} else {'0.2.0'}
        if ($folder -eq 'anterior') { $report.finishedAt = '2025-01-01T00:00:00Z' }
        else { $report.finishedAt = '2025-01-02T00:00:00Z' }
        $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $path 'diagnostico.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $path 'Informe.html') -Value '<!doctype html>'
        @{done = $folder -eq 'actual'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $path 'progress.json')
    }
    $saved = @(Get-SavedReports @($temp))
    if ($saved.Count -ne 2 -or $saved[0].version -ne '0.2.0' -or $saved[1].version -ne '0.1.0') {
        throw 'El historial no recuperó las versiones esperadas o incluyó una ejecución incompleta.'
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
'Datos del informe: filtros, orden, historial heredado y ejecución incompleta verificados.'
