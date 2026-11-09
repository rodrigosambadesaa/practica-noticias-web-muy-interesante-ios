# Integración de conectividad iOS

- Dependencia única de [ConnectivityAndInternetAccess-iOS-mobile](https://github.com/rodrigosambadesaa/ConnectivityAndInternetAccess-iOS-mobile), fijada al commit `1803edfc3becb2a5b011569ca73f974ad24736f3` mientras no exista un tag versionado publicado.
- Observación pasiva con el `NetworkObserver` de la librería, sin segundo `NWPathMonitor`. La ruta activa y el tipo de interfaz son indicios, no validación de Internet ni detección fiable de portales.
- Primero se intenta realmente el RSS por HTTPS. Solo tras errores de transporte se verifica HTTPS general; respuestas HTTP del propio feed (403, 404, 503) no activan diagnósticos redundantes.
- Diagnóstico manual con el pipeline DNS/HTTP de la librería y su modo estricto de portal cautivo, además de DNS de sistema, TCP, TLS, NTP y HTTPS comprobados por separado. DNS/TCP/TLS/NTP solos nunca se interpretan como acceso HTTPS.
- La comprobación general HTTPS exige 204 desde Google o la respuesta literal Success en el endpoint de prueba HTTPS de Apple; no se aceptan páginas cautivas o redirecciones arbitrarias como prueba positiva.
- La UI conserva el estado de red, la búsqueda, caché offline, paginación, WebView, actualización por gesto y el diálogo de diagnóstico.
- GitHub Actions prueba el paquete y compila la app en macOS; solo tras éxito publica automáticamente una **prerelease** con el ZIP de la `.app` de simulador y su SHA-256. No incluye IPA firmado.
