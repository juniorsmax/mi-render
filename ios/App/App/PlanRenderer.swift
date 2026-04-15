// PlanRenderer.swift
// Generación de plano 2D vectorial desde:
//   A) CapturedRoom (RoomPlan) — paredes estructurales con puertas/ventanas
//   B) FloorFootprint (ARKit mesh) — contorno del suelo escaneado
//   C) Combinado — footprint como fondo + paredes RoomPlan encima
// Produce CGMutablePath / UIImage / PDF listos para exportar.

import CoreGraphics
import UIKit
import RoomPlan
import simd

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

    // MARK: - Renderizar plano desde FloorFootprint (ARKit mesh, sin RoomPlan)

    func renderFloorFootprint(_ footprint: FloorFootprint,
                               size: CGSize = CGSize(width: 800, height: 800)) -> UIImage {

        let margin: CGFloat = 40
        let usable  = CGSize(width: size.width - margin*2,
                             height: size.height - margin*2)

        // Escala uniforme para que el footprint quepa en el canvas
        let scaleX  = usable.width  / CGFloat(max(footprint.width,  0.1))
        let scaleY  = usable.height / CGFloat(max(footprint.depth,  0.1))
        let scale   = min(scaleX, scaleY)

        // Offset para centrar
        let drawW   = CGFloat(footprint.width) * scale
        let drawH   = CGFloat(footprint.depth) * scale
        let offX    = (size.width  - drawW) / 2 - CGFloat(footprint.minPoint.x) * scale
        let offY    = (size.height - drawH) / 2 - CGFloat(footprint.minPoint.y) * scale

        let path    = footprint.cgPath(scale: scale, offsetX: offX, offsetY: offY)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext

            // Fondo oscuro
            UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))

            // Relleno del suelo
            c.setFillColor(UIColor(red: 0.15, green: 0.14, blue: 0.13, alpha: 1).cgColor)
            c.addPath(path)
            c.fillPath()

            // Contorno del footprint
            c.setStrokeColor(UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 1).cgColor)
            c.setLineWidth(3.0)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.addPath(path)
            c.strokePath()

            // Etiqueta de área
            let label = String(format: "%.1f m²", footprint.area)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.white,
            ]
            label.draw(at: CGPoint(x: 16, y: 16), withAttributes: attrs)

            // Dimensiones
            let dimLabel = String(format: "%.1f × %.1f m", footprint.width, footprint.depth)
            let dimAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor(white: 0.7, alpha: 1),
            ]
            dimLabel.draw(at: CGPoint(x: 16, y: 40), withAttributes: dimAttrs)

            drawCompass(in: c, at: CGPoint(x: size.width - 40, y: 40), radius: 20)
        }
    }

    // MARK: - Plano combinado: footprint de fondo + paredes RoomPlan encima

    @available(iOS 16.0, *)
    func renderCombined(room: CapturedRoom?,
                        footprint: FloorFootprint?,
                        size: CGSize = CGSize(width: 800, height: 800)) -> UIImage {

        // Si solo hay RoomPlan, usa el renderer original
        if let room = room, footprint == nil {
            return renderImage(from: room, size: size)
        }
        // Si solo hay footprint, usa el nuevo renderer
        if let fp = footprint, room == nil {
            return renderFloorFootprint(fp, size: size)
        }
        // Ambos: footprint como fondo, paredes encima
        guard let room = room, let fp = footprint else {
            return UIImage()
        }

        let margin: CGFloat = 40
        let usable  = CGSize(width: size.width - margin*2,
                             height: size.height - margin*2)
        let scaleX  = usable.width  / CGFloat(max(fp.width,  0.1))
        let scaleY  = usable.height / CGFloat(max(fp.depth,  0.1))
        let scale   = min(scaleX, scaleY)
        let drawW   = CGFloat(fp.width) * scale
        let drawH   = CGFloat(fp.depth) * scale
        let offX    = (size.width  - drawW) / 2 - CGFloat(fp.minPoint.x) * scale
        let offY    = (size.height - drawH) / 2 - CGFloat(fp.minPoint.y) * scale

        let fpPath   = fp.cgPath(scale: scale, offsetX: offX, offsetY: offY)
        let wallPath = generatePlan(from: room, scale: scale)

        // Centrar el wallPath sobre el mismo origen
        let wallBounds = wallPath.boundingBox
        let wx = offX - wallBounds.minX + (CGFloat(fp.minPoint.x) * scale)
        let wy = offY - wallBounds.minY + (CGFloat(fp.minPoint.y) * scale)
        var wallT = CGAffineTransform(translationX: wx - offX, y: wy - offY)
        let centeredWalls = wallPath.copy(using: &wallT) ?? wallPath

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext

            UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))

            // Relleno footprint
            c.setFillColor(UIColor(red: 0.15, green: 0.14, blue: 0.13, alpha: 1).cgColor)
            c.addPath(fpPath); c.fillPath()

            // Contorno footprint (gris suave)
            c.setStrokeColor(UIColor(white: 0.4, alpha: 1).cgColor)
            c.setLineWidth(1.5)
            c.addPath(fpPath); c.strokePath()

            // Paredes RoomPlan (dorado)
            c.setStrokeColor(UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 1).cgColor)
            c.setLineWidth(3.0)
            c.setLineCap(.round)
            c.addPath(centeredWalls); c.strokePath()

            // Área
            let label = String(format: "%.1f m²", fp.area)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.white,
            ]
            label.draw(at: CGPoint(x: 16, y: 16), withAttributes: attrs)

            drawCompass(in: c, at: CGPoint(x: size.width - 40, y: 40), radius: 20)
        }
    }

    // MARK: - Exportar FloorFootprint a PDF

    func exportFloorFootprintPDF(_ footprint: FloorFootprint,
                                  named name: String) -> URL? {
        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(name)_footprint.pdf")

        UIGraphicsBeginPDFContextToFile(url.path, pageSize, nil)
        UIGraphicsBeginPDFPage()

        if let context = UIGraphicsGetCurrentContext() {
            let margin: CGFloat = 40
            let usable  = CGSize(width: pageSize.width  - margin*2,
                                 height: pageSize.height - margin*2)
            let scaleX  = usable.width  / CGFloat(max(footprint.width,  0.1))
            let scaleY  = usable.height / CGFloat(max(footprint.depth,  0.1))
            let scale   = min(scaleX, scaleY)
            let drawW   = CGFloat(footprint.width) * scale
            let drawH   = CGFloat(footprint.depth) * scale
            let offX    = (pageSize.width  - drawW) / 2 - CGFloat(footprint.minPoint.x) * scale
            let offY    = (pageSize.height - drawH) / 2 - CGFloat(footprint.minPoint.y) * scale

            let path = footprint.cgPath(scale: scale, offsetX: offX, offsetY: offY)

            // Relleno gris claro
            context.setFillColor(UIColor(white: 0.92, alpha: 1).cgColor)
            context.addPath(path); context.fillPath()

            // Contorno negro
            context.setStrokeColor(UIColor.black.cgColor)
            context.setLineWidth(2.0)
            context.addPath(path); context.strokePath()

            // Área y dimensiones
            let label = String(format: "Superficie suelo: %.2f m²   (%.1f × %.1f m)",
                               footprint.area, footprint.width, footprint.depth)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.darkGray,
            ]
            label.draw(at: CGPoint(x: margin, y: pageSize.height - 30), withAttributes: attrs)
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
