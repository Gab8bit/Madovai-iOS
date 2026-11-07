# Madovai

Client SwiftUI (iOS 16+) per bus/treni Cotral (extraurbano Lazio) **e** bus/tram/metro Atac + Roma TPL (urbano Roma), su un'unica mappa. Nome dell'app: **Madovai** ("ma dove vai?"), bundle id `dev.gab8bit.madovai`; il progetto mantiene il nome storico `CotralLive.xcodeproj` (solo nome app, icona e bundle id sono cambiati, per non rompere riferimenti interni).

> **Altre versioni.** Port Android nativo (Kotlin + Jetpack Compose): [github.com/Gab8bit/Madovai-Android](https://github.com/Gab8bit/Madovai-Android) · pagina di download su [gab8bit.github.io/Madovai-Android](https://gab8bit.github.io/Madovai-Android/).

## Architettura (dalla 2.0)

Fino alla 1.3 l'app faceva da "server" per se stessa: scaricava i GTFS di Cotral e di Roma (centinaia di MB, parsati al primo avvio), decodificava i feed GTFS-Realtime in protobuf, parlava XML con l'endpoint interno di Cotral e interrogava ASTRAL per i treni.

Dalla **2.0** tutto questo lo fa il **backend Madovai** (`https://madovai.gab8bit.net/api/v1`, progetto Madovai-Backend, documentato nel suo `docs/API.md`). L'app è un client JSON leggero:

- `Sources/API/` — `APIClient` (HTTP, timeout, cache secondo `Cache-Control`, errori del server già in italiano), `MadovaiAPI` (un metodo per endpoint, mappa le risposte sui modelli dell'app), `APIModels` (forme JSON).
- `Sources/Live/` — servizi che fanno polling solo con l'app in primo piano: flotta Atac/Roma TPL, veicoli Cotral vicino alle paline visibili, veicolo "seguito", stato della connessione e del server (`/health`).
- `Sources/ViewModels/` — `MapViewModel` (fermate e percorsi del riquadro visibile, linea isolata, stato di caricamento/errore), `SearchModel`, `LinesStore`.
- `Sources/Views/` — mappa (`MKMapView` incapsulata), schede di fermate/veicoli, tab Linee, Preferiti, Promemoria, Info.

Nessuna dipendenza esterna (ZIPFoundation e SwiftProtobuf non servono più) e nessuna eccezione ATS: il backend è HTTPS. L'indirizzo del server è in `Config.apiBaseURL`; per una build di prova si può cambiare con la chiave Info.plist `MadovaiAPIBaseURL` o con l'argomento di avvio `-MadovaiAPIBaseURL <url>`.

## Come funziona

- **Mappa:** fermate Atac (puntini arancioni), paline/stazioni Cotral (marker blu/indaco, gialli se preferiti) e percorsi delle linee compaiono da zoom "quartiere" in su; i veicoli in movimento sono badge con il numero di linea (pallini a zoom più largo) e non vengono mostrati quando si vede l'intera regione. Il pulsante con il percorso nasconde/mostra le linee.
- **Avvisi:** offline, server non raggiungibile, server che sta preparando i dati, errori di caricamento (sempre con "Riprova"), indicatore "Caricamento dati…" solo se la risposta è lenta. Le schede mantengono i dati già caricati e segnalano un aggiornamento fallito invece di svuotarsi.
- **Tocca un veicolo:** apre l'orario (Atac: fermata per fermata della corsa; treni Cotral: prossimo passaggio di ogni stazione della linea) e isola la linea sulla mappa finché non premi "Reset".
- **Paline Cotral:** transiti PIV.do con ritardo reale quando la corsa è monitorata e il mezzo trasmette, "Segui" per seguire il veicolo. **Stazioni:** orario ASTRAL con ritardi/soppressioni, o tabella GTFS etichettata "Orario stimato".
- **Fermate Atac:** arrivi in tempo reale per direzione (selettore tra le banchine), con orario programmato di ripiego se non c'è nulla di live.
- **Promemoria:** controllo locale in background (`BGAppRefreshTask`) che chiede al backend il prossimo passaggio e mostra una notifica locale. Non si usano le push del server perché APNs richiede un account Apple Developer a pagamento. Limiti: l'orario esatto lo decide iOS, e chiudere l'app forzatamente sospende i controlli.

## Bug della mappa corretti nella 2.0

- **Veicoli non toccabili:** niente callout (intercettavano il tap e lasciavano il marker selezionato), area di tocco di almeno 28–40 pt, veicoli sempre sopra fermate e paline, deselezione differita (un marker rimasto selezionato ignorava il tap successivo), POI della mappa non selezionabili.
- **Veicoli che sparivano durante lo zoom:** i veicoli non partecipano alla "collision" di MapKit, non vengono mai rimossi e riaggiunti a ogni aggiornamento (solo spostati), la posizione non viene animata mentre la camera si muove, e sulla mappa ci sono solo i mezzi del riquadro invece di ~1000.
- **Veicoli in ritardo all'apertura:** il primo aggiornamento veniva annullato dall'evento "app attiva"; ora i veicoli compaiono in 2–3 secondi.

## Setup

```bash
brew install xcodegen  # una tantum
xcodegen generate
open CotralLive.xcodeproj
```

**Test:** `xcodebuild test -project CotralLive.xcodeproj -scheme CotralLive -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`

- `CotralLiveTests` (unitari): decodifica di ogni endpoint con risposte reali del backend, mappatura degli errori HTTP, logica di orari/ritardi (ora di Roma), filtri della mappa, merge dei veicoli Cotral, promemoria e migrazioni dei dati salvati dalla 1.x.
- `CotralLiveUITests` (end-to-end contro il backend di produzione): tap ripetuti sui veicoli, zoom senza perdita di veicoli, schede di fermate/paline, ricerca, Linee, preferiti, promemoria, e gestione degli errori con un server irraggiungibile. `ScreenshotTourUITests` salva gli screenshot di tutte le schermate in `/tmp/madovai-ui/` (solo con `TEST_RUNNER_MADOVAI_SCREENSHOTS=1`).

**Nota xcodegen — icona/risorse:** xcodegen 2.46.0 scarta silenziosamente la chiave `resources:` di un target, quindi la cartella `Resources` è elencata sotto `sources:` (xcodegen riconosce comunque il catalogo `.xcassets`). Se aggiorni xcodegen, vale la pena ritestare `resources:`.

## Distribuzione

Le release su GitHub contengono `Madovai.ipa` (non firmata, da installare con SideStore/AltStore). TestFlight richiede l'Apple Developer Program a pagamento: imposta il Team in `project.yml` (`DEVELOPMENT_TEAM`), poi Product → Archive → App Store Connect.

## Note sui dati

- Il ritardo Cotral è affidabile solo con `monitorata == "1"` e mezzo che trasmette; altrimenti è un valore fittizio e l'app lo nasconde.
- Solo `soppressa == "Y"` conta come corsa soppressa (Cotral a volte restituisce `"S"`, significato non confermato).
- Un ritardo sconosciuto (`null`) non viene mai mostrato come "puntuale".
- Tutti gli orari sono confrontati con l'ora di Roma, anche se il telefono è in un altro fuso.
- La metro A/B/C non ha posizioni né previsioni per fermata nei feed in tempo reale di Roma: compare come percorso e stazioni, e non è selezionabile nei promemoria.
