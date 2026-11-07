import SwiftUI

struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Come funziona") {
                    infoRow(
                        icon: "map",
                        title: "Due fonti, una mappa",
                        text: "Cotral copre l'extraurbano del Lazio, Atac e Roma TPL coprono Roma urbana (bus, tram, metro). Sono fonti indipendenti, mostrate insieme."
                    )
                    infoRow(
                        icon: "location.viewfinder",
                        title: "Copertura dei veicoli in tempo reale",
                        text: "Puoi vedere sulla mappa la posizione in tempo reale dei veicoli Atac e Cotral. Alcuni mezzi non hanno la geolocalizzazione attiva, quindi potrebbero non essere mostrati ma comunque calcolati nelle tabelle di marcia."
                    )
                    infoRow(
                        icon: "hand.tap",
                        title: "Tocca un veicolo",
                        text: "Filtra la mappa al solo percorso e ai mezzi di quella linea, e apre l'orario. Per Atac/Roma TPL è l'orario completo della corsa; per Cotral solo le info disponibili. Il pulsante \"Reset\" in alto riporta alla vista normale."
                    )
                    infoRow(
                        icon: "plus.magnifyingglass",
                        title: "Fermate e linee",
                        text: "Fermate, paline e percorsi compaiono quando avvicini la mappa a livello di quartiere; il pulsante con il percorso a destra li mostra o nasconde."
                    )
                }

                Section("Simboli sulla mappa") {
                    legendRow(color: .blue, symbol: "bus", label: "Palina Cotral (bus)")
                    legendRow(color: .indigo, symbol: "tram.fill", label: "Stazione Cotral (treno/Roma Lido ecc.)")
                    legendRow(color: .yellow, symbol: "star.fill", label: "Palina preferita")
                    legendRow(color: .orange, symbol: nil, label: "Fermata Atac / Roma TPL")
                    legendRow(color: .teal, symbol: "bus", label: "Bus Atac in movimento")
                    legendRow(color: .red, symbol: "m.circle.fill", label: "Metro Atac in movimento")
                    legendRow(color: .green, symbol: "bus", label: "Mezzo Roma TPL in movimento")
                    legendRow(color: .orange, symbol: "bus", label: "Veicolo Cotral in movimento")
                }

                Section("Crediti") {
                    credit("Dati trasporto Roma", "Roma Servizi per la Mobilità — romamobilita.it, licenza CC-BY 3.0 Italia.")
                    credit("Dati Cotral", "Endpoint e feed GTFS pubblici di Cotral S.p.A. Orari e ritardi dei treni: ASTRAL S.p.A.")
                    credit("Server", "I dati arrivano dal server Madovai, che li raccoglie dalle fonti ufficiali e li aggiorna ogni pochi secondi.")
                    credit("Versione", "Madovai \(appVersion)")
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
        }
    }

    private func credit(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func infoRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func legendRow(color: Color, symbol: String?, label: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color).frame(width: 22, height: 22)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Text(label).font(.subheadline)
        }
    }
}
