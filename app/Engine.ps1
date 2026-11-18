param([Parameter(Mandatory=$true)][string]$OutputDirectory)
# Windows PowerShell 5.1. Read-only inventory; writes only its own reports.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'Rules.ps1')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$script:checks = New-Object System.Collections.Generic.List[object]
$script:index = 0
$script:started = Get-Date
$script:admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function Write-AtomicJson($Value, [string]$Path) {
    $temp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $temp -Encoding UTF8
    for($attempt=0;$attempt -lt 10;$attempt++){
        try{Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop;return}
        catch{if($attempt -eq 9){throw};Start-Sleep -Milliseconds 60}
    }
}
function Cim([string]$Class, [string]$Namespace='root/cimv2') {
    @(Get-CimInstance -ClassName $Class -Namespace $Namespace -OperationTimeoutSec 12 -ErrorAction Stop)
}
function Result([string]$Status, [string]$Summary, [string]$Next, $Rows=@()) {
    [pscustomobject]@{status=$Status; summary=$Summary; next=$Next; rows=@($Rows)}
}
function Check([string]$Id, [string]$Category, [string]$Title, [string]$Scope, [scriptblock]$Body) {
    $script:index++
    Write-AtomicJson ([ordered]@{step=$script:index; total=21; title=$Title; done=$false}) (Join-Path $OutputDirectory 'progress.json')
    try {
        $r = & $Body
        if ($null -eq $r -or $r.status -notin @('ok','warn','critical','unknown','info','na')) { throw 'La consulta no devolvio un resultado valido.' }
        $script:checks.Add([pscustomobject]@{id=$Id; category=$Category; title=$Title; scope=$Scope; status=$r.status; summary=$r.summary; next=$r.next; rows=@($r.rows); error=$null})
    } catch {
        $message = $_.Exception.Message
        $script:checks.Add([pscustomobject]@{id=$Id; category=$Category; title=$Title; scope=$Scope; status='unknown'; summary='No se pudo completar esta consulta.'; next='Proba ejecutar como administrador. Si persiste, revisa el detalle tecnico; no equivale a una falla del componente.'; rows=@(); error=$message})
    }
}

