// FloorplanEditorSyncManager.swift
// Sincroniza ediciones entre plano 2D, malla 3D, estructura RoomPlan y SceneGraph.
//
// Flujo de datos:
//   Edición 2D (usuario mueve/redimensiona pared)
//     → WallEdit generado
//     → updateSceneGraph(wall:)     — nodo semántico actualizado
//     → updateRealityKitMesh(wall:) — AnchorEntity reposicionada
//     → updateRoomPlanModel(wall:)  — CapturedRoom overrides locales
//     → notifica observers

import ARKit
import RealityKit
import simd

// MARK: - Edición de pared

struct WallEdit {
    let wallNodeId:    UUID             // SceneNode.id
    let anchorId:      String?          // ARMeshAnchor identifier (opcional)

    // Geometría nueva de la pared
    let startPoint:    SIMD3<Float>     // extremo A en espacio mundo
    let endPoint:      SIMD3<Float>     // extremo B en espacio mundo
    let height:        Float            // metros
    let thickness:     Float            // metros

    var center: SIMD3<Float> {
        (startPoint + endPoint) * 0.5
    }

    var length: Float {
        simd_length(endPoint - startPoint)
    }

    /// Transform: posición=centro, X apunta de start→end, Y=arriba.
    var transform: simd_float4x4 {
        let forward = simd_normalize(endPoint - startPoint)
        let up      = SIMD3<Float>(0, 1, 0)
        let right   = simd_normalize(simd_cross(forward, up))
        let realUp  = simd_cross(right, forward)
        var t = simd_float4x4(1)
        t.columns.0 = SIMD4(forward.x, forward.y, forward.z, 0)
        t.columns.1 = SIMD4(realUp.x,  realUp.y,  realUp.z,  0)
        t.columns.2 = SIMD4(right.x,   right.y,   right.z,   0)
        t.columns.3 = SIMD4(center.x,  center.y,  center.z,  1)
        return t
    }
}

// MARK: - Edición de apertura (puerta / ventana)

struct OpeningEdit {
    let nodeId:     UUID
    let type:       SceneNodeType        // .door o .window
    let center:     SIMD3<Float>
    let width:      Float
    let height:     Float
    let wallNodeId: UUID                 // pared padre
}

// MARK: - Edición de plano libre

enum FloorplanEdit {
    case wall(WallEdit)
    case opening(OpeningEdit)
    case roomResize(nodeId: UUID, newBounds: (min: SIMD2<Float>, max: SIMD2<Float>))
    case nodeDelete(nodeId: UUID)
    case nodeMoveObject(nodeId: UUID, newPosition: SIMD3<Float>)
}

// MARK: - FloorplanEditorSyncManager

class FloorplanEditorSyncManager {

    static let shared = FloorplanEditorSyncManager()

    // MARK: - Dependencias

    private weak var arView: ARView?

    /// Mapa de SceneNode.id → AnchorEntity en la escena RealityKit.
    private var wallEntities: [UUID: AnchorEntity] = [:]

    /// Historial de ediciones para undo.
    private(set) var editHistory: [FloorplanEdit] = []

    // MARK: - Callbacks

    var onWallUpdated:       ((WallEdit) -> Void)?
    var onOpeningUpdated:    ((OpeningEdit) -> Void)?
    var onSceneGraphChanged: (() -> Void)?
    var onMeshChanged:       (() -> Void)?

    // MARK: - Configurar ARView

    func configure(arView: ARView) {
        self.arView = arView
    }

    // MARK: - API pública: aplicar edición

    /// Punto de entrada único para cualquier edición del plano 2D.
    func applyEdit(_ edit: FloorplanEdit) {
        editHistory.append(edit)

        switch edit {
        case .wall(let wallEdit):
            applyWallEdit(wallEdit)

        case .opening(let openingEdit):
            applyOpeningEdit(openingEdit)

        case .roomResize(let nodeId, let bounds):
            applyRoomResize(nodeId: nodeId, newBounds: bounds)

        case .nodeDelete(let nodeId):
            applyNodeDelete(nodeId: nodeId)

        case .nodeMoveObject(let nodeId, let position):
            applyObjectMove(nodeId: nodeId, newPosition: position)
        }
    }

