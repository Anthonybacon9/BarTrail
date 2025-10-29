//
//  RevenueCatManager.swift
//  BarTrail
//
//  Created by Anthony Bacon on 26/10/2025.
//

import SwiftUI
import RevenueCat
import Combine

class RevenueCatManager: NSObject, ObservableObject {
    static let shared = RevenueCatManager()
    
    @Published var isSubscribed = false
    @Published var currentOffering: Offering?
    
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
        
        // Configure RevenueCat
        Purchases.logLevel = .debug // Remove in production
        Purchases.configure(withAPIKey: "appl_XGEpBFsheoTdxkzXHkSsZSSyBrN")
        
        // Set up delegate for real-time updates
        Purchases.shared.delegate = self
        
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
            
            // Update on main thread
            DispatchQueue.main.async {
                self?.isSubscribed = customerInfo.entitlements["premium"]?.isActive == true
            }
        }
    }
    
    func fetchOfferings() {
        Purchases.shared.getOfferings { [weak self] offerings, error in
            guard let offerings = offerings, error == nil else {
                print("Error fetching offerings: \(error?.localizedDescription ?? "")")
                return
            }
            
            DispatchQueue.main.async {
                self?.currentOffering = offerings.current
            }
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
            DispatchQueue.main.async {
                self?.isSubscribed = isPremium
                completion(isPremium, nil)
            }
        }
    }
    
    func restorePurchases(completion: @escaping (Bool, Error?) -> Void) {
        Purchases.shared.restorePurchases { [weak self] customerInfo, error in
            if let error = error {
                completion(false, error)
                return
            }
            
            let isPremium = customerInfo?.entitlements["premium"]?.isActive == true
            DispatchQueue.main.async {
                self?.isSubscribed = isPremium
                completion(isPremium, nil)
            }
        }
    }
}

// MARK: - PurchasesDelegate
extension RevenueCatManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // This gets called automatically when subscription status changes
        DispatchQueue.main.async { [weak self] in
            self?.isSubscribed = customerInfo.entitlements["premium"]?.isActive == true
            print("Subscription status updated: \(self?.isSubscribed ?? false)")
        }
    }
}
