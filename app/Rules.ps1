# Rules deliberately distinguish missing data from healthy data.
function Get-WorstState($States) {
    foreach($s in @('critical','warn','unknown','ok','info','na')) {if($s -in $States){return $s}}
    return 'unknown'
}
function Get-FreeSpaceState([double]$FreePercent,[string]$Health) {
    if($Health -eq 'Unhealthy' -or $FreePercent -lt 5){return 'critical'}
    if($Health -eq 'Warning' -or $FreePercent -lt 10){return 'warn'}
    if($Health -ne 'Healthy'){return 'unknown'}
    return 'ok'
}
function Get-BatteryRatio($Design,$Full) {
    if($null -eq $Design -or $null -eq $Full -or [double]$Design -le 0 -or [double]$Full -le 0){return $null}
    $ratio=100*[double]$Full/[double]$Design
    if($ratio -gt 120){return $null}
    return $ratio
}
function Get-DiskAssessment($Disk,$Counter) {
    $states=@(); $reasons=@()
    switch([string]$Disk.HealthStatus){
        'Healthy' {$states+='ok'}
        'Warning' {$states+='warn'; $reasons+='Windows informa advertencia.'}
        'Unhealthy' {$states+='critical'; $reasons+='Windows informa estado no saludable.'}
        default {$states+='unknown'; $reasons+='Estado Windows desconocido.'}
    }
    foreach($operation in @($Disk.OperationalStatus)){
        if([string]$operation -in @('Failed','Error','Non-Recoverable Error','Lost Communication','No Contact')){$states+='critical';$reasons+='El proveedor informa una falla de operacion o comunicacion.'}
        elseif([string]$operation -in @('Degraded','Stressed','Predictive Failure')){$states+='warn';$reasons+='El proveedor informa operacion degradada.'}
    }
    if($null -eq $Counter){$states+='unknown'; $reasons+='Sin telemetria de confiabilidad.'}
    else {
        if($null -ne $Counter.Wear -and $Counter.Wear -ge 100){$states+='critical';$reasons+='Desgaste declarado igual o mayor al limite estimado.'}
        elseif($null -ne $Counter.Wear -and $Counter.Wear -ge 80){$states+='warn';$reasons+='Desgaste declarado de 80 % o mas.'}
        if(($null -ne $Counter.ReadErrorsUncorrected -and $Counter.ReadErrorsUncorrected -gt 0) -or ($null -ne $Counter.WriteErrorsUncorrected -and $Counter.WriteErrorsUncorrected -gt 0)){$states+='warn';$reasons+='Hay errores no corregidos acumulados; revisar contexto y respaldo.'}
        if($Counter.Temperature -gt 0 -and $Counter.TemperatureMax -gt 0 -and $Counter.Temperature -ge $Counter.TemperatureMax){$states+='warn';$reasons+='Temperatura al limite o por encima del limite declarado.'}
        if($null -eq $Counter.Wear -or $Counter.Temperature -le 0 -or $Counter.TemperatureMax -le 0 -or $null -eq $Counter.ReadErrorsUncorrected -or $null -eq $Counter.WriteErrorsUncorrected){$states+='unknown';$reasons+='Telemetria parcial; no todos los sensores estan disponibles.'}
    }
    [pscustomobject]@{status=(Get-WorstState $states); reasons=$reasons}
}
