//
//  RouteOverlayGenerator.swift
//  BarTrail
//
//  Created by Anthony Bacon on 25/10/2025.
//


import UIKit
import CoreLocation
import MapKit

class RouteOverlayGenerator {
    static let shared = RouteOverlayGenerator()
    
    private init() {}
    
    // MARK: - Generate Transparent Route Image
    
    func generateTransparentRoute(from session: NightSession, placeNames: [UUID: String] = [:], size: CGSize = CGSize(width: 1080, height: 1080)) -> UIImage? {
        guard session.route.count > 1 else { return nil }
        
        // Calculate bounds
        let coordinates = session.route.map { $0.coordinate }
        let bounds = calculateBounds(coordinates: coordinates)
        
        // Create drawing context
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let ctx = context.cgContext
            
            // Clear background (transparent)
            ctx.clear(CGRect(origin: .zero, size: size))
            
            // Convert coordinates to points
            let points = coordinates.map { coordinate in
                convertCoordinateToPoint(
                    coordinate: coordinate,
                    bounds: bounds,
                    size: size
                )
            }
            
            // Draw the route
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(8)
            
            // Create gradient for route
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: [0, 1])!
            
            // Draw route path with gradient
            let path = UIBezierPath()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            
            let startPoint = CGPoint(x: 0, y: 0)
            let endPoint = CGPoint(x: size.width, y: size.height)
            ctx.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
            ctx.restoreGState()
            
            // Draw start point
            if let firstPoint = points.first {
                drawMarker(at: firstPoint, color: .systemGreen, label: "START", in: ctx, size: size)
            }
            
            // Draw end point
            if let lastPoint = points.last {
                drawMarker(at: lastPoint, color: .systemRed, label: "END", in: ctx, size: size)
            }
            
