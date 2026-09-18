import MapKit
import SwiftUI

/// UIViewRepresentable wrapping MKMapView directly (rather than SwiftUI's
/// `Map`) because the live vehicle markers need frame-accurate, animated
/// position interpolation between polls — `UIView.animate` around KVO-
/// observed `MKAnnotation.coordinate` changes, which SwiftUI's `Map`
/// doesn't expose control over on iOS 16 — and because MapKit has no
/// built-in "public transit" layer to toggle: the muted base style plus
/// hand-drawn line/stop overlays below are simulating one (confirmed via
/// Apple developer forums: no such MKMapType exists).
struct MapContainerView: UIViewRepresentable {
    // Cotral
    let poles: [Pole]
    let favoritePoleCodes: Set<String>
    let vehicleCoordinate: CLLocationCoordinate2D?
    let vehicleTrackingState: VehicleTrackingState
    let onSelectPole: (Pole) -> Void

    // Atac/Roma TPL
    let atacStops: [AtacStop]
    let atacShapes: [AtacLineShape]
    let onSelectAtacStop: (AtacStop) -> Void
    /// Resolves a shape's route for coloring — avoids threading
    /// `AtacGtfsStore` itself through this view.
    var routeLookup: ((String) -> AtacRoute?)? = nil

    // Ambient vehicles (Atac full fleet + Cotral opportunistic)
    let transitVehicles: [TransitVehicle]
    let onSelectVehicle: (TransitVehicle) -> Void

