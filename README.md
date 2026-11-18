# OptimizadorPc

Diagnóstico local de hardware y software para Windows 10 y 11. OptimizadorPc 0.2.0 incorpora una ventana de escritorio para consultar los resultados y conserva el motor de diagnóstico de PC Claro.

## Abrir el programa

1. Descargá el código del repositorio como ZIP y extraé toda la carpeta.
2. Ejecutá **Iniciar.cmd** y elegí **Iniciar diagnóstico**. También podés usar **Ver ejemplo** para recorrer la ventana con datos ficticios.
3. Si necesitás más acceso a discos, eventos o seguridad, cerrá la ventana y usá **Iniciar_como_administrador.cmd**.

La aplicación usa Windows PowerShell 5.1 y Windows Forms, incluidos habitualmente en Windows. El análisis automático consulta el equipo local sin conexión. El permiso de ejecución que usa el iniciador se aplica al proceso de la aplicación.

## Qué podés hacer

| Pantalla | Funciones |
| --- | --- |
| Diagnóstico | Iniciar y cancelar la revisión. Buscar y filtrar por área o estado. Seleccionar un control para ver sus datos, alcance y próxima acción. |
| Historial | Volver a abrir diagnósticos completos de esta versión y los anteriores de PC Claro guardados por la misma cuenta de Windows. |
| Pruebas de Windows | Abrir el diagnóstico de RAM, SFC, DISM y el Administrador de dispositivos. Los resultados se consultan en cada herramienta. |

**Informe y pruebas guiadas** abre el HTML local para hacer pruebas de pantalla, audio, teclado y otros periféricos, o imprimir como PDF. **Guardar copia** permite elegir HTML o JSON del análisis automático. Para incluir las respuestas manuales en JSON, usá **Exportar JSON** dentro del informe. El HTML guardado contiene los datos recogidos durante el análisis.

El motor consulta procesador, memoria, discos, placa de video, batería, controladores, eventos, seguridad, programas y red. Algunos controles son de inventario y otros dependen de los datos que exponga Windows. Los sensores de CPU y GPU, las pruebas bajo carga y la inspección de fuente y placa madre siguen fuera del análisis automático. Un estado **Sin alertas** se refiere a la consulta indicada.

Los diagnósticos se guardan en `%LOCALAPPDATA%\OptimizadorPc\Informes`. El historial también lee `%LOCALAPPDATA%\PCClaro\Informes`. Estos informes pueden incluir el nombre del equipo, programas y mensajes con datos personales. Revisalos antes de compartirlos.

## Mantener el proyecto

- `OptimizadorPc.ps1` contiene la interfaz de escritorio y el seguimiento del proceso de diagnóstico.
- `app/Engine.ps1` consulta Windows. `app/Rules.ps1` contiene las reglas de detección.
- `app/ReportData.ps1` lee y filtra los datos de la ventana y el historial.
- `app/Report.html` es la plantilla del informe. `docs/Ejemplo_datos.json` es un ejemplo ficticio para la interfaz y las pruebas.

Las comprobaciones locales de PowerShell se ejecutan desde la raíz del proyecto en Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Rules.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\ReportData.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\OptimizadorPc.ps1 -SmokeTest
```

La última abre la ventana, carga el ejemplo y verifica la búsqueda y el detalle. La lectura de sensores requiere un equipo físico compatible. Para probar la lógica del HTML durante el desarrollo, instalá Node.js y jsdom y ejecutá `node tests/Report.Tests.cjs`. Esas dependencias se usan solo para desarrollo.
