// SemanticMeshClassifier.swift
// Clasifica mallas ARMeshAnchor en categorías semánticas.
// Fuente primaria: ARMeshClassification de ARKit.
// Fallback: heurísticas de normal dominante + posición + volumen.

import ARKit
import simd
import Foundation

// MARK: - MeshCategory

enum MeshCategory: String, Codable, CaseIterable {
    case wall      = "wall"
    case floor     = "floor"
    case ceiling   = "ceiling"
    case door      = "door"
    case window    = "window"
    case furniture = "furniture"
    case appliance = "appliance"
    case unknown   = "unknown"

    /// Color de visualización en SceneViewer (meshSemantic mode).
    var displayColor: UIColor {
        switch self {
        case .wall:      return UIColor(white: 1.0, alpha: 0.90)                        // blanco
        case .floor:     return UIColor(white: 0.50, alpha: 0.90)                       // gris
        case .ceiling:   return UIColor(white: 0.78, alpha: 0.90)                       // gris claro
        case .door:      return UIColor(red: 0.20, green: 0.45, blue: 1.00, alpha: 0.90) // azul
        case .window:    return UIColor(red: 0.30, green: 0.90, blue: 0.95, alpha: 0.90) // cian
        case .furniture: return UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 0.90) // naranja
        case .appliance: return UIColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 0.90) // rojo
        case .unknown:   return UIColor(white: 0.40, alpha: 0.70)                       // gris oscuro
        }
    }
}

// MARK: - SemanticMeshResult

/// Resultado serializable de la clasificación para persistencia JSON.
struct SemanticMeshResult: Codable {
    struct Entry: Codable {
        let anchorID:    String
        let category:   MeshCategory
        let triangleCount: Int
        let centerWorld: [Float]   // SIMD3 como [x, y, z]
    }
    let entries: [Entry]
    let timestamp: TimeInterval

    static var saveURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("semantic_mesh.json")
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.saveURL, options: .atomic)
    }

    static func load() -> SemanticMeshResult? {
        guard let data = try? Data(contentsOf: saveURL) else { return nil }
        return try? JSONDecoder().decode(SemanticMeshResult.self, from: data)
    }
}

// MARK: - SemanticMeshClassifier

class SemanticMeshClassifier {

    static let shared = SemanticMeshClassifier()

    /// Número mínimo de triángulos para considerar un anchor válido.
    private let minTriangleCount = 80

    private init() {}

    // MARK: - API pública

    /// Clasifica un anchor usando ARMeshClassification si disponible, luego heurísticas.
    func classify(anchor: ARMeshAnchor) -> MeshCategory {
        let geo = anchor.geometry
        guard geo.faces.count >= minTriangleCount else { return .unknown }

        // 1. Voto mayoritario de ARMeshClassification nativo
        if let arCategory = dominantARKitClassification(geo: geo) {
            return arCategory
        }

        // 2. Heurística: normal dominante en espacio mundo
        let worldTransform = anchor.transform
        let dominantNormal = computeDominantNormal(geo: geo, transform: worldTransform)
        return heuristicCategory(
            normal:    dominantNormal,
            transform: worldTransform,
            geo:       geo
        )
    }

    /// Divide una lista de ARMeshAnchor en grupos por categoría.
    func splitMeshByCategory(anchors: [ARMeshAnchor]) -> [MeshCategory: [ARMeshAnchor]] {
        var result: [MeshCategory: [ARMeshAnchor]] = [:]
        for anchor in anchors {
            let cat = classify(anchor: anchor)
            result[cat, default: []].append(anchor)
        }
        return result
    }

    // MARK: - Clasificación ARKit

    private func dominantARKitClassification(geo: ARMeshGeometry) -> MeshCategory? {
        guard let clsSource = geo.classification else { return nil }
        let triCount = geo.faces.count
        let iCount   = geo.faces.indexCountPerPrimitive   // normalmente 3

        // clasificación es por vértice (stride en bytes)
        let clsPtr    = clsSource.buffer.contents()
            .advanced(by: clsSource.offset)
            .assumingMemoryBound(to: UInt8.self)
        let clsByteStride = clsSource.stride   // bytes entre clasificaciones

        let facePtr = geo.faces.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)

        var votes: [UInt8: Int] = [:]
        for f in 0..<triCount {
            // Usar el primer vértice de cada triángulo como representativo
            let vi = Int(facePtr[f * iCount])
            let clsVal = clsPtr[vi * clsByteStride]
            votes[clsVal, default: 0] += 1
        }

        guard let (dominantCls, count) = votes.max(by: { $0.value < $1.value }),
              count > triCount / 3 else { return nil }  // necesita >33% de acuerdo

