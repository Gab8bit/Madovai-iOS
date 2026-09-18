/// Wraps a stop from either data source so the search bar can show and
/// merge results from both — previously search only ever queried Cotral,
/// which is why searching an Atac-only stop like "Poggio di Acilia" found
/// nothing.
enum SearchStopResult: Identifiable, Hashable {
    case cotral(GtfsStop)
    case atac(AtacStop)

    var id: String {
        switch self {
        case .cotral(let stop): return "cotral-\(stop.stopId)"
        case .atac(let stop): return "atac-\(stop.stopId)"
        }
    }

    var name: String {
        switch self {
        case .cotral(let stop): return stop.stopName
        case .atac(let stop): return stop.stopName
        }
    }

    var subtitle: String {
        switch self {
        case .cotral(let stop): return stop.isRail ? "Cotral · treno" : "Cotral"
        case .atac: return "Atac / Roma TPL"
        }
    }

    var iconName: String {
        switch self {
        case .cotral(let stop): return stop.isRail ? "tram.fill" : "bus"
        case .atac: return "mappin.circle"
        }
    }
}

enum SearchRouteResult: Identifiable, Hashable {
    case cotral(GtfsRoute)
    case atac(AtacRoute)

    var id: String {
        switch self {
        case .cotral(let route): return "cotral-\(route.routeId)"
        case .atac(let route): return "atac-\(route.routeId)"
        }
    }

    var shortName: String {
        switch self {
        case .cotral(let route): return route.routeShortName
        case .atac(let route): return route.routeShortName
        }
    }

    var longName: String {
        switch self {
        case .cotral(let route): return route.routeLongName
        case .atac(let route): return route.routeLongName
        }
    }

    var subtitle: String {
        switch self {
        case .cotral(let route): return route.isRail ? "Cotral · treno" : "Cotral"
        case .atac(let route): return route.transitOperator.rawValue
        }
    }

    var iconName: String {
        switch self {
        case .cotral(let route): return route.isRail ? "tram.fill" : "bus"
        case .atac(let route): return route.kind.sfSymbolName
        }
    }
}
