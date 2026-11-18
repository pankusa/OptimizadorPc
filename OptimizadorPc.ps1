param([switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'app\ReportData.ps1')
[Windows.Forms.Application]::EnableVisualStyles()

$root = $PSScriptRoot
$local = [Environment]::GetFolderPath('LocalApplicationData')
$reportRoot = Join-Path $local 'OptimizadorPc\Informes'
$legacyRoot = Join-Path $local 'PCClaro\Informes'
$systemDir = [Environment]::SystemDirectory
$windowsDir = [Environment]::GetFolderPath('Windows')
$powerShell = Join-Path $PSHOME 'powershell.exe'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$worker = $null
$runDirectory = $null
$report = $null
$activeDirectory = $null
$cancelling = $false
$refreshing = $false

$ink = [Drawing.Color]::FromArgb(22, 48, 57)
$teal = [Drawing.Color]::FromArgb(0, 102, 91)
$surface = [Drawing.Color]::FromArgb(242, 247, 246)
$white = [Drawing.Color]::White
$statusLabels = @{critical='Prioridad'; warn='Atención'; unknown='Sin verificar'; ok='Sin alertas'; info='Inventario'; na='No aplica'}
$statusColors = @{
    critical = [Drawing.Color]::FromArgb(148, 25, 48)
    warn = [Drawing.Color]::FromArgb(115, 65, 0)
    unknown = [Drawing.Color]::FromArgb(70, 83, 101)
    ok = $teal
    info = $ink
    na = $ink
}

function New-Text([string]$Value, [int]$Size = 10, [switch]$Bold) {
    $control = New-Object Windows.Forms.Label
    $control.Text = $Value
    $style = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $control.Font = [Drawing.Font]::new('Segoe UI', [single]$Size, $style)
    $control.ForeColor = $ink
    $control.AutoSize = $true
    $control.Margin = New-Object Windows.Forms.Padding(0, 5, 12, 5)
    return $control
}

function New-Button([string]$Value, [scriptblock]$Click, [switch]$Primary) {
    $control = New-Object Windows.Forms.Button
    $control.Text = $Value
    $control.AutoSize = $true
    $control.Padding = New-Object Windows.Forms.Padding(8, 3, 8, 3)
    $control.MinimumSize = New-Object Drawing.Size(0, 34)
    $control.Margin = New-Object Windows.Forms.Padding(0, 0, 8, 5)
    $control.FlatStyle = 'Flat'
    $control.BackColor = $white
    $control.ForeColor = $ink
    if ($Primary) {
        $control.BackColor = $teal
        $control.ForeColor = $white
    }
    $control.Add_Click($Click)
    return $control
}

function New-Grid([int]$Columns, [int]$Rows) {
    $control = New-Object Windows.Forms.TableLayoutPanel
    $control.ColumnCount = $Columns
    $control.RowCount = $Rows
    $control.Dock = 'Fill'
    return $control
}

function New-Flow {
    $control = New-Object Windows.Forms.FlowLayoutPanel
    $control.Dock = 'Fill'
    $control.AutoSize = $true
    $control.Margin = New-Object Windows.Forms.Padding(0)
    return $control
}

function New-List([string[]]$Names, [int[]]$Widths) {
    $control = New-Object Windows.Forms.ListView
    $control.Dock = 'Fill'
    $control.View = 'Details'
    $control.FullRowSelect = $true
    $control.HideSelection = $false
    $control.MultiSelect = $false
    $control.HeaderStyle = 'Nonclickable'
    for ($column = 0; $column -lt $Names.Count; $column++) {
        $null = $control.Columns.Add($Names[$column], $Widths[$column])
    }
    return $control
}

function New-Dropdown([string]$Name) {
    $control = New-Object Windows.Forms.ComboBox
    $control.AccessibleName = $Name
    $control.DropDownStyle = 'DropDownList'
    $control.Width = 160
    $control.Margin = New-Object Windows.Forms.Padding(0, 0, 12, 5)
    return $control
}

function Notify([string]$Message) {
    if ($SmokeTest) { throw $Message }
    [Windows.Forms.MessageBox]::Show($form, $Message, 'OptimizadorPc', 'OK', 'Information') | Out-Null
}

function Open-Report {
    if (-not $script:activeDirectory) { return }
    $file = Join-Path $script:activeDirectory 'Informe.html'
    try { Start-Process -FilePath $file }
    catch { Notify ('No se pudo abrir el informe. ' + $_.Exception.Message) }
}

function Open-ReportsFolder {
    try {
        New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
        Start-Process -FilePath (Join-Path $windowsDir 'explorer.exe') -ArgumentList ('"' + $reportRoot + '"')
    } catch { Notify $_.Exception.Message }
}

function Save-Report {
    if (-not $script:activeDirectory) { return }
    $dialog = New-Object Windows.Forms.SaveFileDialog
    $dialog.Title = 'Guardar una copia del diagnóstico'
    $dialog.Filter = 'Informe HTML (*.html)|*.html|Datos del diagnóstico (*.json)|*.json'
    $dialog.FileName = 'Diagnostico-OptimizadorPc'
    try {
        if ($dialog.ShowDialog($form) -ne 'OK') { return }
        $name = if ($dialog.FilterIndex -eq 2) {'diagnostico.json'} else {'Informe.html'}
        if ([IO.Path]::GetExtension($dialog.FileName) -ne [IO.Path]::GetExtension($name)) {
            Notify 'Elegí la extensión correspondiente al formato seleccionado.'
            return
        }
        Copy-Item -LiteralPath (Join-Path $script:activeDirectory $name) -Destination $dialog.FileName -Force
    } catch { Notify ('No se pudo guardar la copia. ' + $_.Exception.Message) }
    finally { $dialog.Dispose() }
}

function Open-Tool([string]$Tool, [string]$Arguments, [string]$Description, [switch]$Elevated) {
    if ([Windows.Forms.MessageBox]::Show($form, $Description, 'Abrir herramienta de Windows', 'OKCancel', 'Information') -ne 'OK') { return }
    try {
        $file = Join-Path $systemDir $Tool
        if ($Elevated) {
            $command = '/d /k "' + $file + '" ' + $Arguments
            Start-Process -FilePath (Join-Path $systemDir 'cmd.exe') -ArgumentList $command -Verb RunAs
        }
        elseif ($Arguments) { Start-Process -FilePath $file -ArgumentList $Arguments }
        else { Start-Process -FilePath $file }
    } catch { Notify ('No se pudo abrir la herramienta. ' + $_.Exception.Message) }
}

function Show-CheckDetail {
    if ($results.SelectedItems.Count -eq 0) {
        $detail.Text = 'Seleccioná un resultado para revisar el alcance, los datos y el próximo paso.'
        return
    }
    $check = $results.SelectedItems[0].Tag
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add($check.title)
    $lines.Add($statusLabels[$check.status] + ' · ' + $check.category)
    $lines.Add('')
    $lines.Add($check.summary)
    $lines.Add('')
    $lines.Add('Qué se comprobó')
    $lines.Add($check.scope)
    $lines.Add('')
    $lines.Add('Próximo paso')
    $lines.Add($check.next)
    if ($check.error) {
        $lines.Add('')
        $lines.Add('Detalle técnico')
        $lines.Add($check.error)
    }
    if ($check.rows.Count) {
        $lines.Add('')
        $lines.Add('Datos encontrados')
        foreach ($row in $check.rows) {
            if ($null -eq $row) { continue }
            $lines.Add('')
            foreach ($property in $row.PSObject.Properties) {
                $value = if ($null -eq $property.Value -or $property.Value -eq '') {'ND'} else {$property.Value -join ', '}
                $lines.Add(('{0}: {1}' -f $property.Name.Replace('_', ' '), $value))
            }
        }
    }
    $detail.Lines = $lines.ToArray()
    $detail.SelectionStart = 0
}

function Refresh-Results {
    if ($script:refreshing) { return }
    $previousId = if ($results.SelectedItems.Count) {$results.SelectedItems[0].Tag.id}
    $results.BeginUpdate()
    try {
        $results.Items.Clear()
        $filtered = @(Get-FilteredChecks -Report $script:report -Category ([string]$category.SelectedItem) -Status $state.SelectedIndex -Query $search.Text)
        $selected = $null
        foreach ($check in $filtered) {
            $item = New-Object Windows.Forms.ListViewItem($statusLabels[$check.status])
            $item.ForeColor = $statusColors[$check.status]
            $null = $item.SubItems.Add($check.title)
            $null = $item.SubItems.Add($check.category)
            $item.Tag = $check
            $null = $results.Items.Add($item)
            if ($check.id -eq $previousId) { $selected = $item }
        }
        if ($results.Items.Count) {
            if (-not $selected) { $selected = $results.Items[0] }
            $selected.Selected = $true
        }
        $resultCount.Text = if ($script:report) {'{0} de {1}' -f $filtered.Count, $script:report.checks.Count} else {'Sin resultados'}
    } finally { $results.EndUpdate() }
    Show-CheckDetail
}

function Set-Report($Data, [string]$Directory) {
    $script:report = $Data
    $script:activeDirectory = $Directory
    $script:refreshing = $true
    try {
        $category.Items.Clear()
        $null = $category.Items.Add('Todas las áreas')
        foreach ($name in @($Data.checks.category | Sort-Object -Unique)) { $null = $category.Items.Add($name) }
        $category.SelectedIndex = 0
        $state.SelectedIndex = 0
        $search.Clear()
    } finally { $script:refreshing = $false }
    $overview.Text = if ($Data.demo) {'Ejemplo con datos ficticios'} else {'{0} · {1}' -f $Data.machine, (Get-ReportDate $Data).ToString('dd/MM/yyyy HH:mm')}
    $totals = foreach ($key in @('critical', 'warn', 'unknown', 'ok')) {
        '{0} {1}' -f @($Data.checks | Where-Object status -eq $key).Count, $statusLabels[$key].ToLowerInvariant()
    }
    $summary.Text = $totals -join '    ·    '
    $htmlButton.Enabled = [bool]$Directory
    $saveButton.Enabled = [bool]$Directory
    Refresh-Results
}

function Refresh-History {
    $history.BeginUpdate()
    try {
        $history.Items.Clear()
        foreach ($record in @(Get-SavedReports -Roots @($reportRoot, $legacyRoot))) {
            $item = New-Object Windows.Forms.ListViewItem($record.date.ToString('dd/MM/yyyy HH:mm'))
            $null = $item.SubItems.Add($record.machine)
            $null = $item.SubItems.Add([string]$record.alerts)
            $null = $item.SubItems.Add($record.version)
            $item.Tag = $record.path
            $null = $history.Items.Add($item)
        }
        $historyStatus.Text = if ($history.Items.Count) {'Seleccioná un diagnóstico para ver sus resultados.'} else {'Todavía no hay diagnósticos guardados.'}
    } finally { $history.EndUpdate() }
}

function Show-HistoryReport {
    if ($history.SelectedItems.Count -eq 0) { return }
    try {
        $directory = $history.SelectedItems[0].Tag
        Set-Report (Read-DiagnosticReport (Join-Path $directory 'diagnostico.json')) $directory
        $tabs.SelectedTab = $diagnosticTab
    } catch { Notify ('No se pudo leer el diagnóstico. ' + $_.Exception.Message) }
}

function Start-Diagnostic {
    if ($script:worker) { return }
    try {
        $script:runDirectory = Join-Path $reportRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $script:runDirectory -Force | Out-Null
        $engine = Join-Path $root 'app\Engine.ps1'
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $engine + '" -OutputDirectory "' + $script:runDirectory + '"'
        $script:worker = Start-Process -FilePath $powerShell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $script:runDirectory 'error.log') -RedirectStandardOutput (Join-Path $script:runDirectory 'salida.log')
        $null = $script:worker.Handle
        $script:cancelling = $false
        $startButton.Enabled = $false
        $cancelButton.Enabled = $true
        $logButton.Enabled = $false
        $progress.Value = 0
        $progress.Style = 'Marquee'
        $scanStatus.Text = 'Iniciando diagnóstico…'
        $timer.Start()
    } catch { Notify ('No se pudo iniciar el diagnóstico. ' + $_.Exception.Message) }
}

