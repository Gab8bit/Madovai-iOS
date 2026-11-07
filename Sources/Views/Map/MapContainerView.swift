import MapKit
import SwiftUI

/// The followed vehicle as the map needs it.
struct FollowedVehicleMarker: Equatable {
    let coordinate: CLLocationCoordinate2D
    let isTreno: Bool
    let isLost: Bool
}

/// `MKMapView` wrapped directly (not SwiftUI's `Map`) for frame-accurate
/// marker animation and full control over hit-testing and diffing.
///
/// Fixes for the 1.x map bugs, all in the coordinator:
/// - **Vehicles not tappable**: no callouts (they swallowed the tap and left
///   the annotation selected), a ≥ 28 pt tap area around every marker,
///   vehicles always above stops (`zPriority`), deselection deferred to the
///   next run loop so the next tap on the same marker selects it again, and
///   map POIs not selectable.
/// - **Vehicles disappearing while zooming**: vehicles never take part in
///   collision hiding (`displayPriority = .required`, `collisionMode =
///   .none`), are never removed/re-added on refresh, only moved; positions
///   aren't animated while the camera is moving (animating annotation
///   coordinates mid-zoom is what made MapKit drop their views), and only
///   the vehicles around the viewport are on the map instead of ~1000.
struct MapContainerView: UIViewRepresentable {
    let poles: [Pole]
    let favoritePoleCodes: Set<String>
    let atacStops: [AtacStop]
    let shapes: [MapShape]
    let vehicles: [TransitVehicle]
    let vehicleStyle: VehicleMarkerStyle
    let followed: FollowedVehicleMarker?
    let cameraRequest: CameraRequest?

    let onSelectPole: (Pole) -> Void
    let onSelectAtacStop: (AtacStop) -> Void
    let onSelectVehicle: (TransitVehicle) -> Void
    let onViewportChange: (MapViewport) -> Void