            // Draw dwell points with names
            for dwell in session.dwells {
                let point = convertCoordinateToPoint(
                    coordinate: dwell.location,
                    bounds: bounds,
                    size: size
                )
                drawDwellMarker(at: point, in: ctx)
                
                // Draw place name if available
                if let placeName = placeNames[dwell.id] {
                    drawPlaceName(at: point, name: placeName, in: ctx, size: size)
                }
            }
        }
        
        return image
    }
    
    //MARK: - Draw Place Name (FIXED - No cutoff)
    
    private func drawPlaceName(at point: CGPoint, name: String, in ctx: CGContext, size: CGSize) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        // Break long text into multiple lines
        let maxWidth: CGFloat = size.width * 0.4  // Max 40% of image width
        
        let text = name as NSString
        
        let sizeAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .black),
            .paragraphStyle: paragraphStyle
        ]
        
        // Calculate text size with wrapping
        let constraintRect = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: sizeAttributes,
            context: nil
        )
        let textSize = boundingBox.size
        
        let padding: CGFloat = 12
        let labelOffset: CGFloat = 35  // Distance below marker
        
        // Calculate position - ensure it stays within bounds
        var xPosition = point.x - textSize.width/2
        let yPosition = point.y + labelOffset
        
        // Prevent left edge cutoff
        if xPosition < padding {
            xPosition = padding
        }
        
        // Prevent right edge cutoff
        if xPosition + textSize.width + padding > size.width {
            xPosition = size.width - textSize.width - padding
        }
        
        let backgroundRect = CGRect(
            x: xPosition - padding,
            y: yPosition - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        
        // Draw rounded background
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
        let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: 8)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        
        let textRect = CGRect(
            x: xPosition,
            y: yPosition,
            width: textSize.width,
            height: textSize.height
        )
        
        // Draw stroke first (outline)
        let strokeAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .black),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle,
            .strokeColor: UIColor.black,
            .strokeWidth: 8.0
        ]
        text.draw(in: textRect, withAttributes: strokeAttributes)
        
        // Draw fill on top (no stroke)
        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .black),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        text.draw(in: textRect, withAttributes: fillAttributes)
    }
    
    // MARK: - Generate Route with White Outline (Better for Photos)
    
    func generateRouteWithOutline(from session: NightSession, placeNames: [UUID: String] = [:], size: CGSize = CGSize(width: 1080, height: 1080)) -> UIImage? {
        guard session.route.count > 1 else { return nil }
        
        let coordinates = session.route.map { $0.coordinate }
        let bounds = calculateBounds(coordinates: coordinates)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.clear(CGRect(origin: .zero, size: size))
            
            let points = coordinates.map { coordinate in
                convertCoordinateToPoint(coordinate: coordinate, bounds: bounds, size: size)
            }
            
            let path = UIBezierPath()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            
            // Draw white outline
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(12)
            ctx.addPath(path.cgPath)
            ctx.strokePath()
            
            // Draw colored route on top with gradient
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: [0, 1])!

            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.setLineWidth(8)
            ctx.replacePathWithStrokedPath()
            ctx.clip()

            let startPoint = CGPoint(x: 0, y: 0)
            let endPoint = CGPoint(x: size.width, y: size.height)
            ctx.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
            ctx.restoreGState()
            
            // Draw markers with outlines
            if let firstPoint = points.first {
                drawMarkerWithOutline(at: firstPoint, color: .systemGreen, label: "START", in: ctx, size: size)
            }
            
            if let lastPoint = points.last {
                drawMarkerWithOutline(at: lastPoint, color: .systemRed, label: "END", in: ctx, size: size)
            }
            
            for dwell in session.dwells {
                let point = convertCoordinateToPoint(coordinate: dwell.location, bounds: bounds, size: size)
                drawDwellMarkerWithOutline(at: point, in: ctx)
                
                // Draw place name if available
                if let placeName = placeNames[dwell.id] {
                    drawPlaceName(at: point, name: placeName, in: ctx, size: size)
                }
            }
        }
        
        return image
    }
    
    // MARK: - Helper Methods
    
    private func calculateBounds(coordinates: [CLLocationCoordinate2D]) -> MapBounds {
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        // Add padding (10%)
        let latPadding = (maxLat - minLat) * 0.1
        let lonPadding = (maxLon - minLon) * 0.1
        
        return MapBounds(
            minLat: minLat - latPadding,
            maxLat: maxLat + latPadding,
            minLon: minLon - lonPadding,
            maxLon: maxLon + lonPadding
        )
    }
    
    private func convertCoordinateToPoint(coordinate: CLLocationCoordinate2D, bounds: MapBounds, size: CGSize) -> CGPoint {
        let x = (coordinate.longitude - bounds.minLon) / (bounds.maxLon - bounds.minLon) * size.width
        let y = (1 - (coordinate.latitude - bounds.minLat) / (bounds.maxLat - bounds.minLat)) * size.height
        return CGPoint(x: x, y: y)
    }
    
    private func drawMarker(at point: CGPoint, color: UIColor, label: String, in ctx: CGContext, size: CGSize) {
        // Draw circle
        ctx.setFillColor(color.cgColor)
        let circleSize: CGFloat = 30
        let circleRect = CGRect(x: point.x - circleSize/2, y: point.y - circleSize/2, width: circleSize, height: circleSize)
        ctx.fillEllipse(in: circleRect)
        
        // Draw white border
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: circleRect)
    }
    
    private func drawMarkerWithOutline(at point: CGPoint, color: UIColor, label: String, in ctx: CGContext, size: CGSize) {
        let circleSize: CGFloat = 30
        let circleRect = CGRect(x: point.x - circleSize/2, y: point.y - circleSize/2, width: circleSize, height: circleSize)
        
        // White outline
        ctx.setFillColor(UIColor.white.cgColor)
        let outlineRect = circleRect.insetBy(dx: -3, dy: -3)
        ctx.fillEllipse(in: outlineRect)
        
        // Colored circle
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: circleRect)
    }
    
    private func drawDwellMarker(at point: CGPoint, in ctx: CGContext) {
        ctx.setFillColor(UIColor.systemPurple.cgColor)
        let size: CGFloat = 20
        let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
        ctx.fillEllipse(in: rect)
        
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: rect)
    }
    
    private func drawDwellMarkerWithOutline(at point: CGPoint, in ctx: CGContext) {
        let size: CGFloat = 20
        let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
        
        // White outline
        ctx.setFillColor(UIColor.white.cgColor)
        let outlineRect = rect.insetBy(dx: -2, dy: -2)
        ctx.fillEllipse(in: outlineRect)
        
        // Purple circle
        ctx.setFillColor(UIColor.systemPurple.cgColor)
        ctx.fillEllipse(in: rect)
    }
    
    struct MapBounds {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
    }
}
