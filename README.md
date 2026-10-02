# Umbral · Ecos de la Ceniza

## Versión 0.2.0 · Firebase y cooperativo

APK actualizado: `releases/umbral-0.2.0+2.apk`. Instalar esta versión en los dos móviles.

- Abre **Firebase · Nube y cooperativo** desde el inicio.
- Puedes jugar online como invitado o crear una cuenta con correo y contraseña. Usa cuentas distintas para los dos jugadores.
- Para recuperar progreso en otro dispositivo, crea una cuenta y pulsa **Subir partida**. En el otro móvil entra con esa cuenta y pulsa **Restaurar partida**. Tras subir/restaurar se activa la subida automática cada minuto de juego. El guardado local continúa cada 8 segundos. Si otra instalación avanzó, se pide resolver el conflicto desde este panel.
- **Crear sala cooperativa** muestra un código de seis caracteres. El compañero lo escribe en **Unirse a la sala**. También aparece en Pausa.
- Se utiliza el mundo del anfitrión; el invitado conserva su clase, nivel y equipo, pero adopta el estado de zonas/sellos del anfitrión. Ambos reciben oro y experiencia; el botín del suelo lo recoge quien llegue primero.
- Los paneles pausan el grupo. El anfitrión dirige los viajes; ambos cambian de zona juntos. Cada jugador guarda localmente su personaje y el mundo compartido.
- La simulación corre en el anfitrión; Firestore transmite entradas cada 300 ms y estado cada 700 ms. Ante pérdida de conexión se pausa; se recupera mientras ambos procesos sigan abiertos. Cerrar la app requiere crear otra sala. No hay migración de anfitrión ni recuperación de sala tras reiniciar el proceso. Las salas caducan a las dos horas.

Firebase: proyecto `nova-5d1c5`; app Android propia y colecciones `umbralSavesV1`, `umbralPresenceV1`, `umbralRoomsV1`. Reglas desplegadas con comprobación de revisión remota; otros bloques conservados. Esta demo confía en el anfitrión y en el progreso importado; no es un servidor competitivo antitrampas. La cuota gratuita se comparte con los otros proyectos.

Validación 0.2.0: **34 pruebas Flutter**, análisis limpio, **48 comprobaciones de reglas**, prueba real con dos clientes cooperativos y recuperación de la cuenta/partida en un tercero. Capturas `releases/umbral-020-*.png`. Pendiente prueba física en dos móviles.

Herramientas: `node tools/firebase-admin.cjs prepare`, comprobar reglas, `deploy` y `verify`. Descargar siempre las reglas vigentes antes de modificarlas. Prueba real: compilar web, ejecutar `node tools/serve.cjs` y `node tools/coop-live.cjs` (Chrome); crea usuarios temporales y limpia los datos de la prueba.

## Demo original 0.1.0 (histórico)

Demo individual de acción y rol en Flutter para Android, con vista cenital, arte vectorial original y guardado local. Nuevo proyecto basado en la configuración técnica documentada de Nova Command.

## Jugar

APK: `releases/umbral-0.1.0+1.apk` (**46.878.275 bytes**, Android 7 o superior). Instálalo en Android y elige **Guardián**, **Arcanista** o **Exploradora**. Funciona sin conexión, en vertical y horizontal.

1. Sal del Refugio por el este; pulsa **Entrar** cerca del arco de salida.
2. Explora el Bosque y activa su portal acercándote. El mapa permite viajar entre portales descubiertos cuando estás junto a uno.
3. Mantén **ATACAR**, utiliza tu habilidad ofensiva y **Amparo**. Esquiva los círculos rojos de los guardianes.
4. Abre cofres y recoge el botín brillante con el botón de interacción. Equípalo desde la mochila; muestra las diferencias de atributos.
5. Recupera el sello del Bosque para abrir la Cripta. El segundo sello abre Corazón de ceniza, donde espera el Rey.

En el Refugio recuperas vida, vendes objetos y compras pociones desde la mochila. Morir devuelve al Refugio conservando equipo, enemigos derrotados y progreso; cuesta hasta 15 monedas y repone al menos tres pociones.

### Controles

| Acción | Móvil | Teclado |
|---|---|---|
| Movimiento | Palanca o tocar el terreno | WASD / flechas |
| Atacar | Mantener ATACAR o tocar enemigo | Espacio |
| Habilidad ofensiva | Torbellino / Nova / Lluvia | Q |
| Protección y curación | Amparo | E |
| Poción | Botón de poción | H |
| Cofre, botín, salida | Botón contextual | F |
| Mochila / mapa / pausa | Botones superiores | I o Tab / M / Esc |

Los paneles pausan la simulación. Guardado cada 8 segundos, al abrir/cerrar paneles y al pasar a segundo plano. Una partida por instalación; **Nueva aventura** pide confirmar antes de sustituirla. Existe una copia del guardado anterior para recuperación.

## Contenido

- Refugio seguro y tres territorios con niebla de exploración, colisiones y navegación alrededor de obstáculos.
- Tres clases: guardián cuerpo a cuerpo, arcanista de área y exploradora a distancia.
- 39 monstruos comunes y tres jefes; ataques anunciados, ralentización, protección, experiencia y niveles.
- Seis cofres, botín generado con cuatro rarezas, tres ranuras de equipo y mochila de 24 objetos.
- Tres sellos de progresión, jefe final, pantalla de victoria y exploración posterior.
- Minimap en horizontal amplio y atlas completo en ambas orientaciones.

## Desarrollo

Flutter `C:/Users/anton/fvm/versions/3.47.4/bin/flutter.bat`, Dart 3.13.3. Android: `dev.umbral.umbral_rpg`. Firma debug de demo.

```powershell
cd D:\proyectos\umbral_rpg\mobile
& 'C:\Users\anton\fvm\versions\3.47.4\bin\flutter.bat' pub get
& 'C:\Users\anton\fvm\versions\3.47.4\bin\flutter.bat' analyze
& 'C:\Users\anton\fvm\versions\3.47.4\bin\flutter.bat' test
cd ..
.\build-apk.ps1
```

El script configura Java 17, caché Gradle y temporales, compila release y copia el APK a `releases`. No simultanear la compilación Android con las pruebas Flutter.

Para jugar en navegador: `flutter run -d web-server --web-port 8174`. Para la comprobación con Edge sin interfaz: `npm --prefix tools install` y `npm --prefix tools run smoke` con ese servidor arrancado. El recorrido real de navegador genera capturas en `releases`.

### Estructura

- `mobile/lib/game.dart`: simulación, navegación, combate, progresión y serialización.
- `mobile/lib/world.dart`: clases, zonas, monstruos y objetos.
- `mobile/lib/world_painter.dart`: escenario, personajes, efectos y minimapa.
- `mobile/lib/app.dart`: menú, controles adaptativos, atlas y equipo.
- `mobile/lib/save_store.dart`: persistencia serializada y recuperación.
- `mobile/test/`: pruebas de mecánicas, campaña con las tres clases e interfaz en tres tamaños.

El arte se dibuja con Flutter Canvas. No requiere descargas de recursos. Esta primera demo es 2D y offline; los monstruos y cofres no reaparecen tras derrotarlos/abrirlos. Una nueva aventura reinicia el mundo. La muerte conserva el daño infligido a los monstruos. No incluye audio ni multijugador.

Validación: **21 pruebas Flutter aprobadas**, análisis sin incidencias, recorrido real de navegador aprobado y APK release con paquete/firma verificados. Capturas en `releases`. Detalles y SHA256: `PROJECT_CONTEXT.json`. Pendiente prueba en un teléfono Android físico.
