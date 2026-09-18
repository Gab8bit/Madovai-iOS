import SwiftUI

struct InfoSheet: View {
    var body: some View {
        NavigationView {
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
                        text: "Atac/Roma TPL: un'unica chiamata restituisce sempre tutta la flotta attiva. Cotral non ha un endpoint simile — i suoi veicoli compaiono solo interrogando le paline attualmente visibili sulla mappa, quindi la copertura è parziale per costruzione, non un difetto."
                    )
                    infoRow(
                        icon: "hand.tap",
                        title: "Tocca un veicolo",
                        text: "Filtra la mappa al solo percorso e ai mezzi di quella linea, e apre l'orario. Per Atac/Roma TPL è l'orario completo della corsa; per Cotral solo le info disponibili (nessun orario completo esposto dall'endpoint usato). Il pulsante col cerchio e la X in basso riporta alla vista normale."
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dati trasporto Roma")
                            .font(.subheadline.weight(.semibold))
                        Text("Roma Servizi per la Mobilità — romamobilita.it, licenza CC-BY 3.0 Italia.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dati Cotral")
                            .font(.subheadline.weight(.semibold))
                        Text("Endpoint e feed GTFS pubblici di Cotral S.p.A.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
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
