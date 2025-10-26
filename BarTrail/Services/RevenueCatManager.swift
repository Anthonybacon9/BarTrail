//
//  RevenueCatManager.swift
//  BarTrail
//
//  Created by Anthony Bacon on 26/10/2025.
//


import SwiftUI
import RevenueCat
import Combine

class RevenueCatManager: ObservableObject {
    static let shared = RevenueCatManager()
    
    @Published var isSubscribed = false
    @Published var currentOffering: Offering?
    
    private init() {
        // Configure RevenueCat
        Purchases.logLevel = .debug // Remove in production
        Purchases.configure(withAPIKey: "appl_XGEpBFsheoTdxkzXHkSsZSSyBrN") // Replace with your key
        
        // Check subscription status
        checkSubscriptionStatus()
        
        // Fetch offerings
        fetchOfferings()
    }
    
    func checkSubscriptionStatus() {
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            guard let customerInfo = customerInfo, error == nil else {
                print("Error fetching customer info: \(error?.localizedDescription ?? "")")
                return
            }
            
            // Check if user has active subscription
            self?.isSubscribed = customerInfo.entitlements["premium"]?.isActive == true
        }
    }
    
    func fetchOfferings() {
        Purchases.shared.getOfferings { [weak self] offerings, error in
            guard let offerings = offerings, error == nil else {
                print("Error fetching offerings: \(error?.localizedDescription ?? "")")
                return
            }
            
            self?.currentOffering = offerings.current
        }
    }
    
    func purchase(package: Package, completion: @escaping (Bool, Error?) -> Void) {
        Purchases.shared.purchase(package: package) { [weak self] transaction, customerInfo, error, userCancelled in
            if let error = error {
                if !userCancelled {
                    completion(false, error)
                }
                return
            }
            
            // Check if premium is now active
            let isPremium = customerInfo?.entitlements["premium"]?.isActive == true
            self?.isSubscribed = isPremium
            completion(isPremium, nil)
        }
    }
    
    func restorePurchases(completion: @escaping (Bool, Error?) -> Void) {
        Purchases.shared.restorePurchases { [weak self] customerInfo, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            let isPremium = customerInfo?.entitlements["premium"]?.isActive == true
            self?.isSubscribed = isPremium
            completion(isPremium, nil)
        }
    }
}
