import Foundation
import CoreLocation
import Combine

class SessionManager: NSObject, ObservableObject {
    static let shared = SessionManager()
    
    @Published var currentSession: NightSession?
    @Published var isTracking = false
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // Live Activity update timer
    private var liveActivityUpdateTimer: Timer?
    
    // MARK: - Dwell Detection State
    private var dwellCandidate: DwellCandidate?
    private var activeDwellId: UUID? // Track which dwell is currently active
    private let dwellRadiusMeters: CLLocationDistance = 25
    private let dwellDurationSeconds: TimeInterval = 20 * 60 // 20 minutes
    
    private struct DwellCandidate {
        let startLocation: CLLocation
        let firstSeenAt: Date
        var lastSeenAt: Date
        var locationCount: Int = 1
        
        var duration: TimeInterval {
            lastSeenAt.timeIntervalSince(firstSeenAt)
        }
    }
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Location Manager Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 25
        
        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        #endif
        
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
    }
    
    // MARK: - Session Control
    func startNight() {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
            return
        }
        
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            print("⚠️ Location authorization denied")
            return
        }
        
        currentSession = NightSession()
        isTracking = true
        
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringVisits()
        
        NotificationManager.shared.scheduleLongNightWarning(hours: 6)
        AutoStopManager.shared.startAutoStopTimer()
        
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.startActivity(
                sessionId: currentSession!.id.uuidString,
                startTime: currentSession!.startTime
            )
            startLiveActivityUpdateTimer()
        }
        
        print("✅ Night started at \(Date())")
    }
    
    func stopNight() {
        guard let session = currentSession else { return }
        
        // FIXED: Finalize any active dwell when stopping
        if let activeDwellId = activeDwellId {
            finalizeActiveDwell(dwellId: activeDwellId, endTime: Date())
        }
        
        // Also check for pending candidate
        if let candidate = dwellCandidate {
            finalizeDwellIfQualified(candidate)
        }
        
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringVisits()
        
        session.end()
        isTracking = false
        
        dwellCandidate = nil
        activeDwellId = nil
        
        NotificationManager.shared.cancelLongNightWarning()
        AutoStopManager.shared.cancelAutoStopTimer()
        stopLiveActivityUpdateTimer()
        
        let totalDistance = calculateTotalDistance(for: session.route)
        let duration = session.duration ?? 0
        
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.endActivity(
                finalDistance: session.totalDistance,
                finalStops: session.dwells.count,
                finalDrinks: session.drinks.total,
                duration: duration
            )
        }
        
        SessionStorage.shared.saveSession(session)
        NotificationManager.shared.sendNightEndedNotification(session: session)
        
        print("🛑 Night stopped at \(Date())")
        print("📍 Total locations tracked: \(session.route.count)")
        print("🏠 Total dwells detected: \(session.dwells.count)")
        print("📏 Total distance: \(String(format: "%.2f", totalDistance / 1000))km")
        print("⏱️ Duration: \(formatDuration(duration))")
    }
    
    // MARK: - Helper Methods
    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    private func calculateTotalDistance(for locations: [CLLocation]) -> CLLocationDistance {
        guard locations.count > 1 else { return 0 }
        
        var totalDistance: CLLocationDistance = 0
        for i in 1..<locations.count {
            totalDistance += locations[i].distance(from: locations[i-1])
        }
        return totalDistance
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func isLocationValid(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100 else {
            return false
        }
        
        guard location.timestamp.timeIntervalSinceNow > -60 else {
            return false
        }
        
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            return false
        }
        
        return true
    }
    
    // MARK: - FIXED Dwell Detection Logic
    
    private func processDwellDetection(for location: CLLocation) {
        guard let session = currentSession else { return }
        
        // If user is moving fast, end any active dwell or candidate
        if location.speed > 1.4 {
            if let dwellId = activeDwellId {
                finalizeActiveDwell(dwellId: dwellId, endTime: Date())
                activeDwellId = nil
            }
            if let candidate = dwellCandidate {
                finalizeDwellIfQualified(candidate)
                dwellCandidate = nil
            }
            print("🚶 Moving detected - dwells cleared")
            return
        }
        
        // Check if we're updating an active dwell
        if let dwellId = activeDwellId {
            guard let currentDwell = session.dwells.first(where: { $0.id == dwellId }) else {
                activeDwellId = nil
                return
            }
            
            let dwellLocation = CLLocation(
                latitude: currentDwell.location.latitude,
                longitude: currentDwell.location.longitude
            )
            let distance = location.distance(from: dwellLocation)
            
            if distance <= dwellRadiusMeters {
                // Still at the active dwell - update its endTime
                updateActiveDwellEndTime(dwellId: dwellId, newEndTime: Date())
                print("📍 Still at active dwell (updated)")
                return
            } else {
                // User left the dwell - finalize it
                finalizeActiveDwell(dwellId: dwellId, endTime: Date())
                activeDwellId = nil
                print("🚶 Left active dwell - finalized")
                
                // Start new candidate at current location
                dwellCandidate = DwellCandidate(
                    startLocation: location,
                    firstSeenAt: Date(),
                    lastSeenAt: Date()
                )
                print("🎯 New candidate started after leaving dwell")
                return
            }
        }
        
        // No active dwell - check candidate
        if dwellCandidate == nil {
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: Date(),
                lastSeenAt: Date()
            )
            print("🎯 New dwell candidate started")
            return
        }
        
        guard var candidate = dwellCandidate else { return }
        let distance = location.distance(from: candidate.startLocation)
        
        if distance <= dwellRadiusMeters {
            // Still within radius
            candidate.lastSeenAt = Date()
            candidate.locationCount += 1
            dwellCandidate = candidate
            
            let duration = candidate.duration
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            print("📍 Still at candidate (\(candidate.locationCount) updates, \(minutes)m \(seconds)s)")
            
            // FIXED: Candidate qualified - create dwell and mark as active
            if duration >= dwellDurationSeconds {
                let dwellPoint = DwellPoint(
                    location: candidate.startLocation.coordinate,
                    startTime: candidate.firstSeenAt,
                    endTime: Date() // Will be updated as user stays
                )
                session.addDwell(dwellPoint)
                
                // Mark this dwell as active (ongoing)
                activeDwellId = dwellPoint.id
                
                print("✅ DWELL QUALIFIED - Now tracking as active")
                print("   Duration so far: \(formatDuration(dwellPoint.duration))")
                
                NotificationManager.shared.sendDwellDetectedNotification(
                    dwell: dwellPoint,
                    dwellNumber: session.dwells.count
                )
                
                // Clear candidate
                dwellCandidate = nil
            }
        } else {
            // User left candidate area
            print("🚶 Left candidate area (moved \(String(format: "%.0f", distance))m)")
            finalizeDwellIfQualified(candidate)
            
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: Date(),
                lastSeenAt: Date()
            )
            print("🎯 New candidate at new location")
        }
    }
    
    // NEW: Update an active dwell's end time by replacing it
    private func updateActiveDwellEndTime(dwellId: UUID, newEndTime: Date) {
        guard let session = currentSession,
              let index = session.dwells.firstIndex(where: { $0.id == dwellId }) else {
            return
        }
        
        let oldDwell = session.dwells[index]
        
        // Create new DwellPoint with updated endTime
        let updatedDwell = DwellPoint(
            id: oldDwell.id, // Keep same ID
            location: oldDwell.location,
            startTime: oldDwell.startTime,
            endTime: newEndTime
        )
        
        // Replace in array
        session.dwells[index] = updatedDwell
        
        let duration = updatedDwell.duration
        print("⏱️ Updated active dwell endTime (duration: \(formatDuration(duration)))")
    }
    
    // NEW: Finalize an active dwell when user leaves
    private func finalizeActiveDwell(dwellId: UUID, endTime: Date) {
        guard let session = currentSession,
              let index = session.dwells.firstIndex(where: { $0.id == dwellId }) else {
            return
        }
        
        let oldDwell = session.dwells[index]
        
        // Create final DwellPoint with correct endTime
        let finalDwell = DwellPoint(
            id: oldDwell.id,
            location: oldDwell.location,
            startTime: oldDwell.startTime,
            endTime: endTime
        )
        
        // Replace in array
        session.dwells[index] = finalDwell
        
        let finalDuration = finalDwell.duration
        print("✅ DWELL FINALIZED")
        print("   Total duration: \(formatDuration(finalDuration))")
    }
    
    private func finalizeDwellIfQualified(_ candidate: DwellCandidate) {
        guard let session = currentSession else { return }
        
        var finalCandidate = candidate
        finalCandidate.lastSeenAt = Date()
        
        if finalCandidate.duration >= dwellDurationSeconds {
            let dwellPoint = DwellPoint(
                location: finalCandidate.startLocation.coordinate,
                startTime: finalCandidate.firstSeenAt,
                endTime: finalCandidate.lastSeenAt
            )
            session.addDwell(dwellPoint)
            
            print("✅ DWELL FINALIZED (candidate on departure)")
            print("   Duration: \(formatDuration(dwellPoint.duration))")
        } else {
            let duration = finalCandidate.duration
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            print("⏱️ Candidate didn't qualify (\(minutes)m \(seconds)s)")
        }
    }
    
    // MARK: - Live Activity Updates
    
    private func startLiveActivityUpdateTimer() {
        guard #available(iOS 16.2, *) else { return }
        
        liveActivityUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateLiveActivity()
        }
    }
    
    private func stopLiveActivityUpdateTimer() {
        liveActivityUpdateTimer?.invalidate()
        liveActivityUpdateTimer = nil
    }
    
    @available(iOS 16.2, *)
    private func updateLiveActivity() {
        guard let session = currentSession, isTracking else { return }
        
        let elapsed = Date().timeIntervalSince(session.startTime)
        
        LiveActivityManager.shared.updateActivity(
            distance: session.totalDistance,
            stops: session.dwells.count,
            drinks: session.drinks.total,
            elapsedTime: elapsed
        )
    }
}

