import Foundation
import CoreLocation
import Combine

extension Date {
    var year: Int {
        return Calendar.current.component(.year, from: self)
    }
}

// MARK: - Dwell Types & Confidence (from SessionManager)
enum DwellType: String, Codable {
    case passthrough = "Passed through"    // 5-10 minutes
    case quickStop = "Quick stop"          // 10-20 minutes
    case shortVisit = "Short visit"        // 20-40 minutes
    case longStop = "Settled in"           // 40-60 minutes
    case marathon = "Long session"         // 60+ minutes
    
    var icon: String {
        switch self {
        case .passthrough: return "🚶"
        case .quickStop: return "☕️"
        case .shortVisit: return "🍺"
        case .longStop: return "🍻"
        case .marathon: return "🎉"
        }
    }
    
    var color: String {
        switch self {
        case .passthrough: return "gray"
        case .quickStop: return "orange"
        case .shortVisit: return "blue"
        case .longStop: return "purple"
        case .marathon: return "pink"
        }
    }
    
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
    case high = "High"          // <20m accuracy, 5+ samples
    case medium = "Medium"      // 20-50m accuracy
    case low = "Low"            // 50-100m accuracy or few samples
    case estimated = "Estimated" // From Apple Visit API or poor GPS
    
    var icon: String {
        switch self {
        case .high: return "⭐⭐⭐"
        case .medium: return "⭐⭐"
        case .low: return "⭐"
        case .estimated: return "📍"
        }
    }
}

// MARK: - Enhanced Dwell Point Model
struct DwellPoint: Codable, Identifiable, Equatable {
    let id: UUID
    let location: CLLocationCoordinate2D
    let startTime: Date
    var endTime: Date // Mutable to allow updates while active
    
    // 🆕 New properties for enhanced tracking
    var confidence: DwellConfidence
    var isRevisit: Bool
    var revisitOfId: UUID?
    
    // Venue naming
    var placeName: String?           // Auto-detected name
    var manualPlaceName: String?     // User's manual override
    var suggestedPlaces: [String]?   // Nearby alternatives for selection
    
    // MARK: - Computed Properties
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    // Tiered dwell type based on duration
    var dwellType: DwellType {
        DwellType.from(duration: duration)
    }
    
    // This is what should be displayed - prioritizes manual selection
    var displayName: String? {
        manualPlaceName ?? placeName
    }
    
    // Check if this was manually corrected
    var isManuallySet: Bool {
        manualPlaceName != nil
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        location: CLLocationCoordinate2D,
        startTime: Date,
        endTime: Date,
        confidence: DwellConfidence = .medium,
        isRevisit: Bool = false,
        revisitOfId: UUID? = nil
    ) {
        // Validate dates are reasonable
        let currentYear = Calendar.current.component(.year, from: Date())
        
        guard startTime < endTime else {
            fatalError("DwellPoint: startTime must be before endTime")
        }
        
        guard startTime.year <= currentYear + 1 && endTime.year <= currentYear + 1 else {
            fatalError("DwellPoint: dates are too far in the future")
        }
        
        guard startTime.year >= 2020 else {
            fatalError("DwellPoint: dates are too far in the past")
        }
        
        self.id = id
        self.location = location
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isRevisit = isRevisit
        self.revisitOfId = revisitOfId
        self.placeName = nil
        self.manualPlaceName = nil
        self.suggestedPlaces = nil
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, startTime, endTime
        case placeName, manualPlaceName, suggestedPlaces
        case confidence, isRevisit, revisitOfId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        
        // Legacy support - old saves won't have these
        placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
        manualPlaceName = try container.decodeIfPresent(String.self, forKey: .manualPlaceName)
        suggestedPlaces = try container.decodeIfPresent([String].self, forKey: .suggestedPlaces)
        
        // 🆕 New properties with defaults for backward compatibility
        confidence = try container.decodeIfPresent(DwellConfidence.self, forKey: .confidence) ?? .medium
        isRevisit = try container.decodeIfPresent(Bool.self, forKey: .isRevisit) ?? false
        revisitOfId = try container.decodeIfPresent(UUID.self, forKey: .revisitOfId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(location.latitude, forKey: .latitude)
        try container.encode(location.longitude, forKey: .longitude)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encodeIfPresent(placeName, forKey: .placeName)
        try container.encodeIfPresent(manualPlaceName, forKey: .manualPlaceName)
        try container.encodeIfPresent(suggestedPlaces, forKey: .suggestedPlaces)
        
        // 🆕 Encode new properties
        try container.encode(confidence, forKey: .confidence)
        try container.encode(isRevisit, forKey: .isRevisit)
        try container.encodeIfPresent(revisitOfId, forKey: .revisitOfId)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: DwellPoint, rhs: DwellPoint) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helper Extensions

extension DwellPoint {
    /// Get a user-friendly description of the dwell
    var summary: String {
        let type = dwellType.rawValue
        let duration = formatDuration(self.duration)
        let name = displayName ?? "Unknown Location"
        return "\(type) at \(name) (\(duration))"
    }
    
    /// Format duration for display
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Check if this dwell is near another dwell (for revisit detection)
    func isNear(_ other: DwellPoint, threshold: Double = 35.0) -> Bool {
        let thisLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let otherLoc = CLLocation(latitude: other.location.latitude, longitude: other.location.longitude)
        return thisLoc.distance(from: otherLoc) < threshold
    }
}

// MARK: - Collection Extensions

extension Array where Element == DwellPoint {
    /// Group dwells by type
    func groupedByType() -> [DwellType: [DwellPoint]] {
        Dictionary(grouping: self) { $0.dwellType }
    }
    
    /// Get total time spent at dwells
    var totalDuration: TimeInterval {
        reduce(0) { $0 + $1.duration }
    }
    
    /// Get only revisits
    var revisits: [DwellPoint] {
        filter { $0.isRevisit }
    }
    
    /// Get unique venues (non-revisits only)
    var uniqueVenues: [DwellPoint] {
        filter { !$0.isRevisit }
    }
    
    /// Find the longest dwell
    var longestDwell: DwellPoint? {
        self.max(by: { $0.duration < $1.duration })
    }
}