        return categoryFromARKitCode(dominantCls)
    }

    private func categoryFromARKitCode(_ code: UInt8) -> MeshCategory? {
        // ARMeshClassification: 0=none, 1=wall, 2=floor, 3=ceiling, 4=table, 5=seat, 6=window, 7=door
        switch code {
        case 1: return .wall
        case 2: return .floor
        case 3: return .ceiling
        case 4: return .furniture   // table → furniture
        case 5: return .furniture   // seat  → furniture
        case 6: return .window
        case 7: return .door
        default: return nil         // none / desconocido → heurística
        }
    }

    // MARK: - Heurísticas

    private func computeDominantNormal(geo: ARMeshGeometry,
                                        transform: simd_float4x4) -> SIMD3<Float> {
        guard let normSource = geo.normals else {
            // Si no hay normales, usar posiciones para estimar
            return estimateNormalFromPositions(geo: geo, transform: transform)
        }

        let nPtr = normSource.buffer.contents()
            .advanced(by: normSource.offset)
            .assumingMemoryBound(to: Float.self)
        let nStride = normSource.stride / MemoryLayout<Float>.stride
        let count   = min(geo.vertices.count, 200)   // muestra para rapidez

        var accumLocal = SIMD3<Float>.zero
        for i in stride(from: 0, to: count, by: max(1, count / 60)) {
            let nx = nPtr[i * nStride]
            let ny = nPtr[i * nStride + 1]
            let nz = nPtr[i * nStride + 2]
            accumLocal += SIMD3<Float>(nx, ny, nz)
        }
        let localNorm = simd_normalize(accumLocal)

        // Rotar al espacio mundo
        let rotMat = simd_float3x3(columns: (
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        ))
        return simd_normalize(rotMat * localNorm)
    }

    private func estimateNormalFromPositions(geo: ARMeshGeometry,
                                              transform: simd_float4x4) -> SIMD3<Float> {
        guard geo.vertices.count >= 3 else { return SIMD3<Float>(0, 1, 0) }
        let vPtr = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let stride = geo.vertices.stride / MemoryLayout<Float>.stride
        let p0 = SIMD3<Float>(vPtr[0], vPtr[1], vPtr[2])
        let p1 = SIMD3<Float>(vPtr[stride], vPtr[stride+1], vPtr[stride+2])
        let p2 = SIMD3<Float>(vPtr[stride*2], vPtr[stride*2+1], vPtr[stride*2+2])
        let raw = simd_normalize(simd_cross(p1 - p0, p2 - p0))
        let rotMat = simd_float3x3(columns: (
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        ))
        return simd_normalize(rotMat * raw)
    }

    private func heuristicCategory(normal: SIMD3<Float>,
                                    transform: simd_float4x4,
                                    geo: ARMeshGeometry) -> MeshCategory {
        let ny = normal.y

        // Suelo: normal apunta hacia arriba
        if ny > 0.9 { return .floor }

        // Techo: normal apunta hacia abajo
        if ny < -0.9 { return .ceiling }

        // Plano vertical
        if abs(ny) < 0.2 {
            // Diferenciar puerta/ventana de pared genérica
            if looksLikeOpening(geo: geo, transform: transform) {
                // Heurística simple: si la altura media del bounding box está entre 0.7m y 2.2m
                // y el área es pequeña → ventana; si el bounding box toca el suelo → puerta
                let (minY, maxY) = verticalExtent(geo: geo, transform: transform)
                let height = maxY - minY
                if height > 1.5 && minY < 0.3 {
                    return .door
                } else if height < 1.4 && minY > 0.4 {
                    return .window
                }
            }
            return .wall
        }

        // Superficie inclinada con volumen pequeño por encima del suelo → mobiliario
        let center = worldCenter(of: geo, transform: transform)
        if center.y > 0.2 && center.y < 1.5 {
            let volume = estimateBoundingVolume(geo: geo, transform: transform)
            if volume < 1.5 {
                return .furniture
            }
        }

        // Superficie pequeña y elevada → electrodoméstico
        if center.y > 0.5 && center.y < 1.8 {
            let volume = estimateBoundingVolume(geo: geo, transform: transform)
            if volume < 0.4 {
                return .appliance
            }
        }

        return .unknown
    }

    // MARK: - Auxiliares geométricos

    /// Detecta geometría con "hueco" (varianza de distribución de normales alta = apertura).
    private func looksLikeOpening(geo: ARMeshGeometry, transform: simd_float4x4) -> Bool {
        // Heurística: si el anchor tiene pocos triángulos en relación con su área → hueco probable
        let triCount = geo.faces.count
        let area     = estimateSurfaceArea(geo: geo, transform: transform)
        guard area > 0 else { return false }
        let density = Float(triCount) / area   // triángulos/m²
        // Una pared maciza tiene alta densidad de triángulos; una abertura tiene baja densidad
        return density < 120.0
    }

    private func estimateSurfaceArea(geo: ARMeshGeometry, transform: simd_float4x4) -> Float {
        guard geo.faces.count > 0 else { return 0 }
        let verts = extractWorldVertices(geo: geo, transform: transform, maxCount: 300)
        let fPtr  = geo.faces.buffer.contents().assumingMemoryBound(to: UInt32.self)
        let ic    = geo.faces.indexCountPerPrimitive
        var area: Float = 0
        let sample = min(geo.faces.count, 100)
        let step   = max(1, geo.faces.count / sample)
        for f in stride(from: 0, to: geo.faces.count, by: step) {
            let i0 = Int(fPtr[f * ic])
            let i1 = Int(fPtr[f * ic + 1])
            let i2 = Int(fPtr[f * ic + 2])
            guard i0 < verts.count, i1 < verts.count, i2 < verts.count else { continue }
            let cross = simd_cross(verts[i1] - verts[i0], verts[i2] - verts[i0])
            area += simd_length(cross) * 0.5
        }
        return area * Float(geo.faces.count) / Float(sample)  // escalar por muestra
    }

    private func verticalExtent(geo: ARMeshGeometry,
                                 transform: simd_float4x4) -> (minY: Float, maxY: Float) {
        let verts = extractWorldVertices(geo: geo, transform: transform, maxCount: 200)
        let ys = verts.map { $0.y }
        return (ys.min() ?? 0, ys.max() ?? 0)
    }

    private func worldCenter(of geo: ARMeshGeometry,
                              transform: simd_float4x4) -> SIMD3<Float> {
        let verts = extractWorldVertices(geo: geo, transform: transform, maxCount: 100)
        guard !verts.isEmpty else { return SIMD3<Float>(transform.columns.3.x,
                                                         transform.columns.3.y,
                                                         transform.columns.3.z) }
        let sum = verts.reduce(SIMD3<Float>.zero, +)
        return sum / Float(verts.count)
    }

    private func estimateBoundingVolume(geo: ARMeshGeometry,
                                         transform: simd_float4x4) -> Float {
        let verts = extractWorldVertices(geo: geo, transform: transform, maxCount: 200)
        guard !verts.isEmpty else { return 0 }
        var mn = verts[0], mx = verts[0]
        for v in verts {
            mn = simd_min(mn, v)
            mx = simd_max(mx, v)
        }
        let ext = mx - mn
        return ext.x * ext.y * ext.z
    }

    private func extractWorldVertices(geo: ARMeshGeometry,
                                       transform: simd_float4x4,
                                       maxCount: Int) -> [SIMD3<Float>] {
        let total    = geo.vertices.count
        let sampleN  = min(total, maxCount)
        let step     = max(1, total / sampleN)
        let vPtr     = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let vStride  = geo.vertices.stride / MemoryLayout<Float>.stride

        var result = [SIMD3<Float>]()
        result.reserveCapacity(sampleN)
        var i = 0
        while i < total {
            let local = SIMD4<Float>(vPtr[i*vStride], vPtr[i*vStride+1], vPtr[i*vStride+2], 1)
            let world = transform * local
            result.append(SIMD3<Float>(world.x, world.y, world.z))
            i += step
        }
        return result
    }

    // MARK: - Persistencia

    /// Clasifica todos los anchors y guarda resultado en Documents/semantic_mesh.json.
    @discardableResult
    func classifyAndSave(anchors: [ARMeshAnchor]) -> SemanticMeshResult {
        var entries: [SemanticMeshResult.Entry] = []
        for anchor in anchors {
            guard anchor.geometry.faces.count >= minTriangleCount else { continue }
            let cat    = classify(anchor: anchor)
            let center = worldCenter(of: anchor.geometry, transform: anchor.transform)
            entries.append(SemanticMeshResult.Entry(
                anchorID:      anchor.identifier.uuidString,
                category:      cat,
                triangleCount: anchor.geometry.faces.count,
                centerWorld:   [center.x, center.y, center.z]
            ))
        }
        let result = SemanticMeshResult(entries: entries, timestamp: Date().timeIntervalSince1970)
        result.save()
        return result
    }
}

// ARMeshGeometry.classification es una propiedad pública de ARKit (iOS 14+).
// No se necesita extensión — se accede directamente como geo.classification en el código.