    static let romeCenter = CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964)

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = false
        mapView.isRotateEnabled = true
        // Muted base map: the lines and stops drawn on top stand out (MapKit
        // has no public-transport layer to toggle; this simulates one).
        mapView.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        // Map POIs must never steal a tap meant for a vehicle or a stop.
        mapView.selectableMapFeatures = []

        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Pole")
        mapView.register(AtacStopAnnotationView.self, forAnnotationViewWithReuseIdentifier: AtacStopAnnotationView.reuseIdentifier)
        mapView.register(VehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: VehicleAnnotationView.reuseIdentifier)
        mapView.register(FollowedVehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: FollowedVehicleAnnotationView.reuseIdentifier)

        // Without a location fix (permission denied, slow GPS) this is what
        // the user sees: it must be above `Config.minDataZoom` (a 6 km wide
        // view was zoom ≈ 12.96 and showed an empty map with no stops).
        mapView.setRegion(MKCoordinateRegion(center: Self.romeCenter, latitudinalMeters: 4000, longitudinalMeters: 4000), animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.syncPoles(on: mapView)
        coordinator.syncAtacStops(on: mapView)
        coordinator.syncShapes(on: mapView)
        coordinator.syncVehicles(on: mapView)
        coordinator.syncFollowed(on: mapView)
        coordinator.applyCamera(on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapContainerView

        private var poleAnnotations: [String: PoleAnnotation] = [:]
        private var atacAnnotations: [String: AtacStopAnnotation] = [:]
        private var shapeOverlays: [String: ShapePolyline] = [:]
        private var vehicleAnnotations: [String: VehicleAnnotation] = [:]
        private var followedAnnotation: FollowedVehicleAnnotation?
        private var appliedVehicleStyle: VehicleMarkerStyle = .badge
        private var lastCameraRequestId: UUID?
        /// True between `regionWillChange` and `regionDidChange`.
        private var isCameraMoving = false
        private var viewportDebounce: DispatchWorkItem?

        // Cheap change detection: skip a layer entirely when its input is
        // the same as last time (SwiftUI calls `updateUIView` often).
        private var lastPoleKeys: [String] = []
        private var lastAtacKeys: [String] = []
        private var lastShapeKeys: [String] = []

        init(parent: MapContainerView) {
            self.parent = parent
        }

        // MARK: Poles

        func syncPoles(on mapView: MKMapView) {
            let favorites = parent.favoritePoleCodes
            let keys = parent.poles.map { "\($0.id)|\(favorites.contains($0.id) ? 1 : 0)" }
            guard keys != lastPoleKeys else { return }
            lastPoleKeys = keys

            let wanted = Dictionary(parent.poles.filter { $0.coordinate != nil }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let stale = poleAnnotations.keys.filter { wanted[$0] == nil }
            mapView.removeAnnotations(stale.compactMap { poleAnnotations.removeValue(forKey: $0) })

            var added: [PoleAnnotation] = []
            for (id, pole) in wanted {
                let isFavorite = favorites.contains(id)
                if let existing = poleAnnotations[id] {
                    existing.update(pole: pole)
                    if existing.isFavorite != isFavorite {
                        existing.isFavorite = isFavorite
                        if let view = mapView.view(for: existing) as? MKMarkerAnnotationView {
                            Self.style(view, for: existing)
                        }
                    }
                } else {
                    let annotation = PoleAnnotation(pole: pole, isFavorite: isFavorite)
                    poleAnnotations[id] = annotation
                    added.append(annotation)
                }
            }
            mapView.addAnnotations(added)
        }

        private static func style(_ view: MKMarkerAnnotationView, for annotation: PoleAnnotation) {
            view.canShowCallout = false
            view.animatesWhenAdded = false
            view.titleVisibility = .adaptive
            view.subtitleVisibility = .hidden
            view.markerTintColor = annotation.isFavorite ? .systemYellow : (annotation.pole.isTreno ? .systemIndigo : .systemBlue)
            view.glyphImage = UIImage(systemName: annotation.pole.isTreno ? "tram.fill" : "bus")
            view.displayPriority = annotation.isFavorite ? .required : .defaultHigh
            view.collisionMode = .circle
            view.zPriority = .defaultUnselected
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityIdentifier = "map.pole"
            view.accessibilityLabel = (annotation.pole.isTreno ? "Stazione " : "Palina ") + annotation.pole.displayName
        }

        // MARK: Atac stops

        func syncAtacStops(on mapView: MKMapView) {
            let keys = parent.atacStops.map(\.stopId)
            guard keys != lastAtacKeys else { return }
            lastAtacKeys = keys

            let wanted = Dictionary(parent.atacStops.map { ($0.stopId, $0) }, uniquingKeysWith: { first, _ in first })
            let stale = atacAnnotations.keys.filter { wanted[$0] == nil }
            mapView.removeAnnotations(stale.compactMap { atacAnnotations.removeValue(forKey: $0) })
            let added = wanted.compactMap { id, stop -> AtacStopAnnotation? in
                guard atacAnnotations[id] == nil else { return nil }
                let annotation = AtacStopAnnotation(stop: stop)
                atacAnnotations[id] = annotation
                return annotation
            }
            mapView.addAnnotations(added)
        }

        // MARK: Shapes

        func syncShapes(on mapView: MKMapView) {
            let keys = parent.shapes.map { "\($0.id)|\($0.routeId)|\($0.colorHex ?? "")" }
            guard keys != lastShapeKeys else { return }
            lastShapeKeys = keys

            let wanted = Dictionary(parent.shapes.map { ("\($0.id)|\($0.routeId)", $0) }, uniquingKeysWith: { first, _ in first })
            let stale = shapeOverlays.keys.filter { wanted[$0] == nil }
            mapView.removeOverlays(stale.compactMap { shapeOverlays.removeValue(forKey: $0) })
            for (key, shape) in wanted where shapeOverlays[key] == nil && shape.coordinates.count > 1 {
                let polyline = ShapePolyline(coordinates: shape.coordinates, count: shape.coordinates.count)
                polyline.shapeId = shape.id
                polyline.kind = shape.kind
                polyline.colorHex = shape.colorHex
                shapeOverlays[key] = polyline
                mapView.addOverlay(polyline, level: .aboveRoads)
            }
        }

        // MARK: Vehicles

        func syncVehicles(on mapView: MKMapView) {
            let styleChanged = parent.vehicleStyle != appliedVehicleStyle
            appliedVehicleStyle = parent.vehicleStyle

            let wanted = Dictionary(parent.vehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let stale = vehicleAnnotations.keys.filter { wanted[$0] == nil }
            if !stale.isEmpty {
                mapView.removeAnnotations(stale.compactMap { vehicleAnnotations.removeValue(forKey: $0) })
            }

            var added: [VehicleAnnotation] = []
            var toAnimate: [(VehicleAnnotation, CLLocationCoordinate2D)] = []
            for (id, vehicle) in wanted {
                guard let existing = vehicleAnnotations[id] else {
                    let annotation = VehicleAnnotation(vehicle: vehicle)
                    vehicleAnnotations[id] = annotation
                    added.append(annotation)
                    continue
                }
                let changed = existing.vehicle != vehicle
                existing.vehicle = vehicle
                let view = mapView.view(for: existing) as? VehicleAnnotationView
                if changed || styleChanged {
                    view?.apply(vehicle, style: appliedVehicleStyle)
                }
                let target = vehicle.coordinate
                guard !existing.coordinate.isApproximately(target) else { continue }
                // Glide only short, visible moves while the camera is still;
                // anything else jumps (an off-screen or mid-zoom animation
                // is exactly what used to make markers disappear).
                if view != nil, !isCameraMoving, existing.coordinate.distance(to: target) < 1500 {
                    toAnimate.append((existing, target))
                } else {
                    existing.coordinate = target
                }
            }
            if !added.isEmpty { mapView.addAnnotations(added) }
            if !toAnimate.isEmpty {
                UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                    for (annotation, target) in toAnimate { annotation.coordinate = target }
                }
            }
        }

        func syncFollowed(on mapView: MKMapView) {
            guard let marker = parent.followed else {
                if let annotation = followedAnnotation {
                    mapView.removeAnnotation(annotation)
                    followedAnnotation = nil
                }
                return
            }
            guard let annotation = followedAnnotation else {
                let annotation = FollowedVehicleAnnotation(coordinate: marker.coordinate, isTreno: marker.isTreno, isLost: marker.isLost)
                followedAnnotation = annotation
                mapView.addAnnotation(annotation)
                return
            }
            if annotation.isTreno != marker.isTreno || annotation.isLost != marker.isLost {
                annotation.isTreno = marker.isTreno
                annotation.isLost = marker.isLost
                (mapView.view(for: annotation) as? FollowedVehicleAnnotationView)?.apply(isTreno: marker.isTreno, isLost: marker.isLost)
            }
            if !annotation.coordinate.isApproximately(marker.coordinate) {
                if mapView.view(for: annotation) != nil, !isCameraMoving, annotation.coordinate.distance(to: marker.coordinate) < 3000 {
                    UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                        annotation.coordinate = marker.coordinate
                    }
                } else {
                    annotation.coordinate = marker.coordinate
                }
            }
        }

        // MARK: Camera

        func applyCamera(on mapView: MKMapView) {
            guard let request = parent.cameraRequest, request.id != lastCameraRequestId else { return }
            lastCameraRequestId = request.id
            switch request.target {
            case .center(let coordinate, let meters):
                let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
                mapView.setRegion(mapView.regionThatFits(region), animated: true)
            case .fit(let points, let maxZoom):
                guard !points.isEmpty else { return }
                var rect = MKMapRect.null
                for point in points {
                    let mapPoint = MKMapPoint(point)
                    rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
                }
                // Don't zoom in further than `maxZoom` (a line with a
                // single stop would otherwise fill the screen with one pin).
                let width = Double(max(mapView.bounds.width, 320))
                let minLonDelta = 360 * width / 256 / pow(2, maxZoom)
                let minRectWidth = MKMapSize.world.width * minLonDelta / 360
                if rect.size.width < minRectWidth {
                    let grow = (minRectWidth - rect.size.width) / 2
                    rect = rect.insetBy(dx: -grow, dy: -grow * Double(mapView.bounds.height / max(mapView.bounds.width, 1)))
                }
                let padding = UIEdgeInsets(top: 140, left: 40, bottom: 120, right: 40)
                mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                return nil
            case let pole as PoleAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "Pole", for: pole) as! MKMarkerAnnotationView
                view.annotation = pole
                Self.style(view, for: pole)
                return view
            case let stop as AtacStopAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: AtacStopAnnotationView.reuseIdentifier, for: stop)
                view.annotation = stop
                return view
            case let vehicle as VehicleAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: VehicleAnnotationView.reuseIdentifier, for: vehicle) as! VehicleAnnotationView
                view.annotation = vehicle
                view.apply(vehicle.vehicle, style: appliedVehicleStyle)
                return view
            case let followed as FollowedVehicleAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: FollowedVehicleAnnotationView.reuseIdentifier, for: followed) as! FollowedVehicleAnnotationView
                view.annotation = followed
                view.apply(isTreno: followed.isTreno, isLost: followed.isLost)
                return view
            default:
                return nil
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? ShapePolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = polyline.strokeColor.withAlphaComponent(0.9)
            renderer.lineWidth = polyline.kind == .metro || polyline.kind == .treno ? 4 : 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            switch annotation {
            case let vehicle as VehicleAnnotation:
                parent.onSelectVehicle(vehicle.vehicle)
            case let pole as PoleAnnotation:
                parent.onSelectPole(pole.pole)
            case let stop as AtacStopAnnotation:
                parent.onSelectAtacStop(stop.stop)
            default:
                break
            }
            // Deferred: deselecting inside the delegate callback can leave
            // MapKit thinking the annotation is still selected, and a
            // selected annotation ignores the next tap on it.
            DispatchQueue.main.async {
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isCameraMoving = true
            viewportDebounce?.cancel()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isCameraMoving = false
            let region = mapView.region
            let width = Double(mapView.bounds.width)
            let viewport = MapViewport(
                bounds: ViewportBounds(region: region),
                zoom: MapViewport.zoom(longitudeDelta: region.span.longitudeDelta, widthPoints: width)
            )
            viewportDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.parent.onViewportChange(viewport) }
            viewportDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.viewportSettleDelay, execute: work)
        }
    }
}