    let userLocation: CLLocationCoordinate2D?
    @Binding var pendingCenter: CLLocationCoordinate2D?
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        // Simulated "public transit" look: mute roads/POIs so the lines and
        // stops we draw on top are what stands out.
        mapView.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)

        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "PoleAnnotation")
        mapView.register(VehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: VehicleAnnotationView.reuseIdentifier)
        mapView.register(AtacStopAnnotationView.self, forAnnotationViewWithReuseIdentifier: AtacStopAnnotationView.reuseIdentifier)
        mapView.register(TransitVehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: TransitVehicleAnnotationView.reuseIdentifier)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        updatePoleAnnotations(on: mapView, coordinator: coordinator)
        updateVehicleAnnotation(on: mapView, coordinator: coordinator)
        updateAtacStopAnnotations(on: mapView, coordinator: coordinator)
        updateAtacShapeOverlays(on: mapView, coordinator: coordinator)
        updateTransitVehicleAnnotations(on: mapView, coordinator: coordinator)

        if let target = pendingCenter {
            let region = MKCoordinateRegion(center: target, latitudinalMeters: 900, longitudinalMeters: 900)
            mapView.setRegion(region, animated: true)
            DispatchQueue.main.async { pendingCenter = nil }
        } else if !coordinator.hasCenteredOnUser, let userLocation {
            coordinator.hasCenteredOnUser = true
            let region = MKCoordinateRegion(center: userLocation, latitudinalMeters: 1200, longitudinalMeters: 1200)
            mapView.setRegion(region, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Cotral poles

    private func updatePoleAnnotations(on mapView: MKMapView, coordinator: Coordinator) {
        let currentCodes = Set(poles.map(\.id))
        let existingCodes = Set(coordinator.poleAnnotations.keys)

        for staleCode in existingCodes.subtracting(currentCodes) {
            if let annotation = coordinator.poleAnnotations.removeValue(forKey: staleCode) {
                mapView.removeAnnotation(annotation)
            }
        }

        for pole in poles where pole.coordinate != nil {
            let isFavorite = favoritePoleCodes.contains(pole.id)
            if let existing = coordinator.poleAnnotations[pole.id] {
                existing.isFavorite = isFavorite
            } else {
                let annotation = PoleAnnotation(pole: pole, isFavorite: isFavorite)
                coordinator.poleAnnotations[pole.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }
    }

    // MARK: - Followed Cotral vehicle (single, explicit "segui bus")

    private func updateVehicleAnnotation(on mapView: MKMapView, coordinator: Coordinator) {
        guard let vehicleCoordinate else {
            if let annotation = coordinator.vehicleAnnotation {
                mapView.removeAnnotation(annotation)
                coordinator.vehicleAnnotation = nil
            }
            return
        }

        if let annotation = coordinator.vehicleAnnotation {
            if !annotation.coordinate.isApproximately(vehicleCoordinate) {
                UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut]) {
                    annotation.coordinate = vehicleCoordinate
                }
            }
        } else {
            let annotation = VehicleAnnotation(coordinate: vehicleCoordinate, title: "Bus in tempo reale")
            coordinator.vehicleAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        if let annotation = coordinator.vehicleAnnotation,
           let view = mapView.view(for: annotation) as? VehicleAnnotationView {
            view.apply(trackingState: vehicleTrackingState)
        }
    }

    // MARK: - Atac/Roma TPL stops

    private func updateAtacStopAnnotations(on mapView: MKMapView, coordinator: Coordinator) {
        let currentIds = Set(atacStops.map(\.stopId))
        let existingIds = Set(coordinator.atacStopAnnotations.keys)

        for staleId in existingIds.subtracting(currentIds) {
            if let annotation = coordinator.atacStopAnnotations.removeValue(forKey: staleId) {
                mapView.removeAnnotation(annotation)
            }
        }

        for stop in atacStops where coordinator.atacStopAnnotations[stop.stopId] == nil {
            let annotation = AtacStopAnnotation(stop: stop)
            coordinator.atacStopAnnotations[stop.stopId] = annotation
            mapView.addAnnotation(annotation)
        }
    }

    // MARK: - Atac/Roma TPL line shapes

    private func updateAtacShapeOverlays(on mapView: MKMapView, coordinator: Coordinator) {
        let currentIds = Set(atacShapes.map(\.shapeId))
        let existingIds = Set(coordinator.atacPolylines.keys)

        for staleId in existingIds.subtracting(currentIds) {
            if let overlay = coordinator.atacPolylines.removeValue(forKey: staleId) {
                mapView.removeOverlay(overlay)
            }
        }

        for shape in atacShapes where coordinator.atacPolylines[shape.shapeId] == nil {
            let polyline = AtacPolyline(coordinates: shape.coordinates, count: shape.coordinates.count)
            let route = coordinator.parent.routeLookup?(shape.routeId)
            polyline.routeId = shape.routeId
            polyline.kind = route?.kind ?? .bus
            polyline.colorHex = route?.colorHex
            coordinator.atacPolylines[shape.shapeId] = polyline
            mapView.addOverlay(polyline, level: .aboveLabels)
        }
    }

    // MARK: - Ambient vehicles (Atac full fleet + Cotral opportunistic)

    private func updateTransitVehicleAnnotations(on mapView: MKMapView, coordinator: Coordinator) {
        let currentIds = Set(transitVehicles.map(\.id))
        let existingIds = Set(coordinator.transitVehicleAnnotations.keys)

        for staleId in existingIds.subtracting(currentIds) {
            if let annotation = coordinator.transitVehicleAnnotations.removeValue(forKey: staleId) {
                mapView.removeAnnotation(annotation)
            }
        }

        for vehicle in transitVehicles {
            if let existing = coordinator.transitVehicleAnnotations[vehicle.id] {
                existing.vehicle = vehicle
                if !existing.coordinate.isApproximately(vehicle.coordinate) {
                    UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut]) {
                        existing.coordinate = vehicle.coordinate
                    }
                }
                if let view = mapView.view(for: existing) as? TransitVehicleAnnotationView {
                    view.apply(vehicle)
                }
            } else {
                let annotation = TransitVehicleAnnotation(vehicle: vehicle)
                coordinator.transitVehicleAnnotations[vehicle.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapContainerView
        var poleAnnotations: [String: PoleAnnotation] = [:]
        var vehicleAnnotation: VehicleAnnotation?
        var atacStopAnnotations: [String: AtacStopAnnotation] = [:]
        var atacPolylines: [String: AtacPolyline] = [:]
        var transitVehicleAnnotations: [String: TransitVehicleAnnotation] = [:]
        var hasCenteredOnUser = false

        init(parent: MapContainerView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let poleAnnotation = annotation as? PoleAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "PoleAnnotation", for: poleAnnotation) as? MKMarkerAnnotationView
                view?.annotation = poleAnnotation
                view?.canShowCallout = true
                view?.markerTintColor = poleAnnotation.isFavorite ? .systemYellow : (poleAnnotation.pole.isTreno ? .systemIndigo : .systemBlue)
                view?.glyphImage = UIImage(systemName: poleAnnotation.pole.isTreno ? "tram.fill" : "bus")
                view?.displayPriority = .defaultLow
                return view
            }

            if let vehicleAnnotation = annotation as? VehicleAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: VehicleAnnotationView.reuseIdentifier, for: vehicleAnnotation) as? VehicleAnnotationView
                view?.annotation = vehicleAnnotation
                view?.apply(trackingState: parent.vehicleTrackingState)
                return view
            }

            if let stopAnnotation = annotation as? AtacStopAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: AtacStopAnnotationView.reuseIdentifier, for: stopAnnotation)
                view.annotation = stopAnnotation
                return view
            }

            if let vehicleAnnotation = annotation as? TransitVehicleAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: TransitVehicleAnnotationView.reuseIdentifier, for: vehicleAnnotation) as? TransitVehicleAnnotationView
                view?.annotation = vehicleAnnotation
                view?.apply(vehicleAnnotation.vehicle)
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? AtacPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline.strokeColor
                renderer.lineWidth = 2.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let poleAnnotation = view.annotation as? PoleAnnotation {
                parent.onSelectPole(poleAnnotation.pole)
                mapView.deselectAnnotation(poleAnnotation, animated: false)
            } else if let stopAnnotation = view.annotation as? AtacStopAnnotation {
                parent.onSelectAtacStop(stopAnnotation.stop)
                mapView.deselectAnnotation(stopAnnotation, animated: false)
            } else if let vehicleAnnotation = view.annotation as? TransitVehicleAnnotation {
                parent.onSelectVehicle(vehicleAnnotation.vehicle)
                mapView.deselectAnnotation(vehicleAnnotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }
    }
}
