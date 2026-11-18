# Self-contained boundary tests; no Pester, hardware access or admin required.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'app\Rules.ps1')
$script:passed=0
function Assert-Equal($Actual,$Expected,[string]$Message){
    if($Actual -ne $Expected){throw "$Message - esperado: $Expected; obtenido: $Actual"}
    $script:passed++
}
Assert-Equal (Get-WorstState @('ok','unknown')) 'unknown' 'Dato ausente no es saludable'
Assert-Equal (Get-WorstState @('warn','unknown','critical')) 'critical' 'Una falla tiene prioridad'
Assert-Equal (Get-WorstState @()) 'unknown' 'Coleccion vacia'
Assert-Equal (Get-FreeSpaceState 4.99 'Healthy') 'critical' 'Espacio inferior a 5'
Assert-Equal (Get-FreeSpaceState 5 'Healthy') 'warn' 'Limite exacto 5'
Assert-Equal (Get-FreeSpaceState 9.99 'Healthy') 'warn' 'Espacio inferior a 10'
Assert-Equal (Get-FreeSpaceState 10 'Healthy') 'ok' 'Limite exacto 10'
Assert-Equal (Get-FreeSpaceState 50 'Unknown') 'unknown' 'Estado de volumen desconocido'
Assert-Equal (Get-FreeSpaceState 50 'Unhealthy') 'critical' 'Estado de volumen no saludable'
Assert-Equal (Get-BatteryRatio 0 5000) $null 'Bateria sin capacidad de diseno'
Assert-Equal (Get-BatteryRatio 5000 $null) $null 'Bateria sin capacidad completa'
Assert-Equal (Get-BatteryRatio 5000 3500) 70 'Relacion de bateria'
Assert-Equal (Get-BatteryRatio 5000 7000) $null 'Bateria fuera de rango razonable'
$healthy=[pscustomobject]@{HealthStatus='Healthy';OperationalStatus=@('OK')}
$bad=[pscustomobject]@{HealthStatus='Unhealthy';OperationalStatus=@('OK')}
$counter=[pscustomobject]@{Wear=0;Temperature=30;TemperatureMax=70;ReadErrorsUncorrected=0;WriteErrorsUncorrected=0}
Assert-Equal (Get-DiskAssessment $healthy $null).status 'unknown' 'Disco sin contadores'
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'ok' 'Disco sin alertas en datos presentes'
Assert-Equal (Get-DiskAssessment $bad $null).status 'critical' 'Falla de disco aunque falten sensores'
$counter.Wear=80
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'warn' 'Desgaste 80'
$counter.Wear=100
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'critical' 'Desgaste 100'
$counter.Wear=0;$counter.Temperature=70
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'warn' 'Temperatura en limite declarado'
$counter.Temperature=30;$counter.ReadErrorsUncorrected=1
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'warn' 'Errores historicos requieren revision'
$counter.ReadErrorsUncorrected=0;$counter.Wear=$null
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'unknown' 'Dato de desgaste ausente'
$counter.Wear=0;$counter.TemperatureMax=$null
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'unknown' 'Limite termico ausente'
$counter.TemperatureMax=70;$counter.WriteErrorsUncorrected=$null
Assert-Equal (Get-DiskAssessment $healthy $counter).status 'unknown' 'Contador de escritura ausente'
$disconnected=[pscustomobject]@{HealthStatus='Healthy';OperationalStatus=@('Lost Communication')}
Assert-Equal (Get-DiskAssessment $disconnected $counter).status 'critical' 'Falla operativa tiene prioridad sobre estado saludable'
Write-Host "$script:passed pruebas aprobadas."