function Stop-Diagnostic {
    if (-not $script:worker -or $script:worker.HasExited) { return }
    try {
        $script:worker.Kill()
        $script:cancelling = $true
        $cancelButton.Enabled = $false
        $scanStatus.Text = 'Cancelando…'
    } catch {
        if (-not $script:worker.HasExited) { Notify ('No se pudo cancelar. ' + $_.Exception.Message) }
    }
}

function Update-Scan {
    $progressPath = Join-Path $script:runDirectory 'progress.json'
    if (-not $script:cancelling -and (Test-Path -LiteralPath $progressPath)) {
        try {
            $scan = Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $progress.Style = 'Continuous'
            $progress.Maximum = [Math]::Max(1, [int]$scan.total)
            $progress.Value = [Math]::Max(0, [Math]::Min($progress.Maximum, [int]$scan.step))
            $scanStatus.Text = '{0}/{1} · {2}' -f $scan.step, $scan.total, $scan.title
        } catch {
            # The worker may be replacing the status file between reads.
        }
    }
    if (-not $script:worker.HasExited) { return }

    $timer.Stop()
    $exitCode = $script:worker.ExitCode
    $script:worker.Dispose()
    $script:worker = $null
    $startButton.Enabled = $true
    $cancelButton.Enabled = $false
    $progress.Style = 'Continuous'
    if ($script:cancelling) {
        $progress.Value = 0
        $scanStatus.Text = 'Diagnóstico cancelado.'
        return
    }
    try {
        if ($exitCode -ne 0) { throw ('Código de salida: ' + $exitCode) }
        $data = Read-DiagnosticReport (Join-Path $script:runDirectory 'diagnostico.json')
        if (-not (Test-Path -LiteralPath (Join-Path $script:runDirectory 'Informe.html') -PathType Leaf)) {
            throw 'El informe HTML no se generó.'
        }
        Set-Report $data $script:runDirectory
        $progress.Value = $progress.Maximum
        $scanStatus.Text = 'Diagnóstico terminado y guardado.'
        Refresh-History
    } catch {
        $scanStatus.Text = 'Diagnóstico incompleto. ' + $_.Exception.Message
        $logButton.Enabled = Test-Path -LiteralPath (Join-Path $script:runDirectory 'error.log') -PathType Leaf
    }
}

