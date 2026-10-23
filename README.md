# Muy Interesante — iOS

Reimplementación nativa SwiftUI de [practica-noticias-web-muy-interesante](https://github.com/rodrigosambadesaa/practica-noticias-web-muy-interesante).

Feed: `https://www.muyinteresante.com/feed/`; archivo RSS con parámetro `paged` como en Android.

Incluye listado de noticias, imágenes, búsqueda, caché offline, paginación, detalle con WKWebView, navegador externo y compartir. Motor de diagnóstico de conectividad adaptado desde la clase Android: observación pasiva NWPathMonitor y comprobaciones DNS/TCP/TLS/NTP/HTTPS con límites de concurrencia, solamente manuales o después de una descarga fallida de forma ambigua. La seguridad de la red no se puede verificar al 100 % desde una app iOS.

Para compilar: en macOS instalar Xcode y XcodeGen, ejecutar `xcodegen generate` y abrir `NewsReaderIOS.xcodeproj`. GitHub Actions ejecuta tests del núcleo y compila para simulador. La firma para iPhone físico y App Store requiere credenciales y perfiles Apple Developer (no se incluyen).
