# Verificación de paridad con ConnectivityAndInternetAccess-iOS-mobile

La dependencia Swift Package Manager incorpora **el paquete completo**, no una copia parcial de su código, fijado al commit corregido `b31a010cc2bcafde10e23cbf774c837ef4a34774`. La app solo utiliza los módulos adecuados al ciclo de vida SwiftUI.

| Capacidad del paquete | Integración en el lector |
| --- | --- |
| `NetworkState`, `NWPathMonitor`, observador y token | Conexión pasiva compartida con el lector; coste, modo reducido, interfaz y fecha |
| `ConnectivityBuilder`, configuración por hosts, resolvers, timeout | Motor diagnóstico manual completo y configurable |
| DNS de sistema `getaddrinfo` | Primera etapa del motor compartido |
| DNS UDP directo (Cloudflare, Google, Quad9, OpenDNS) | Segunda etapa si la primera no tiene éxito |
| HTTP/HTTPS probes | Tercera etapa del motor compartido y verificación HTTPS independiente |
| `strictCaptivePortalBuilder` | Comprobación estricta separada y a petición |
| `ReachabilityResult` completo | Estado, etapa, endpoint, duración, sondas intentadas y mensaje de error |
| Swift Concurrency (async/await) | Coordinación no bloqueante de diagnósticos |
| Combine, AsyncStream, callbacks y SwiftUI | API disponible en el paquete; el lector usa callbacks tokenizados por su ciclo de vida |

**Límites intencionados:** no se hacen sondas por imagen, noticia ni apertura de WebView. Un DNS positivo no garantiza HTTPS y un `NWPath` satisfecho no significa Internet validado ni ausencia de portal. No se afirma detección fiable de VPN/MitM/Evil Twin.

**CI:** `swift test --parallel` valida NewsCore, después verifica el SHA de la dependencia, ejecuta los tests deterministas de la librería upstream y compila la app iOS Simulator con Xcode. Solo cuando todo pasa se genera una nueva prerelease de simulador (no un IPA firmado).