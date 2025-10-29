//
//  PremiumUpgradeView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 26/10/2025.
//
import SwiftUI
import RevenueCat
import Combine

struct PremiumBuyingTest: View {
    @State private var customerInfo: CustomerInfo?
    @State private var isPro: Bool = false
    
    
    var body: some View {
        Button("Subscribe Monthly"){
            purchase(productID: "AnthonyBacon.BarTrail.Monthly")
        }
    }
    
    func purchase(productID: String){
        Task {
            do{
                let products: [StoreProduct] = await Purchases.shared.products([productID])
                guard let product = products.first else{
                    print("product not found \(productID)")
                    return
                }
                let result = try await Purchases.shared.purchase(product: product)
                customerInfo = result.customerInfo
                isPro = customerInfo?.entitlements.active
                    .contains(where: {
                        $0.value.isActive
                    }) ?? false
                
            } catch {
                print("Failed to purchase \(error)")
            }
        }
    }
}

// MARK: - Premium Upgrade View
struct PremiumUpgradeView: View {
    @Binding var isOnboardingComplete: Bool
    @State private var selectedPlan: PricingPlan = .yearly
    @State private var isAnimating = false
    
    // COMMENTED OUT: RevenueCat integration until approval
    // @EnvironmentObject var revenueCatManager: RevenueCatManager
    @State private var customerInfo: CustomerInfo?
    @State private var isPro: Bool = false
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum PricingPlan {
        case monthly, yearly
        
        var price: String {
            switch self {
            case .monthly: return "£2.99"
            case .yearly: return "£19.99"
            }
        }
        
        // COMMENTED OUT: RevenueCat price fetching
        // func getPrice(from revenueCatManager: RevenueCatManager) -> String {
        //     guard let offering = revenueCatManager.currentOffering else {
        //         return self == .yearly ? "£19.99" : "£2.99"
        //     }
        //
        //     let package = self == .yearly ?
        //         offering.package(identifier: "annual") :
        //         offering.package(identifier: "monthly")
        //
        //     return package?.storeProduct.localizedPriceString ?? (self == .yearly ? "£19.99" : "£2.99")
        // }
        
        var period: String {
            switch self {
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }
        
        var productID: String {
            switch self {
            case .monthly: return "AnthonyBacon.BarTrail.Monthly"
            case .yearly: return "AnthonyBacon.BarTrail.Annual"
            }
        }
        
        var savings: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Save 44%"
            }
        }
        
