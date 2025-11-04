import Foundation
import UIKit
import CoreLocation
import Combine

// MARK: - Simplified SessionManager
// Collects raw location data during tracking, does smart analysis after stopping
class SessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SessionManager()
    
    @Published var currentSession: NightSession?
    @Published var isTracking = false
    
    private var isInBackground = false
    private let locationManager = CLLocationManager()
//    private var cancellables = Set<AnyCancellable>()
    
    // Live Activity update timer
    private var liveActivityUpdateTimer: Timer?
    
    // MARK: - Simple validation thresholds
    private let maxAccuracyMeters: CLLocationAccuracy = 150
    private let maxLocationAgeSeconds: TimeInterval = 120
    
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
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone
        
        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        #endif
        
        print("📍 Location manager configured for simple tracking")
    }
    
    // MARK: - App State Observers
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInBackground = true
            self?.switchToBackgroundMode()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInBackground = false
            if self?.isTracking == true {
                self?.switchToForegroundMode()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isInBackground = false
            if self?.isTracking == true {
                self?.switchToForegroundMode()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("⚠️ Memory warning - attempting cleanup")
            // Clear any cached data or large temporary structures
            if let session = self?.currentSession {
                // Simplify route more aggressively if needed
                session.route = RouteSimplifier.simplify(
                    locations: session.route,
                    tolerance: 30.0  // More aggressive
                )
            }
        }
    }
    
    // MARK: - Background/Foreground Mode Switching
    private func switchToBackgroundMode() {
        guard isTracking else { return }
        
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10.0
        locationManager.stopUpdatingLocation()
        locationManager.startUpdatingLocation()
//        locationManager.startMonitoringSignificantLocationChanges()
        
        stopLiveActivityUpdateTimer()
        
        print("🌙 Background mode activated")
    }

    private func switchToForegroundMode() {
        guard isTracking else { return }

        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.startUpdatingLocation()

        if #available(iOS 16.2, *) {
            startLiveActivityUpdateTimer()
        }
        
        print("☀️ Foreground mode activated")
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
        
        // Create new session on main thread (no queue needed)
        currentSession = NightSession()
        isTracking = true
        
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
        
        print("🎉 Night started - collecting location data")
    }
    
    private var isProcessing = false
    
    func stopNight() {
        guard let session = currentSession else { return }
        
        guard !isProcessing else {
            print("⚠️ Already processing a session")
            return
        }
        isProcessing = true
        
        // Stop location updates first
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.disallowDeferredLocationUpdates()
        locationManager.stopMonitoringVisits()
        
        NotificationManager.shared.cancelLongNightWarning()
        AutoStopManager.shared.cancelAutoStopTimer()
        stopLiveActivityUpdateTimer()

        
        isTracking = false
        
        print("🔄 Processing session data...")
        
        // Process session data in background
        Task.detached(priority: .userInitiated) {
            do {
                try await self.processSessionData(session)
                
                await MainActor.run {
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
                    
                    self.printNightSummary(session: session)
                    
                    // ✅ Reset flag AFTER everything completes
                    self.isProcessing = false
                }
            } catch {
                print("❌ Session processing failed: \(error)")
                await MainActor.run {
                    // Save raw session even if processing fails
                    SessionStorage.shared.saveSession(session)
                    self.isProcessing = false
                }
            }
        }
    }
    
    enum SessionError: Error {
        case noLocationData
        case processingFailed(String)
    }
    
    // MARK: - Post-Processing (The Smart Stuff)
    private func processSessionData(_ session: NightSession) async throws {
        guard !session.route.isEmpty else {
            throw SessionError.noLocationData
        }
        
        let startTime = Date()
        
        // Step 1: Detect gaps on FULL route
        let gapDwells = detectStationaryGaps(from: session.route)
        
        // Step 2: Detect dwells on FULL route
        let clusterDwells = await detectDwells(from: session.route)
        
        // Step 3: Merge and split
        let mergedDwells = mergeDwells(gaps: gapDwells, clusters: clusterDwells)
        let splitDwells = splitAdjacentClusters(mergedDwells, from: session.route)

        await MainActor.run {
            session.dwells = splitDwells
        }
        
        // Step 4: NOW simplify route for display/storage
        let simplifiedRoute = RouteSimplifier.simplify(
            locations: session.route,
            tolerance: 15.0
        )
        
        await MainActor.run {
            session.route = simplifiedRoute
        }
        
        // Step 5: Detect revisits
        await detectRevisits(in: session)
        
        print("✅ Processing completed in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
    }
    
    // MARK: - Gap Detection for Indoor Venues
    private func detectStationaryGaps(from locations: [CLLocation]) -> [DwellPoint] {
        var dwells: [DwellPoint] = []
        
        print("🔍 Checking \(locations.count-1) location pairs for gaps...")
        
        for i in 0..<locations.count - 1 {
            let current = locations[i]
            let next = locations[i + 1]
            let timeDiff = next.timestamp.timeIntervalSince(current.timestamp)
            let distance = current.distance(from: next)
            
            if timeDiff >= 60 {
                print("   Pair \(i): \(Int(timeDiff))s gap, \(Int(distance))m apart")
            }
            
            // Adjusted thresholds:
            // - Longer time gaps (15+ min) allow larger distances (for GPS blackouts)
            // - Shorter gaps require closer proximity
            if timeDiff >= 15 * 60 && distance < 300 {  // ← 15 min, 300m for blackouts
                let dwell = DwellPoint(
                    location: current.coordinate,
                    startTime: current.timestamp,
                    endTime: next.timestamp,
                    confidence: .estimated
                )
                dwells.append(dwell)
                print("📍 Gap detected: \(formatDuration(timeDiff)) at distance \(Int(distance))m")
            }
        }
        
        return dwells
    }
    
    // MARK: - Merge Gap Dwells with Cluster Dwells
    private func mergeDwells(gaps: [DwellPoint], clusters: [DwellPoint]) -> [DwellPoint] {
        var merged = clusters
        
        for gap in gaps {
            // Check if this gap overlaps with any existing cluster dwell
            let overlaps = clusters.contains { cluster in
                // Check if they're close in time (within 5 minutes)
                let timeOverlap = abs(cluster.startTime.timeIntervalSince(gap.startTime)) < 5 * 60 ||
                                 abs(cluster.endTime.timeIntervalSince(gap.endTime)) < 5 * 60
                
                // Check if they're close in space (within 100m)
                let clusterLoc = CLLocation(latitude: cluster.location.latitude, longitude: cluster.location.longitude)
                let gapLoc = CLLocation(latitude: gap.location.latitude, longitude: gap.location.longitude)
                let spaceOverlap = clusterLoc.distance(from: gapLoc) < 100
                
                return timeOverlap && spaceOverlap
            }
            
            if !overlaps {
                merged.append(gap)
                print("✅ Added gap dwell to final results")
            } else {
                print("⚠️ Gap dwell overlaps with cluster, skipping to avoid duplicate")
            }
        }
        
        return merged.sorted { $0.startTime < $1.startTime }
    }
    
    // Add this NEW function after mergeDwells:

    // MARK: - Split Adjacent Venue Clusters
    private func splitAdjacentClusters(_ dwells: [DwellPoint], from locations: [CLLocation]) -> [DwellPoint] {
        var splitDwells: [DwellPoint] = []
        
        for dwell in dwells {
            // Find all locations within this dwell's timeframe
            let dwellLocations = locations.filter {
                $0.timestamp >= dwell.startTime && $0.timestamp <= dwell.endTime
            }
            
            guard dwellLocations.count > 10 else {
                splitDwells.append(dwell)
                continue
            }
            
            // 🆕 Check if this is random GPS drift - don't split if it is
            let isDrift = detectRandomGPSDrift(dwellLocations)
            if isDrift {
                print("🎲 Skipping split for random GPS drift cluster")
                splitDwells.append(dwell)
                continue
            }
            
            // Look for significant spatial jumps (venue changes)
            var splits: [Int] = [0]
            
            // Calculate centroid of first 10 points (initial venue)
            let initialPoints = Array(dwellLocations.prefix(min(10, dwellLocations.count)))
            var initialCentroid = calculateCentroid(of: initialPoints)
            var initialCentroidLoc = CLLocation(
                latitude: initialCentroid.latitude,
                longitude: initialCentroid.longitude
            )
            
            for i in 10..<dwellLocations.count {
                let current = dwellLocations[i]
                let distanceFromInitial = current.distance(from: initialCentroidLoc)
                
                // If we've moved >35m from the initial centroid for 5+ consecutive points
                if distanceFromInitial > 35 {
                    var consecutiveAway = 1
                    for j in i+1..<min(i+5, dwellLocations.count) {
                        if dwellLocations[j].distance(from: initialCentroidLoc) > 35 {
                            consecutiveAway += 1
                        }
                    }
                    
                    if consecutiveAway >= 3 {
                        splits.append(i)
                        // Update centroid to new venue
                        let remainingPoints = Array(dwellLocations[i...])
                        let newPoints = Array(remainingPoints.prefix(min(10, remainingPoints.count)))
                        initialCentroid = calculateCentroid(of: newPoints)
                        initialCentroidLoc = CLLocation(
                            latitude: initialCentroid.latitude,
                            longitude: initialCentroid.longitude
                        )
                        print("🔄 Detected venue change at index \(i)")
                    }
                }
            }
            
            splits.append(dwellLocations.count)
            
            // Create separate dwells for each segment
            if splits.count > 2 { // Found splits
                for i in 0..<splits.count-1 {
                    let startIdx = splits[i]
                    let endIdx = splits[i+1]
                    let segment = Array(dwellLocations[startIdx..<endIdx])
                    
                    guard let first = segment.first,
                          let last = segment.last else {
                        continue
                    }
                    
                    let segmentDuration = last.timestamp.timeIntervalSince(first.timestamp)
                    
                    // 🆕 Increase minimum duration for split segments
                    guard segmentDuration >= 10 * 60 else { // Was 5 min, now 10 min
                        print("⚠️ Skipping split segment: too short (\(Int(segmentDuration/60))min)")
                        continue
                    }
                    
                    let centroid = calculateCentroid(of: segment)
                    let splitDwell = DwellPoint(
                        location: centroid,
                        startTime: first.timestamp,
                        endTime: last.timestamp,
                        confidence: dwell.confidence
                    )
                    splitDwells.append(splitDwell)
                    print("✂️ Split cluster into segment: \(Int(segmentDuration/60))min")
                }
            } else {
                splitDwells.append(dwell)
            }
        }
        
        return splitDwells
    }
    
    // MARK: - Helper: Remove walking transitions from clusters
    private func removeWalkingTransitions(from cluster: [CLLocation]) -> [CLLocation] {
        guard cluster.count > 5 else { return cluster }
        
        var cleanedCluster: [CLLocation] = []
        
        for i in 0..<cluster.count {
            let point = cluster[i]
            
            // Check if this point is part of a walking sequence
            var isWalking = false
            
            // Look at nearby points (±2 positions)
            for offset in -2...2 {
                let checkIndex = i + offset
                guard checkIndex >= 0 && checkIndex < cluster.count - 1 else { continue }
                
                let current = cluster[checkIndex]
                let next = cluster[checkIndex + 1]
                
                let distance = current.distance(from: next)
                let timeDiff = next.timestamp.timeIntervalSince(current.timestamp)
                
                // If moving >30m in 30s, this is walking
                if timeDiff > 0 && distance / timeDiff > 1.5 { // Was 1.0, now 1.5 m/s
                    isWalking = true
                    break
                }
            }
            
            if !isWalking {
                cleanedCluster.append(point)
            }
        }
        
        if cleanedCluster.count < cluster.count / 2 {
            print("⚠️ Walking transition removal too aggressive, keeping original cluster")
            return cluster
        }
        
        return cleanedCluster
    }
    
    private func findNeighbors(
        for location: CLLocation,
        in locations: [CLLocation],
        epsilon: CLLocationDistance,
        temporalWindow: TimeInterval? = nil // Make it optional
    ) -> [Int] {
        var neighbors: [Int] = []
        
        // Adaptive temporal window based on cluster density
        // For very close venues, use shorter window
        let window = temporalWindow ?? 15 * 60 // Default to 15 minutes instead of 30
        
        for (index, other) in locations.enumerated() {
            let spatialDistance = location.distance(from: other)
            let temporalDistance = abs(location.timestamp.timeIntervalSince(other.timestamp))
            
            // Both spatial AND temporal constraints must be met
            if spatialDistance <= epsilon && temporalDistance <= window {
                neighbors.append(index)
            }
        }
        
        return neighbors
    }
    
    // MARK: - DBSCAN Clustering for Dwell Detection
    private func detectDwells(from locations: [CLLocation]) async -> [DwellPoint] {
        guard locations.count > 5 else { return [] }
        
        let epsilon: CLLocationDistance = 75.0
        let minPoints = 5
        let minDuration: TimeInterval = 5 * 60
        
        var clusters: [[CLLocation]] = []
        var visited = Set<Int>()
        var noise = Set<Int>()
        
        // DBSCAN Algorithm
        for (index, location) in locations.enumerated() {
            guard !visited.contains(index) else { continue }
            visited.insert(index)
            
            let neighbors = findNeighbors(
                for: location,
                in: locations,
                epsilon: epsilon,
                temporalWindow: nil // Remove temporal constraint for now
            )
            
            if neighbors.count < minPoints {
                noise.insert(index)
                continue
            }
            
            // Start new cluster
            var cluster = [location]
            var seeds = neighbors
            
            while !seeds.isEmpty {
                let neighborIndex = seeds.removeFirst()
                
                if noise.contains(neighborIndex) {
                    noise.remove(neighborIndex)
                }
                
                if visited.contains(neighborIndex) {
                    continue
                }
                
                visited.insert(neighborIndex)
                cluster.append(locations[neighborIndex])
                
                let neighborNeighbors = findNeighbors(
                    for: locations[neighborIndex],
                    in: locations,
                    epsilon: epsilon,
                    temporalWindow: nil
                )
                
                if neighborNeighbors.count >= minPoints {
                    seeds.append(contentsOf: neighborNeighbors)
                }
            }
            
            clusters.append(cluster)
            print("🔍 DBSCAN found cluster: \(cluster.count) points, duration=\(Int((cluster.last!.timestamp.timeIntervalSince(cluster.first!.timestamp))/60))min")
        }
        
        // Convert clusters to DwellPoints
        var dwells: [DwellPoint] = []

        for cluster in clusters {
            // 🆕 Remove walking transition points from cluster
            let cleanedCluster = removeWalkingTransitions(from: cluster)
            
            guard let first = cleanedCluster.first,
                  let last = cleanedCluster.last else { continue }

            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            
            print("🔍 DBSCAN found cluster: \(cluster.count) points -> \(cleanedCluster.count) after cleanup, duration=\(Int(duration/60))min")
            
            // 🆕 Check cluster density - reject if too sparse
            let pointsPerMinute = Double(cleanedCluster.count) / (duration / 60.0)
            if pointsPerMinute < 1.5 && duration < 20 * 60 {
                // Less than 1.5 points per minute for short stops = probably not stationary
                print("⚠️ Rejected cluster: too sparse (\(String(format: "%.1f", pointsPerMinute)) points/min)")
                continue
            }
            
            // Only create dwell if duration meets minimum
            guard duration >= minDuration else { continue }
            
            // Calculate total path distance within cluster
            var totalPathDistance: CLLocationDistance = 0
            for i in 1..<cleanedCluster.count {
                totalPathDistance += cleanedCluster[i].distance(from: cleanedCluster[i-1])
            }
            
            // Calculate centroid using cleaned cluster
            let centroid = calculateCentroid(of: cleanedCluster)
            let centroidLocation = CLLocation(
                latitude: centroid.latitude,
                longitude: centroid.longitude
            )
            let maxRadius = cluster.map { loc in
                loc.distance(from: centroidLocation)
            }.max() ?? 0
            
            // 🆕 IMPROVED MOVEMENT DETECTION
            // Calculate movement rate (meters per minute)
            let durationMinutes = duration / 60.0
            let movementRate = totalPathDistance / durationMinutes
            let distances = cleanedCluster.map { $0.distance(from: centroidLocation) }
            let avgDistance = distances.reduce(0, +) / Double(distances.count)
            let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Double(distances.count)
            let spread = sqrt(variance)
            
            let isRandomDrift = detectRandomGPSDrift(cleanedCluster)

            if isRandomDrift {
                print("🎲 Detected random GPS drift pattern - treating as stationary")
            }
            
            // Different thresholds based on duration AND spread:
            let movementThreshold: Double
            if isRandomDrift {
                // Random GPS drift gets very lenient threshold
                movementThreshold = 80.0 // Allow up to 80 m/min for drift
            } else if durationMinutes < 10 {
                // Very short stops (5-10 min): Lenient
                movementThreshold = 20.0
            } else if durationMinutes < 20 {
                // Short stops (10-20 min): Adaptive based on spread
                if spread < 15 {
                    movementThreshold = 14.0
                } else if spread < 50 {
                    movementThreshold = 20.0
                } else {
                    movementThreshold = 25.0
                }
            } else {
                // Long stops (20+ min): Strict
                movementThreshold = 10.0
            }

            if movementRate > movementThreshold {
                print("⚠️ Rejected cluster: duration=\(Int(durationMinutes))min, movement=\(String(format: "%.1f", movementRate))m/min (threshold=\(String(format: "%.1f", movementThreshold)), spread=\(Int(spread))m)")
                continue
            }
            
            print("✅ Accepted cluster: duration=\(Int(durationMinutes))min, movement=\(String(format: "%.1f", movementRate))m/min, radius=\(Int(maxRadius))m")
            
            // Calculate confidence based on accuracy
            let avgAccuracy = cluster.map { $0.horizontalAccuracy }.reduce(0, +) / Double(cluster.count)
            let confidence: DwellConfidence
            if cluster.count >= 5 && avgAccuracy < 20 {
                confidence = .high
            } else if avgAccuracy < 50 {
                confidence = .medium
            } else {
                confidence = .low
            }
            
            let dwell = DwellPoint(
                location: centroid,
                startTime: first.timestamp,
                endTime: last.timestamp,
                confidence: confidence
            )
            
            dwells.append(dwell)
        }

        return dwells
    }
    
    // MARK: - Detect Random GPS Drift
    private func detectRandomGPSDrift(_ locations: [CLLocation]) -> Bool {
        guard locations.count >= 10 else { return false }
        
        // Calculate net displacement vs total path distance
        guard let first = locations.first,
              let last = locations.last else { return false }
        
        let netDisplacement = first.distance(from: last)
        
        var totalPathDistance: CLLocationDistance = 0
        for i in 1..<locations.count {
            totalPathDistance += locations[i].distance(from: locations[i-1])
        }
        
        // If path distance is much larger than net displacement, it's random movement
        // Walking: path=1000m, net=800m (ratio=1.25)
        // Random drift: path=3000m, net=50m (ratio=60)
        let ratio = totalPathDistance / max(netDisplacement, 1)
        
        // Also check if average accuracy is poor (>30m)
        let avgAccuracy = locations.map { $0.horizontalAccuracy }.reduce(0, +) / Double(locations.count)
        
        let isDrift = ratio > 20 && avgAccuracy > 30
        
        if isDrift {
            print("   Path/Net ratio: \(String(format: "%.1f", ratio)), Avg accuracy: \(Int(avgAccuracy))m")
        }
        
        return isDrift
    }
    
    private func calculateCentroid(of locations: [CLLocation]) -> CLLocationCoordinate2D {
        guard !locations.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
        
        for location in locations {
            let lat = location.coordinate.latitude * .pi / 180
            let lon = location.coordinate.longitude * .pi / 180
            
            x += cos(lat) * cos(lon)
            y += cos(lat) * sin(lon)
            z += sin(lat)
        }
        
        let count = Double(locations.count)
        x /= count
        y /= count
        z /= count
        
        let lon = atan2(y, x)
        let hyp = sqrt(x * x + y * y)
        let lat = atan2(z, hyp)
        
        return CLLocationCoordinate2D(
            latitude: lat * 180 / .pi,
            longitude: lon * 180 / .pi
        )
    }
    
    // MARK: - Revisit Detection
    private func detectRevisits(in session: NightSession) async {
        let revisitThreshold: CLLocationDistance = 35.0
        
        await MainActor.run {
            for i in 0..<session.dwells.count {
                for j in 0..<i {
                    let current = session.dwells[i]
                    let previous = session.dwells[j]
                    
                    let currentLoc = CLLocation(
                        latitude: current.location.latitude,
                        longitude: current.location.longitude
                    )
                    let previousLoc = CLLocation(
                        latitude: previous.location.latitude,
                        longitude: previous.location.longitude
                    )
                    
                    if currentLoc.distance(from: previousLoc) < revisitThreshold {
                        session.dwells[i].isRevisit = true
                        session.dwells[i].revisitOfId = previous.id
                        break
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
    
    private func isLocationValid(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 &&
              location.horizontalAccuracy <= maxAccuracyMeters else {
            return false
        }
        
        guard location.timestamp.timeIntervalSinceNow > -maxLocationAgeSeconds else {
            return false
        }
        
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            return false
        }
        
        return true
    }
    
    private func printNightSummary(session: NightSession) {
        let duration = session.duration ?? 0
        
        print("\n" + String(repeating: "=", count: 50))
        print("🌙 NIGHT OUT SUMMARY")
        print(String(repeating: "=", count: 50))
        print("⏱️  Duration: \(formatDuration(duration))")
        print("📏 Distance: \(String(format: "%.2f", session.totalDistance / 1000))km")
        print("📍 Locations tracked: \(session.route.count)")
        print("🍺 Stops detected: \(session.dwells.count)")
        
        if !session.dwells.isEmpty {
            print("\n📊 Stop Breakdown:")
            let grouped = Dictionary(grouping: session.dwells) { $0.dwellType }
            
            for type in [DwellType.passthrough, .quickStop, .shortVisit, .longStop, .marathon] {
                if let count = grouped[type]?.count, count > 0 {
                    print("   \(type.rawValue): \(count)")
                }
            }
            
            if let longest = session.dwells.max(by: { $0.duration < $1.duration }) {
                print("\n⭐ Longest stop: \(formatDuration(longest.duration))")
            }
            
            let revisits = session.dwells.filter { $0.isRevisit }
            if !revisits.isEmpty {
                print("🔄 Revisited venues: \(revisits.count)")
            }
        }
        
        print(String(repeating: "=", count: 50) + "\n")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Live Activity Updates
    private func startLiveActivityUpdateTimer() {
        guard #available(iOS 16.2, *) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.liveActivityUpdateTimer?.invalidate()
            self?.liveActivityUpdateTimer = Timer.scheduledTimer(
                withTimeInterval: 60,
                repeats: true
            ) { [weak self] _ in
                self?.updateLiveActivity()
            }
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
        guard let session = currentSession, isTracking else { return }
        
        let distance = session.totalDistance
        let stops = session.dwells.count
        let drinks = session.drinks.total
        let elapsed = Date().timeIntervalSince(session.startTime)
        
        LiveActivityManager.shared.updateActivity(
            distance: distance,
            stops: stops,
            drinks: drinks,
            elapsedTime: elapsed
        )
    }
    
    // MARK: - Test Simulation Suite
#if DEBUG
    func runAllTests() async {
        print("\n🧪 RUNNING COMPREHENSIVE TEST SUITE ALTERNATIVE MIN POINTS 5\n")
        
        await testGymWithGPSBlackout()
        await testPubCrawl()
        await testQuickCoffeeStop()
        await testLongBarSession()
        await testWalkingOnlyNoStops()
        await testRevisitSameVenue()
        await testAdjacentVenues()
        await testCrowdedAreaNavigation()
        await testVehicleRide()
        await testOutdoorToIndoorTransition()
        await testExtremeGPSDrift()
        
        print("\n" + String(repeating: "=", count: 60))
        print("📊 TEST SUITE COMPLETE")
        print(String(repeating: "=", count: 60))
        print("Check results above. All tests should PASS.")
        print(String(repeating: "=", count: 60) + "\n")
        
        await MainActor.run {
            self.currentSession = nil
            print("🧹 Test cleanup complete")
        }
    }
    

    // Test 1: Gym with GPS blackout
    func testGymWithGPSBlackout() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 1: GYM WITH GPS BLACKOUT")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        
        // Walk to gym (5 minutes, moving continuously)
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.0002,
                    longitude: -2.7500 + Double(i) * 0.0002
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(Double(i * 30))
            ))
        }
        
        // Gym arrival
        let gymLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.4320, longitude: -2.7520),
            altitude: 0,
            horizontalAccuracy: 18,
            verticalAccuracy: 10,
            timestamp: baseTime.addingTimeInterval(300)
        )
        testLocations.append(gymLoc)
        
        // GPS blackout for 75 minutes
        
        // Gym exit
        testLocations.append(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.4321, longitude: -2.7521),
            altitude: 0,
            horizontalAccuracy: 45,
            verticalAccuracy: 15,
            timestamp: baseTime.addingTimeInterval(4800) // 75 min gap
        ))
        
        // Walk home (5 minutes)
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4321 - Double(i) * 0.0002,
                    longitude: -2.7521 - Double(i) * 0.0002
                ),
                altitude: 0,
                horizontalAccuracy: 20,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(4800 + Double(i * 30))
            ))
        }
        
        // Home - stationary for 15 minutes (30 points with minimal movement)
        let homeLat = 53.4301
        let homeLon = -2.7501
        print("🏠 Generating home cluster at \(homeLat), \(homeLon)...")
        for i in 0..<40 { // Increased from 30 to 40 points
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: homeLat + Double.random(in: -0.000008...0.000008), // Tighter radius (was 0.00001)
                    longitude: homeLon + Double.random(in: -0.000008...0.000008)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 8...15), // Better accuracy
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(5100 + Double(i * 25)) // Every 25s instead of 30s
            ))
        }
        print("🏠 Home cluster: 40 points over \(40 * 25 / 60) minutes")
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 2, testName: "Gym+Home")
    }

    // Test 2: Pub crawl with multiple stops
    func testPubCrawl() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 2: PUB CRAWL (3 VENUES)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        var currentTime = 0.0
        
        // Pub 1: 45 minutes
        for i in 0..<90 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double.random(in: -0.00002...0.00002),
                    longitude: -2.7500 + Double.random(in: -0.00002...0.00002)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 90 * 30
        
        // Walk to Pub 2 (3 minutes)
        for i in 0..<6 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.0003,
                    longitude: -2.7500 + Double(i) * 0.0003
                ),
                altitude: 0,
                horizontalAccuracy: 20,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 6 * 30
        
        // Pub 2: 30 minutes
        for i in 0..<60 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4318 + Double.random(in: -0.00002...0.00002),
                    longitude: -2.7518 + Double.random(in: -0.00002...0.00002)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 60 * 30
        
        // Walk to Pub 3 (2 minutes)
        for i in 0..<4 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4318 + Double(i) * 0.0002,
                    longitude: -2.7518 - Double(i) * 0.0002
                ),
                altitude: 0,
                horizontalAccuracy: 20,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 4 * 30
        
        // Pub 3: 60 minutes
        for i in 0..<120 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4326 + Double.random(in: -0.00002...0.00002),
                    longitude: -2.7510 + Double.random(in: -0.00002...0.00002)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 3, testName: "Pub Crawl")
    }

    // Test 3: Quick coffee stop
    func testQuickCoffeeStop() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 3: QUICK COFFEE (8 MINUTES)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        
        // Walking
        for i in 0..<5 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.0002,
                    longitude: -2.7500
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(Double(i * 30))
            ))
        }
        
        // Coffee shop: 8 minutes (should be detected as "passthrough")
        for i in 0..<16 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4310 + Double.random(in: -0.00001...0.00001),
                    longitude: -2.7500 + Double.random(in: -0.00001...0.00001)
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(150 + Double(i * 30))
            ))
        }
        
        // Continue walking
        for i in 0..<5 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4310 + Double(i) * 0.0002,
                    longitude: -2.7500
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(630 + Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 1, testName: "Quick Coffee")
    }

    // Test 4: Long bar session (2+ hours)
    func testLongBarSession() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 4: MARATHON BAR SESSION (150 MINUTES)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        
        // Bar: 150 minutes (300 points)
        for i in 0..<300 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double.random(in: -0.00003...0.00003),
                    longitude: -2.7500 + Double.random(in: -0.00003...0.00003)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...30),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 1, testName: "Marathon Session")
    }

    // Test 5: Walking only (should detect 0 dwells)
    func testWalkingOnlyNoStops() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 5: WALKING ONLY (NO STOPS)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        
        // Continuous walking for 30 minutes
        for i in 0..<60 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.0003,
                    longitude: -2.7500 + Double(i) * 0.0002
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 0, testName: "Walking Only")
    }
    
    // MARK: - Additional Edge Case Tests

    // Test 6: Revisit same venue twice in one night (should detect 2 separate dwells)
    func testRevisitSameVenue() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 6: REVISIT SAME PUB TWICE")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        var currentTime = 0.0
        
        // Pub 1 - First visit: 45 minutes
        print("🍺 First visit to Pub 1...")
        for i in 0..<90 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double.random(in: -0.00002...0.00002),
                    longitude: -2.7500 + Double.random(in: -0.00002...0.00002)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 90 * 30
        
        // Walk to Pub 2 (5 minutes, 400m away)
        print("🚶 Walking to Pub 2...")
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.0005,
                    longitude: -2.7500 + Double(i) * 0.0005
                ),
                altitude: 0,
                horizontalAccuracy: 20,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 10 * 30
        
        // Pub 2: 30 minutes
        print("🍺 Visit to Pub 2...")
        for i in 0..<60 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4350 + Double.random(in: -0.00002...0.00002),
                    longitude: -2.7550 + Double.random(in: -0.00002...0.00002)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 60 * 30
        
        // Walk back to Pub 1 (5 minutes)
        print("🚶 Walking back to Pub 1...")
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4350 - Double(i) * 0.0005,
                    longitude: -2.7550 - Double(i) * 0.0005
                ),
                altitude: 0,
                horizontalAccuracy: 20,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 10 * 30
        
        // Pub 1 - Second visit: 60 minutes (IMPORTANT: Should be separate dwell)
        print("🍺 Second visit to Pub 1...")
        for i in 0..<120 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double.random(in: -0.00002...0.00002),
                    longitude: -2.7500 + Double.random(in: -0.00002...0.00002)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...25),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 3, testName: "Revisit Same Venue")
    }

    // Test 7: Two bars very close together (<50m apart)
    func testAdjacentVenues() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 7: TWO ADJACENT BARS (40M APART)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        var currentTime = 0.0
        
        // Bar A: 40 minutes
        print("🍺 Bar A...")
        for i in 0..<80 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double.random(in: -0.00001...0.00001),
                    longitude: -2.7500 + Double.random(in: -0.00001...0.00001)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...20),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 80 * 30
        
        // Walk 40m to Bar B (takes 30 seconds)
        print("🚶 Walking 40m to Bar B...")
        testLocations.append(CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 53.4300,
                longitude: -2.7500
            ),
            altitude: 0,
            horizontalAccuracy: 15,
            verticalAccuracy: 10,
            timestamp: baseTime.addingTimeInterval(currentTime)
        ))
        
        testLocations.append(CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 53.43036, // ~40m north
                longitude: -2.7500
            ),
            altitude: 0,
            horizontalAccuracy: 15,
            verticalAccuracy: 10,
            timestamp: baseTime.addingTimeInterval(currentTime + 30)
        ))
        currentTime += 30
        
        // Bar B: 50 minutes
        print("🍺 Bar B...")
        for i in 0..<100 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.43036 + Double.random(in: -0.00001...0.00001),
                    longitude: -2.7500 + Double.random(in: -0.00001...0.00001)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 10...20),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 2, testName: "Adjacent Venues")
    }

    // Test 8: Walking through crowded area with brief stops
    func testCrowdedAreaNavigation() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 8: CROWDED AREA WITH BRIEF STOPS")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        var currentTime = 0.0
        
        // Walk 100m
        print("🚶 Walking...")
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.0001,
                    longitude: -2.7500
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 10 * 30
        
        // Stop 1: 2 minutes (too short)
        print("⏸️ Brief stop 1 (2 min)...")
        for i in 0..<4 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4310 + Double.random(in: -0.00001...0.00001),
                    longitude: -2.7500 + Double.random(in: -0.00001...0.00001)
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 4 * 30
        
        // Walk another 100m
        print("🚶 Walking...")
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4310 + Double(i) * 0.0001,
                    longitude: -2.7500
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 10 * 30
        
        // Stop 2: 3 minutes (too short)
        print("⏸️ Brief stop 2 (3 min)...")
        for i in 0..<6 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4320 + Double.random(in: -0.00001...0.00001),
                    longitude: -2.7500 + Double.random(in: -0.00001...0.00001)
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 6 * 30
        
        // Walk final 100m
        print("🚶 Walking...")
        for i in 0..<10 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4320 + Double(i) * 0.0001,
                    longitude: -2.7500
                ),
                altitude: 0,
                horizontalAccuracy: 15,
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 0, testName: "Crowded Area")
    }

    // Test 9: Uber/taxi ride (extended movement at vehicle speeds)
    func testVehicleRide() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 9: UBER RIDE (SHOULD NOT DETECT)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        
        // 15-minute car ride at ~40 km/h (667 m/min)
        print("🚗 Uber ride...")
        for i in 0..<30 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double(i) * 0.001, // Moving ~111m per step
                    longitude: -2.7500 + Double(i) * 0.001
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 15...30),
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 0, testName: "Vehicle Ride")
    }

    // Test 10: Sitting outside (smoking area, patio) then going inside
    func testOutdoorToIndoorTransition() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 10: OUTDOOR PATIO → INDOOR BAR")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        var currentTime = 0.0
        
        // Outside on patio: 15 minutes (good GPS)
        print("🌤️ Sitting outside on patio...")
        for i in 0..<30 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.4300 + Double.random(in: -0.00001...0.00001),
                    longitude: -2.7500 + Double.random(in: -0.00001...0.00001)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 5...15), // Good accuracy outside
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        currentTime += 30 * 30
        
        // Walk inside (5m, 10 seconds)
        print("🚶 Walking inside...")
        testLocations.append(CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 53.43005,
                longitude: -2.75005
            ),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: baseTime.addingTimeInterval(currentTime)
        ))
        currentTime += 10
        
        // Inside bar: 45 minutes (worse GPS, some drift)
        print("🏠 Inside bar...")
        for i in 0..<90 {
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 53.43005 + Double.random(in: -0.00003...0.00003), // More drift
                    longitude: -2.75005 + Double.random(in: -0.00003...0.00003)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 20...50), // Worse accuracy inside
                verticalAccuracy: 10,
                timestamp: baseTime.addingTimeInterval(currentTime + Double(i * 30))
            ))
        }
        
        // Should detect as 1 dwell (same venue, patio and indoor should merge)
        await runTest(session: testSession, locations: testLocations, expectedDwells: 1, testName: "Outdoor→Indoor")
    }

    // Test 11: GPS drift while stationary (worst case)
    func testExtremeGPSDrift() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST 11: EXTREME GPS DRIFT (UNDERGROUND BAR)")
        print(String(repeating: "=", count: 60))
        
        let testSession = NightSession()
        let baseTime = Date().addingTimeInterval(-7200)
        var testLocations: [CLLocation] = []
        
        // 60 minutes stationary but GPS drifts wildly within 50m radius
        print("📍 Stationary with extreme GPS drift...")
        let centerLat = 53.4300
        let centerLon = -2.7500
        
        for i in 0..<120 {
            // Random walk within 50m radius
            let angle = Double.random(in: 0...(2 * .pi))
            let radius = Double.random(in: 0...0.0005) // ~50m
            
            testLocations.append(CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: centerLat + radius * cos(angle),
                    longitude: centerLon + radius * sin(angle)
                ),
                altitude: 0,
                horizontalAccuracy: Double.random(in: 30...65), // Poor accuracy
                verticalAccuracy: 15,
                timestamp: baseTime.addingTimeInterval(Double(i * 30))
            ))
        }
        
        await runTest(session: testSession, locations: testLocations, expectedDwells: 1, testName: "Extreme GPS Drift")
    }

    // Helper function to run tests
    private func runTest(session: NightSession, locations: [CLLocation], expectedDwells: Int, testName: String) async {
//        session.isTestMode = true  // ← Add this
        
        for loc in locations {
            session.addLocation(loc)
        }
        
//        session.finalizeRoute(skipSimplification: true) // ← Add flag
        
        print("\n📊 Test data: \(locations.count) locations over \(Int(locations.last!.timestamp.timeIntervalSince(locations.first!.timestamp) / 60)) minutes")
        
        try? await self.processSessionData(session)
        
        await MainActor.run {
            let actual = session.dwells.count
            let passed = actual == expectedDwells
            
            print("\n" + String(repeating: "-", count: 60))
            print(passed ? "✅ PASS" : "❌ FAIL")
            print("Expected: \(expectedDwells) dwells | Got: \(actual) dwells")
            
            if !session.dwells.isEmpty {
                print("\nDetected dwells:")
                for (i, dwell) in session.dwells.enumerated() {
                    print("  \(i+1). \(dwell.dwellType.rawValue) - \(Int(dwell.duration/60))min (\(dwell.confidence.rawValue))")
                }
            }
            print(String(repeating: "-", count: 60))
        }
    }
    #endif
}


