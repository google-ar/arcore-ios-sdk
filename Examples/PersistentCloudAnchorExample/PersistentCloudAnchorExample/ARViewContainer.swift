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
  @EnvironmentObject var manager: CloudAnchorManager

  /// Coordinator to act as `ARSessionDelegate` for `ARView`.
  class Coordinator: NSObject, ARSessionDelegate {
    private enum Constants {
      /// Name of USDZ file to load cloud anchor model from.
      static let cloudAnchorName = "cloud_anchor"
      /// Material for rendered planes.
      static let planeMaterial = UnlitMaterial(
        color: UIColor(red: 0, green: 0, blue: 1, alpha: 0.7))
    }

    private let manager: CloudAnchorManager
    fileprivate let arView = ARView(
      frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private let worldOrigin = AnchorEntity(world: matrix_identity_float4x4)
    private var planeModels: [UUID: ModelEntity] = [:]
    private var resolvedModels: [UUID: Entity] = [:]
    private var hostedAnchorId: UUID?
    private var hostedModel: Entity?
    private var qualityIndicator: QualityIndicator?
    private var startedHosting: Bool = false

    fileprivate init(manager: CloudAnchorManager) {
      self.manager = manager
      super.init()
      arView.scene.addAnchor(worldOrigin)
      arView.session.delegate = self
      manager.startSession(arView: arView)
    }

    private static func createCloudAnchorModel() -> Entity? {
      return try? Entity.load(named: Constants.cloudAnchorName)
    }

    private static func createPlaneMesh(for planeAnchor: ARPlaneAnchor) -> MeshResource? {
      var descriptor = MeshDescriptor()
      descriptor.positions = MeshBuffers.Positions(planeAnchor.geometry.vertices)
      descriptor.primitives = .triangles(planeAnchor.geometry.triangleIndices.map { UInt32($0) })
      return try? MeshResource.generate(from: [descriptor])
    }

    private static func createPlaneModel(for planeAnchor: ARPlaneAnchor) -> ModelEntity? {
      guard let mesh = createPlaneMesh(for: planeAnchor) else {
        return nil
      }
      return ModelEntity(mesh: mesh, materials: [Constants.planeMaterial])
    }

    private static func updatePlaneModel(_ model: ModelEntity, planeAnchor: ARPlaneAnchor) {
      guard let planeMesh = createPlaneMesh(for: planeAnchor) else {
        return
      }
      model.model?.mesh = planeMesh
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
      for anchor in anchors {
        if anchor is AREnvironmentProbeAnchor { continue }
        if let planeAnchor = (anchor as? ARPlaneAnchor) {
          guard let model = Coordinator.createPlaneModel(for: planeAnchor) else { continue }
          planeModels[planeAnchor.identifier] = model
          let anchorEntity = AnchorEntity(.anchor(identifier: anchor.identifier))
          anchorEntity.addChild(model)
          arView.scene.addAnchor(anchorEntity)
          continue
        }
        guard let model = Coordinator.createCloudAnchorModel() else { continue }
        hostedModel = model
        hostedAnchorId = anchor.identifier
        let anchorEntity = AnchorEntity(.anchor(identifier: anchor.identifier))
        anchorEntity.addChild(model)
        qualityIndicator = QualityIndicator(
          parent: model, isOnHorizontalPlane: manager.isOnHorizontalPlane)
        arView.scene.addAnchor(anchorEntity)
      }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
      for anchor in anchors {
        guard let planeAnchor = (anchor as? ARPlaneAnchor) else { continue }
        guard let model = planeModels[planeAnchor.identifier] else { continue }
        Coordinator.updatePlaneModel(model, planeAnchor: planeAnchor)
      }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
      for anchor in anchors {
        guard let planeAnchor = (anchor as? ARPlaneAnchor) else { continue }
        let model = planeModels.removeValue(forKey: planeAnchor.identifier)
        model?.parent?.removeFromParent()
      }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      guard let garSession = manager.garSession, let garFrame = try? garSession.update(frame) else {
        return
      }
      for garAnchor in garFrame.anchors {
        if let model = resolvedModels[garAnchor.identifier] {
          model.transform = Transform(matrix: garAnchor.transform)
          continue
        }
        guard let model = Coordinator.createCloudAnchorModel() else { continue }
        resolvedModels[garAnchor.identifier] = model
        model.transform = Transform(matrix: garAnchor.transform)
        worldOrigin.addChild(model)
      }

      guard !startedHosting, frame.camera.trackingState == .normal, let hostedAnchorId,
        let qualityIndicator,
        let anchor = frame.anchors.first(where: { $0.identifier == hostedAnchorId })
      else { return }
      let quality =
        (try? garSession.estimateFeatureMapQualityForHosting(frame.camera.transform))
        ?? .insufficient
      let anchorFromCamera = simd_mul(simd_inverse(anchor.transform), frame.camera.transform)
      let (averageQuality, distance) = qualityIndicator.update(
        quality: quality, anchorFromCamera: anchorFromCamera)
      let didHost = manager.processFrame(
        anchor: anchor, quality: quality, averageQuality: averageQuality, distance: distance)
      if didHost {
        startedHosting = true
      }
    }
  }

  func makeUIView(context: Context) -> ARView {
    return context.coordinator.arView
  }

  func updateUIView(_ uiView: ARView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(manager: manager)
  }
}
