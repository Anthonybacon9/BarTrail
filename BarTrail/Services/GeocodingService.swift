//
//  GeocodingService.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import Foundation
import CoreLocation
import MapKit

class GeocodingService {
    static let shared = GeocodingService()
    
    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]
    
    private init() {}
    
    // MARK: - Improved Venue Name Detection
    
    func getBestVenueName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let cacheKey = "\(coordinate.latitude),\(coordinate.longitude)"
        
        // Check cache first
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Strategy 1: Try MKLocalSearch for nearby venues (most reliable for business names)
        if let venueName = await searchForVenueName(coordinate: coordinate) {
            cache[cacheKey] = venueName
            print("✅ Found venue via local search: \(venueName)")
            return venueName
        }
        
        // Strategy 2: Try reverse geocoding with improved POI detection
        if let poiName = await getPOIName(for: coordinate) {
            cache[cacheKey] = poiName
            print("✅ Found venue via POI detection: \(poiName)")
            return poiName
        }
        
        // Strategy 3: Last resort - use address but prefer locality over street
        if let addressName = await getAddressName(for: coordinate) {
            cache[cacheKey] = addressName
            print("⚠️ Using address name: \(addressName)")
            return addressName
        }
        
        print("❌ No venue name found for coordinate: \(coordinate)")
        return nil
    }
    
    // MARK: - Improved Local Search
    
    private func searchForVenueName(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 50) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Try multiple search categories
        let categories = [
            "restaurant", "bar", "pub", "club", "cafe", "nightclub",
            "brewery", "lounge", "hotel", "store", "shop", "mall"
        ]
        
        for category in categories {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = category
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )
            request.resultTypes = [.pointOfInterest]
            
            let search = MKLocalSearch(request: request)
            
            do {
                let response = try await search.start()
                
                // Find the closest place within radius
                let sortedPlaces = response.mapItems.sorted { place1, place2 in
                    let dist1 = place1.placemark.location?.distance(from: location) ?? Double.greatestFiniteMagnitude
                    let dist2 = place2.placemark.location?.distance(from: location) ?? Double.greatestFiniteMagnitude
                    return dist1 < dist2
                }
                
                if let closest = sortedPlaces.first,
                   let placeLocation = closest.placemark.location,
                   placeLocation.distance(from: location) <= radius,
                   let name = closest.name,
                   !name.isEmpty {
                    return name
                }
            } catch {
                continue // Try next category
            }
        }
        
        return nil
    }
    
    // MARK: - Improved POI Name Detection
    
    private func getPOIName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US"))
            
            guard let placemark = placemarks.first else {
                return nil
            }
            
            // Priority 1: Areas of Interest (most likely business names)
            if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                return areasOfInterest.first
            }
            
            // Priority 2: Name field (if it's not just an address component)
            if let name = placemark.name,
               isValidBusinessName(name, placemark: placemark) {
                return name
            }
            
            // Priority 3: Check if this is a point of interest
            if placemark.administrativeArea != nil || placemark.locality != nil {
                // This might be a significant location, use the most specific name available
                if let name = placemark.name, !name.isEmpty {
                    return name
                }
            }
            
            return nil
        } catch {
            print("❌ POI detection error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Address Name (fallback)
    
    private func getAddressName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                return nil
            }
            
            // Prefer locality/subLocality over street address
            if let locality = placemark.locality {
                if let subLocality = placemark.subLocality, subLocality != locality {
                    return "\(subLocality), \(locality)"
                }
                return locality
            }
            
            // Fallback to thoroughfare
            return placemark.thoroughfare ?? "Unknown Location"
        } catch {
            return nil
        }
    }
    
    // MARK: - Business Name Validation
    
    private func isValidBusinessName(_ name: String, placemark: CLPlacemark) -> Bool {
        // Exclude generic address components
        let excludedPatterns = [
            placemark.thoroughfare,
            placemark.subThoroughfare,
            "\(placemark.subThoroughfare ?? "") \(placemark.thoroughfare ?? "")"
        ].compactMap { $0 }
        
        for pattern in excludedPatterns {
            if name == pattern || name.contains(pattern) {
                return false
            }
        }
        
        // Additional checks
        guard name.count > 3 else { return false }
        guard !name.contains("Street") else { return false }
        guard !name.contains("Avenue") else { return false }
        guard !name.contains("Road") else { return false }
        guard !name.contains("Lane") else { return false }
        
        return true
    }
    
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Place Info Model

struct PlaceInfo {
    let name: String?
    let thoroughfare: String?
    let subThoroughfare: String?
    let locality: String?
    let subLocality: String?
    let administrativeArea: String?
    let postalCode: String?
    let country: String?
    
    var formattedAddress: String {
        var components: [String] = []
        
        if let subThoroughfare = subThoroughfare, let thoroughfare = thoroughfare {
            components.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = thoroughfare {
            components.append(thoroughfare)
        }
        
        if let locality = locality {
            components.append(locality)
        }
        
        if let administrativeArea = administrativeArea {
            components.append(administrativeArea)
        }
        
        if let postalCode = postalCode {
            components.append(postalCode)
        }
        
        return components.joined(separator: ", ")
    }
    
    var shortAddress: String {
        if let name = name {
            return name
        }
        
        if let thoroughfare = thoroughfare {
            return thoroughfare
        }
        
        if let locality = locality {
            return locality
        }
        
        return "Unknown Location"
    }
}
