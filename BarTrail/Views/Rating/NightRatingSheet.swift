//
//  NightRatingSheet.swift
//  BarTrail
//
//  Created by Anthony Bacon on 26/10/2025.
//


import SwiftUI

// Random phrases for each rating level
let ratingPhrases: [Int: [String]] = [
    5: [
        "Legendary night! 🔥",
        "Absolute banger! 🎉",
        "One for the history books! 📖",
        "Peak performance! 🏆",
        "Chef's kiss! 👨‍🍳💋",
        "Hall of fame material! 🌟",
        "Elite tier night! 💎",
        "Absolutely massive! 🚀"
    ],
    4: [
        "Solid night out! 👊",
        "Good vibes all round! ✨",
        "Can't complain! 😎",
        "Quality evening! 🥂",
        "Did the job! 🍻",
        "Above average! 📈",
        "Respectable showing! 👌"
    ],
    3: [
        "Not bad, not bad! 🤷",
        "It was alright! 👍",
        "Middle of the road! 🛣️",
        "Could be worse! 😅",
        "Did what it said on the tin! 📦",
        "Decent enough! ⭐"
    ],
    2: [
        "Bit rough that one... 😬",
        "Seen better nights! 😕",
        "Could've gone better! 🫤",
        "Not your finest! 😓",
        "Room for improvement! 📉"
    ],
    1: [
        "One to forget! 😵",
        "Rough night! 🤕",
        "Write that one off! ❌",
        "We've all been there... 😩",
        "Less said the better! 🤐"
    ]
]

struct NightRatingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: NightSession
    let onRatingComplete: (Int) -> Void
    
    @State private var selectedRating: Int = 0
    @State private var showConfetti = false
    
    var currentPhrase: String {
        guard selectedRating > 0 else { return "How was your night?" }
        return ratingPhrases[selectedRating]?.randomElement() ?? "Rate your night!"
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.barTrailPrimary.opacity(0.2), Color.barTrailSecondary.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if showConfetti && selectedRating == 5 {
                TemporaryFireworks(duration: 4.0)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 32) {
                Spacer()
                
                // Title
                VStack(spacing: 8) {
                    Text("Night Complete!")
                        .font(Font.custom("Poppins-Bold", size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text(currentPhrase)
                        .font(Font.custom("Poppins-Regular", size: 18))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut, value: selectedRating)
                }
                .padding(.horizontal)
                
                // Quick stats
                HStack(spacing: 20) {
                    statBubble(icon: "clock.fill", value: formatDuration(session.duration ?? 0))
                    statBubble(icon: "figure.walk", value: formatDistance(session.totalDistance))
                    statBubble(icon: "mappin.circle.fill", value: "\(session.dwells.count)")
                }
                .padding(.horizontal)
                
                // Star Rating
                HStack(spacing: 20) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                selectedRating = star
                                
                                // Trigger confetti for 5 stars
                                if star == 5 {
                                    showConfetti = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        showConfetti = false
                                    }
                                }
                            }
                            
                            // Haptic feedback
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                        } label: {
                            Image(systemName: star <= selectedRating ? "star.fill" : "star")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    star <= selectedRating ?
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ) :
                                    LinearGradient(
                                        colors: [.gray.opacity(0.3), .gray.opacity(0.3)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(
                                    color: star <= selectedRating ? .orange.opacity(0.5) : .clear,
                                    radius: 8
                                )
                                .scaleEffect(star == selectedRating ? 1.2 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 20)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    // Save Rating Button
                    Button {
                        if selectedRating > 0 {
                            onRatingComplete(selectedRating)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(selectedRating > 0 ? "Save Rating" : "Select Rating")
                                .font(.title3.bold())
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            selectedRating > 0 ?
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [.gray, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: selectedRating > 0 ? Color.barTrailPrimary.opacity(0.4) : .clear, radius: 10)
                    }
                    .disabled(selectedRating == 0)
                    
                    // Skip Button
                    Button {
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(Font.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
    
    @ViewBuilder
    private func statBubble(icon: String, value: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(value)
                .font(Font.custom("Poppins-Bold", size: 16))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}
