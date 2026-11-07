import Foundation
import XCTest
@testable import CotralLive

/// Intercepts every request of a dedicated URLSession and answers from a
/// handler — the API layer is tested end to end (URL building, status
/// codes, decoding) without touching the network.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var body: String = "{}"
        var error: URLError?
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Response)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        requests = []
    }

    static var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        let response = handler?(request) ?? Response(status: 404, body: #"{"error":"no stub"}"#)
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum TestAPI {
    static let baseURL = URL(string: "https://example.test/api/v1")!

    static func make() -> MadovaiAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        return MadovaiAPI(client: APIClient(baseURL: baseURL, session: URLSession(configuration: configuration)))
    }

    /// Routes stubbed responses by endpoint name (last path component).
    static func route(_ table: [String: StubURLProtocol.Response]) {
        StubURLProtocol.handler = { request in
            let name = request.url?.lastPathComponent ?? ""
            return table[name] ?? StubURLProtocol.Response(status: 404, body: #"{"error":"Percorso inesistente"}"#)
        }
    }
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// A Rome date for deterministic time-based tests.
func romeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return RomeTime.calendar.date(from: components)!
}

/// Real response bodies captured from https://madovai.gab8bit.net/api/v1
/// on 2026-11-07 (trimmed to a few items).
enum Samples {
    static let health = #"{"ok":true,"version":"1.0.0","gtfsReady":true}"#

    static let search = #"""
    {"stops":[{"source":"cotral","id":"RL_ACILIA","name":"Acilia","lat":41.7832974,"lon":12.36061706,"rail":true},
    {"source":"atac","id":"71402","name":"OSTIENSE/CAVALCAVIA ACILIA","lat":41.787247,"lon":12.370137,"rail":false,"metro":false},
    {"source":"atac","id":"AD27","name":"Anagnina","lat":41.84284,"lon":12.585758,"rail":false,"metro":true}],
    "routes":[{"source":"atac","id":"MEA","shortName":"MEA","longName":"","displayName":"Metro A","kind":"metro","operator":"Atac","color":"E27439","rail":false},
    {"source":"cotral","id":"F:ROMALIDO","shortName":"ROMALIDO","longName":"METROMARE","displayName":"ROMALIDO","kind":"treno","operator":"Cotral","color":null,"rail":true}]}
    """#

    static let stops = #"""
    {"cotral":[{"id":"f14638","name":"ROMA | Termini FS (Piazza Cinquecento)","locality":"ROMA","lat":41.9005699992,"lon":12.5004022291,"rail":false}],
    "atac":[{"id":"80725","name":"TERMINI (MA-MB-FS)","lat":41.900615,"lon":12.500038},{"id":"80785","name":"TERMINI (MA-MB-FS)","lat":41.900662,"lon":12.500093}]}
    """#

    static let transits = #"""
    {"pole":{"code":"f3583","name":"ROMA, Anagnina (Metro A)","stopName":"Anagnina Metro A","locality":"Roma Anagnina","comune":"Roma","lat":41.8432872876794,"lon":12.585553320626},
    "transits":[{"idCorsa":"8484405","percorso":"FR766D","partenzaCorsa":"Roma Anagnina, Anagnina Metro A","orarioPartenzaCorsa":"12:15","arrivoCorsa":"FROSINONE | Piazza Pertini (f3486)","orarioArrivoCorsa":"13:55","soppressa":"N","numeroOrdine":"1","tempoTransito":"12:15","ritardoSeconds":82,"passato":"1","vehicleCode":"4007","vehicleAlive":true,"testoFermata":"-","instradamento":"Tor Vergata V.Alimena-Roma Via Alimena","banchina":"10","monitorata":"1","accessibile":"1"},
    {"idCorsa":"8484406","percorso":"CF952A","partenzaCorsa":"x","orarioPartenzaCorsa":"12:40","arrivoCorsa":"VELLETRI | Stazione FS (f2818)","orarioArrivoCorsa":"13:30","soppressa":"Y","numeroOrdine":"2","tempoTransito":"12:42","ritardoSeconds":0,"passato":"0","vehicleCode":null,"vehicleAlive":false,"testoFermata":"-","instradamento":"","banchina":"","monitorata":"0","accessibile":"0"}]}
    """#

    static let emptyTransits = #"{"pole":null,"transits":[]}"#

    static let rail = #"""
    {"source":"astral","directions":[
    {"destination":"Cristoforo Colombo","route":"RL_PSP-CC","entries":[
      {"id":"10001","time":"05:36","sortSeconds":20160,"delayMinutes":0,"isCancelled":false,"isReplacementBus":false},
      {"id":"10045","time":"12:36","sortSeconds":45360,"delayMinutes":3,"isCancelled":true,"isReplacementBus":false},
      {"id":"10047","time":"12:51","sortSeconds":46260,"delayMinutes":null,"isCancelled":false,"isReplacementBus":true}]},
    {"destination":"Porta San Paolo","route":"RL_CC-PSP","entries":[
      {"id":"20002","time":"12:40","sortSeconds":45600,"delayMinutes":2,"isCancelled":false,"isReplacementBus":false}]}]}
    """#

    static let pole = #"{"id":"RL_ACILIA","name":"Acilia","locality":"Acilia","lat":41.7832974,"lon":12.36061706,"rail":true,"trainRoutes":["RL_CC-PSP","RL_PSP-CC"]}"#

    static let astralLine = #"""
    {"route":"RL_PSP-CC","directionLabel":"Porta San Paolo → Cristoforo Colombo","lineName":"Metromare","stations":[
    {"name":"Porta San Paolo","code":"ff90009","order":1,"next":{"id":"10045","time":"12:25","sortSeconds":44700,"delayMinutes":0,"isCancelled":false,"isReplacementBus":false}},
    {"name":"Acilia","code":"ff90020","order":9,"next":{"id":"10045","time":"12:44","sortSeconds":45840,"delayMinutes":1,"isCancelled":false,"isReplacementBus":false}},
    {"name":"Cristoforo Colombo","code":"ff90006","order":13,"next":null}]}
    """#

    static let atacVehicles = #"""
    {"updated":1794050490,"vehicles":[
    {"id":"atac-54","lat":41.881634,"lon":12.54327,"bearing":null,"routeId":"409","routeLabel":"409","kind":"bus","operator":"Atac","tripId":"0#1639-14","headsign":"Arco Di Travertino"},
    {"id":"atac-900","lat":41.89,"lon":12.49,"bearing":90,"routeId":"MEA","routeLabel":"MEA","kind":"metro","operator":"Atac","tripId":null,"headsign":null},
    {"id":"tpl-7","lat":41.95,"lon":12.55,"bearing":null,"routeId":"061","routeLabel":"061","kind":"bus","operator":"Roma TPL","tripId":"1#5-1","headsign":""},
    {"id":"atac-bad","lat":0,"lon":0,"bearing":null,"routeId":"1","routeLabel":"1","kind":"bus","operator":"Atac","tripId":null,"headsign":null}]}
    """#

    static let cotralVehicles = #"""
    {"vehicles":[{"id":"cotral-T395","code":"T395","lat":41.7865448817851,"lon":12.3703211675315,"routeId":"RL_CC-PSP","routeLabel":"RL_CC-PSP","kind":"treno","delaySeconds":112,"tripId":"8950734"}]}
    """#

    static let atacLive = #"""
    {"updated":1794050490,"stops":{"70240":[
    {"tripId":"0#1549-11","routeId":"360","routeLabel":"360","kind":"bus","ts":1794051014,"delaySeconds":-224,"headsign":"Zama","cancelled":false},
    {"tripId":"0#3280-9","routeId":"82","routeLabel":"82","kind":"bus","ts":1794050780,"delaySeconds":null,"headsign":"Monte Sacro","cancelled":true}]}}
    """#

    static let atacStop = #"""
    {"name":"TERMINI (MA-MB-FS)","stops":[{"id":"05000","name":"TERMINI (MA-MB-FS)","lat":41.901308,"lon":12.500433,"headsign":"Termini"},
    {"id":"70240","name":"TERMINI (MA-MB-FS)","lat":41.901158,"lon":12.500047,"headsign":"Tonino Bello"}]}
    """#

    static let atacSchedule = #"[{"tripId":"0#2065-13","routeId":"514","routeLabel":"514","kind":"bus","ts":1794050580,"headsign":"Termini"}]"#

    static let atacTrip = #"""
    {"tripId":"0#3280-9","routeId":"82","routeLabel":"82","headsign":"Monte Sacro","stops":[
    {"stopId":"70138","stopName":"XX SETTEMBRE/MIN. FINANZE","sequence":22,"ts":1794050500,"delaySeconds":-314},
    {"stopId":"70240","stopName":"TERMINI (MA-MB-FS)","sequence":24,"ts":1794050810,"delaySeconds":null}]}
    """#

    static let line = #"""
    {"route":{"source":"atac","id":"MEA","shortName":"MEA","longName":"","displayName":"Metro A","kind":"metro","operator":"Atac","color":"E27439","rail":false},
    "stops":[{"id":"AD27","name":"Anagnina","lat":41.84284,"lon":12.585758,"headsign":"Anagnina"},{"id":"AP1","name":"Anagnina","lat":41.842997,"lon":12.585897,"headsign":"Battistini"}],
    "shapes":[{"id":"50818","coords":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","bbox":[41.84292,12.4149,41.91274,12.58582]}]}
    """#

    static let lines = #"""
    {"atac":[{"source":"atac","id":"211","shortName":"211","longName":"","displayName":"211","kind":"bus","operator":"Atac","color":null,"rail":false}],
    "cotralRail":[{"source":"cotral","id":"F:ROMALIDO","shortName":"ROMALIDO","longName":"METROMARE","displayName":"ROMALIDO","kind":"treno","operator":"Cotral","color":null,"rail":true}]}
    """#

    static let shapes = #"{"shapes":[{"id":"52894","routeId":"P02","kind":"bus","color":null,"coords":"_p~iF~ps|U_ulLnnqC"}]}"#
}
