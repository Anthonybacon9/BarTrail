//
//  BarTrailApp.swift
//  BarTrail
//
//  Created by Anthony Bacon on 23/10/2025.
//

import SwiftUI
import RevenueCat

@main
struct BarTrailApp: App {
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    
//    init() {
//        Purchases.configure(withAPIKey: "appl_XGEpBFsheoTdxkzXHkSsZSSyBrN")
//    }
    
    var body: some Scene {
        WindowGroup {
            if !isOnboardingComplete {
                    OnboardingFlow(isOnboardingComplete: $isOnboardingComplete)
                        .environmentObject(revenueCatManager)
                } else {
                    ContentView()
                        .environmentObject(revenueCatManager)
                }
//            PremiumBuyingTest()
        }
    }
}
