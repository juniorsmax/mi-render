// PlanRenderer.swift
// Generación de plano 2D vectorial desde paredes de CapturedRoom.
// Produce CGMutablePath listo para dibujar o exportar.
// Compatible con CoreGraphics, SwiftUI Canvas y exportación PDF.

import CoreGraphics
import UIKit
import RoomPlan

class PlanRenderer {

    static let shared = PlanRenderer()

    // MARK: - Generar path 2D desde paredes RoomPlan

    @available(iOS 16.0, *)
    func generatePlan(from room: CapturedRoom,
                      scale: CGFloat = 100.0) -> CGMutablePath {

        let path = CGMutablePath()

        for wall in room.walls {

            let transform  = wall.transform
            let dimensions = wall.dimensions

            let cx = CGFloat(transform.columns.3.x) * scale
            let cz = CGFloat(transform.columns.3.z) * scale

            let angle = atan2(
                CGFloat(transform.columns.0.z),
                CGFloat(transform.columns.0.x)
            )

            let halfW = CGFloat(dimensions.x) * scale / 2.0

            let startPoint = CGPoint(
                x: cx - halfW * cos(angle),
                y: cz - halfW * sin(angle)
            )
            let endPoint = CGPoint(
                x: cx + halfW * cos(angle),
                y: cz + halfW * sin(angle)
            )

            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }

        for door in room.doors {
            addOpening(door.transform, dimensions: door.dimensions,
                       to: path, scale: scale, dashed: false)
        }

        for window in room.windows {
            addOpening(window.transform, dimensions: window.dimensions,
                       to: path, scale: scale, dashed: true)
        }

        return path
    }

    // MARK: - Renderizar plano en UIImage

    @available(iOS 16.0, *)
    func renderImage(from room: CapturedRoom,
                     size: CGSize = CGSize(width: 800, height: 800)) -> UIImage {

        let path = generatePlan(from: room, scale: 80.0)

        let bounds = path.boundingBox
        let translateX = (size.width  - bounds.width)  / 2 - bounds.minX
        let translateY = (size.height - bounds.height) / 2 - bounds.minY

        var transform = CGAffineTransform(translationX: translateX, y: translateY)
        guard let centeredPath = path.copy(using: &transform) else {
            return UIImage()
        }

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let context = ctx.cgContext

            UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.setStrokeColor(UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 1).cgColor)
            context.setLineWidth(3.0)
            context.setLineCap(.round)
            context.addPath(centeredPath)
            context.strokePath()

            drawCompass(in: context, at: CGPoint(x: size.width - 40, y: 40), radius: 20)
        }
    }

    // MARK: - Exportar a PDF

    @available(iOS 16.0, *)
    func exportPDF(from room: CapturedRoom,
                   named name: String) -> URL? {

        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(name)_plan.pdf")

        UIGraphicsBeginPDFContextToFile(url.path, pageSize, nil)
        UIGraphicsBeginPDFPage()

        if let context = UIGraphicsGetCurrentContext() {
            let path = generatePlan(from: room, scale: 60.0)
            let bounds = path.boundingBox
            let tx = (pageSize.width  - bounds.width)  / 2 - bounds.minX
            let ty = (pageSize.height - bounds.height) / 2 - bounds.minY

            var transform = CGAffineTransform(translationX: tx, y: ty)
            if let centered = path.copy(using: &transform) {
                context.setStrokeColor(UIColor.black.cgColor)
                context.setLineWidth(2.0)
                context.addPath(centered)
                context.strokePath()
            }
        }

        UIGraphicsEndPDFContext()
        return url
    }

    // MARK: - Helpers privados

    private func addOpening(_ transform: simd_float4x4,
                             dimensions: simd_float3,
                             to path: CGMutablePath,
                             scale: CGFloat,
                             dashed: Bool) {

        let cx = CGFloat(transform.columns.3.x) * scale
        let cz = CGFloat(transform.columns.3.z) * scale
        let halfW = CGFloat(dimensions.x) * scale / 2.0
        let angle = atan2(CGFloat(transform.columns.0.z), CGFloat(transform.columns.0.x))

        let start = CGPoint(x: cx - halfW * cos(angle), y: cz - halfW * sin(angle))
        let end   = CGPoint(x: cx + halfW * cos(angle), y: cz + halfW * sin(angle))

        path.move(to: start)
        path.addLine(to: end)
    }

    private func drawCompass(in context: CGContext, at center: CGPoint, radius: CGFloat) {
        context.setFillColor(UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 0.8).cgColor)
        context.addArc(center: center, radius: radius,
                       startAngle: 0, endAngle: .pi * 2, clockwise: true)
        context.fillPath()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.black
        ]
        "N".draw(at: CGPoint(x: center.x - 5, y: center.y - 8), withAttributes: attrs)
    }
}