$form = New-Object Windows.Forms.Form
$form.Text = 'OptimizadorPc'
$form.ClientSize = New-Object Drawing.Size(1120, 680)
$form.MinimumSize = New-Object Drawing.Size(760, 550)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
$form.BackColor = $surface
$form.Font = [Drawing.Font]::new('Segoe UI', [single]10)
$layout = New-Grid 1 2
$layout.Padding = New-Object Windows.Forms.Padding(16, 12, 16, 12)
$null = $layout.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize)))
$null = $layout.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, [single]100)))
$form.Controls.Add($layout)

$header = New-Flow
$header.Controls.Add((New-Text 'OptimizadorPc' 23 -Bold))
$permission = if ($admin) {'Administrador'} else {'Usuario estándar'}
$header.Controls.Add((New-Text ('Diagnóstico local de Windows · ' + $permission)))
$layout.Controls.Add($header, 0, 0)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$layout.Controls.Add($tabs, 0, 1)
$diagnosticTab = New-Object Windows.Forms.TabPage('Diagnóstico')
$historyTab = New-Object Windows.Forms.TabPage('Historial')
$toolsTab = New-Object Windows.Forms.TabPage('Pruebas de Windows')
$tabs.TabPages.AddRange(@($diagnosticTab, $historyTab, $toolsTab))
foreach ($page in $tabs.TabPages) { $page.BackColor = $surface; $page.Padding = New-Object Windows.Forms.Padding(12) }

