# Registro de cambios

Los cambios de WEBOS-FW-BLOCK, en español.  Los títulos de sección quedan en inglés para que coincidan con el [CHANGELOG.md](../CHANGELOG.md) original, que tiene todas las versiones.

## [0.1.2] - 2026-11-20

### Added

- **Novedades en tu idioma.**  Después de una actualización, y cuando la app ofrece una, las notas de la versión se muestran en español o ruso si la app está en uno de ellos.  Las notas traducidas vienen firmadas con la versión y se comprueban igual antes de mostrarse.

### Fixed

- **Ya no aparece "no se pudo contactar con GitHub" al abrir la app.**  La primera comprobación podía perder la respuesta de GitHub, o hacerse antes de que la red de la TV estuviera lista.  Ahora la app conserva cada petición hasta que recibe respuesta, y vuelve a intentar en silencio unas cuantas veces una comprobación que no llegó a GitHub antes de avisar.
