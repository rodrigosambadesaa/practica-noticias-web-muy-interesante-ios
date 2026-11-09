import SwiftUI
import NewsCore
import ConnectivityAndInternetAccess

/// A dedicated screen is needed: a short alert hides most diagnostic output.
struct ConnectivityDiagnosticsView: View {
    @ObservedObject var viewModel: NewsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Observación pasiva de red") {
                    if let state = viewModel.networkSnapshot {
                        value("Ruta disponible", state.available ? "Sí" : "No")
                        value("Interfaz", state.interfaceName)
                        value("Conexión de coste elevado", state.expensive ? "Sí" : "No")
                        value("Modo de datos reducidos", state.constrained ? "Sí" : "No")
                        value("Instantánea", state.observedAt.formatted(date: .numeric, time: .standard))
                    } else {
                        Text("Esperando la primera actualización de NWPathMonitor…")
                    }
                    Text("NWPathMonitor solo describe el camino de red. No confirma Internet, VPN, ausencia de ataques ni portal cautivo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Pruebas activas a petición") {
                    if viewModel.isDiagnosing {
                        ProgressView("Ejecutando sondas…")
                    }
                    Button {
                        Task { await viewModel.runDiagnostics() }
                    } label: {
                        Label("Repetir diagnóstico completo", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isDiagnosing)
                    Text("Se accede a endpoints externos únicamente al solicitar este diagnóstico o tras un error de transporte RSS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let report = viewModel.diagnosticReport {
                    Section("Verificaciones de protocolos") {
                        value("HTTPS real", report.https ? "Respuesta de referencia válida" : "No confirmado")
                        value("DNS del sistema", state(report.dns))
                        value("TCP", state(report.tcp))
                        value("TLS", state(report.tls))
                        value("NTP", state(report.ntp))
                        value("Tiempo total", String(format: "%.2f s", report.elapsed))
                        Text("DNS, TCP, TLS y NTP son pruebas independientes; ninguna de ellas, por sí sola, demuestra que el feed RSS sea accesible.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    probeSection(
                        title: "Motor compartido: DNS y HTTP",
                        result: report.sharedProbe
                    )
                    probeSection(
                        title: "Comprobación estricta de portal",
                        result: report.portalProbe
                    )
                    Section("Interpretación") {
                        Text(report.https
                             ? "Se verificó HTTPS con un endpoint de referencia. El servidor RSS todavía puede fallar."
                             : "No se pudo verificar HTTPS general; una respuesta DNS positiva no cambia ese resultado.")
                        Text(report.portalProbe.isReachable
                             ? "El endpoint de referencia respondió como se esperaba. No es garantía absoluta de ausencia de interceptación."
                             : "La comprobación estricta fue negativa o no concluyente; no implica necesariamente que exista un portal cautivo.")
                    }
                }
            }
            .navigationTitle("Diagnóstico de red")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func state(_ ok: Bool) -> String { ok ? "Respuesta positiva" : "No confirmado" }

    private func value(_ name: String, _ status: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
            Spacer(minLength: 8)
            Text(status)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func probeSection(title: String, result: ReachabilityResult) -> some View {
        Section(title) {
            value("Resultado", result.isReachable ? "Sonda positiva" : "Sin confirmación")
            value("Etapa", result.stage.description)
            value("Duración", "\(result.durationMs) ms")
            if let host = result.reachedHost {
                Text("Endpoint: \(host)")
                    .font(.caption)
                    .textSelection(.enabled)
            }
            if let error = result.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.attemptedHosts.isEmpty {
                DisclosureGroup("Sondas intentadas (\(result.attemptedHosts.count))") {
                    ForEach(result.attemptedHosts, id: \.self) { host in
                        Text(host)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