$dashboard = New-Grid 1 7
for ($index = 0; $index -lt 6; $index++) { $null = $dashboard.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))) }
$null = $dashboard.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, [single]100)))
$diagnosticTab.Controls.Add($dashboard)

$actions = New-Flow
$startButton = New-Button 'Iniciar diagnóstico' { Start-Diagnostic } -Primary
$cancelButton = New-Button 'Cancelar' { Stop-Diagnostic }
$htmlButton = New-Button 'Informe y pruebas guiadas' { Open-Report }
$saveButton = New-Button 'Guardar copia' { Save-Report }
$demoButton = New-Button 'Ver ejemplo' {
    try {
        Set-Report (Read-DiagnosticReport (Join-Path $root 'docs\Ejemplo_datos.json')) ''
    } catch { Notify $_.Exception.Message }
}
$logButton = New-Button 'Abrir registro' {
    try { Start-Process -FilePath (Join-Path $script:runDirectory 'error.log') }
    catch { Notify $_.Exception.Message }
}
$actions.Controls.AddRange(@($startButton, $cancelButton, $htmlButton, $saveButton, $demoButton, $logButton))
$cancelButton.Enabled = $false
$htmlButton.Enabled = $false
$saveButton.Enabled = $false
$logButton.Enabled = $false
$dashboard.Controls.Add($actions, 0, 0)

