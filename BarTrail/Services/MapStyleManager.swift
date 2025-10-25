//
//  MapStyleManager.swift
//  BarTrail
//
//  Created by Anthony Bacon on 25/10/2025.
//


import SwiftUI
import MapKit
import Combine

class MapStyleManager: ObservableObject {
    static let shared = MapStyleManager()
    
    @Published var selectedStyle: MapStyleType = .imagery {
        didSet {
            saveStyle()
        }
    }
    
    private let styleKey = "selectedMapStyle"
    
    init() {
        loadStyle()
    }
    
    private func saveStyle() {
        UserDefaults.standard.set(selectedStyle.rawValue, forKey: styleKey)
    }
    
    private func loadStyle() {
        if let savedStyle = UserDefaults.standard.string(forKey: styleKey),
           let style = MapStyleType(rawValue: savedStyle) {
            selectedStyle = style
        }
    }
    
    func getMapStyle() -> MapStyle {
        switch selectedStyle {
        case .standard:
            return .standard(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        }
    }
}

enum MapStyleType: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case imagery = "Satellite"
    case hybrid = "Hybrid"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .standard: return "map"
        case .imagery: return "globe.americas.fill"
        case .hybrid: return "map.fill"
        }
    }
    
    var description: String {
        switch self {
        case .standard: return "Classic map with roads and labels"
        case .imagery: return "Satellite imagery view"
        case .hybrid: return "Satellite with road overlay"
        }
    }
}
