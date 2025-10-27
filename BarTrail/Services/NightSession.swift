//
//  NightSession.swift
//  BarTrail
//
//  Created by Anthony Bacon on 27/10/2025.
//

import Combine
import SwiftUI
import Foundation
import CoreLocation

// MARK: - Night Session Model
class NightSession: Codable, Identifiable, ObservableObject {
    let id: UUID
    let startTime: Date
    @Published var endTime: Date?
    @Published var route: [CLLocation]
    @Published var dwells: [DwellPoint]
    @Published var rating: Int? // 1-5 star rating
    
    var isActive: Bool {
        endTime == nil
    }
    
    var duration: TimeInterval? {
        guard let end = endTime else {
            // If session is active, calculate duration from start to now
            return Date().timeIntervalSince(startTime)
        }
        return end.timeIntervalSince(startTime)
    }
    
    var totalDistance: CLLocationDistance {
        guard route.count > 1 else { return 0 }
        var distance: CLLocationDistance = 0
        for i in 1..<route.count {
            distance += route[i].distance(from: route[i-1])
        }
        return distance
    }
    
    init(id: UUID = UUID(), startTime: Date = Date()) {
        self.id = id
        self.startTime = startTime
        self.endTime = nil
        self.route = []
        self.dwells = []
        self.rating = nil
    }
    
    func end() {
        endTime = Date()
    }
    
    func addLocation(_ location: CLLocation) {
        route.append(location)
    }
    
    func addDwell(_ dwell: DwellPoint) {
        dwells.append(dwell)
    }
    
    func setRating(_ stars: Int) {
        rating = min(max(stars, 1), 5) // Clamp between 1-5
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, route, dwells, rating
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        
        // Decode route as array of coordinate dictionaries
        let routeData = try container.decode([[String: Double]].self, forKey: .route)
        route = routeData.compactMap { dict in
            guard let lat = dict["latitude"],
                  let lon = dict["longitude"],
                  let timestamp = dict["timestamp"] else { return nil }
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: 0,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
        }
        
        dwells = try container.decode([DwellPoint].self, forKey: .dwells)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(rating, forKey: .rating)
        
        // Encode route as array of coordinate dictionaries
        let routeData = route.map { location in
            [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "timestamp": location.timestamp.timeIntervalSince1970
            ]
        }
        try container.encode(routeData, forKey: .route)
        try container.encode(dwells, forKey: .dwells)
    }
}
