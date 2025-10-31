//
//  StatsOverlayGenerator.swift
//  BarTrail
//
//  Created by Anthony Bacon on 31/10/2025.
//


import UIKit
import CoreLocation

class StatsOverlayGenerator {
    static let shared = StatsOverlayGenerator()
    
    private init() {}
    
    // MARK: - Generate Stats Grid Overlay
    
    func generateStatsGrid(from session: NightSession, size: CGSize = CGSize(width: 1080, height: 1080)) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let ctx = context.cgContext
            
            // Clear background (transparent)
            ctx.clear(CGRect(origin: .zero, size: size))
            
            // Card background
            let padding: CGFloat = 40
            let cardRect = CGRect(
                x: padding,
                y: padding,
                width: size.width - (padding * 2),
                height: size.height - (padding * 2)
            )
            
            // Draw rounded card with gradient
            let colors = [
                UIColor.systemBlue.withAlphaComponent(0.95).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.95).cgColor
            ]
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )!
            
            ctx.saveGState()
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 30)
            ctx.addPath(cardPath.cgPath)
            ctx.clip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: cardRect.minX, y: cardRect.minY),
                end: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
                options: []
            )
            ctx.restoreGState()
            
            // Add white border
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(4)
            ctx.addPath(cardPath.cgPath)
            ctx.strokePath()
            
            // Calculate stats
            let stats = calculateStats(from: session)
            
            // Draw content
            let contentPadding: CGFloat = 60
            let contentRect = cardRect.insetBy(dx: contentPadding, dy: contentPadding)
            
            drawStatsContent(stats: stats, in: contentRect, context: ctx)
        }
        
        return image
    }
    
    // MARK: - Calculate Stats
    
    private func calculateStats(from session: NightSession) -> SessionStats {
        let duration = session.duration ?? 0
        let venueCount = session.dwells.count
        let totalDrinks = session.drinks.total
        let distance = session.totalDistance
        let rating = session.rating
        
        // Average time per venue
        let avgTimePerVenue = venueCount > 0 ? duration / TimeInterval(venueCount) : 0
        
        // Most visited type
        let dwellTypes = session.dwells.map { $0.dwellType }
        let mostCommonType = dwellTypes.mostCommon()?.rawValue ?? "N/A"
        
        return SessionStats(
            duration: duration,
            venueCount: venueCount,
            totalDrinks: totalDrinks,
            distance: distance,
            rating: rating,
            avgTimePerVenue: avgTimePerVenue,
            mostCommonType: mostCommonType,
            startTime: session.startTime
        )
    }
    
    // MARK: - Draw Stats Content
    
    private func drawStatsContent(stats: SessionStats, in rect: CGRect, context: CGContext) {
        let ctx = context
        
        // Title
        drawText(
            "Night Out Stats",
            font: UIFont.systemFont(ofSize: 56, weight: .black),
            color: .white,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 80),
            alignment: .center,
            context: ctx
        )
        
        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let dateString = dateFormatter.string(from: stats.startTime)
        
        drawText(
            dateString,
            font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            color: UIColor.white.withAlphaComponent(0.9),
            in: CGRect(x: rect.minX, y: rect.minY + 80, width: rect.width, height: 40),
            alignment: .center,
            context: ctx
        )
        
        // Main stats grid - 2x3 layout
        let gridStartY = rect.minY + 160
        let gridHeight = rect.height - 200
        let cellHeight = gridHeight / 3
        let cellWidth = rect.width / 2
        
        let mainStats: [(icon: String, label: String, value: String)] = [
            ("⏱️", "Duration", formatDuration(stats.duration)),
            ("📍", "Venues", "\(stats.venueCount)"),
            ("🍺", "Drinks", "\(stats.totalDrinks)"),
            ("🚶", "Distance", formatDistance(stats.distance)),
            ("⏰", "Avg Time/Venue", formatDuration(stats.avgTimePerVenue)),
            ("⭐", "Rating", stats.rating != nil ? String(repeating: "⭐", count: stats.rating!) : "—")
        ]
        
        for (index, stat) in mainStats.enumerated() {
            let row = index / 2
            let col = index % 2
            
            let cellRect = CGRect(
                x: rect.minX + (CGFloat(col) * cellWidth),
                y: gridStartY + (CGFloat(row) * cellHeight),
                width: cellWidth,
                height: cellHeight
            )
            
            drawStatCell(
                icon: stat.icon,
                label: stat.label,
                value: stat.value,
                in: cellRect,
                context: ctx
            )
        }
    }
    
    // MARK: - Draw Stat Cell
    
    private func drawStatCell(icon: String, label: String, value: String, in rect: CGRect, context: CGContext) {
        let padding: CGFloat = 20
        let contentRect = rect.insetBy(dx: padding, dy: padding)
        
        // Icon
        drawText(
            icon,
            font: UIFont.systemFont(ofSize: 48),
            color: .white,
            in: CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: 60),
            alignment: .center,
            context: context
        )
        
        // Value (large)
        drawText(
            value,
            font: UIFont.systemFont(ofSize: 44, weight: .bold),
            color: .white,
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 65, width: contentRect.width, height: 55),
            alignment: .center,
            context: context
        )
        
        // Label (small)
        drawText(
            label,
            font: UIFont.systemFont(ofSize: 24, weight: .medium),
            color: UIColor.white.withAlphaComponent(0.8),
            in: CGRect(x: contentRect.minX, y: contentRect.minY + 125, width: contentRect.width, height: 30),
            alignment: .center,
            context: context
        )
    }
    
    // MARK: - Helper: Draw Text
    
    private func drawText(_ text: String, font: UIFont, color: UIColor, in rect: CGRect, alignment: NSTextAlignment, context: CGContext) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        let nsText = text as NSString
        nsText.draw(in: rect, withAttributes: attributes)
    }
    
    // MARK: - Formatters
    
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
    
    // MARK: - Session Stats Model
    
    struct SessionStats {
        let duration: TimeInterval
        let venueCount: Int
        let totalDrinks: Int
        let distance: Double
        let rating: Int?
        let avgTimePerVenue: TimeInterval
        let mostCommonType: String
        let startTime: Date
    }
}

// MARK: - Array Extension for Most Common Element

extension Array where Element: Hashable {
    func mostCommon() -> Element? {
        let counts = self.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}