    // MARK: - Registrar AnchorEntity existente para una pared

    func registerWallEntity(_ anchor: AnchorEntity, forNodeId nodeId: UUID) {
        wallEntities[nodeId] = anchor
    }

    // MARK: - Aplicar edición de pared

    private func applyWallEdit(_ edit: WallEdit) {
        // 1. SceneGraph
        updateSceneGraph(wall: edit)

        // 2. Mesh RealityKit
        updateRealityKitMesh(wall: edit)

        // 3. Override local del modelo RoomPlan
        if #available(iOS 16.0, *) {
            updateRoomPlanModel(wall: edit)
        }

        onWallUpdated?(edit)
        onSceneGraphChanged?()
        onMeshChanged?()
    }

    // MARK: - Aplicar edición de apertura

    private func applyOpeningEdit(_ edit: OpeningEdit) {
        // Actualizar nodo en SceneGraph
        SceneGraphManager.shared.updateNode(id: edit.nodeId) { node in
            let t = simd_float4x4(translation: edit.center)
            node = SceneNode(
                id:        node.id,
                type:      edit.type,
                label:     edit.type == .door ? "puerta" : "ventana",
                transform: t,
                children:  node.children,
                metadata:  ["width":  String(format: "%.2f", edit.width),
                             "height": String(format: "%.2f", edit.height)],
                boundingMin: SIMD3(-edit.width/2, 0, -0.05),
                boundingMax: SIMD3( edit.width/2, edit.height, 0.05)
            )
        }

        // Actualizar malla de apertura si existe entidad
        if let entity = wallEntities[edit.nodeId] {
            DispatchQueue.main.async {
                let newTransform = Transform(
                    scale:       SIMD3(edit.width, edit.height, 0.1),
                    rotation:    simd_quatf(matrix_identity_float4x4),
                    translation: edit.center
                )
                entity.move(to: newTransform, relativeTo: nil)
            }
        }

        onOpeningUpdated?(edit)
        onSceneGraphChanged?()
    }

    // MARK: - Aplicar redimensionado de habitación

    private func applyRoomResize(nodeId: UUID,
                                 newBounds: (min: SIMD2<Float>, max: SIMD2<Float>)) {
        SceneGraphManager.shared.updateNode(id: nodeId) { node in
            node.minX = newBounds.min.x
            node.minZ = newBounds.min.y
            node.maxX = newBounds.max.x
            node.maxZ = newBounds.max.y
            node.metadata["floorArea"] = String(
                format: "%.2f",
                (newBounds.max.x - newBounds.min.x) * (newBounds.max.y - newBounds.min.y)
            )
        }
        onSceneGraphChanged?()
    }

    // MARK: - Eliminar nodo

    private func applyNodeDelete(nodeId: UUID) {
        // Quitar de escena RealityKit
        DispatchQueue.main.async {
            self.wallEntities[nodeId]?.removeFromParent()
            self.wallEntities.removeValue(forKey: nodeId)
        }
        SceneGraphManager.shared.removeNode(id: nodeId)
        onSceneGraphChanged?()
        onMeshChanged?()
    }

    // MARK: - Mover objeto

    private func applyObjectMove(nodeId: UUID, newPosition: SIMD3<Float>) {
        SceneGraphManager.shared.updateNode(id: nodeId) { node in
            node.t30 = newPosition.x
            node.t31 = newPosition.y
            node.t32 = newPosition.z
        }
        if let entity = wallEntities[nodeId] {
            DispatchQueue.main.async {
                entity.move(to: Transform(translation: newPosition), relativeTo: nil)
            }
        }
        onSceneGraphChanged?()
    }

    // MARK: - 1. Actualizar SceneGraph

    private func updateSceneGraph(wall: WallEdit) {
        let t = wall.transform
        SceneGraphManager.shared.updateNode(id: wall.wallNodeId) { node in
            // Reescribir transform
            node.t00 = t.columns.0.x; node.t01 = t.columns.0.y
            node.t02 = t.columns.0.z; node.t03 = t.columns.0.w
            node.t10 = t.columns.1.x; node.t11 = t.columns.1.y
            node.t12 = t.columns.1.z; node.t13 = t.columns.1.w
            node.t20 = t.columns.2.x; node.t21 = t.columns.2.y
            node.t22 = t.columns.2.z; node.t23 = t.columns.2.w
            node.t30 = t.columns.3.x; node.t31 = t.columns.3.y
            node.t32 = t.columns.3.z; node.t33 = t.columns.3.w

            node.minX = -wall.length / 2; node.maxX = wall.length / 2
            node.minY = 0;               node.maxY = wall.height
            node.minZ = -wall.thickness / 2; node.maxZ = wall.thickness / 2

            node.metadata["length"]    = String(format: "%.2f", wall.length)
            node.metadata["height"]    = String(format: "%.2f", wall.height)
            node.metadata["thickness"] = String(format: "%.2f", wall.thickness)
        }
    }

    // MARK: - 2. Actualizar malla RealityKit

    private func updateRealityKitMesh(wall: WallEdit) {
        DispatchQueue.main.async {
            guard let arView = self.arView else { return }

            // Construir box para la pared
            let mesh     = MeshResource.generateBox(
                size: SIMD3(wall.length, wall.height, wall.thickness))
            var material = SimpleMaterial()
            material.color = .init(tint: UIColor(red: 0.8, green: 0.85, blue: 1.0, alpha: 0.5))

            let model = ModelEntity(mesh: mesh, materials: [material])

            if let existing = self.wallEntities[wall.wallNodeId] {
                // Actualizar entidad existente
                existing.children.forEach { $0.removeFromParent() }
                existing.addChild(model)
                existing.move(
                    to: Transform(matrix: wall.transform),
                    relativeTo: nil
                )
            } else {
                // Crear nueva entidad
                let anchor = AnchorEntity(world: wall.center)
                anchor.name = "wall_\(wall.wallNodeId.uuidString)"
                anchor.addChild(model)
                arView.scene.addAnchor(anchor)
                self.wallEntities[wall.wallNodeId] = anchor
            }
        }
    }

    // MARK: - 3. Override local del modelo RoomPlan

    @available(iOS 16.0, *)
    private func updateRoomPlanModel(wall: WallEdit) {
        // RoomPlan no expone mutación directa de CapturedRoom.
        // Guardamos las ediciones como overrides locales en SceneGraph,
        // que se aplican al exportar o al renderizar el plano.
        SceneGraphManager.shared.updateNode(id: wall.wallNodeId) { node in
            node.metadata["editedAt"] = ISO8601DateFormatter().string(from: Date())
            node.metadata["source"]   = "floorplanEditor"
        }
        // Notificar a RoomPlanManager para que regenere el footprint
        RoomPlanManager.shared.buildFloorFootprint()
    }

    // MARK: - Undo

    func undoLastEdit() {
        guard !editHistory.isEmpty else { return }
        editHistory.removeLast()
        // TODO: snapshot-based undo — guardar estado anterior por edición
        print("[FloorplanSync] undo — \(editHistory.count) ediciones restantes")
    }

    // MARK: - Persistir estado tras edición

    func saveAfterEdit(projectId: UUID) {
        SceneGraphManager.shared.saveGraph { ok in
            print("[FloorplanSync] sceneGraph guardado tras edición: \(ok)")
        }
    }

    // MARK: - Reset

    func reset() {
        wallEntities.values.forEach { $0.removeFromParent() }
        wallEntities.removeAll()
        editHistory.removeAll()
    }
}

// MARK: - simd_float4x4 translation helper

private extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t.x, t.y, t.z, 1)
    }
}
