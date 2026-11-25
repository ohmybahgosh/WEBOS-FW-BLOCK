# Registro de cambios

Los cambios de WEBOS-FW-BLOCK, en español.  Los títulos de sección quedan en inglés para que coincidan con el [CHANGELOG.md](../CHANGELOG.md) original, que tiene todas las versiones.

## [1.3.0] - 2026-11-25

### Added

- **Avisa cuando el actualizador de LG pasó al encender.**  El actualizador de LG busca firmware en el primer medio minuto tras encender la TV, diga lo que digan sus ajustes.  Si el inicio del Homebrew Channel (que ejecuta FW Block) llega después, esa búsqueda puede llegar a LG antes de que haya bloqueos.  Cuando la respuesta ofrece un firmware, el actualizador muestra un aviso de actualización "webOS Re:New".  No se descarga nada, porque los bloqueos ya están puestos antes de que empiece la descarga.  FW Block ahora lo detecta en el propio registro del actualizador en cada encendido.  Lo anota en Actividad, lo muestra en rojo arriba, envía un aviso en la TV y borra lo que el actualizador encontró.  No aceptes el aviso.

### Fixed

- **El README decía que los ajustes de actualización de webOS detienen la búsqueda desde que la TV se enciende.**  No detienen la búsqueda que el actualizador hace al encender.  Ahora lo dice, y tiene una sección nueva sobre bloquear los servidores de actualización de LG en el router, el único bloqueo que está puesto antes que la TV.

## [1.2.2] - 2026-11-24

### Fixed

- **Funciona con el Homebrew Channel 0.8.0.**  Su Block system updates ahora también ajusta la búsqueda de actualizaciones de webOS, y al desactivarlo la vuelve a activar.  Con FW Block activado, su comprobación de cada 30 segundos ahora nota el cambio del interruptor del Homebrew Channel y vuelve a desactivar la búsqueda en segundos, en vez de en la siguiente comprobación de cada 10 minutos.  Todo lo demás ya era compatible: FW Block reconoce que el bloqueo de 0.8.0 mantiene la búsqueda desactivada, y las llamadas al Homebrew Channel que usa (ejecutar, instalar, reiniciar) no cambian.

## [1.2.1] - 2026-11-23

### Fixed

- **La asistencia remota de LG (y a veces la dirección de respaldo) podía aparecer "no bloqueada" un momento al abrir la app.**  Las reglas del cortafuegos se comprobaban sin esperar el bloqueo de iptables, así que una comprobación hecha mientras otra cosa usaba iptables (la vigilancia en segundo plano contando paquetes, u otra petición de la propia app) fallaba enseguida y tomaba como ausente una regla que sí estaba.  Ahora FW Block espera hasta 5 segundos ese bloqueo.  Además nunca toma como ausente una regla que no pudo leer, así que la comprobación en segundo plano no "vuelve a poner" lo que nunca faltó.

### Changed

- **"comprobando…" en vez de suponer.**  Si las reglas del cortafuegos siguen sin poder leerse, la dirección de respaldo y la asistencia remota muestran "comprobando…" en ámbar, y la app vuelve a preguntar unos segundos después.

## [1.2.0] - 2026-11-23

### Added

- **Una versión nueva se ve enseguida.**  Como en el instalador de Entware: cuando sale una, aparece una fila "Actualizar a la v…" arriba en la pestaña Más, la pestaña Más lleva un punto y, la primera vez que se encuentra, la app se abre en ella, salvo que ya hayas empezado a usar el mando.

## [1.1.1] - 2026-11-23

### Fixed

- **La asistencia remota podía aparecer abierta uno o dos minutos después de encender el televisor, con Glasshouse instalado.**  FW Block y el bloqueador de anuncios de Glasshouse arrancan los dos en segundo plano.  Si Glasshouse ponía su tabla sobre /etc/hosts justo después de que FW Block añadiera sus líneas, estas quedaban ocultas hasta la siguiente reescritura de Glasshouse, y mientras tanto solo las reglas del cortafuegos bloqueaban la asistencia remota.  Ahora la comprobación de cada 30 segundos detecta las líneas que faltan y las vuelve a poner enseguida (bajo el encabezado de Glasshouse), sin esperar a la comprobación de cada 10 minutos.

## [1.1.0] - 2026-11-20

### Added

- **Probar el bloqueo.**  Un botón nuevo (pestaña Actividad, y `sh fw-block.sh test`) prueba la vía de actualización de LG como lo haría el actualizador: los dos ajustes de actualización, la búsqueda de cada servidor de actualizaciones y de asistencia remota, y una conexión a las direcciones sin nombre, sin enviar nada.  Antes comprueba que hay red, para no confundir la falta de red con un bloqueo.
- **Limpiar el firmware descargado y los indicadores de LG.**  El firmware que LG descargó antes del bloqueo, y los indicadores de LG que pueden forzar una actualización, activar opciones de depuración o cambiar el servidor de actualizaciones, se listan y se borran cuando lo pides.  Nunca durante una actualización, y solo después de una copia de seguridad.
- **Pausa para una actualización planeada.**  Para una actualización que quieres, el bloqueo se quita durante 1, 3 o 24 horas y vuelve por sí solo al terminar el tiempo o en el próximo encendido del televisor.
- **Avisos en el televisor.**  Un aviso corto, en el idioma de la app, cuando FW Block vuelve a poner un bloqueo que algo quitó, o cuando termina su pausa.  Como mucho uno al día por lo mismo, y se pueden desactivar.

### Fixed

- **Funciona con el bloqueador de anuncios de Glasshouse.**  Glasshouse mantiene su propia tabla sobre /etc/hosts y quita las líneas de otras herramientas salvo que estén bajo su encabezado "Kept from /etc/hosts".  Ahora FW Block añade ese encabezado antes de sus líneas, así que ya no se quitan y se vuelven a poner cada 10 minutos.

## [1.0.0] - 2026-11-20

### Changed

- **1.0.0: el bloqueo está completo.**  Cada vía de actualización encontrada (la comprobación del propio actualizador, LG Remote Support, las apps del móvil y las descargas que empiezan igualmente) tiene su bloqueo, funciona junto al Homebrew Channel y LG-USB-2-ETH0, hace una copia de seguridad antes de cambiar nada y solo se actualiza desde versiones firmadas.  Por ahora se ha probado en una sola TV, así que los informes de otras TV siguen siendo bienvenidos.

### Fixed

- **Textos en español y ruso.**  Se reformularon algunos textos en ruso.

### Security

- **Una actualización se comprueba dos veces antes de instalarse.**  Ahora el script también se asegura de que la descarga es el IPK de esta misma app, de sus propias versiones en GitHub y de la versión exacta ofrecida, antes de dársela al Homebrew Channel.  Hasta ahora solo lo comprobaba la búsqueda de actualizaciones.

## [0.1.2] - 2026-11-20

### Added

- **Novedades en tu idioma.**  Después de una actualización, y cuando la app ofrece una, las notas de la versión se muestran en español o ruso si la app está en uno de ellos.  Las notas traducidas vienen firmadas con la versión y se comprueban igual antes de mostrarse.

### Fixed

- **Ya no aparece "no se pudo contactar con GitHub" al abrir la app.**  La primera comprobación podía perder la respuesta de GitHub, o hacerse antes de que la red de la TV estuviera lista.  Ahora la app conserva cada petición hasta que recibe respuesta, y vuelve a intentar en silencio unas cuantas veces una comprobación que no llegó a GitHub antes de avisar.
