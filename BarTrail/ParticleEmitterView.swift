//
//  ParticleEmitterView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import SwiftUI
import UIKit // Still needed for CAEmitterLayer, UIView, UIColor, UIImage

// MARK: - Particle Emitter View (Add this to your project)
struct ParticleEmitterView: UIViewRepresentable {
    let duration: TimeInterval = 4.0
    
    func makeUIView(context: Context) -> UIView {
        let size = CGSize(width: 400.0, height: 400.0)
        let host = UIView(frame: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
        
        let particlesLayer = CAEmitterLayer()
        particlesLayer.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height)
        
        host.layer.addSublayer(particlesLayer)
        host.layer.masksToBounds = true
        
        particlesLayer.backgroundColor = UIColor.clear.cgColor
        particlesLayer.emitterShape = .point
        particlesLayer.emitterPosition = CGPoint(x: size.width / 2, y: size.height)
        particlesLayer.emitterSize = CGSize(width: 0.0, height: 0.0)
        particlesLayer.emitterMode = .outline
        particlesLayer.renderMode = .additive
        
        // Parent cell
        let cell1 = CAEmitterCell()
        cell1.name = "Parent"
        cell1.birthRate = 3.0
        cell1.lifetime = 2.5
        cell1.velocity = 200.0
        cell1.velocityRange = 80.0
        cell1.yAcceleration = -100.0
        cell1.emissionLongitude = -90.0 * (.pi / 180.0)
        cell1.emissionRange = 45.0 * (.pi / 180.0)
        cell1.scale = 0.0
        cell1.color = UIColor.white.cgColor
        cell1.redRange = 0.9
        cell1.greenRange = 0.9
        cell1.blueRange = 0.9
        
        // Trail subcell
        let subcell1_1 = CAEmitterCell()
        subcell1_1.contents = UIImage(named: "Spark")?.cgImage
        subcell1_1.name = "Trail"
        subcell1_1.birthRate = 30.0
        subcell1_1.lifetime = 0.5
        subcell1_1.beginTime = 0.01
        subcell1_1.duration = 1.7
        subcell1_1.velocity = 60.0
        subcell1_1.velocityRange = 80.0
        subcell1_1.xAcceleration = 80.0
        subcell1_1.yAcceleration = 250.0
        subcell1_1.emissionLongitude = -360.0 * (.pi / 180.0)
        subcell1_1.emissionRange = 22.5 * (.pi / 180.0)
        subcell1_1.scale = 0.4
        subcell1_1.scaleSpeed = 0.1
        subcell1_1.alphaSpeed = -0.7
        subcell1_1.color = UIColor.white.cgColor
        
        // Firework subcell
        let subcell1_2 = CAEmitterCell()
        subcell1_2.contents = UIImage(named: "Spark")?.cgImage
        subcell1_2.name = "Firework"
        subcell1_2.birthRate = 15000.0
        subcell1_2.lifetime = 10.0
        subcell1_2.beginTime = 1.6
        subcell1_2.duration = 0.1
        subcell1_2.velocity = 150.0
        subcell1_2.yAcceleration = 60.0
        subcell1_2.emissionRange = 360.0 * (.pi / 180.0)
        subcell1_2.spin = 114.6 * (.pi / 180.0)
        subcell1_2.scale = 0.08
        subcell1_2.scaleSpeed = 0.07
        subcell1_2.alphaSpeed = -0.7
        subcell1_2.color = UIColor.white.cgColor
        
        cell1.emitterCells = [subcell1_1, subcell1_2]
        particlesLayer.emitterCells = [cell1]
        
        // Store reference in coordinator
        context.coordinator.particlesLayer = particlesLayer
        context.coordinator.hostView = host
        
        // Start fade out sequence
        context.coordinator.startFadeOutSequence(duration: duration)
        
        return host
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var particlesLayer: CAEmitterLayer?
        var hostView: UIView?
        
        func startFadeOutSequence(duration: TimeInterval) {
            // Stop emitting new particles 1 second before end
            DispatchQueue.main.asyncAfter(deadline: .now() + (duration - 1.0)) {
                self.particlesLayer?.birthRate = 0
            }
            
            // Start fading out the entire view 0.5 seconds before end
            DispatchQueue.main.asyncAfter(deadline: .now() + (duration - 0.5)) {
                UIView.animate(withDuration: 0.5) {
                    self.hostView?.alpha = 0.0
                }
            }
        }
    }
}
