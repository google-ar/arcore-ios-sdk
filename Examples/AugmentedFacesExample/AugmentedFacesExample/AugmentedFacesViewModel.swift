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
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreMotion
import Foundation
import SceneKit
import UIKit
import simd

/// Demonstrates how to use ARCore Augmented Faces with SceneKit.
class AugmentedFacesViewModel: NSObject, ObservableObject {

  // MARK: - Member Variables

  @Published var showsAlert = false
  @Published private(set) var alertWindowTitle = ""
  @Published private(set) var alertMessage = ""
  var viewSize: CGSize?

  // MARK: - Camera / Scene properties

  private var captureDevice: AVCaptureDevice?
  private var captureSession: AVCaptureSession?
  @Published private(set) var scene: SCNScene?
  @Published private(set) var pointOfView = SCNNode()
  private lazy var sceneCamera = SCNCamera()
  private lazy var motionManager = CMMotionManager()

  // MARK: - Face properties

  private var faceSession: GARAugmentedFaceSession?
  private lazy var faceMeshConverter = FaceMeshGeometryConverter()
  private lazy var faceNode = SCNNode()
  private lazy var faceTextureNode = SCNNode()
  private lazy var faceOccluderNode = SCNNode()
  private var faceTextureMaterial = SCNMaterial()
  private var faceOccluderMaterial = SCNMaterial()
  private var noseTipNode: SCNNode?
  private var foreheadLeftNode: SCNNode?
  private var foreheadRightNode: SCNNode?

  // MARK: - Implementation methods

  override init() {
    super.init()

    if !setupScene() {
      return
    }
    if !setupCamera() {
      return
    }
    if !setupMotion() {
      return
    }

    do {
      faceSession = try GARAugmentedFaceSession(
        fieldOfView: captureDevice?.activeFormat.videoFieldOfView ?? 0)
    } catch {
      alertWindowTitle = "A fatal error occurred."
      alertMessage = "Failed to create session. Error description: \(error)"
      showsAlert = true
    }
  }

  /// Create the scene view from a scene and supporting nodes, and add to the view.
  ///
  /// The scene is loaded from 'fox_face.scn' which was created from 'canonical_face_mesh.fbx', the
  /// canonical face mesh asset.
  /// https://developers.google.com/ar/develop/developer-guides/creating-assets-for-augmented-faces
  /// - Returns: true when the function has fatal error; false when not.
  private func setupScene() -> Bool {
    guard let faceImage = UIImage(named: "Face.scnassets/face_texture.png"),
      let scene = SCNScene(named: "Face.scnassets/fox_face.scn"),
      let modelRoot = scene.rootNode.childNode(withName: "asset", recursively: false)
    else {
      alertWindowTitle = "A fatal error occurred."
      alertMessage = "Failed to load face scene!"
      showsAlert = true
      return false
    }
    self.scene = scene

    // SceneKit uses meters for units, while the canonical face mesh asset uses centimeters.
    modelRoot.simdScale = simd_float3(1, 1, 1) * 0.01
    foreheadLeftNode = modelRoot.childNode(withName: "FOREHEAD_LEFT", recursively: true)
    foreheadRightNode = modelRoot.childNode(withName: "FOREHEAD_RIGHT", recursively: true)
    noseTipNode = modelRoot.childNode(withName: "NOSE_TIP", recursively: true)

    faceNode.addChildNode(faceTextureNode)
    faceNode.addChildNode(faceOccluderNode)
    scene.rootNode.addChildNode(faceNode)

    pointOfView.camera = sceneCamera

    faceTextureMaterial.diffuse.contents = faceImage
    // SCNMaterial does not premultiply alpha even with blendMode set to alpha, so do it manually.
    faceTextureMaterial.shaderModifiers =
      [SCNShaderModifierEntryPoint.fragment: "_output.color.rgb *= _output.color.a;"]
    faceOccluderMaterial.colorBufferWriteMask = []

    return true
  }