$progress = New-Object Windows.Forms.ProgressBar
$progress.Dock = 'Top'
$progress.Height = 8
$progress.AccessibleName = 'Avance del diagnóstico'
$dashboard.Controls.Add($progress, 0, 1)
$scanStatus = New-Text 'Listo para revisar esta PC.'
$dashboard.Controls.Add($scanStatus, 0, 2)
$overview = New-Text 'Resultados del diagnóstico' 15 -Bold
$dashboard.Controls.Add($overview, 0, 3)
$summary = New-Text 'Iniciá un diagnóstico o abrí el ejemplo.'
$dashboard.Controls.Add($summary, 0, 4)
$filters = New-Flow
$category = New-Dropdown 'Área'
$null = $category.Items.Add('Todas las áreas')
$category.SelectedIndex = 0
$state = New-Dropdown 'Estado'
$state.Items.AddRange(@('Todos los estados', 'Alertas y pendientes', 'Prioridad', 'Atención', 'Sin verificar', 'Sin alertas', 'Inventario', 'No aplica'))
$state.SelectedIndex = 0
$search = New-Object Windows.Forms.TextBox
$search.AccessibleName = 'Buscar resultados'
$search.Width = 165
$search.Margin = New-Object Windows.Forms.Padding(0, 0, 10, 5)
$resultCount = New-Text 'Sin resultados'
$filters.Controls.AddRange(@($category, $state, (New-Text 'Buscar'), $search, $resultCount))
$dashboard.Controls.Add($filters, 0, 5)

