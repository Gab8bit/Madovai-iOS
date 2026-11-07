import Foundation

/// One Cotral run at a pole (`cotral-transits` → `transits[]`). Field names
/// are Cotral's own, passed through unchanged by the backend. Decoding is
/// lenient (missing strings become "") because PIV.do leaves fields out
/// freely depending on the run.
struct Transit: Codable, Identifiable, Hashable {
    var idCorsa: String
    var percorso: String
    var partenzaCorsa: String
    var orarioPartenzaCorsa: String
    var arrivoCorsa: String
    var orarioArrivoCorsa: String
    /// "Y" = cancelled. Cotral has also been seen returning "S" on some
    /// runs; its meaning isn't confirmed, so (like the backend and the web
    /// app) only "Y" counts as cancelled.
    var soppressa: String
    var numeroOrdine: String
    /// Scheduled time at *this* pole, "HH:MM" Rome.
    var tempoTransito: String
    /// Raw seconds (negative = early). Only meaningful when `trackingStatus
    /// == .realtime`: Cotral fills it with a fictitious value on runs that
    /// aren't monitored or whose vehicle isn't transmitting.
    var ritardoSeconds: Int
    var passato: String
    /// Usable to follow the vehicle only when `monitorata == "1"`.
    var vehicleCode: String?
    var vehicleAlive: Bool
    var testoFermata: String
    var instradamento: String
    var banchina: String
    /// "1" when this run supports real-time tracking.
    var monitorata: String
    var accessibile: String

    var id: String {
        idCorsa.isEmpty ? "\(partenzaCorsa)-\(arrivoCorsa)-\(orarioPartenzaCorsa)-\(tempoTransito)" : idCorsa
    }

    init(
        idCorsa: String = "", percorso: String = "", partenzaCorsa: String = "", orarioPartenzaCorsa: String = "",
        arrivoCorsa: String = "", orarioArrivoCorsa: String = "", soppressa: String = "N", numeroOrdine: String = "",
        tempoTransito: String = "", ritardoSeconds: Int = 0, passato: String = "", vehicleCode: String? = nil,
        vehicleAlive: Bool = false, testoFermata: String = "", instradamento: String = "", banchina: String = "",
        monitorata: String = "0", accessibile: String = ""
    ) {
        self.idCorsa = idCorsa
        self.percorso = percorso
        self.partenzaCorsa = partenzaCorsa
        self.orarioPartenzaCorsa = orarioPartenzaCorsa
        self.arrivoCorsa = arrivoCorsa
        self.orarioArrivoCorsa = orarioArrivoCorsa
        self.soppressa = soppressa
        self.numeroOrdine = numeroOrdine
        self.tempoTransito = tempoTransito
        self.ritardoSeconds = ritardoSeconds
        self.passato = passato
        self.vehicleCode = vehicleCode
        self.vehicleAlive = vehicleAlive
        self.testoFermata = testoFermata
        self.instradamento = instradamento
        self.banchina = banchina
        self.monitorata = monitorata
        self.accessibile = accessibile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String {
            if let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
            if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return String(value) }
            return ""
        }
        idCorsa = string(.idCorsa)
        percorso = string(.percorso)
        partenzaCorsa = string(.partenzaCorsa)
        orarioPartenzaCorsa = string(.orarioPartenzaCorsa)
        arrivoCorsa = string(.arrivoCorsa)
        orarioArrivoCorsa = string(.orarioArrivoCorsa)
        soppressa = string(.soppressa)
        numeroOrdine = string(.numeroOrdine)
        tempoTransito = string(.tempoTransito)
        ritardoSeconds = (try? c.decodeIfPresent(Int.self, forKey: .ritardoSeconds)) ?? 0
        passato = string(.passato)
        let code = try? c.decodeIfPresent(String.self, forKey: .vehicleCode)
        vehicleCode = (code?.isEmpty ?? true) ? nil : code
        vehicleAlive = (try? c.decodeIfPresent(Bool.self, forKey: .vehicleAlive)) ?? false
        testoFermata = string(.testoFermata)
        instradamento = string(.instradamento)
        banchina = string(.banchina)
        monitorata = string(.monitorata)
        accessibile = string(.accessibile)
    }
}

enum TransitTrackingStatus {
    /// Monitored run whose vehicle is transmitting right now.
    case realtime
    /// Monitored run, but the vehicle isn't transmitting.
    case monitoredOffline
    /// Schedule-only run.
    case scheduled
}

extension Transit {
    /// Same rule as the backend's `isDelayReliable` / the web's `trackingStatus`.
    var trackingStatus: TransitTrackingStatus {
        guard monitorata == "1" else { return .scheduled }
        return vehicleAlive ? .realtime : .monitoredOffline
    }

    var isDelayReliable: Bool { trackingStatus == .realtime }

    var isCancelled: Bool {
        soppressa.trimmingCharacters(in: .whitespaces).uppercased() == "Y"
    }

    var displayTime: String {
        !tempoTransito.isEmpty ? tempoTransito : orarioPartenzaCorsa
    }

    /// `displayTime` corrected for a reliable delay of at least a minute —
    /// what a rider cares about is when the bus will really be there.
    var adjustedDisplayTime: String {
        guard isDelayReliable, abs(ritardoSeconds) >= 60 else { return displayTime }
        return RomeTime.adding(seconds: ritardoSeconds, to: displayTime)
    }

    /// "segui bus in tempo reale" is offered for this run.
    var canTrackVehicle: Bool {
        monitorata == "1" && !(vehicleCode ?? "").isEmpty
    }

    /// Minutes until the delay-aware arrival. Backs the "tra N min" label,
    /// the sort order and the "already passed" filter alike, so a late run
    /// whose original time has ticked by doesn't look gone.
    func minutesFromNow(now: Date = Date()) -> Int? {
        RomeTime.minutesFromNow(adjustedDisplayTime, now: now)
    }

    /// Destination without Cotral's internal codes ("FROSINONE | Piazza
    /// Pertini (f3486)" → "FROSINONE").
    var destinationLabel: String {
        arrivoCorsa.isEmpty ? "Destinazione N/D" : StopText.locality(arrivoCorsa)
    }

    /// "FR766D · FROSINONE"; for a train `percorso` is an internal ASTRAL
    /// route code ("RL_PSP-CC"), meaningless to a rider, so it's dropped.
    var lineAndDestinationLabel: String {
        guard CotralTrainRoute(rawValue: percorso) == nil, !percorso.isEmpty else { return destinationLabel }
        return "\(percorso) · \(destinationLabel)"
    }
}

extension Array where Element == Transit {
    /// Soonest first, dropping runs whose real arrival passed more than
    /// ~2 minutes ago (Cotral's feed can get stuck reporting one forever) —
    /// same filter as the web app's PoleSheet.
    func upcomingSorted(now: Date = Date()) -> [Transit] {
        let withMinutes = map { ($0, $0.minutesFromNow(now: now)) }
        return withMinutes
            .filter { ($0.1 ?? 0) >= -2 }
            .sorted { ($0.1 ?? .max) < ($1.1 ?? .max) }
            .map(\.0)
    }
}

enum StopText {
    /// Cotral appends codes to names ("ROMA | Termini FS (f14638)"): keep the
    /// part before the first `|`, `!` or `(` — same as the web's `extractLocality`.
    static func locality(_ name: String) -> String {
        let cut = name.split(whereSeparator: { $0 == "|" || $0 == "!" || $0 == "(" }).first.map(String.init) ?? name
        let trimmed = cut.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name.trimmingCharacters(in: .whitespaces) : trimmed
    }
}