// MARK: - CLLocationManagerDelegate
extension SessionManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let session = currentSession, isTracking else { return }
        
        for location in locations {
            guard isLocationValid(location) else { continue }
            
            session.addLocation(location)
            processDwellDetection(for: location)
            
            let accuracy = String(format: "%.1f", location.horizontalAccuracy)
            let speed = location.speed >= 0 ? String(format: "%.1f", location.speed) : "N/A"
            print("📍 Location: (\(location.coordinate.latitude), \(location.coordinate.longitude)) | Accuracy: \(accuracy)m | Speed: \(speed)m/s")
        }
        
        objectWillChange.send()
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard let session = currentSession, isTracking else { return }
        
        let arrivalDate = visit.arrivalDate
        let departureDate = visit.departureDate
        let duration = departureDate.timeIntervalSince(arrivalDate)
        
        print("🏠 Apple Visit detected:")
        print("   Duration: \(formatDuration(duration))")
        
        if duration >= dwellDurationSeconds {
            let hasOverlap = session.dwells.contains { dwell in
                let dwellLocation = CLLocation(latitude: dwell.location.latitude, longitude: dwell.location.longitude)
                let visitLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
                let distance = dwellLocation.distance(from: visitLocation)
                
                return distance < 50 &&
                       dwell.startTime < departureDate &&
                       dwell.endTime > arrivalDate
            }
            
            if !hasOverlap {
                let dwellPoint = DwellPoint(
                    location: visit.coordinate,
                    startTime: arrivalDate,
                    endTime: departureDate
                )
                session.addDwell(dwellPoint)
                print("✅ Apple Visit added as dwell")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📱 Location authorization changed: \(status.rawValue)")
        
        if isTracking && (status == .authorizedAlways || status == .authorizedWhenInUse) {
            locationManager.startUpdatingLocation()
            locationManager.startMonitoringVisits()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("   Error: Location access denied")
                isTracking = false
            case .network:
                print("   Error: Network error")
            default:
                print("   Error code: \(clError.code.rawValue)")
            }
        }
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print("⏸️ Location updates paused")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print("▶️ Location updates resumed")
    }
}
