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
    
    // MARK: - Reverse Geocoding
    
    func getPlaceName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let cacheKey = "\(coordinate.latitude),\(coordinate.longitude)"
        
        // Check cache first
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                return nil
            }
            
            // Try to get a meaningful name in order of preference
            let name = placemark.name ?? 
                       placemark.thoroughfare ?? 
                       placemark.locality ?? 
                       placemark.administrativeArea ??
                       "Unknown Location"
            
            // Cache the result
            cache[cacheKey] = name
            
            return name
        } catch {
            print("❌ Geocoding error: \(error.localizedDescription)")
            return nil
        }
    }
    
    func getDetailedPlaceName(for coordinate: CLLocationCoordinate2D) async -> PlaceInfo? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                return nil
            }
            
            return PlaceInfo(
                name: placemark.name,
                thoroughfare: placemark.thoroughfare,
                subThoroughfare: placemark.subThoroughfare,
                locality: placemark.locality,
                subLocality: placemark.subLocality,
                administrativeArea: placemark.administrativeArea,
                postalCode: placemark.postalCode,
                country: placemark.country
            )
        } catch {
            print("❌ Detailed geocoding error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Place Search (for venue names)
    
    func searchNearbyPlaces(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 50) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "bar restaurant pub cafe"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            return response.mapItems
        } catch {
            print("❌ Place search error: \(error.localizedDescription)")
            return []
        }
    }
    
    func getBestVenueName(for coordinate: CLLocationCoordinate2D) async -> String? {
        // First try to find a specific venue nearby
        let places = await searchNearbyPlaces(coordinate: coordinate)
        
        // Find the closest place
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let sortedPlaces = places.sorted { place1, place2 in
            let dist1 = place1.placemark.location?.distance(from: location) ?? Double.greatestFiniteMagnitude
            let dist2 = place2.placemark.location?.distance(from: location) ?? Double.greatestFiniteMagnitude
            return dist1 < dist2
        }
        
        // If we found a place within 50m, use it
        if let closest = sortedPlaces.first,
           let placeLocation = closest.placemark.location,
           placeLocation.distance(from: location) < 50 {
            return closest.name
        }
        
        // Otherwise fall back to reverse geocoding
        return await getPlaceName(for: coordinate)
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