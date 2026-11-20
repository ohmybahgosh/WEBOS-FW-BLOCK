# Registro de cambios

Los cambios de WEBOS-FW-BLOCK, en español.  Los títulos de sección quedan en inglés para que coincidan con el [CHANGELOG.md](../CHANGELOG.md) original, que tiene todas las versiones.

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
