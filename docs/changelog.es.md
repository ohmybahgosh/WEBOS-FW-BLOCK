# Registro de cambios

Los cambios de WEBOS-FW-BLOCK, en español.  Los títulos de sección quedan en inglés para que coincidan con el [CHANGELOG.md](../CHANGELOG.md) original, que tiene todas las versiones.

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
