# Cobertura necesaria para un diagnóstico más completo

La versión 0.1 reúne evidencia inicial y permite reconocer lo que quedó pendiente. Para acercarse al objetivo de diagnosticar cada parte hace falta incorporar módulos verificables y probarlos en distintos equipos reales.

| Prioridad | Módulo | Qué debe demostrar antes de considerarlo completo |
|---|---|---|
| 1 | Validación real en Windows | Ejecutar la aplicación con y sin elevación en Windows 10/11, PC de escritorio y notebook. Confirmar datos contra herramientas del fabricante. |
| 2 | Sensores | Incorporar un proveedor auditado y con licencia compatible para CPU/GPU, RPM, frecuencias y throttling. Mostrar el origen del sensor, datos ausentes y límites específicos del componente. |
| 3 | SMART y NVMe | Obtener atributos completos, advertencias, errores y autopruebas del fabricante, contemplando SATA, NVMe, USB y RAID. Diferenciar dato histórico, tendencia y falla actual. |
| 4 | Pruebas de estabilidad | CPU, memoria y GPU por separado, con tiempo, cancelación, monitoreo térmico y criterios de corte. Nunca iniciar carga intensa sin una acción explícita del usuario. |
| 5 | RAM con reinicio | Detectar y vincular el resultado de Windows con la ejecución correspondiente. Ofrecer un flujo de prueba arrancable para una evaluación más extensa. |
| 6 | Integridad de Windows | Capturar SFC y DISM, sus códigos de salida y resultados interpretables en distintos idiomas. Separar claramente diagnóstico de reparación. |
| 7 | Conectividad | Gateway, DNS, latencia, pérdida de paquetes y transferencia LAN. Pruebas externas solo al elegirlas; distinguir falta de Internet de una política que bloquea ICMP. |
| 8 | Historial | Comparar ejecuciones por identificador de componente, conservar respuestas manuales e importar JSON validados. Alertar ante cambios o degradación con evidencia. |
| 9 | Software y arranque | Servicios, tareas programadas, impacto de inicio, minidumps y conflictos. Evitar conclusiones basadas únicamente en antigüedad o consumo puntual. |
| 10 | Distribución | Empaquetado firmado, actualizaciones controladas y una interfaz de escritorio ampliable. Probar instalación, retiro y ejecución con cuentas restringidas. |

Fuente, conectores, placa madre, condensadores y daños físicos conservan una parte de diagnóstico técnico presencial. Ningún módulo debe informar «correcto» cuando solo reconoce que el dispositivo existe.

Cada resultado futuro debe conservar: componente, prueba, fecha, duración, evidencia, alcance, estado y siguiente paso. La reparación requiere un flujo separado que indique el cambio concreto y permita revisión.
