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
import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// SwiftUI wrapper for an `ARView` and all rendering code.
struct ARViewContainer: UIViewRepresentable {
  let manager: CloudAnchorManager

  /// Coordinator to act as `ARSessionDelegate` for `ARView`.
  class Coordinator: NSObject, ARSessionDelegate {
    private enum Constants {
      /// Name of USDZ file to load Android model from.
      static let andyName = "andy"
      /// Material for rendered planes.
      static let planeMaterial = UnlitMaterial(
        color: UIColor(red: 0, green: 0, blue: 1, alpha: 0.7))
    }

    private let manager: CloudAnchorManager
    private var hostedAnchorModel: Entity?
    private var resolvedAnchorModel: Entity?
    private var planeModels: [UUID: ModelEntity] = [:]

    init(manager: CloudAnchorManager) {
      self.manager = manager
      super.init()
      manager.arView.session.delegate = self
    }

    private static func createAndyNode() -> Entity? {
      return try? Entity.load(named: Constants.andyName)
    }

    private static func createPlaneMesh(plane: ARPlaneAnchor) -> MeshResource? {
      var descriptor = MeshDescriptor()
      descriptor.positions = MeshBuffers.Positions(plane.geometry.vertices)
      descriptor.primitives = .triangles(plane.geometry.triangleIndices.map { UInt32($0) })
      return try? MeshResource.generate(from: [descriptor])
    }

    private static func createPlaneModel(plane: ARPlaneAnchor) -> ModelEntity? {
      guard let mesh = createPlaneMesh(plane: plane) else {
        return nil
      }
      return ModelEntity(mesh: mesh, materials: [Constants.planeMaterial])
    }

    private static func updatePlaneModel(model: ModelEntity, plane: ARPlaneAnchor) {
      guard let planeMesh = createPlaneMesh(plane: plane) else {
        return
      }
      model.model?.mesh = planeMesh
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
      for anchor in anchors {
        if anchor is AREnvironmentProbeAnchor { continue }
        if let plane = (anchor as? ARPlaneAnchor) {
          guard let model = Coordinator.createPlaneModel(plane: plane) else { continue }
          planeModels[plane.identifier] = model
          let anchorEntity = AnchorEntity(.anchor(identifier: anchor.identifier))
          anchorEntity.addChild(model)
          manager.arView.scene.addAnchor(anchorEntity)
          continue
        }
        guard let model = Coordinator.createAndyNode() else { continue }
        hostedAnchorModel = model
        let anchorEntity = AnchorEntity(.anchor(identifier: anchor.identifier))
        anchorEntity.addChild(model)
        manager.arView.scene.addAnchor(anchorEntity)
      }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
      for anchor in anchors {
        if anchor is AREnvironmentProbeAnchor { continue }
        if let plane = (anchor as? ARPlaneAnchor) {
          guard let model = planeModels.removeValue(forKey: plane.identifier) else { continue }
          model.parent?.removeFromParent()
          continue
        }
        hostedAnchorModel?.parent?.removeFromParent()
        hostedAnchorModel = nil
      }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
      for anchor in anchors {
        guard let plane = (anchor as? ARPlaneAnchor) else { continue }
        guard let model = planeModels[plane.identifier] else { continue }
        Coordinator.updatePlaneModel(model: model, plane: plane)
      }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      guard let garFrame = try? manager.garSession?.update(frame) else { return }
      guard let garAnchor = garFrame.anchors.first else {
        resolvedAnchorModel?.parent?.removeFromParent()
        resolvedAnchorModel = nil
        return
      }
      if resolvedAnchorModel == nil {
        guard let model = Coordinator.createAndyNode() else { return }
        resolvedAnchorModel = model
        let anchorEntity = AnchorEntity(world: matrix_identity_float4x4)
        anchorEntity.addChild(model)
        manager.arView.scene.addAnchor(anchorEntity)
      }
      guard let resolvedAnchorModel else { return }
      resolvedAnchorModel.transform = Transform(matrix: garAnchor.transform)
      resolvedAnchorModel.isEnabled = (garAnchor.trackingState == .tracking)
    }
  }

  func makeUIView(context: Context) -> some UIView {
    return manager.arView
  }

  func updateUIView(_ uiView: UIViewType, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(manager: manager)
  }
}
