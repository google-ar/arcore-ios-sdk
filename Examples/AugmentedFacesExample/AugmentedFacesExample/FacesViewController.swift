/*
 * Copyright 2019 Google LLC. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import AVFoundation
import CoreMedia
import CoreMotion
import SceneKit
import UIKit

  import ARCore

/// Demonstrates how to use ARCore Augmented Faces with SceneKit.
public final class FacesViewController: UIViewController {

  // MARK: - Camera / Scene properties

  private var captureDevice: AVCaptureDevice?
  private var captureSession: AVCaptureSession?
  private var videoFieldOfView = Float(0)
  private lazy var cameraImageLayer = CALayer()
  private lazy var sceneView = SCNView()
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

  override public func viewDidLoad() {
    super.viewDidLoad()

    setupScene()
    setupCamera()
    setupMotion()

    faceSession = try! GARAugmentedFaceSession(fieldOfView: videoFieldOfView)
  }

  /// Create the scene view from a scene and supporting nodes, and add to the view.
  /// The scene is loaded from 'fox_face.scn' which was created from 'canonical_face_mesh.fbx', the
  /// canonical face mesh asset.
  /// https://developers.google.com/ar/develop/developer-guides/creating-assets-for-augmented-faces
  private func setupScene() {
    guard let faceImage = UIImage(named: "Face.scnassets/face_texture.png"),
      let scene = SCNScene(named: "Face.scnassets/fox_face.scn"),
      let modelRoot = scene.rootNode.childNode(withName: "asset", recursively: false)
    else { fatalError("Failed to load face scene!") }

    // SceneKit uses meters for units, while the canonical face mesh asset uses centimeters.
    modelRoot.simdScale = simd_float3(1, 1, 1) * 0.01
    foreheadLeftNode = modelRoot.childNode(withName: "FOREHEAD_LEFT", recursively: true)
    foreheadRightNode = modelRoot.childNode(withName: "FOREHEAD_RIGHT", recursively: true)
    noseTipNode = modelRoot.childNode(withName: "NOSE_TIP", recursively: true)

    faceNode.addChildNode(faceTextureNode)
    faceNode.addChildNode(faceOccluderNode)
    scene.rootNode.addChildNode(faceNode)

    let cameraNode = SCNNode()
    cameraNode.camera = sceneCamera
    scene.rootNode.addChildNode(cameraNode)

    sceneView.scene = scene
    sceneView.frame = view.bounds
    sceneView.delegate = self
    sceneView.rendersContinuously = true
    sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    sceneView.backgroundColor = .clear
    // Flip 'x' to mirror content to mimic 'selfie' mode
    sceneView.layer.transform = CATransform3DMakeScale(-1, 1, 1)
    view.addSubview(sceneView)

    faceTextureMaterial.diffuse.contents = faceImage
    // SCNMaterial does not premultiply alpha even with blendMode set to alpha, so do it manually.
    faceTextureMaterial.shaderModifiers =
      [SCNShaderModifierEntryPoint.fragment: "_output.color.rgb *= _output.color.a;"]
    faceOccluderMaterial.colorBufferWriteMask = []
  }

  /// Setup a camera capture session from the front camera to receive captures.
  private func setupCamera() {
    guard
      let device =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
      let input = try? AVCaptureDeviceInput(device: device)
    else {
      NSLog("Failed to create capture device from front camera.")
      return
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

    videoFieldOfView = captureDevice?.activeFormat.videoFieldOfView ?? 0

    cameraImageLayer.contentsGravity = .center
    cameraImageLayer.frame = self.view.bounds
    view.layer.insertSublayer(cameraImageLayer, at: 0)

    // Start capturing images from the capture session once permission is granted.
    getVideoPermission(permissionHandler: { granted in
      guard granted else {
        NSLog("Permission not granted to use camera.")
        return
      }
      self.captureSession?.startRunning()
    })
  }

  /// Start receiving motion updates to determine device orientation for use in the face session.
  private func setupMotion() {
    guard motionManager.isDeviceMotionAvailable else {
      NSLog("Device does not have motion sensors.")
      return
    }
    motionManager.deviceMotionUpdateInterval = 0.01
    motionManager.startDeviceMotionUpdates()
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
    guard let node = regionNode else { return }

    let localScale = node.simdScale
    node.simdWorldTransform = transform
    node.simdScale = localScale

    // The .scn asset (and the canonical face mesh asset that it is created from) have their
    // 'forward' (Z+) opposite of SceneKit's forward (Z-), so rotate to orient correctly.
    node.simdLocalRotate(by: simd_quatf(angle: .pi, axis: simd_float3(0, 1, 0)))
  }

}

// MARK: - Camera delegate

extension FacesViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let imgBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
      let deviceMotion = motionManager.deviceMotion
    else { return }

    let frameTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

    // Use the device's gravity vector to determine which direction is up for a face. This is the
    // positive counter-clockwise rotation of the device relative to landscape left orientation.
    let rotation = 2 * .pi - atan2(deviceMotion.gravity.x, deviceMotion.gravity.y) + .pi / 2
    let rotationDegrees = (UInt)(rotation * 180 / .pi) % 360

    faceSession?.update(with: imgBuffer, timestamp: frameTime, recognitionRotation: rotationDegrees)
  }

}

// MARK: - Scene Renderer delegate

extension FacesViewController: SCNSceneRendererDelegate {

  public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
    guard let frame = faceSession?.currentFrame else { return }

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

    // Set the scene camera's transform to the projection matrix for this frame.
    sceneCamera.projectionTransform = SCNMatrix4.init(
      frame.projectionMatrix(
        forViewportSize: cameraImageLayer.bounds.size,
        presentationOrientation: .portrait,
        mirrored: false,
        zNear: 0.05,
        zFar: 100)
    )

    // Update the camera image layer's transform to the display transform for this frame.
    CATransaction.begin()
    CATransaction.setAnimationDuration(0)
    cameraImageLayer.contents = frame.capturedImage as CVPixelBuffer
    cameraImageLayer.setAffineTransform(
      frame.displayTransform(
        forViewportSize: cameraImageLayer.bounds.size,
        presentationOrientation: .portrait,
        mirrored: true)
    )
    CATransaction.commit()

    // Only show AR content when a face is detected.
    sceneView.scene?.rootNode.isHidden = frame.face == nil
  }

}