$resultsLayout = New-Grid 2 1
$null = $resultsLayout.ColumnStyles.Add(([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, [single]58)))
$null = $resultsLayout.ColumnStyles.Add(([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, [single]42)))
$null = $resultsLayout.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, [single]100)))
$dashboard.Controls.Add($resultsLayout, 0, 6)
$results = New-List @('Estado', 'Comprobación', 'Área') @(116, 290, 125)
$results.AccessibleName = 'Resultados del diagnóstico'
$results.Add_SizeChanged({
    $width = $results.ClientSize.Width - [Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    $results.Columns[1].Width = [Math]::Max(95, $width - $results.Columns[0].Width - $results.Columns[2].Width)
})
$resultsLayout.Controls.Add($results, 0, 0)
$detail = New-Object Windows.Forms.TextBox
$detail.AccessibleName = 'Detalle del resultado'
$detail.Multiline = $true
$detail.ScrollBars = 'Vertical'
$detail.ReadOnly = $true
$detail.BackColor = $white
$detail.ForeColor = $ink
$detail.Dock = 'Fill'
$detail.Margin = New-Object Windows.Forms.Padding(9, 3, 0, 3)
$resultsLayout.Controls.Add($detail, 1, 0)
$results.Add_SelectedIndexChanged({ Show-CheckDetail })
$category.Add_SelectedIndexChanged({ Refresh-Results })
$state.Add_SelectedIndexChanged({ Refresh-Results })
$search.Add_TextChanged({ Refresh-Results })

$historyLayout = New-Grid 1 3
$null = $historyLayout.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize)))
$null = $historyLayout.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize)))
$null = $historyLayout.RowStyles.Add(([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, [single]100)))
$historyTab.Controls.Add($historyLayout)
$historyActions = New-Flow
$showHistoryButton = New-Button 'Ver diagnóstico seleccionado' { Show-HistoryReport } -Primary
$showHistoryButton.Enabled = $false
$historyActions.Controls.AddRange(@($showHistoryButton, (New-Button 'Actualizar' { Refresh-History }), (New-Button 'Abrir carpeta de informes' { Open-ReportsFolder })))
$historyLayout.Controls.Add($historyActions, 0, 0)
$historyStatus = New-Text ''
$historyLayout.Controls.Add($historyStatus, 0, 1)
$history = New-List @('Fecha', 'Equipo', 'Alertas', 'Versión') @(180, 225, 90, 100)
$history.AccessibleName = 'Historial de diagnósticos'
$history.Add_SelectedIndexChanged({ $showHistoryButton.Enabled = $history.SelectedItems.Count -gt 0 })
$history.Add_DoubleClick({ Show-HistoryReport })
$historyLayout.Controls.Add($history, 0, 2)

$tools = New-Flow
$tools.FlowDirection = 'TopDown'
$tools.WrapContents = $false
$tools.AutoScroll = $true
$toolsTab.Controls.Add($tools)
$tools.Controls.Add((New-Text 'Verificaciones adicionales' 16 -Bold))
$tools.Controls.Add((New-Text 'Consultá los resultados en la herramienta de Windows que se abre.'))
$tools.Controls.Add((New-Button 'Diagnóstico de memoria RAM' {
    Open-Tool 'mdsched.exe' '' 'Guardá tu trabajo antes de elegir el reinicio en Diagnóstico de memoria.'
}))
$tools.Controls.Add((New-Button 'Verificar archivos de Windows (SFC)' {
    Open-Tool 'sfc.exe' '/verifyonly' 'SFC verifica los archivos protegidos de Windows con permisos de administrador.' -Elevated
}))
$tools.Controls.Add((New-Button 'Analizar la imagen de Windows (DISM)' {
    Open-Tool 'Dism.exe' '/Online /Cleanup-Image /ScanHealth' 'DISM analiza el almacén de componentes con permisos de administrador.' -Elevated
}))
$tools.Controls.Add((New-Button 'Administrador de dispositivos' {
    Open-Tool 'mmc.exe' ('"' + (Join-Path $systemDir 'devmgmt.msc') + '"') 'Se abrirá el Administrador de dispositivos.'
}))

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({ Update-Scan })
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:worker -and -not $script:worker.HasExited) {
        $answer = [Windows.Forms.MessageBox]::Show($form, '¿Cerrar y cancelar el diagnóstico en curso?', 'OptimizadorPc', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { $eventArgs.Cancel = $true; return }
        Stop-Diagnostic
        if (-not $script:cancelling -and -not $script:worker.HasExited) { $eventArgs.Cancel = $true; return }
    }
    $timer.Stop()
})

Refresh-History
Refresh-Results
if ($SmokeTest) {
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $demoButton.PerformClick()
    if ($results.Items.Count -ne $report.checks.Count -or $results.Items.Count -eq 0 -or $htmlButton.Enabled) { throw 'No se cargó el ejemplo en la ventana.' }
    $search.Text = 'procesador'
    if ($results.Items.Count -ne 1) { throw 'La búsqueda de la ventana no devolvió el resultado esperado.' }
    $results.Items[0].Selected = $true
    Show-CheckDetail
    if ($detail.Text -notmatch 'Procesador') { throw 'No se cargó el detalle del resultado.' }
    $form.Close()
    'Interfaz: ejemplo, búsqueda y detalle verificados.'
    return
}
[Windows.Forms.Application]::Run($form)