  /// Setup a camera capture session from the front camera to receive captures.
  /// - Returns: true when the function has fatal error; false when not.
  private func setupCamera() -> Bool {
    guard
      let device =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    else {
      alertWindowTitle = "A fatal error occurred."
      alertMessage = "Failed to get device from AVCaptureDevice."
      showsAlert = true
      return false
    }

    guard
      let input = try? AVCaptureDeviceInput(device: device)
    else {
      alertWindowTitle = "A fatal error occurred."
      alertMessage = "Failed to get device input from AVCaptureDeviceInput."
      showsAlert = true
      return false
    }

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))

    let session = AVCaptureSession()
    session.sessionPreset = .high
    session.addInput(input)
    session.addOutput(output)
    captureSession = session
    captureDevice = device

    // Start capturing images from the capture session once permission is granted.
    getVideoPermission { [weak self] granted in
      guard let self else { return }
      guard granted else {
        NSLog("Permission not granted to use camera.")
        self.alertWindowTitle = "Alert"
        self.alertMessage = "Permission not granted to use camera."
        self.showsAlert = true
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.captureSession?.startRunning()
      }
    }

    return true
  }

  /// Start receiving motion updates to determine device orientation for use in the face session.
  /// - Returns: true when the function has fatal error; false when not.
  private func setupMotion() -> Bool {
    guard motionManager.isDeviceMotionAvailable else {
      alertWindowTitle = "Alert"
      alertMessage = "Device does not have motion sensors."
      showsAlert = true
      return false
    }
    motionManager.deviceMotionUpdateInterval = 0.01
    motionManager.startDeviceMotionUpdates()

    return true
  }

  /// Get permission to use device camera.
  ///
  /// - Parameters:
  ///   - permissionHandler: The closure to call with whether permission was granted when
  ///     permission is determined.
  private func getVideoPermission(permissionHandler: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      permissionHandler(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video, completionHandler: permissionHandler)
    default:
      permissionHandler(false)
    }
  }

  /// Update a region node's transform with the transform from the face session. Ignore the scale
  /// on the passed in transform to preserve the root level unit conversion.
  ///
  /// - Parameters:
  ///   - transform: The world transform to apply to the node.
  ///   - regionNode: The region node on which to apply the transform.
  private func updateTransform(_ transform: simd_float4x4, for regionNode: SCNNode?) {
    guard let node = regionNode else {
      NSLog("In updateTransform, node is nil.")
      return
    }

    let localScale = node.simdScale
    node.simdWorldTransform = transform
    node.simdScale = localScale

    // The .scn asset (and the canonical face mesh asset that it is created from) have their
    // 'forward' (Z+) opposite of SceneKit's forward (Z-), so rotate to orient correctly.
    node.simdLocalRotate(by: simd_quatf(angle: .pi, axis: simd_float3(0, 1, 0)))
  }
}

// MARK: - Camera delegate

extension AugmentedFacesViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let imgBuffer = sampleBuffer.imageBuffer, let deviceMotion = motionManager.deviceMotion
    else {
      NSLog("In captureOutput, imgBuffer or deviceMotion is nil.")
      return
    }

    let frameTime = sampleBuffer.presentationTimeStamp.seconds
    // Use the device's gravity vector to determine which direction is up for a face. This is the
    // positive counter-clockwise rotation of the device relative to landscape left orientation.
    let rotation = 2 * .pi - atan2(deviceMotion.gravity.x, deviceMotion.gravity.y) + .pi / 2
    let rotationDegrees = UInt(rotation * 180 / .pi) % 360

    faceSession?.update(with: imgBuffer, timestamp: frameTime, recognitionRotation: rotationDegrees)
  }

}

// MARK: - Scene Renderer delegate

extension AugmentedFacesViewModel: SCNSceneRendererDelegate {

  /// Calculates the rectangle to crop the camera image to so it fits the viewport.
  ///
  /// - Parameters:
  ///   - viewSize: The size of the view.
  ///   - extent: The extent of the `CIImage`.
  /// - Returns: the rectangle to crop to.
  private func cropRect(for viewSize: CGSize, extent: CGRect) -> CGRect {
    CGRect(
      x: extent.maxX / 2 - viewSize.width / 2,
      y: extent.minY / 2 - viewSize.height / 2,
      width: viewSize.width,
      height: viewSize.height)
  }

  public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    guard let frame = faceSession?.currentFrame else {
      NSLog("In renderer, currentFrame is nil.")
      return
    }

    if let face = frame.face {
      faceTextureNode.geometry = faceMeshConverter.geometryFromFace(face)
      faceTextureNode.geometry?.firstMaterial = faceTextureMaterial
      faceOccluderNode.geometry = faceTextureNode.geometry?.copy() as? SCNGeometry
      faceOccluderNode.geometry?.firstMaterial = faceOccluderMaterial

      faceNode.simdWorldTransform = face.centerTransform
      updateTransform(face.transform(for: .nose), for: noseTipNode)
      updateTransform(face.transform(for: .foreheadLeft), for: foreheadLeftNode)
      updateTransform(face.transform(for: .foreheadRight), for: foreheadRightNode)
    }
    guard let viewSize else { return }

    // Set the scene camera's transform to the projection matrix for this frame.
    sceneCamera.projectionTransform = SCNMatrix4(
      frame.projectionMatrix(
        forViewportSize: viewSize,
        presentationOrientation: .portrait,
        mirrored: false,
        zNear: 0.05,
        zFar: 100))

    let ciImage = CIImage(cvPixelBuffer: frame.capturedImage).transformed(
      by: frame.displayTransform(
        forViewportSize: viewSize,
        presentationOrientation: .portraitUpsideDown,
        mirrored: false))
    scene?.background.contents = CIContext().createCGImage(
      ciImage, from: cropRect(for: viewSize, extent: ciImage.extent))

    // Only show AR content when a face is detected.
    scene?.rootNode.isHidden = frame.face == nil
  }
}