        var subtitle: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Best Value"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.barTrailPrimary.opacity(0.3),
                    Color.barTrailSecondary.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isAnimating ? 1.0 : 0.8)
                            .opacity(isAnimating ? 1 : 0)
                        
                        Text("BarTrail+")
                            .font(Font.custom("Poppins-Bold", size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 20)
                        
                        Text("Story-worthy night summaries")
                            .font(Font.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.secondary)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 20)
                    }
                    .padding(.top, 20)
                    
                    // Premium features list (compact)
                    VStack(alignment: .leading, spacing: 14) {
                        CompactFeatureRow(icon: "flame.fill", title: "Heatmaps", description: "See where you spend the most time")
                        CompactFeatureRow(icon: "crown.fill", title: "Unlock All Premium Tools", description: "Themes, overlays, stats, and cloud sync")
                        CompactFeatureRow(icon: "infinity", title: "Unlimited Everything", description: "History, exports, and all future features")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .opacity(isAnimating ? 1 : 0)
                    
                    // Pricing cards
                    VStack(spacing: 12) {
                        PricingCard(
                            plan: .yearly,
                            isSelected: selectedPlan == .yearly,
                            action: { selectedPlan = .yearly }
                        )
                        
                        PricingCard(
                            plan: .monthly,
                            isSelected: selectedPlan == .monthly,
                            action: { selectedPlan = .monthly }
                        )
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1 : 0)
                    
                    // CTA Button
                    Button {
                        purchase(productID: selectedPlan.productID)
                        
                        // COMMENTED OUT: RevenueCat purchase flow
                        // guard let offering = revenueCatManager.currentOffering else {
                        //     errorMessage = "Unable to load products. Please try again."
                        //     showError = true
                        //     return
                        // }
                        //
                        // let package = selectedPlan == .yearly ?
                        //     offering.package(identifier: "Annual") :
                        //     offering.package(identifier: "Monthly")
                        //
                        // guard let package = package else {
                        //     errorMessage = "Selected plan not available."
                        //     showError = true
                        //     return
                        // }
                        //
                        // isPurchasing = true
                        // revenueCatManager.purchase(package: package) { success, error in
                        //     isPurchasing = false
                        //
                        //     if success {
                        //         isOnboardingComplete = true
                        //     } else if let error = error {
                        //         errorMessage = error.localizedDescription
                        //         showError = true
                        //     }
                        // }
                    } label: {
                        if #available(iOS 26.0, *) {
                            Text(selectedPlan == .yearly ? "Start 7-Day Free Trial" : "Start Premium")
                                .font(Font.custom("Poppins-SemiBold", size: 17))
                            
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .glassEffect(.regular.tint(Color.barTrailPrimary.opacity(0.5)), in: .rect(cornerRadius: 16.0))
                                .shadow(color: Color.barTrailPrimary.opacity(0.4), radius: 10)
                        } else {
                            Text(selectedPlan == .yearly ? "Start 7-Day Free Trial" : "Start Premium")
                                .font(Font.custom("Poppins-SemiBold", size: 17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                                .shadow(color: Color.barTrailPrimary.opacity(0.4), radius: 10)
                        }
                    }
                    .disabled(isPurchasing)
                    .alert("Error", isPresented: $showError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(errorMessage)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .opacity(isAnimating ? 1 : 0)
                    
                    // Trial info for yearly
                    if selectedPlan == .yearly {
                        Text("7 days free, then \(selectedPlan.price)/year")
                            .font(Font.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.secondary)
                            .opacity(isAnimating ? 1 : 0)
                    }
                    
                    // Continue without premium
                    Button {
                        isOnboardingComplete = true
                    } label: {
                        Text("Continue with Free Version")
                            .font(Font.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .opacity(isAnimating ? 1 : 0)
                    
                    Button {
                        restorePurchases()
                        
                        // COMMENTED OUT: RevenueCat restore
                        // isPurchasing = true
                        // revenueCatManager.restorePurchases { success, error in
                        //     isPurchasing = false
                        //
                        //     if success {
                        //         isOnboardingComplete = true
                        //     } else if let error = error {
                        //         errorMessage = error.localizedDescription
                        //         showError = true
                        //     }
                        // }
                    } label: {
                        Text("Restore Purchases")
                            .font(Font.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                isAnimating = true
            }
        }
    }
    
    // Direct purchase function (from PremiumBuyingTest)
    func purchase(productID: String) {
        isPurchasing = true
        Task {
            do {
                let products: [StoreProduct] = await Purchases.shared.products([productID])
                guard let product = products.first else {
                    print("product not found \(productID)")
                    await MainActor.run {
                        errorMessage = "Product not found: \(productID)"
                        showError = true
                        isPurchasing = false
                    }
                    return
                }
                let result = try await Purchases.shared.purchase(product: product)
                await MainActor.run {
                    customerInfo = result.customerInfo
                    isPro = customerInfo?.entitlements.active
                        .contains(where: {
                            $0.value.isActive
                        }) ?? false
                    
                    isPurchasing = false
                    if isPro {
                        isOnboardingComplete = true
                    }
                }
            } catch {
                print("Failed to purchase \(error)")
                await MainActor.run {
                    errorMessage = "Failed to purchase: \(error.localizedDescription)"
                    showError = true
                    isPurchasing = false
                }
            }
        }
    }
    
    func restorePurchases() {
        isPurchasing = true
        Task {
            do {
                let result = try await Purchases.shared.restorePurchases()
                await MainActor.run {
                    customerInfo = result
                    isPro = customerInfo?.entitlements.active
                        .contains(where: {
                            $0.value.isActive
                        }) ?? false
                    
                    isPurchasing = false
                    if isPro {
                        isOnboardingComplete = true
                    } else {
                        errorMessage = "No previous purchases found"
                        showError = true
                    }
                }
            } catch {
                print("Failed to restore purchases \(error)")
                await MainActor.run {
                    errorMessage = "Failed to restore: \(error.localizedDescription)"
                    showError = true
                    isPurchasing = false
                }
            }
        }
    }
}

// MARK: - Premium Upgrade Sheet
struct PremiumUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PricingPlan = .yearly
    @State private var isAnimating = false
    
    // COMMENTED OUT: RevenueCat integration until approval
    // @EnvironmentObject var revenueCatManager: RevenueCatManager
    @State private var customerInfo: CustomerInfo?
    @State private var isPro: Bool = false
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum PricingPlan {
        case monthly, yearly
        
        var price: String {
            switch self {
            case .monthly: return "£2.99"
            case .yearly: return "£19.99"
            }
        }
        
        var period: String {
            switch self {
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }
        
        var productID: String {
            switch self {
            case .monthly: return "AnthonyBacon.BarTrail.Monthly"
            case .yearly: return "AnthonyBacon.BarTrail.Annual"
            }
        }
        
        var savings: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Save 44%"
            }
        }
        
        var subtitle: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Best Value"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.barTrailPrimary.opacity(0.3),
                    Color.barTrailSecondary.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isAnimating ? 1.0 : 0.8)
                            .opacity(isAnimating ? 1 : 0)
                        
                        Text("BarTrail+")
                            .font(Font.custom("Poppins-Bold", size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 20)
                        
                        Text("Story-worthy night summaries")
                            .font(Font.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.secondary)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : 20)
                    }
                    .padding(.top, 20)
                    
                    // Premium features list (compact)
                    VStack(alignment: .leading, spacing: 14) {
                        CompactFeatureRow(icon: "flame.fill", title: "Heatmaps", description: "See where you spend the most time")
                        CompactFeatureRow(icon: "crown.fill", title: "Unlock All Premium Tools", description: "Themes, overlays, stats, and cloud sync")
                        CompactFeatureRow(icon: "infinity", title: "Unlimited Everything", description: "History, exports, and all future features")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .opacity(isAnimating ? 1 : 0)
                    
                    // Pricing cards
                    VStack(spacing: 12) {
                        PricingCard(
                            plan: .yearly,
                            isSelected: selectedPlan == .yearly,
                            action: { selectedPlan = .yearly }
                        )
                        
                        PricingCard(
                            plan: .monthly,
                            isSelected: selectedPlan == .monthly,
                            action: { selectedPlan = .monthly }
                        )
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1 : 0)
                    
                    // CTA Button
                    Button {
                        purchase(productID: selectedPlan.productID)
                    } label: {
                        if #available(iOS 26.0, *) {
                            Text(selectedPlan == .yearly ? "Start 7-Day Free Trial" : "Start Premium")
                                .font(Font.custom("Poppins-SemiBold", size: 17))
                            
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .glassEffect(.regular.tint(Color.barTrailPrimary.opacity(0.5)), in: .rect(cornerRadius: 16.0))
                                .shadow(color: Color.barTrailPrimary.opacity(0.4), radius: 10)
                        } else {
                            Text(selectedPlan == .yearly ? "Start 7-Day Free Trial" : "Start Premium")
                                .font(Font.custom("Poppins-SemiBold", size: 17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                                .shadow(color: Color.barTrailPrimary.opacity(0.4), radius: 10)
                        }
                    }
                    .disabled(isPurchasing)
                    .alert("Error", isPresented: $showError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(errorMessage)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .opacity(isAnimating ? 1 : 0)
                    
                    // Trial info for yearly
                    if selectedPlan == .yearly {
                        Text("7 days free, then \(selectedPlan.price)/year")
                            .font(Font.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.secondary)
                            .opacity(isAnimating ? 1 : 0)
                    }
                    
                    // Continue without premium
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue with Free Version")
                            .font(Font.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .opacity(isAnimating ? 1 : 0)
                    
                    Button {
                        restorePurchases()
                    } label: {
                        Text("Restore Purchases")
                            .font(Font.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                isAnimating = true
            }
        }
    }
    
    // Direct purchase function
    func purchase(productID: String) {
        isPurchasing = true
        Task {
            do {
                let products: [StoreProduct] = await Purchases.shared.products([productID])
                guard let product = products.first else {
                    print("product not found \(productID)")
                    await MainActor.run {
                        errorMessage = "Product not found: \(productID)"
                        showError = true
                        isPurchasing = false
                    }
                    return
                }
                let result = try await Purchases.shared.purchase(product: product)
                await MainActor.run {
                    customerInfo = result.customerInfo
                    isPro = customerInfo?.entitlements.active
                        .contains(where: {
                            $0.value.isActive
                        }) ?? false
                    
                    isPurchasing = false
                    if isPro {
                        dismiss()
                    }
                }
            } catch {
                print("Failed to purchase \(error)")
                await MainActor.run {
                    errorMessage = "Failed to purchase: \(error.localizedDescription)"
                    showError = true
                    isPurchasing = false
                }
            }
        }
    }
    
    func restorePurchases() {
        isPurchasing = true
        Task {
            do {
                let result = try await Purchases.shared.restorePurchases()
                await MainActor.run {
                    customerInfo = result
                    isPro = customerInfo?.entitlements.active
                        .contains(where: {
                            $0.value.isActive
                        }) ?? false
                    
                    isPurchasing = false
                    if isPro {
                        dismiss()
                    } else {
                        errorMessage = "No previous purchases found"
                        showError = true
                    }
                }
            } catch {
                print("Failed to restore purchases \(error)")
                await MainActor.run {
                    errorMessage = "Failed to restore: \(error.localizedDescription)"
                    showError = true
                    isPurchasing = false
                }
            }
        }
    }
}

// MARK: - Compact Feature Row (for tighter spacing)
struct CompactFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(Font.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(Font.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Pricing Card
struct PricingCard: View {
    let plan: PremiumUpgradeView.PricingPlan
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        let price = plan.price
        
        if #available(iOS 26.0, *) {
            if isSelected {
                Button(action: action) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(plan.period.capitalized)
                                    .font(Font.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(isSelected ? .white : .primary)
                                
                                if let savings = plan.savings {
                                    Text(savings)
                                        .font(Font.custom("Poppins-Medium", size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green)
                                        .cornerRadius(8)
                                }
                                
                                if let subtitle = plan.subtitle {
                                    Text(subtitle)
                                        .font(Font.custom("Poppins-Medium", size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                }
                            }
                            
                            Text("\(price) / \(plan.period)")
                                .font(Font.custom("Poppins-Regular", size: 14))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                    .padding(20)
                    .glassEffect(.regular.tint(Color.barTrailPrimary.opacity(0.3)), in: .rect(cornerRadius: 16.0))
                    .cornerRadius(16)
                    .shadow(color: isSelected ? Color.barTrailPrimary.opacity(0.4) : Color.clear, radius: 10)
                }
            } else {
                Button(action: action) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(plan.period.capitalized)
                                    .font(Font.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(isSelected ? .white : .primary)
                                
                                if let savings = plan.savings {
                                    Text(savings)
                                        .font(Font.custom("Poppins-Medium", size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green)
                                        .cornerRadius(8)
                                }
                            }
                            
                            Text("\(price) / \(plan.period)")
                                .font(Font.custom("Poppins-Regular", size: 14))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16.0))
                    .cornerRadius(16)
                    .shadow(color: isSelected ? Color.barTrailPrimary.opacity(0.4) : Color.clear, radius: 10)
                }
            }
        } else {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(plan.period.capitalized)
                                .font(Font.custom("Poppins-SemiBold", size: 18))
                                .foregroundColor(isSelected ? .white : .primary)
                            
                            if let savings = plan.savings {
                                Text(savings)
                                    .font(Font.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .cornerRadius(8)
                            }
                        }
                        
                        Text("\(price) / \(plan.period)")
                            .font(Font.custom("Poppins-Regular", size: 14))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? .white : .gray)
                }
                .padding(20)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            LinearGradient(
                                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    }
                )
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected ?
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                                LinearGradient(
                                    colors: [Color.clear, Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                            lineWidth: 2
                        )
                )
                .shadow(color: isSelected ? Color.barTrailPrimary.opacity(0.4) : Color.clear, radius: 10)
            }
        }
    }
}
