import Foundation
import UIKit
import CoreLocation
import Combine

class SessionManager: NSObject, ObservableObject {
    static let shared = SessionManager()
    
    @Published var currentSession: NightSession?
    @Published var isTracking = false
    
    private var isInBackground = false
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // 🔒 Thread-safe queue for all mutations
    private let sessionQueue = DispatchQueue(label: "com.app.sessionmanager", qos: .userInitiated)
    
    // Live Activity update timer
    private var liveActivityUpdateTimer: Timer?
    
    // MARK: - Tiered Dwell Detection State
    private var dwellCandidate: DwellCandidate?
    private var activeDwellId: UUID?
    
    // 🎯 Tiered dwell thresholds (in seconds)
    private let quickStopThreshold: TimeInterval = 5 * 60      // 5 minutes
    private let shortVisitThreshold: TimeInterval = 10 * 60    // 10 minutes
    private let dwellThreshold: TimeInterval = 20 * 60         // 20 minutes
    private let longStopThreshold: TimeInterval = 40 * 60      // 40 minutes
    
    // Adaptive radius based on GPS quality
    private let baseRadiusMeters: CLLocationDistance = 25
    private let maxRadiusExpansionMeters: CLLocationDistance = 75
    
    // Dwell qualification
    private let minInRadiusSamplesForDwell = 3
    private let leaveHysteresisSeconds: TimeInterval = 90 // 1.5 min for night out chaos
    
    // Track recent locations for displacement calculation
    private var recentLocations: [CLLocation] = []
    private let recentLocationsLimit = 15 // Increased for better analysis
    
//    // MARK: - Background Task Management
//    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
//    private let backgroundTaskLock = NSLock()
    
    // MARK: - Dwell Types
    enum DwellType: String, Codable {
        case passthrough = "Passed through"    // 5-10 minutes
        case quickStop = "Quick stop"          // 10-20 minutes
        case shortVisit = "Short visit"        // 20-40 minutes
        case longStop = "Settled in"           // 40-60 minutes
        case marathon = "Long session"         // 60+ minutes
        
        static func from(duration: TimeInterval) -> DwellType {
            switch duration {
            case 0..<10*60: return .passthrough
            case 10*60..<20*60: return .quickStop
            case 20*60..<40*60: return .shortVisit
            case 40*60..<60*60: return .longStop
            default: return .marathon
            }
        }
    }
    
    enum DwellConfidence: String, Codable {
        case high      // <20m accuracy, 5+ samples
        case medium    // 20-50m accuracy
        case low       // 50-100m accuracy or few samples
        case estimated // From Apple Visit API or poor GPS
    }
    
    private struct DwellCandidate {
        var startLocation: CLLocation
        let firstSeenAt: Date
        var lastSeenAt: Date
        var locationCount: Int = 1
        var outOfRadiusAccumulated: TimeInterval = 0
        var accuracySum: Double = 0 // For calculating average accuracy

        var duration: TimeInterval {
            lastSeenAt.timeIntervalSince(firstSeenAt)
        }
        
        var averageAccuracy: Double {
            locationCount > 0 ? accuracySum / Double(locationCount) : 0
        }
        
        var confidence: DwellConfidence {
            let avg = averageAccuracy
            if locationCount >= 5 && avg < 20 { return .high }
            if avg < 50 { return .medium }
            return .low
        }
    }
    
    private override init() {
        super.init()
        setupLocationManager()
        setupAppStateObservers()
    }
    
    // MARK: - Location Manager Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        
        // Disable automatic pausing - we want continuous tracking for night out
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // 🆕 CRITICAL: Set to kCLDistanceFilterNone to get updates even when stationary
        locationManager.distanceFilter = kCLDistanceFilterNone  // Changed from 10
        
        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        #endif
        
