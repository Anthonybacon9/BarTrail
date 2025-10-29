import Foundation
import CoreLocation
import Combine

extension Date {
    var year: Int {
        return Calendar.current.component(.year, from: self)
    }
}

// MARK: - Dwell Point Model (Updated)
struct DwellPoint: Codable, Identifiable {
    let id: UUID
    let location: CLLocationCoordinate2D
    let startTime: Date
    let endTime: Date
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    var placeName: String? // Auto-detected name
    var manualPlaceName: String? // User's manual override
    var suggestedPlaces: [String]? // Nearby alternatives for selection
    
    // This is what should be displayed - prioritizes manual selection
    var displayName: String? {
        manualPlaceName ?? placeName
    }
    
    // Check if this was manually corrected
    var isManuallySet: Bool {
        manualPlaceName != nil
    }
    
    init(id: UUID = UUID(), location: CLLocationCoordinate2D, startTime: Date, endTime: Date) {
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
        self.placeName = nil
        self.manualPlaceName = nil
        self.suggestedPlaces = nil
    }
    
    // Custom Codable implementation for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, startTime, endTime, placeName, manualPlaceName, suggestedPlaces
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
        manualPlaceName = try container.decodeIfPresent(String.self, forKey: .manualPlaceName)
        suggestedPlaces = try container.decodeIfPresent([String].self, forKey: .suggestedPlaces)
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
    }
}


