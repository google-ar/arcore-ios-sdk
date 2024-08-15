//
// Copyright 2024 Google LLC. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import ARCore
import ARKit
import RealityKit
import SwiftUI
import simd

/// SwiftUI wrapper for an `ARView` and all rendering code.
struct ARViewContainer: UIViewRepresentable {
  let manager: GeospatialManager

  /// Coordinator to act as `ARSessionDelegate` for `ARView`.
  class Coordinator: NSObject, ARSessionDelegate {
    private enum Constants {
      /// Name of USDZ file to load Geospatial marker model from.
      static let geospatialMarkerName = "geospatial_marker"
      /// Material for terrain mesh.
      static let terrainMaterial = UnlitMaterial(
        color: UIColor(red: 0, green: 0.5, blue: 0, alpha: 0.7))
      /// Material for rendered planes.
      static let planeMaterial = UnlitMaterial(
        color: UIColor(red: 0, green: 0, blue: 1, alpha: 0.7))

      static func textureName(anchorType: GeospatialManager.AnchorType) -> String {
        return anchorType == .geospatial ? "spatial-marker-baked" : "spatial-marker-yellow"
      }

      static func randomBuildingMaterial() -> UnlitMaterial {
        let colors = [
          UIColor(red: 0.7, green: 0, blue: 0.7, alpha: 0.8),
          UIColor(red: 0.7, green: 0.7, blue: 0, alpha: 0.8),
          UIColor(red: 0, green: 0.7, blue: 0.7, alpha: 0.8),
        ]
        return UnlitMaterial(color: colors.randomElement()!)
      }
    }

    private let manager: GeospatialManager
    private var worldOrigin = AnchorEntity(world: matrix_identity_float4x4)
    private var anchorModels: [UUID: ModelEntity] = [:]
    private var streetscapeGeometryModels: [UUID: ModelEntity] = [:]
    private var planeModels: [UUID: ModelEntity] = [:]

    init(_ manager: GeospatialManager) {
      self.manager = manager
      super.init()
      manager.arView.session.delegate = self
      manager.arView.scene.addAnchor(worldOrigin)
    }

    private static func createMarkerModel(anchorType: GeospatialManager.AnchorType) -> ModelEntity?
    {
      do {
        let entity = try Entity.loadModel(named: Constants.geospatialMarkerName)
        var material = UnlitMaterial()
        material.color.texture = MaterialParameters.Texture(
          try .load(named: Constants.textureName(anchorType: anchorType)))
        entity.model?.materials = [material]
        return entity
      } catch {
        return nil
      }
    }

    private static func createStreetscapeGeometryModel(_ geometry: GARStreetscapeGeometry)
      -> ModelEntity?
    {
      var descriptor = MeshDescriptor()

      var vertices: [simd_float3] = []
      for i in 0..<Int(geometry.mesh.vertexCount) {
        let vertex = geometry.mesh.vertices[i]
        vertices.append(simd_make_float3(vertex.x, vertex.y, vertex.z))
      }
      descriptor.positions = MeshBuffers.Positions(vertices)

      var triangleIndices: [UInt32] = []
      for i in 0..<Int(geometry.mesh.triangleCount) {
        let triangle = geometry.mesh.triangles[i]
        triangleIndices.append(triangle.indices.0)
        triangleIndices.append(triangle.indices.1)
        triangleIndices.append(triangle.indices.2)
      }
      descriptor.primitives = .triangles(triangleIndices)

      guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
      let material =
        (geometry.type == .terrain) ? Constants.terrainMaterial : Constants.randomBuildingMaterial()
      let model = ModelEntity(mesh: mesh, materials: [material])

      // Need the iOS 18 SDK for `triangleFillMode`.
      #if __IPHONE_18_0
        if #available(iOS 18, *) {
          let linesMaterial = UnlitMaterial(color: .black)
          linesMaterial.triangleFillMode = .lines
          model.addChild(ModelEntity(mesh: mesh, materials: [linesMaterial]))
        }
      #endif

      return model
    }

    private static func createPlaneMesh(planeAnchor: ARPlaneAnchor) -> MeshResource? {
      var descriptor = MeshDescriptor()
      descriptor.positions = MeshBuffers.Positions(planeAnchor.geometry.vertices)
      descriptor.primitives = .triangles(planeAnchor.geometry.triangleIndices.map { UInt32($0) })
      return try? MeshResource.generate(from: [descriptor])
    }