Check 'inventory' 'Equipo' 'Equipo y Windows' 'Identificacion; no prueba funcionamiento.' {
    $os = Cim 'Win32_OperatingSystem' | Select-Object -First 1
    $pc = Cim 'Win32_ComputerSystem' | Select-Object -First 1
    $board = Cim 'Win32_BaseBoard' | Select-Object -First 1
    $bios = Cim 'Win32_BIOS' | Select-Object -First 1
    $rows = @(
        [pscustomobject]@{Dato='Equipo'; Valor=$env:COMPUTERNAME},
        [pscustomobject]@{Dato='Fabricante / modelo'; Valor=('{0} / {1}' -f $pc.Manufacturer,$pc.Model)},
        [pscustomobject]@{Dato='Windows'; Valor=('{0} - compilacion {1} - {2}' -f $os.Caption,$os.BuildNumber,$os.OSArchitecture)},
        [pscustomobject]@{Dato='Placa madre'; Valor=('{0} {1}' -f $board.Manufacturer,$board.Product)},
        [pscustomobject]@{Dato='BIOS / UEFI'; Valor=$bios.SMBIOSBIOSVersion},
        [pscustomobject]@{Dato='Ultimo inicio'; Valor=([datetime]$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm')},
        [pscustomobject]@{Dato='Permisos'; Valor=$(if($script:admin){'Administrador'}else{'Usuario estandar; algunas consultas pueden faltar'})}
    )
    Result 'info' 'Inventario del equipo y del sistema operativo.' 'La fecha de BIOS no determina por si sola si hay una actualizacion necesaria.' $rows
}
Check 'cpu' 'Hardware' 'Procesador y actividad' 'Tres muestras de uso; sin carga de estres ni lectura termica.' {
    $cpu = @(Cim 'Win32_Processor')
    $samples = @(1..3 | ForEach-Object {
        $p = @(Cim 'Win32_PerfFormattedData_PerfOS_Processor' | Where-Object {$_.Name -eq '_Total'})
        if ($p.Count -eq 0 -or $null -eq $p[0].PercentProcessorTime) { throw 'Contador de CPU no disponible.' }
        [double]$p[0].PercentProcessorTime
        Start-Sleep -Milliseconds 800
    })
    $state = if (@($samples | Where-Object {$_ -ge 90}).Count -eq 3) {'warn'} else {'ok'}
    $rows = @($cpu | ForEach-Object {[pscustomobject]@{Modelo=$_.Name; Nucleos=$_.NumberOfCores; Hilos=$_.NumberOfLogicalProcessors; Frecuencia_nominal_MHz=$_.MaxClockSpeed}})
    $avg = [math]::Round(($samples | Measure-Object -Average).Average,1)
    Result $state "Uso promedio durante la muestra: $avg %." 'Si el uso permanece alto en reposo, revisa Procesos. Esta muestra no certifica estabilidad, frecuencia sostenida ni temperatura.' $rows
}
Check 'ram' 'Hardware' 'Memoria instalada y disponible' 'Capacidad, modulos y presion de memoria en este momento.' {
    $os = Cim 'Win32_OperatingSystem' | Select-Object -First 1
    if ([double]$os.TotalVisibleMemorySize -le 0) {throw 'Memoria total no disponible.'}
    $used = [math]::Round(100 * (1 - [double]$os.FreePhysicalMemory/[double]$os.TotalVisibleMemorySize),1)
    $rows = @(Cim 'Win32_PhysicalMemory' | ForEach-Object {[pscustomobject]@{Ranura=$_.DeviceLocator; Capacidad_GB=[math]::Round($_.Capacity/1073741824,2); Velocidad_configurada_MHz=$_.ConfiguredClockSpeed; Fabricante=$_.Manufacturer; Modelo=$_.PartNumber}})
    Result $(if($used -ge 90){'warn'}else{'ok'}) "Memoria en uso: $used %. Disponible: $([math]::Round($os.FreePhysicalMemory/1048576,2)) GB." 'La deteccion de los modulos no descarta errores de RAM. Ejecuta tambien la prueba con reinicio.' $rows
}
Check 'ramtest' 'Hardware' 'Prueba completa de RAM' 'Requiere reinicio; no se ejecuta en el analisis automatico.' {
    Result 'unknown' 'Prueba de memoria pendiente.' 'En la ventana principal, abri Diagnostico de memoria. Guarda tu trabajo antes de elegir reiniciar. Para una prueba mas extensa, usa F1 durante el diagnostico y selecciona Extended. Consulta luego el resultado en Windows.'
}
Check 'gpu' 'Hardware' 'Placa de video y controlador' 'Enumeracion del adaptador; no prueba VRAM, renderizado ni estabilidad.' {
    $g = @(Cim 'Win32_VideoController')
    if ($g.Count -eq 0) {throw 'Windows no devolvio adaptadores de video.'}
    $bad = @($g | Where-Object {$null -ne $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0})
    $rows = @($g | ForEach-Object {[pscustomobject]@{Adaptador=$_.Name; Controlador=$_.DriverVersion; Codigo_dispositivo=$_.ConfigManagerErrorCode; Resolucion=('{0} x {1}' -f $_.CurrentHorizontalResolution,$_.CurrentVerticalResolution)}})
    Result $(if($bad.Count){'warn'}else{'info'}) "$($g.Count) adaptador(es) detectado(s)." 'Si hay artefactos, pantalla negra o cierres al jugar, hace falta una prueba grafica supervisada y monitoreo de temperatura. La VRAM no se estima con AdapterRAM porque puede informar valores incorrectos.' $rows
}
Check 'disks' 'Almacenamiento' 'Discos: estado y telemetria' 'Estado que informa Windows; contadores segun soporte del controlador.' {
    $disks = @(Get-PhysicalDisk -ErrorAction Stop)
    if ($disks.Count -eq 0) {throw 'No se detectaron discos fisicos con este proveedor.'}
    $rows = @(); $states = @()
    foreach ($d in $disks) {
        $counter=$null; $note=''
        try {$counter = $d | Get-StorageReliabilityCounter -ErrorAction Stop} catch {$note='Contadores no disponibles; revisar permisos o compatibilidad.'}
        $assessment = Get-DiskAssessment $d $counter
        $states += $assessment.status
        $rows += [pscustomobject]@{Disco=$d.FriendlyName; Tipo=[string]$d.MediaType; GB=[math]::Round($d.Size/1073741824,2); Estado_Windows=[string]$d.HealthStatus; Operacion=($d.OperationalStatus -join ', '); Temperatura_C=$(if($counter -and $counter.Temperature -gt 0){$counter.Temperature}else{'ND'}); Limite_termico_C=$(if($counter -and $counter.TemperatureMax -gt 0){$counter.TemperatureMax}else{'ND'}); Desgaste_pct=$(if($counter -and $null -ne $counter.Wear){$counter.Wear}else{'ND'}); Lecturas_no_corregidas=$(if($counter -and $null -ne $counter.ReadErrorsUncorrected){$counter.ReadErrorsUncorrected}else{'ND'}); Escrituras_no_corregidas=$(if($counter -and $null -ne $counter.WriteErrorsUncorrected){$counter.WriteErrorsUncorrected}else{'ND'}); Observacion=($assessment.reasons -join ' ') + ' ' + $note}
    }
    Result (Get-WorstState $states) "$($disks.Count) disco(s) consultado(s). Los valores ND quedan sin verificar." 'Ante un estado de falla, prioriza el respaldo. Los contadores historicos no prueban por si solos una falla actual; un estado Healthy tampoco garantiza toda la superficie ni estima vida restante.' $rows
}
Check 'volumes' 'Almacenamiento' 'Espacio y estado de volumenes' 'Unidades locales con letra; no ejecuta CHKDSK ni un escaneo de superficie.' {
    $vols = @(Get-Volume -ErrorAction Stop | Where-Object {$_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0})
    if (-not $vols.Count) {throw 'No se pudieron consultar volumenes locales.'}
    $rows=@(); $states=@()
    foreach ($v in $vols) {
        $free=100*$v.SizeRemaining/$v.Size
        $st=Get-FreeSpaceState $free ([string]$v.HealthStatus)
        $states += $st
        $rows += [pscustomobject]@{Unidad=([string]$v.DriveLetter + ':'); Sistema=$v.FileSystemType; Estado=[string]$v.HealthStatus; Total_GB=[math]::Round($v.Size/1073741824,2); Libre_GB=[math]::Round($v.SizeRemaining/1073741824,2); Libre_pct=[math]::Round($free,1)}
    }
    Result (Get-WorstState $states) 'Umbrales de espacio: menos de 10 % requiere atencion; menos de 5 % requiere prioridad.' 'Son umbrales orientativos de espacio libre. No representan una falla fisica del disco.' $rows
}
Check 'pnp' 'Hardware' 'Dispositivos y controladores con errores' 'Codigos de Administrador de dispositivos; no busca drivers nuevos en Internet.' {
    $devices = @(Cim 'Win32_PnPEntity')
    if (-not $devices.Count) {throw 'Inventario de dispositivos vacio.'}
    $bad = @($devices | Where-Object {$null -ne $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0})
    $rows = @($bad | ForEach-Object {[pscustomobject]@{Dispositivo=$_.Name; Clase=$_.PNPClass; Codigo=$_.ConfigManagerErrorCode; Estado=$_.Status}})
    Result $(if($bad.Count){'warn'}else{'ok'}) "$($bad.Count) dispositivo(s) con codigo de problema entre $($devices.Count) enumerados." 'Un dispositivo deshabilitado intencionalmente tambien puede aparecer. Revisa su codigo en Administrador de dispositivos antes de reinstalar controladores.' $rows
}
Check 'battery' 'Hardware' 'Bateria de notebook' 'Capacidad declarada por el firmware; no prueba autonomia real.' {
    $batteries = @(Cim 'Win32_Battery')
    if (-not $batteries.Count) {
        $pc=Cim 'Win32_ComputerSystem' | Select-Object -First 1
        if ($pc.PCSystemType -eq 2) {Result 'unknown' 'Notebook sin bateria detectada.' 'Puede estar retirada o no ser visible para Windows. Revisa conexiones y firmware.'; return}
        Result 'na' 'No se detecto bateria en este equipo.' 'En una PC de escritorio esta comprobacion normalmente no corresponde.'; return
    }
    $static = @(Cim 'BatteryStaticData' 'root/wmi')
    $full = @(Cim 'BatteryFullChargedCapacity' 'root/wmi')
    $rows=@(); $states=@()
    foreach($b in $static){
        $f=$full | Where-Object {$_.InstanceName -eq $b.InstanceName} | Select-Object -First 1
        $ratio=Get-BatteryRatio $b.DesignedCapacity $f.FullChargedCapacity
        $states += $(if($null -eq $ratio){'unknown'}elseif($ratio -lt 70){'warn'}else{'ok'})
        $rows += [pscustomobject]@{Bateria=$b.DeviceName; Diseno_mWh=$b.DesignedCapacity; Carga_completa_mWh=$f.FullChargedCapacity; Capacidad_relativa_pct=$(if($null -eq $ratio){'ND'}else{[math]::Round($ratio,1)})}
    }
    if(-not $rows.Count){throw 'El firmware no expone capacidades de bateria.'}
    Result (Get-WorstState $states) 'Capacidad completa comparada con la capacidad de diseno.' 'Menos de 70 % es una referencia orientativa de desgaste. Valores ausentes, cero o fuera de rango quedan sin verificar. No estima horas de uso.' $rows
}
Check 'thermals' 'Hardware' 'Temperaturas, ventiladores y fuente' 'Pendiente de sensor compatible y mediciones fisicas.' {
    Result 'unknown' 'Temperatura de CPU/GPU, ventiladores y fuente sin verificar.' 'Esta version no incorpora un controlador de sensores. Las zonas termicas ACPI no se presentan como temperatura de CPU. La fuente requiere medicion fisica o prueba con otra fuente; el software no certifica sus tensiones ni su estado.'
}
Check 'events' 'Estabilidad' 'Eventos de hardware, disco y reinicios' 'Ultimos 7 dias; hasta 200 eventos coincidentes mas recientes.' {
    $filter=@{LogName='System'; StartTime=(Get-Date).AddDays(-7); Id=@(7,11,17,18,19,20,41,51,55,129,153,1001,6008)}
    $err=@()
    $events=@(Get-WinEvent -FilterHashtable $filter -MaxEvents 200 -ErrorAction SilentlyContinue -ErrorVariable err)
    if(-not $events.Count -and $err.Count -and @($err | Where-Object {$_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound'}).Count){throw $err[0]}
    $events=@($events | Where-Object {
        ($_.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' -and $_.Id -in @(17,18,19,20)) -or
        ($_.ProviderName -in @('disk','Ntfs','Microsoft-Windows-Ntfs','storahci','stornvme','iaStorA','iaStorAC') -and $_.Id -in @(7,11,51,55,129,153)) -or
        ($_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41) -or
        ($_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' -and $_.Id -eq 1001) -or
        ($_.ProviderName -eq 'EventLog' -and $_.Id -eq 6008)
    })
    $rows=@($events | ForEach-Object {[pscustomobject]@{Fecha=$_.TimeCreated.ToString('yyyy-MM-dd HH:mm'); Origen=$_.ProviderName; Id=$_.Id; Nivel=$_.LevelDisplayName; Mensaje=([string]$_.Message).Substring(0,[math]::Min(1400,([string]$_.Message).Length))}})
    Result $(if($events.Count){'warn'}else{'ok'}) "$($events.Count) evento(s) relevante(s) en la ventana consultada." 'Un reinicio inesperado no demuestra una falla de fuente. Correlaciona fecha, actividad y recurrencia. Un registro vacio, truncado o borrado puede omitir antecedentes.' $rows
}
Check 'appscrash' 'Estabilidad' 'Cierres y bloqueos de aplicaciones' 'Ultimos 7 dias; hasta 100 eventos mas recientes.' {
    $err=@()
    $e=@(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-7); Id=@(1000,1002)} -MaxEvents 100 -ErrorAction SilentlyContinue -ErrorVariable err)
    if(-not $e.Count -and $err.Count -and @($err | Where-Object {$_.FullyQualifiedErrorId -notmatch 'NoMatchingEventsFound'}).Count){throw $err[0]}
    $e=@($e | Where-Object {$_.ProviderName -in @('Application Error','Application Hang')})
    $rows=@($e | ForEach-Object {[pscustomobject]@{Fecha=$_.TimeCreated.ToString('yyyy-MM-dd HH:mm'); Origen=$_.ProviderName; Id=$_.Id; Mensaje=([string]$_.Message).Substring(0,[math]::Min(1400,([string]$_.Message).Length))}})
    Result $(if($e.Count){'warn'}else{'ok'}) "$($e.Count) cierre(s) o bloqueo(s) registrado(s)." 'Varios fallos de una misma aplicacion orientan a revisar esa aplicacion, sus complementos y sus controladores. No atribuirlos automaticamente a RAM.' $rows
}
Check 'security' 'Windows' 'Antivirus y proteccion' 'Estado declarado; no ejecuta un analisis de malware.' {
    $av=@(Cim 'AntiVirusProduct' 'root/SecurityCenter2')
    $rows=@($av | ForEach-Object {[pscustomobject]@{Producto=$_.displayName; Estado_declarado=$_.productState}})
    if(-not $av.Count){Result 'warn' 'No hay antivirus registrado en el Centro de seguridad.' 'Revisa Seguridad de Windows. La ausencia de registro no demuestra por si sola que no exista una proteccion corporativa.' $rows; return}
    $m=$null
    try {$m=Get-MpComputerStatus -ErrorAction Stop} catch {}
    if($m -and $m.AMRunningMode -eq 'Normal') {
        $rows += [pscustomobject]@{Producto='Microsoft Defender'; Proteccion_tiempo_real=$m.RealTimeProtectionEnabled; Antiguedad_firmas_dias=$m.AntivirusSignatureAge}
        $status=if(-not $m.RealTimeProtectionEnabled -or ($null -ne $m.AntivirusSignatureAge -and $m.AntivirusSignatureAge -gt 7)){'warn'}else{'ok'}
        Result $status 'Microsoft Defender informa su estado activo.' 'La proteccion habilitada no garantiza ausencia de malware. Si hay sintomas, ejecuta un analisis desde Seguridad de Windows.' $rows
    } else {Result 'unknown' 'Hay antivirus registrado; su proteccion efectiva no se valido.' 'Revisa estado y firmas desde la aplicacion del antivirus. No se interpreta el codigo productState como garantia de proteccion.' $rows}
}
Check 'firewall' 'Windows' 'Firewall de Windows' 'Perfiles configurados; no escanea puertos ni verifica una suite de terceros.' {
    $profiles=@(Get-NetFirewallProfile -ErrorAction Stop)
    if(-not $profiles.Count){throw 'No se recibieron perfiles de firewall.'}
    $rows=@($profiles | ForEach-Object {[pscustomobject]@{Perfil=$_.Name; Habilitado=[string]$_.Enabled; Entrada=[string]$_.DefaultInboundAction}})
    Result $(if(@($profiles|Where-Object {$_.Enabled -ne 'True'}).Count){'warn'}else{'ok'}) 'Configuracion de perfiles de firewall consultada.' 'Un perfil desactivado puede responder a una politica o a otra suite de seguridad. Verifica el contexto antes de modificarlo.' $rows
}
Check 'updates' 'Windows' 'Actualizaciones instaladas y reinicio' 'Historial local parcial; no comprueba actualizaciones disponibles en linea.' {
    $hotfix=@(Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 15)
    $pending=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    $rows=@($hotfix | ForEach-Object {[pscustomobject]@{Actualizacion=$_.HotFixID; Tipo=$_.Description; Fecha=$(if($_.InstalledOn){$_.InstalledOn.ToString('yyyy-MM-dd')}else{'ND'})}})
    Result $(if($pending){'warn'}else{'info'}) $(if($pending){'Windows tiene una senal de reinicio pendiente.'}else{'Se consulto el historial local. Vigencia de parches sin verificar.'}) 'Abri Windows Update para comprobar parches disponibles y soporte de tu edicion. Get-HotFix no incluye todos los tipos de actualizacion.' $rows
}
Check 'integrity' 'Windows' 'Integridad de archivos y componentes' 'SFC y DISM son pruebas adicionales, no parte de la revision rapida.' {
    Result 'unknown' 'Integridad de Windows pendiente de analisis.' 'Desde la ventana principal podes abrir SFC /verifyonly y DISM /ScanHealth con permisos de administrador. Los resultados quedan en sus ventanas y registros de Windows; no se importan automaticamente a este informe.'
}
Check 'processes' 'Software' 'Procesos con mayor uso de memoria' 'Instantanea; no analiza codigo malicioso ni mide CPU historica por proceso.' {
    $rows=@(Get-Process -ErrorAction Stop | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 | ForEach-Object {[pscustomobject]@{Proceso=$_.ProcessName; PID=$_.Id; Memoria_MB=[math]::Round($_.WorkingSet64/1048576,1); CPU_acumulada_s=$(if($null -ne $_.CPU){[math]::Round($_.CPU,1)}else{'ND'})}})
    Result 'info' '15 procesos con mayor memoria residente.' 'La CPU acumulada corresponde al tiempo de vida del proceso; no es un porcentaje de uso actual. No cierres procesos solo por aparecer en esta lista.' $rows
}
Check 'startup' 'Software' 'Inicio automatico' 'Comandos de inicio visibles por WMI; no incluye todas las tareas y servicios.' {
    $rows=@(Cim 'Win32_StartupCommand' | ForEach-Object {[pscustomobject]@{Programa=$_.Name; Ubicacion=$_.Location}})
    Result 'info' "$($rows.Count) entrada(s) de inicio detectada(s)." 'Revisa el impacto desde Administrador de tareas > Aplicaciones de inicio. No se publican comandos ni rutas personales en esta tabla.' $rows
}
Check 'software' 'Software' 'Programas instalados' 'Entradas de desinstalacion de maquina y usuario actual; no todos los paquetes Store.' {
    $paths=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $apps=@(foreach($path in $paths){if(Test-Path ($path -replace '\\\*$','')){Get-ItemProperty -Path $path -ErrorAction Stop | Where-Object {$_.DisplayName} | Select-Object -Property @('DisplayName','DisplayVersion','Publisher')}})
    $rows=@($apps | Sort-Object -Property @('DisplayName','DisplayVersion') -Unique | ForEach-Object {[pscustomobject]@{Programa=$_.DisplayName; Version=$_.DisplayVersion; Editor=$_.Publisher}})
    Result 'info' "$($rows.Count) programa(s) inventariado(s)." 'Este inventario no verifica vulnerabilidades, licencias ni compatibilidad. Se lee el registro; no se consulta Win32_Product para evitar reparaciones MSI.' $rows
}
Check 'network' 'Conectividad' 'Adaptadores y enlace de red' 'Estado local del enlace; no prueba acceso a Internet, DNS ni velocidad real.' {
    $adapters=@(Get-NetAdapter -Physical -ErrorAction Stop)
    if(-not $adapters.Count){Result 'unknown' 'No hay adaptadores fisicos visibles.' 'En maquinas virtuales o adaptadores especiales puede no corresponder este filtro.'; return}
    $rows=@($adapters | ForEach-Object {[pscustomobject]@{Adaptador=$_.Name; Modelo=$_.InterfaceDescription; Enlace=[string]$_.Status; Velocidad_negociada=$_.LinkSpeed}})
    Result $(if(@($adapters | Where-Object {$_.Status -eq 'Up'}).Count){'ok'}else{'warn'}) 'Estado de enlace de adaptadores fisicos consultado.' 'Un enlace desconectado puede ser intencional. La velocidad negociada no es la velocidad de Internet. No se envia trafico de prueba.' $rows
}
Check 'peripherals' 'Perifericos' 'Audio, pantalla, USB e impresion' 'Deteccion de dispositivos; funcionamiento fisico requiere prueba manual.' {
    $rows=@(Cim 'Win32_SoundDevice' | ForEach-Object {[pscustomobject]@{Tipo='Audio'; Nombre=$_.Name; Estado=$_.Status}})
    $rows+=@(Cim 'Win32_Printer' | ForEach-Object {[pscustomobject]@{Tipo='Impresora'; Nombre=$_.Name; Estado=$_.PrinterStatus}})
    Result 'unknown' 'Pruebas funcionales de perifericos pendientes.' 'El informe incluye una lista manual para pantalla, audio, microfono, camara, teclado, mouse, USB, red e impresion. Detectar un dispositivo no comprueba su funcionamiento.' $rows
}

$report=[ordered]@{schemaVersion=1; appVersion='0.2.0'; machine=$env:COMPUTERNAME; startedAt=$script:started.ToString('o'); finishedAt=(Get-Date).ToString('o'); administrator=$script:admin; checks=@($script:checks.ToArray()); manual=@(); limitations=@('No es una certificacion de hardware ni garantiza ausencia de fallas.','No ejecuta carga de estres, pruebas completas de RAM/VRAM ni escaneo de superficie.','No lee sensores CPU/GPU ni certifica fuente, placa madre o refrigeracion.','Los resultados pueden ser parciales por permisos, controladores, firmware o registros incompletos.','No instala, repara, limpia, actualiza ni reinicia automaticamente.')}
Write-AtomicJson $report (Join-Path $OutputDirectory 'diagnostico.json')
$json=$report | ConvertTo-Json -Depth 16 -Compress
$data=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$template=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Report.html') -Raw -Encoding UTF8
$template.Replace('__REPORT_BASE64__',$data) | Set-Content -LiteralPath (Join-Path $OutputDirectory 'Informe.html') -Encoding UTF8
Write-AtomicJson ([ordered]@{step=21; total=21; title='Informe disponible'; done=$true; report=(Join-Path $OutputDirectory 'Informe.html')}) (Join-Path $OutputDirectory 'progress.json')
