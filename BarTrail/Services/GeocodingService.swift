import Foundation
import CoreLocation
import MapKit
import CoreLocation

class GeocodingService {
    static let shared = GeocodingService()
    
    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]
    private var nearbyCache: [String: [VenueOption]] = [:] // Cache for nearby venues
    
    private init() {}
    
    // MARK: - Venue Option Model
    
    struct VenueOption: Identifiable {
        let id = UUID()
        let name: String
        let distance: Double // Distance from the dwell point in meters
        let category: String? // e.g., "Restaurant", "Bar", "Cafe"
        
        var formattedDistance: String {
            if distance < 1000 {
                return String(format: "%.0fm away", distance)
            } else {
                return String(format: "%.1fkm away", distance / 1000)
            }
        }
    }
    
    // MARK: - Get Multiple Nearby Venues
    
    func getNearbyVenues(for coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 150) async -> [VenueOption] {
        let cacheKey = "\(coordinate.latitude),\(coordinate.longitude)-nearby"
        
        // Check cache first
        if let cached = nearbyCache[cacheKey] {
            print("✅ Returning cached nearby venues: \(cached.count) options")
            return cached
        }
        
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var venues: [VenueOption] = []
        
        // Search categories for nightlife/dining
        let categories = [
            "bar", "pub", "nightclub", "restaurant", "cafe",
            "brewery", "lounge", "club", "hotel", "venue"
        ]
        
        // Use TaskGroup to search all categories concurrently
        await withTaskGroup(of: [VenueOption].self) { group in
            for category in categories {
                group.addTask {
                    await self.searchCategory(category: category, coordinate: coordinate, location: location, radius: radius)
                }
            }
            
            for await categoryVenues in group {
                venues.append(contentsOf: categoryVenues)
            }
        }
        
        // Remove duplicates (same name, similar location)
        venues = removeDuplicateVenues(venues)
        
        // Sort by distance
        venues.sort { $0.distance < $1.distance }
        
        // Limit to top 10 closest venues
        let topVenues = Array(venues.prefix(10))
        
        // Cache the results
        nearbyCache[cacheKey] = topVenues
        
        print("✅ Found \(topVenues.count) nearby venues")
        return topVenues
    }
    
    // MARK: - Search Single Category
    
    private func searchCategory(category: String, coordinate: CLLocationCoordinate2D, location: CLLocation, radius: CLLocationDistance) async -> [VenueOption] {
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
            
            var options: [VenueOption] = []
            
            for item in response.mapItems {
                guard let itemLocation = item.placemark.location,
                      let name = item.name,
                      !name.isEmpty else { continue }
                
                let distance = itemLocation.distance(from: location)
                
                // Only include venues within the specified radius
                if distance <= radius {
                    // Clean up the category name
                    let categoryName: String
                    if let poiCategory = item.pointOfInterestCategory {
                        categoryName = cleanCategoryName(poiCategory.rawValue)
                    } else {
                        categoryName = category.capitalized
                    }
                    
                    options.append(VenueOption(
                        name: name,
                        distance: distance,
                        category: categoryName
                    ))
                }
            }
            
            return options
        } catch {
            return []
        }
    }
    
    // MARK: - Remove Duplicate Venues
    
    private func removeDuplicateVenues(_ venues: [VenueOption]) -> [VenueOption] {
        var seen: Set<String> = []
        var unique: [VenueOption] = []
        
        for venue in venues {
            let normalizedName = venue.name.lowercased().trimmingCharacters(in: .whitespaces)
            if !seen.contains(normalizedName) {
                seen.insert(normalizedName)
                unique.append(venue)
            }
        }
        
        return unique
    }
    
    // MARK: - Improved Venue Name Detection (Original Method)
    
    func getBestVenueName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let cacheKey = "\(coordinate.latitude),\(coordinate.longitude)"
        
        // Check cache first
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // Strategy 1: Try MKLocalSearch for nearby venues
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
        
        // Strategy 3: Last resort - use address
        if let addressName = await getAddressName(for: coordinate) {
            cache[cacheKey] = addressName
            print("⚠️ Using address name: \(addressName)")
            return addressName
        }
        
        print("❌ No venue name found for coordinate: \(coordinate)")
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    private func searchForVenueName(coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 50) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
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
                continue
            }
        }
        
        return nil
    }
    
    private func getPOIName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US"))
            
            guard let placemark = placemarks.first else {
                return nil
            }
            
            if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                return areasOfInterest.first
            }
            
            if let name = placemark.name,
               isValidBusinessName(name, placemark: placemark) {
                return name
            }
            
            if placemark.administrativeArea != nil || placemark.locality != nil {
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
    
    private func getAddressName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                return nil
            }
            
            if let locality = placemark.locality {
                if let subLocality = placemark.subLocality, subLocality != locality {
                    return "\(subLocality), \(locality)"
                }
                return locality
            }
            
            return placemark.thoroughfare ?? "Unknown Location"
        } catch {
            return nil
        }
    }
    
    private func isValidBusinessName(_ name: String, placemark: CLPlacemark) -> Bool {
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
        
        guard name.count > 3 else { return false }
        guard !name.contains("Street") else { return false }
        guard !name.contains("Avenue") else { return false }
        guard !name.contains("Road") else { return false }
        guard !name.contains("Lane") else { return false }
        
        return true
    }
    
    func clearCache() {
        cache.removeAll()
        nearbyCache.removeAll()
    }
    
    // MARK: - Clean Category Name
    
    private func cleanCategoryName(_ rawCategory: String) -> String {
        // Remove "MKPOICategory" prefix if present
        var cleaned = rawCategory
        if cleaned.hasPrefix("MKPOICategory") {
            cleaned = String(cleaned.dropFirst("MKPOICategory".count))
        }
        
        // Convert camelCase to readable format
        // e.g., "restaurant" -> "Restaurant", "nightlife" -> "Nightlife"
        let result = cleaned.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        
        // Capitalize first letter
        return result.prefix(1).uppercased() + result.dropFirst().lowercased()
    }
}