        print("📍 Location manager configured:")
        print("   Desired accuracy: \(locationManager.desiredAccuracy)m")
        print("   Distance filter: \(locationManager.distanceFilter == kCLDistanceFilterNone ? "NONE (continuous)" : "\(locationManager.distanceFilter)m")")
        print("   Activity type: fitness")
    }
    
    // MARK: - App State Observers
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInBackground = true  // Add this
            self?.switchToBackgroundMode()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInBackground = false  // Add this
            if self?.isTracking == true {
                self?.switchToForegroundMode()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInBackground = false  // Add this
            if self?.isTracking == true {
                self?.switchToForegroundMode()
            }
        }
    }
    
    // MARK: - Smart Mode Switching for Night Out
    private func switchToBackgroundMode() {
        guard isTracking, let session = currentSession else { return }
        
        let sessionDuration = Date().timeIntervalSince(session.startTime)
        
        // 🎯 Keep high accuracy for first 8 hours (typical night out range)
        if sessionDuration < 8 * 3600 {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = kCLDistanceFilterNone  // Changed from 15
        } else {
            // After 8 hours, assume user forgot to stop - save battery
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager.distanceFilter = 50
        }
        
        // ✅ CRITICAL: Explicitly restart location updates after changing settings
        locationManager.stopUpdatingLocation()
        locationManager.startUpdatingLocation()
        
        // Add significant location changes as backup
        locationManager.startMonitoringSignificantLocationChanges()
        
        stopLiveActivityUpdateTimer()
        
        print("🌙 Background mode: High accuracy for night out tracking")
        print("   Desired accuracy: \(locationManager.desiredAccuracy)m")
        print("   Distance filter: \(locationManager.distanceFilter == kCLDistanceFilterNone ? "NONE" : "\(locationManager.distanceFilter)m")")
    }

    private func switchToForegroundMode() {
        guard isTracking else { return }

        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone  // Changed from 10
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startUpdatingLocation()

        if #available(iOS 16.2, *) {
            startLiveActivityUpdateTimer()
        }
        
        print("☀️ Foreground mode: Best accuracy")
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
        
        sessionQueue.sync {
            currentSession = NightSession()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isTracking = true
        }
        
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringVisits()
        
        NotificationManager.shared.scheduleLongNightWarning(hours: 8)
        AutoStopManager.shared.startAutoStopTimer()
        
        if #available(iOS 16.2, *), let session = currentSession {
            LiveActivityManager.shared.startActivity(
                sessionId: session.id.uuidString,
                startTime: session.startTime
            )
            startLiveActivityUpdateTimer()
        }
        
        print("🎉 Night started at \(Date())")
        print("⚡ Expected battery usage: ~20-25% over 5 hours")
    }
    
    func stopNight() {
        sessionQueue.sync {
            guard let session = currentSession else { return }
            
            if let activeDwellId = activeDwellId {
                finalizeActiveDwell(dwellId: activeDwellId, endTime: Date())
            }
            
            if let candidate = dwellCandidate {
                finalizeDwellIfQualified(candidate)
            }
            
            locationManager.stopUpdatingLocation()
            locationManager.stopMonitoringSignificantLocationChanges()
            locationManager.disallowDeferredLocationUpdates()
            locationManager.stopMonitoringVisits()
            
            session.end()
            
            dwellCandidate = nil
            activeDwellId = nil
            recentLocations.removeAll()
            
            NotificationManager.shared.cancelLongNightWarning()
            AutoStopManager.shared.cancelAutoStopTimer()
            
            DispatchQueue.main.async { [weak self] in
                self?.stopLiveActivityUpdateTimer()
            }
            
//            endBackgroundTask()
            
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
            
            // Print night summary
            printNightSummary(session: session, distance: totalDistance, duration: duration)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isTracking = false
        }
    }
    
    // MARK: - Smart Auto-Stop Detection
    private func checkAutoStopConditions() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.currentSession else { return }
            
            let now = Date()
            let duration = now.timeIntervalSince(session.startTime)
            let hour = Calendar.current.component(.hour, from: now)
            
            // Scenario 1: Stationary for 45+ minutes between 2-8am (likely home/asleep)
            if hour >= 2 && hour < 8 {
                if let lastDwell = session.dwells.last {
                    let stationaryDuration = now.timeIntervalSince(lastDwell.startTime)
                    if stationaryDuration > 45 * 60 {
                        print("💤 Auto-stop: User likely home/asleep")
                        DispatchQueue.main.async {
                            self.stopNight()
                        }
                        return
                    }
                }
            }
            
            // Scenario 2: Session >12 hours (definitely forgot to stop)
            if duration > 12 * 3600 {
                print("⏰ Auto-stop: Session exceeded 12 hours")
                DispatchQueue.main.async {
                    self.stopNight()
                }
                return
            }
            
            // Scenario 3: No movement for 2+ hours at any time
            if let lastLocation = session.route.last {
                let timeSinceLastMove = now.timeIntervalSince(lastLocation.timestamp)
                if timeSinceLastMove > 2 * 3600 {
                    print("🛑 Auto-stop: No movement for 2+ hours")
                    DispatchQueue.main.async {
                        self.stopNight()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    // 🔧 DEBUG: Check location manager status
    func checkLocationStatus() {
        print("\n📊 LOCATION STATUS CHECK")
        print("=========================")
        print("Authorization: \(locationManager.authorizationStatus.rawValue)")
        print("Is Tracking: \(isTracking)")
        print("Has Session: \(currentSession != nil)")
        print("Session ID: \(currentSession?.id.uuidString ?? "none")")
        print("Route Points: \(currentSession?.route.count ?? 0)")
        print("Dwells: \(currentSession?.dwells.count ?? 0)")
        print("Desired Accuracy: \(locationManager.desiredAccuracy)")
        print("Distance Filter: \(locationManager.distanceFilter)")
        print("Activity Type: \(locationManager.activityType.rawValue)")
        print("=========================\n")
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
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 150 else {
            return false
        }
        
        guard location.timestamp.timeIntervalSinceNow > -120 else {
            return false
        }
        
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            return false
        }
        
        return true
    }
    
    private func centroid(of locations: [CLLocation]) -> CLLocation? {
        guard !locations.isEmpty else { return nil }
        var x: Double = 0, y: Double = 0, z: Double = 0
        for loc in locations {
            let lat = loc.coordinate.latitude * .pi / 180
            let lon = loc.coordinate.longitude * .pi / 180
            x += cos(lat) * cos(lon)
            y += cos(lat) * sin(lon)
            z += sin(lat)
        }
        let count = Double(locations.count)
        x /= count; y /= count; z /= count
        let lon = atan2(y, x)
        let hyp = sqrt(x*x + y*y)
        let lat = atan2(z, hyp)
        let coord = CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: lon * 180 / .pi)
        return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
    }
    
    // MARK: - 🎯 Smart Movement Detection for Night Outs
    private func isUserMovingBetweenVenues(_ location: CLLocation) -> Bool {
        // Check speed if available and reliable
        if location.speed >= 0 && location.horizontalAccuracy < 30 {
            let speedKmh = location.speed * 3.6
            if speedKmh > 6 {  // Faster than drunk stumble (was 6, keeping it)
                // But check if this is sustained movement over 30 seconds
                let last30Seconds = recentLocations.filter {
                    Date().timeIntervalSince($0.timestamp) < 30
                }
                
                // Need at least 3 recent locations with high speed
                let highSpeedCount = last30Seconds.filter {
                    $0.speed >= 0 && ($0.speed * 3.6) > 6
                }.count
                
                if highSpeedCount >= 3 {
                    return true
                }
            }
        }
        
        // Check displacement over last 60 seconds (was 45, now 60 for more tolerance)
        guard recentLocations.count >= 4 else { return false }
        
        let last60Seconds = recentLocations.filter {
            Date().timeIntervalSince($0.timestamp) < 60
        }
        
        guard last60Seconds.count >= 3,
              let first = last60Seconds.first,
              let last = last60Seconds.last else {
            return false
        }
        
        let displacement = last.distance(from: first)
        let timeSpan = last.timestamp.timeIntervalSince(first.timestamp)
        
        // Moved >80m in 60 seconds = definitely transitioning (was 60m in 45s)
        if displacement > 80 && timeSpan > 0 {
            return true
        }
        
        // Check if consistently moving away from any active dwell
        if let activeDwellId = activeDwellId,
           let session = currentSession,
           let activeDwell = session.dwells.first(where: { $0.id == activeDwellId }) {
            let dwellLoc = CLLocation(
                latitude: activeDwell.location.latitude,
                longitude: activeDwell.location.longitude
            )
            
            // Moving away consistently = leaving venue (increased threshold)
            let distanceFromDwell = location.distance(from: dwellLoc)
            if distanceFromDwell > 150 {  // Increased from 100 to 150
                return true
            }
        }
        
        return false
    }
    
    // MARK: - 🎯 Enhanced Dwell Detection for Night Outs
    private func processDwellDetection(for location: CLLocation) {
        guard let session = currentSession else { return }
        
        // Maintain recent locations buffer
        recentLocations.append(location)
        if recentLocations.count > recentLocationsLimit {
            recentLocations.removeFirst()
        }
        
        // 🎯 Adaptive radius based on GPS quality (indoor/outdoor detection)
        let accuracy = max(location.horizontalAccuracy, 0)
        let isPoorGPS = accuracy > 50  // Likely indoors or urban canyon
        
        let effectiveRadius: CLLocationDistance
        if isPoorGPS {
            // Indoors: be more lenient
            effectiveRadius = baseRadiusMeters + min(accuracy * 1.5, maxRadiusExpansionMeters)
        } else {
            // Good GPS: standard radius
            effectiveRadius = baseRadiusMeters + min(accuracy, maxRadiusExpansionMeters / 2)
        }
        
        // Check if user is moving between venues
        let isMoving = isUserMovingBetweenVenues(location)
        
        if isMoving {
            if let dwellId = activeDwellId {
                finalizeActiveDwell(dwellId: dwellId, endTime: Date())
                activeDwellId = nil
            }
            if let candidate = dwellCandidate {
                finalizeDwellIfQualified(candidate)
                dwellCandidate = nil
            }
            if !isInBackground {
                print("🚶 Moving between venues - dwells cleared")
            }
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
            
            if distance <= effectiveRadius {
                updateActiveDwellEndTime(dwellId: dwellId, newEndTime: Date())
                return
            } else {
                // Start hysteresis - might just be walking around venue
                dwellCandidate = DwellCandidate(
                    startLocation: dwellLocation,
                    firstSeenAt: currentDwell.startTime,
                    lastSeenAt: Date(),
                    locationCount: 0,
                    outOfRadiusAccumulated: 0,
                    accuracySum: accuracy
                )
                return
            }
        }
        
        // No active dwell - check/create candidate
        if dwellCandidate == nil {
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: Date(),
                lastSeenAt: Date(),
                accuracySum: accuracy
            )
            if !isInBackground {
                let gpsQuality = isPoorGPS ? "📶 Poor GPS (indoors?)" : "📡 Good GPS"
                print("🎯 New dwell candidate started - \(gpsQuality)")
            }
            return
        }
        
        guard var candidate = dwellCandidate else { return }
        let distance = location.distance(from: candidate.startLocation)
        
        if distance <= effectiveRadius {
            // Still within radius
            candidate.lastSeenAt = Date()
            candidate.locationCount += 1
            candidate.accuracySum += accuracy
            candidate.outOfRadiusAccumulated = 0
            
            // Smooth the anchor point using recent locations
            if let smoothed = centroid(of: recentLocations.suffix(5)) {
                candidate.startLocation = smoothed
            }
            
            dwellCandidate = candidate
            
            let duration = candidate.duration
            
            // 🎯 Tiered dwell qualification
            if duration >= quickStopThreshold && candidate.locationCount >= minInRadiusSamplesForDwell {
                let dwellType = DwellType.from(duration: duration)
                
                // Only create dwell for stops >= 5 minutes
                let dwellPoint = DwellPoint(
                    location: candidate.startLocation.coordinate,
                    startTime: candidate.firstSeenAt,
                    endTime: Date()
                )
                
                // Check if this is a revisit to earlier venue
                let isRevisit = detectVenueRevisit(dwellPoint, session: session)
                
                session.addDwell(dwellPoint)
                activeDwellId = dwellPoint.id
                
                if !isInBackground {
                    let confidenceStr = candidate.confidence.rawValue
                    print("✅ DWELL QUALIFIED: \(dwellType.rawValue)")
                    print("   Duration: \(formatDuration(duration))")
                    print("   Confidence: \(confidenceStr)")
                    print("   Samples: \(candidate.locationCount)")
                    if isRevisit {
                        print("   🔄 Revisited earlier venue!")
                    }
                }
                
                NotificationManager.shared.sendDwellDetectedNotification(
                    dwell: dwellPoint,
                    dwellNumber: session.dwells.count
                )
                
                if #available(iOS 16.2, *) {
                        updateLiveActivity()
                    }
                
                dwellCandidate = nil
            } else if !isInBackground {
                // Progress update
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                print("📍 At candidate: \(minutes)m \(seconds)s (\(candidate.locationCount) samples)")
            }
        } else {
            // Outside radius - apply hysteresis
            var tmp = candidate
            let now = Date()
            let delta = now.timeIntervalSince(tmp.lastSeenAt)
            tmp.outOfRadiusAccumulated += max(0, delta)
            tmp.lastSeenAt = now
            dwellCandidate = tmp

            // 🎯 Shorter hysteresis for night outs (90s vs 120s)
            if tmp.outOfRadiusAccumulated >= leaveHysteresisSeconds {
                finalizeDwellIfQualified(tmp)
                
                // Start fresh candidate at new location
                dwellCandidate = DwellCandidate(
                    startLocation: location,
                    firstSeenAt: Date(),
                    lastSeenAt: Date(),
                    accuracySum: accuracy
                )
            }
        }
    }
    
    // MARK: - 🔄 Venue Revisit Detection
    private func detectVenueRevisit(_ newDwell: DwellPoint, session: NightSession) -> Bool {
        for existingDwell in session.dwells where existingDwell.id != newDwell.id {
            let distance = CLLocation(
                latitude: newDwell.location.latitude,
                longitude: newDwell.location.longitude
            ).distance(from: CLLocation(
                latitude: existingDwell.location.latitude,
                longitude: existingDwell.location.longitude
            ))
            
            // Within 35m = probably same venue
            if distance < 35 {
                return true
            }
        }
        return false
    }
    
    // MARK: - Dwell Update Methods
    private func updateActiveDwellEndTime(dwellId: UUID, newEndTime: Date) {
        guard let session = currentSession,
              let index = session.dwells.firstIndex(where: { $0.id == dwellId }) else {
            return
        }
        
        guard index < session.dwells.count else { return }
        
        let oldDwell = session.dwells[index]
        let updatedDwell = DwellPoint(
            id: oldDwell.id,
            location: oldDwell.location,
            startTime: oldDwell.startTime,
            endTime: newEndTime
        )
        
        session.dwells[index] = updatedDwell
    }
    
    private func finalizeActiveDwell(dwellId: UUID, endTime: Date) {
        guard let session = currentSession,
              let index = session.dwells.firstIndex(where: { $0.id == dwellId }) else {
            return
        }
        
        guard index < session.dwells.count else { return }
        
        let oldDwell = session.dwells[index]
        let finalDwell = DwellPoint(
            id: oldDwell.id,
            location: oldDwell.location,
            startTime: oldDwell.startTime,
            endTime: endTime
        )
        
        session.dwells[index] = finalDwell
        
        let dwellType = DwellType.from(duration: finalDwell.duration)
        
        if !isInBackground {
            print("✅ DWELL FINALIZED: \(dwellType.rawValue)")
            print("   Total duration: \(formatDuration(finalDwell.duration))")
        }
    }
    
    private func finalizeDwellIfQualified(_ candidate: DwellCandidate) {
        guard let session = currentSession else { return }
        
        var finalCandidate = candidate
        finalCandidate.lastSeenAt = Date()
        
        // 🎯 Only save dwells >= 5 minutes (quick stops and above)
        if finalCandidate.duration >= quickStopThreshold {
            let dwellPoint = DwellPoint(
                location: finalCandidate.startLocation.coordinate,
                startTime: finalCandidate.firstSeenAt,
                endTime: finalCandidate.lastSeenAt
            )
            
            let dwellType = DwellType.from(duration: dwellPoint.duration)
            session.addDwell(dwellPoint)
            
            if !isInBackground {
                print("✅ DWELL FINALIZED: \(dwellType.rawValue)")
                print("   Duration: \(formatDuration(dwellPoint.duration))")
            }
        } else {
            if !isInBackground {
                let duration = finalCandidate.duration
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                print("⏱️ Candidate too short (\(minutes)m \(seconds)s) - not saved")
            }
        }
    }
    
    // MARK: - Night Summary
    private func printNightSummary(session: NightSession, distance: CLLocationDistance, duration: TimeInterval) {
        print("\n" + String(repeating: "=", count: 50))
        print("🌙 NIGHT OUT SUMMARY")
        print(String(repeating: "=", count: 50))
        print("⏱️  Duration: \(formatDuration(duration))")
        print("📏 Distance: \(String(format: "%.2f", distance / 1000))km")
        print("📍 Locations tracked: \(session.route.count)")
        print("🍺 Stops detected: \(session.dwells.count)")
        
        if !session.dwells.isEmpty {
            print("\n📊 Stop Breakdown:")
            let grouped = Dictionary(grouping: session.dwells) {
                DwellType.from(duration: $0.duration)
            }
            
            for type in [DwellType.passthrough, .quickStop, .shortVisit, .longStop, .marathon] {
                if let count = grouped[type]?.count, count > 0 {
                    print("   \(type.rawValue): \(count)")
                }
            }
            
            let longestDwell = session.dwells.max(by: { $0.duration < $1.duration })
            if let longest = longestDwell {
                print("\n⭐ Longest stop: \(formatDuration(longest.duration))")
            }
        }
        
        print(String(repeating: "=", count: 50) + "\n")
    }
    
    // MARK: - Live Activity Updates
    private func startLiveActivityUpdateTimer() {
        guard #available(iOS 16.2, *) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.liveActivityUpdateTimer?.invalidate()
            self?.liveActivityUpdateTimer = Timer.scheduledTimer(
                withTimeInterval: 60,  // Changed from 30 to 60 seconds
                repeats: true
            ) { [weak self] _ in
                self?.updateLiveActivity()
            }
            
            // Trigger immediate first update
            self?.updateLiveActivity()
        }
    }
    
    private func stopLiveActivityUpdateTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.liveActivityUpdateTimer?.invalidate()
            self?.liveActivityUpdateTimer = nil
        }
    }
    
    @available(iOS 16.2, *)
    private func updateLiveActivity() {
        // Don't use sessionQueue.sync here - just read the values safely
        guard let session = currentSession, isTracking else { return }
        
        let distance = session.totalDistance
        let stops = session.dwells.count
        let drinks = session.drinks.total
        let elapsed = Date().timeIntervalSince(session.startTime)
        
        // Update on main thread to avoid any potential issues
        DispatchQueue.main.async {
            LiveActivityManager.shared.updateActivity(
                distance: distance,
                stops: stops,
                drinks: drinks,
                elapsedTime: elapsed
            )
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension SessionManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }

        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.currentSession else { return }

            if self.isInBackground {
                // Background mode: process only the latest location
                guard let location = locations.last, self.isLocationValid(location) else { return }
                
                session.addLocation(location)
                self.processDwellDetection(for: location)
                
                print("📍 BG: Location recorded at \(Date())")
                print("   Accuracy: \(String(format: "%.1f", location.horizontalAccuracy))m")
                print("   Route points: \(session.route.count)")
                
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            } else {
                // Foreground mode: process all locations
                for location in locations {
                    guard self.isLocationValid(location) else { continue }

                    session.addLocation(location)
                    self.processDwellDetection(for: location)

                    let accuracy = String(format: "%.1f", location.horizontalAccuracy)
                    let speed = location.speed >= 0 ? String(format: "%.1f", location.speed) : "N/A"
                    print("📍 Location: (\(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude))) | Accuracy: \(accuracy)m | Speed: \(speed)m/s")
                }

                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
            
            // Check auto-stop conditions periodically
            if locations.count > 0 {
                self.checkAutoStopConditions()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        if let error = error {
            print("❌ Deferred updates error: \(error.localizedDescription)")
        }
//        endBackgroundTask()
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard isTracking else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.currentSession else { return }
            
            let arrivalDate = visit.arrivalDate
            let departureDate = visit.departureDate
            let duration = departureDate.timeIntervalSince(arrivalDate)
            
            print("🏠 Apple Visit detected:")
            print("   Duration: \(self.formatDuration(duration))")
            
            // 🎯 Only use Apple Visits for longer stops (20+ minutes)
            if duration >= self.dwellThreshold {
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
                    
                    let dwellType = DwellType.from(duration: duration)
                    print("✅ Apple Visit added as dwell: \(dwellType.rawValue)")
                }
            } else {
                print("   ⏭️ Visit too short - ignoring")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📱 Location authorization changed: \(status.rawValue)")
        
        switch status {
        case .notDetermined:
            print("   Status: Not Determined")
        case .restricted:
            print("   Status: Restricted")
        case .denied:
            print("   Status: Denied")
        case .authorizedAlways:
            print("   Status: Authorized Always ✅")
        case .authorizedWhenInUse:
            print("   Status: Authorized When In Use ✅")
        @unknown default:
            print("   Status: Unknown")
        }
        
        if isTracking && (status == .authorizedAlways || status == .authorizedWhenInUse) {
            print("✅ Re-starting location updates after authorization")
            locationManager.startUpdatingLocation()
            locationManager.startMonitoringVisits()
        } else if status == .denied || status == .restricted {
            print("⚠️ Location access denied/restricted - stopping tracking")
            DispatchQueue.main.async { [weak self] in
                self?.stopNight()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("   Error: Location access denied")
                DispatchQueue.main.async { [weak self] in
                    self?.isTracking = false
                }
            case .network:
                print("   Error: Network error (will retry)")
            case .locationUnknown:
                print("   Error: Location temporarily unknown (will retry)")
            default:
                print("   Error code: \(clError.code.rawValue)")
            }
        }
//        endBackgroundTask()
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print("⏸️ Location updates paused (system optimization)")
        // Note: This shouldn't happen since we disabled auto-pause
        // If it does, resume immediately for night out tracking
        if isTracking {
            locationManager.startUpdatingLocation()
            print("▶️ Forcing resume for night out tracking")
        }
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print("▶️ Location updates resumed")
    }
}
