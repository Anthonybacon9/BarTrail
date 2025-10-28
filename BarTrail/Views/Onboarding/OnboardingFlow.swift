import SwiftUI
import RevenueCat

// MARK: - Onboarding Container
struct OnboardingFlow: View {
    @State private var currentPage = 0
    @State private var showPremium = false
    @Binding var isOnboardingComplete: Bool
    
    var body: some View {
        ZStack {
            if showPremium {
                PremiumUpgradeView(isOnboardingComplete: $isOnboardingComplete)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else {
                OnboardingPagesView(
                    currentPage: $currentPage,
                    showPremium: $showPremium
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .leading)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showPremium)
    }
}

// MARK: - Onboarding Pages View
struct OnboardingPagesView: View {
    @Binding var currentPage: Int
    @Binding var showPremium: Bool
    
    let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to\nBarTrail",
            subtitle: "Your nights, mapped and remembered",
            imageName: "map.fill",
            accentColor: .barTrailPrimary,
            description: "Never wonder 'where did we go last night?' again"
        ),
        OnboardingPage(
            title: "Own Your\nNights",
            subtitle: "Automatic memory preservation",
            imageName: "brain.head.profile",
            accentColor: .barTrailSecondary,
            description: "BarTrail tracks your route while you focus on the fun. Wake up to a beautiful map of your adventure"
        ),
        OnboardingPage(
            title: "Share Your\nStory",
            subtitle: "Story-worthy summaries",
            imageName: "photo.on.rectangle.angled",
            accentColor: .barTrailPrimary,
            description: "Turn your nights into shareable art. Overlay routes on photos, export transparent maps, and relive the memories"
        ),
        OnboardingPage(
            title: "Private &\nSecure",
            subtitle: "Your data stays on your device",
            imageName: "lock.shield.fill",
            accentColor: .barTrailSecondary,
            description: "100% on-device tracking. No servers, no data collection, no tracking. Your nights are yours alone"
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.barTrailPrimary.opacity(0.2),
                    Color.barTrailSecondary.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Custom page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        if #available(iOS 26.0, *) {
                            Capsule()
                                .fill(currentPage == index ?
                                      LinearGradient(
                                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                      ) :
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                                .glassEffect()
                                .frame(width: currentPage == index ? 32 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        } else {
                            Capsule()
                                .fill(currentPage == index ?
                                      LinearGradient(
                                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                      ) :
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                                .frame(width: currentPage == index ? 32 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                }
                .padding(.bottom, 20)
                
                // Action buttons
                VStack(spacing: 12) {
                    if currentPage == pages.count - 1 {
                        BarTrail.ContinueButton(action: goToPremium, color: Color.barTrailPrimary, color2: nil, text: "Continue", img: nil)
                    } else {
                        BarTrail.ContinueButton(action: nextPage, color: Color.barTrailPrimary, color2: nil, text: "Next", img: nil)
                        
                        Button {
                            withAnimation {
                                showPremium = true
                            }
                        } label: {
                            Text("Skip")
                                .font(Font.custom("Poppins-Regular", size: 16))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }
    
    private func goToPremium() {
        withAnimation {
            showPremium = true
        }
    }
    
    private func nextPage() {
        withAnimation {
            currentPage += 1
        }
    }
}

struct ContinueButton: View {
    let action: () -> Void
    let color: Color
    let color2: Color?
    let text: String
    let img: String?
    
    var body: some View {
        GeometryReader { geometry in
            Button(action: action) {
                if #available(iOS 26.0, *) {
                    HStack {
                        Text(text)
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassEffect(.regular.tint(color.opacity(0.3)), in: .rect(cornerRadius: 16))
                    .shadow(color: color.opacity(0.4), radius: 10)
                } else {
                    HStack {
                        Text(text)
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [color, color2 ?? Color.barTrailSecondary], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: color.opacity(0.4), radius: 10)
                }
            }
            .frame(width: geometry.size.width * 0.81)
            .frame(maxWidth: .infinity) // Center the button
        }
        .frame(height: 60) // Set a fixed height for GeometryReader
    }
}

// MARK: - Individual Onboarding Page
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon with gradient background
            ZStack {
                if #available(iOS 26.0, *) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [page.accentColor.opacity(0.2), page.accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .glassEffect()
                        .frame(width: 160, height: 160)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1 : 0)
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [page.accentColor.opacity(0.2), page.accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1 : 0)
                }
                
                Image(systemName: page.imageName)
                    .font(.system(size: 70, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1 : 0)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 12) {
                Text(page.title)
                    .font(Font.custom("Poppins-Bold", size: 42))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)
                
                Text(page.subtitle)
                    .font(Font.custom("Poppins-Medium", size: 18))
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)
                
                Text(page.description)
                    .font(Font.custom("Poppins-Regular", size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)
            }
            
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isAnimating = true
            }
        }
    }
}



// MARK: - Supporting Models
struct OnboardingPage {
    let title: String
    let subtitle: String
    let imageName: String
    let accentColor: Color
    let description: String
}

// MARK: - Preview
#Preview {
    OnboardingFlow(isOnboardingComplete: .constant(false))
        .environmentObject(RevenueCatManager.shared)
}