    private static func createPlaneModel(planeAnchor: ARPlaneAnchor) -> ModelEntity? {
      guard let mesh = createPlaneMesh(planeAnchor: planeAnchor) else { return nil }
      return ModelEntity(mesh: mesh, materials: [Constants.planeMaterial])
    }

    private static func updatePlaneModel(model: ModelEntity, planeAnchor: ARPlaneAnchor) {
      guard let mesh = createPlaneMesh(planeAnchor: planeAnchor) else { return }
      model.model?.mesh = mesh
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
      for anchor in anchors {
        guard let planeAnchor = (anchor as? ARPlaneAnchor) else { continue }
        guard let model = Coordinator.createPlaneModel(planeAnchor: planeAnchor) else { continue }
        planeModels[anchor.identifier] = model
        let anchorEntity = AnchorEntity(.anchor(identifier: anchor.identifier))
        anchorEntity.addChild(model)
        manager.arView.scene.addAnchor(anchorEntity)
      }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
      for anchor in anchors {
        guard let planeAnchor = (anchor as? ARPlaneAnchor) else { continue }
        guard let model = planeModels[planeAnchor.identifier] else { continue }
        Coordinator.updatePlaneModel(model: model, planeAnchor: planeAnchor)
      }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
      for anchor in anchors {
        guard anchor is ARPlaneAnchor else { continue }
        let model = planeModels.removeValue(forKey: anchor.identifier)
        model?.parent?.removeFromParent()
      }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      guard let garFrame = manager.update(frame) else { return }

      // Hide all anchors and geometries if not localized to high accuracy.
      worldOrigin.isEnabled = manager.earthTracking && manager.highAccuracy

      var currentAnchorIds = Set<UUID>()
      for garAnchor in garFrame.anchors {
        currentAnchorIds.insert(garAnchor.identifier)

        var model = anchorModels[garAnchor.identifier]
        if model == nil {
          guard let anchorType = manager.anchorTypes[garAnchor.identifier] else { continue }
          model = Coordinator.createMarkerModel(anchorType: anchorType)
          anchorModels[garAnchor.identifier] = model
          model?.setParent(worldOrigin)
        }
        guard let model else { continue }

        // Rotate the virtual object 180 degrees around the Y axis to make the object face the GL
        // camera -Z axis, since camera Z axis faces toward users.
        let rotation = simd_quaternion(Float.pi, simd_make_float3(0, 1, 0))
        model.transform = Transform(matrix: simd_mul(garAnchor.transform, simd_matrix4x4(rotation)))

        // Scale up anchors which are far from the camera.
        let distance = simd_distance(
          frame.camera.transform.columns.3, garAnchor.transform.columns.3)
        let scale = 1.0 + (simd_clamp(distance, 5.0, 20.0) - 5.0) / 15.0
        model.scale = simd_make_float3(scale, scale, scale)
      }

      for anchorId in anchorModels.keys {
        if !currentAnchorIds.contains(anchorId) {
          anchorModels[anchorId]?.removeFromParent()
        }
      }

      for (_, model) in planeModels {
        // Hide planes when showing Streetscape Geometry.
        model.isEnabled = !manager.streetscapeGeometryEnabled
      }

      guard let geometries = garFrame.streetscapeGeometries else {
        for (_, model) in streetscapeGeometryModels {
          model.removeFromParent()
        }
        streetscapeGeometryModels.removeAll()
        return
      }

      for geometry in geometries {
        var model = streetscapeGeometryModels[geometry.identifier]
        if model == nil {
          model = Coordinator.createStreetscapeGeometryModel(geometry)
          streetscapeGeometryModels[geometry.identifier] = model
          model?.setParent(worldOrigin)
        }
        guard let model else { continue }

        model.transform = Transform(matrix: geometry.meshTransform)

        if geometry.trackingState == .stopped {
          // Remove geometries that permanently stopped tracking.
          streetscapeGeometryModels.removeValue(forKey: geometry.identifier)
          model.removeFromParent()
        } else {
          // Hide geometries if not actively tracking.
          model.isEnabled = (geometry.trackingState == .tracking)
        }
      }
    }
  }

  func makeUIView(context: Context) -> ARView {
    return manager.arView
  }

  func updateUIView(_ uiView: ARView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    return Coordinator(manager)
  }
}
