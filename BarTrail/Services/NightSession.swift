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

struct DrinkCount: Codable {
    var beer: Int = 0
    var spirits: Int = 0
    var cocktails: Int = 0
    var shots: Int = 0
    var wine: Int = 0
    var other: Int = 0
    
    var total: Int {
        beer + spirits + cocktails + shots + wine + other
    }
}

enum DrinkType: String, CaseIterable {
    case beer = "Beer"
    case spirits = "Spirits"
    case cocktails = "Cocktails"
    case shots = "Shots"
    case wine = "Wine"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .beer: return "🍺"
        case .spirits: return "🍾"
        case .cocktails: return "🍹"
        case .shots: return "🥃"
        case .wine: return "🍷"
        case .other: return "🧃"
        }
    }
}

// MARK: - Night Session Model
class NightSession: Codable, Identifiable, ObservableObject {
    let id: UUID
    let startTime: Date
    @Published var endTime: Date?
    @Published var route: [CLLocation]
    @Published var dwells: [DwellPoint]
    @Published var rating: Int? // 1-5 star rating
    @Published var drinks: DrinkCount = DrinkCount()
    
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
    
    func addDrink(type: DrinkType) {
        switch type {
        case .beer: drinks.beer += 1
        case .spirits: drinks.spirits += 1
        case .cocktails: drinks.cocktails += 1
        case .shots: drinks.shots += 1
        case .wine: drinks.wine += 1
        case .other: drinks.other += 1
        }
        
        // Update Live Activity immediately when drink added
            if #available(iOS 16.2, *) {
                DispatchQueue.main.async {
                    LiveActivityManager.shared.updateActivity(
                        distance: SessionManager.shared.currentSession?.totalDistance ?? 0,
                        stops: SessionManager.shared.currentSession?.dwells.count ?? 0,
                        drinks: self.drinks.total,
                        elapsedTime: Date().timeIntervalSince(self.startTime)
                    )
                }
            }
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
        case id, startTime, endTime, route, dwells, rating, drinks
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        drinks = try container.decodeIfPresent(DrinkCount.self, forKey: .drinks) ?? DrinkCount()
        
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
        try container.encode(drinks, forKey: .drinks)
        
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
