import Foundation

/// A scheduled/real-time transit at a pole, as returned inside
/// GET /transits/{poleCode}.
struct Transit: Codable, Identifiable, Hashable {
    var idCorsa: String
    var percorso: String
    var partenzaCorsa: String
    var orarioPartenzaCorsa: String
    var arrivoCorsa: String
    var orarioArrivoCorsa: String
    var soppressa: String
    var numeroOrdine: String
    var tempoTransito: String
    /// Raw seconds (negative = ahead of schedule), kept as an Int rather
    /// than the "HH:MM" string Cotral's XML implies — round-tripping a
    /// small value like -15s through "HH:MM" formatting produced the
    /// literal string "-00:00" (sign kept, but rounds to zero minutes),
    /// which a naive `!= "00:00"` check doesn't catch, showing a nonsensical
    /// "anticipo 00:00". Keeping raw seconds lets the display layer apply
    /// one clear rule: a difference under 60s isn't worth surfacing as a
    /// delay/advance at all. Only meaningful when `trackingStatus ==
    /// .realtime` — Cotral always fills this with a fictitious 0 on
    /// non-monitored or offline runs, so it must never be shown as a real
    /// delay outside that case.
    var ritardoSeconds: Int
    var passato: String
    var automezzo: Vehicle
    var testoFermata: String
    /// Not a usable timestamp (confirmed against the server's own XML source) —
    /// never use this to compute "updated N seconds ago".
    var dataModifica: String
    var instradamento: String
    var banchina: String
    /// "1" when this run supports real-time tracking, else "0".
    var monitorata: String
    var accessibile: String

    var id: String {
        idCorsa.isEmpty ? "\(partenzaCorsa)-\(arrivoCorsa)-\(orarioPartenzaCorsa)" : idCorsa
    }
}

enum TransitTrackingStatus {
    /// `monitorata == "1"` and the assigned vehicle is currently transmitting.
    case realtime
    /// `monitorata == "1"` but the assigned vehicle isn't transmitting right now.
    case monitoredOffline
    /// `monitorata != "1"` — schedule-only, no live tracking possible for this run.
    case scheduled
}

extension Transit {
    /// Mirrors the backend's own `getTransitTrackingStatus` (packages/shared) so the
    /// client and server never disagree about what counts as "live".
    var trackingStatus: TransitTrackingStatus {
        guard monitorata == "1" else { return .scheduled }
        return (automezzo.isAlive ?? false) ? .realtime : .monitoredOffline
    }

    /// `ritardo` is only a real punctuality reading in the realtime state.
    var isDelayReliable: Bool { trackingStatus == .realtime }

    var displayTime: String {
        !tempoTransito.isEmpty ? tempoTransito : orarioPartenzaCorsa
    }

    /// Whether "segui bus in tempo reale" should be offered for this run.
    var canTrackVehicle: Bool {
        monitorata == "1" && !(automezzo.codice ?? "").isEmpty
    }

    /// Minutes from now until `displayTime`, handling the schedule's own
    /// midnight-rollover convention (Cotral times can read e.g. "25:10" for a
    /// trip after midnight). Nil if the time can't be parsed.
    var minutesFromNow: Int? {
        Self.minutesFromNow(displayTime)
    }

    static func minutesFromNow(_ time: String, now: Date = Date()) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let targetMinutes = h * 60 + m

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        guard let nowHour = comps.hour, let nowMinute = comps.minute else { return nil }
        let nowMinutes = nowHour * 60 + nowMinute

        var diff = targetMinutes - nowMinutes
        // Times can be expressed past 24:00 for post-midnight trips; a single
        // day wrap is enough to bring a "now-ish" reading back near zero.
        if diff > 12 * 60 { diff -= 24 * 60 }
        if diff < -12 * 60 { diff += 24 * 60 }
        return diff
    }
}