class RouteSimplifier {
    /// Simplify a route using the Douglas-Peucker algorithm
    /// - Parameters:
    ///   - locations: Array of CLLocation points to simplify
    ///   - tolerance: Distance tolerance in meters (higher = more aggressive simplification)
    /// - Returns: Simplified array of locations
    static func simplify(locations: [CLLocation], tolerance: Double = 10.0) -> [CLLocation] {
        guard locations.count > 2 else { return locations }
        
        return douglasPeucker(points: locations, tolerance: tolerance)
    }
    
    private static func douglasPeucker(points: [CLLocation], tolerance: Double) -> [CLLocation] {
        guard points.count > 2 else { return points }
        
        guard let first = points.first, let last = points.last else { return points }
        
        var maxDistance = 0.0
        var maxIndex = 0
        
        // Find the point with maximum distance from the line between first and last
        for i in 1..<(points.count - 1) {
            let distance = perpendicularDistance(point: points[i], lineStart: first, lineEnd: last)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }
        
        // If max distance is greater than tolerance, recursively simplify
        if maxDistance > tolerance {
            let leftPoints = douglasPeucker(points: Array(points[0...maxIndex]), tolerance: tolerance)
            let rightPoints = douglasPeucker(points: Array(points[maxIndex..<points.count]), tolerance: tolerance)
            
            // Combine results (remove duplicate middle point)
            return leftPoints.dropLast() + rightPoints
        } else {
            // All points are within tolerance, return just the endpoints
            return [first, last]
        }
    }
    
    
    
    private static func perpendicularDistance(point: CLLocation, lineStart: CLLocation, lineEnd: CLLocation) -> Double {
        let x0 = point.coordinate.latitude
        let y0 = point.coordinate.longitude
        let x1 = lineStart.coordinate.latitude
        let y1 = lineStart.coordinate.longitude
        let x2 = lineEnd.coordinate.latitude
        let y2 = lineEnd.coordinate.longitude
        
        let dx = x2 - x1
        let dy = y2 - y1
        
        // Calculate the perpendicular distance from point to line
        let norm = sqrt(dx * dx + dy * dy)
        guard norm > 0 else {
            // If start and end are the same point, return distance to that point
            return point.distance(from: lineStart)
        }
        
        // Formula: |dy*x0 - dx*y0 + x2*y1 - y2*x1| / norm
        let numerator = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1)
        
        // Convert to meters (approximate conversion at typical latitudes)
        return (numerator / norm) * 111_000
    }
}
