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
import simd

/// Model object for hosting and resolving Cloud Anchors.
class CloudAnchorManager: ObservableObject {
  private enum Constants {
    /// Fill in your own API Key here.
    static let apiKey = "your-api-key"
    /// User defaults key for storing anchor creation timestamps.
    static let timeDictionaryUserDefaultsKey = "NicknameTimeStampDictionary"
    /// User defaults key for storing anchor IDs.
    static let anchorIdDictionaryUserDefaultsKey = "NicknameAnchorIdDictionary"
    /// User defaults key for storing privacy notice acceptance.
    static let privacyNoticeUserDefaultsKey = "PrivacyNoticeAccepted"
    /// Average quality threshold for hosting an anchor.
    static let featureMapQualityThreshold: Float = 0.6
    /// Maximum distance from anchor (in meters) before displaying warning.
    static let maxDistance: Float = 10
    /// Minimum distance from anchor (in meters) before displaying warning.
    static let minDistance: Float = 0.2
  }

  /// Enum representing the child pages in the navigation stack.
  enum Page {
    case host
    case resolvePicker
    case resolve
  }

  @Published var navigationPath: [Page] = [] {
    willSet {
      if newValue.count < navigationPath.count {
        backButtonPressed()
      }
    }
  }
  @Published var showPrivacyNotice = false
  @Published var showAnchorNameDialog = false
  @Published var anchorNameDialogField = ""
  @Published var messageLabel = ""
  @Published var debugLabel = ""

  private var placedAnchor: Bool = false
  var isOnHorizontalPlane: Bool = false
  private var hostFuture: GARHostCloudAnchorFuture?

  private var resolvedAnchorIds: [String] = []
  private var resolveFutures: [GARResolveCloudAnchorFuture] = []

  var garSession: GARSession?
  private var arView: ARView?

  private func createGARSession() -> Bool {
    do {
      garSession = try GARSession(apiKey: Constants.apiKey, bundleIdentifier: nil)
    } catch {
      print("Failed to create GARSession: \(error)")
      return false
    }
    let configuration = GARSessionConfiguration()
    configuration.cloudAnchorMode = .enabled
    var error: NSError? = nil
    garSession?.setConfiguration(configuration, error: &error)
    if let error {
      print("Failed to configure GARSession: \(error)")
      return false
    }
    return true
  }

  private func runSession(trackPlanes: Bool) {
    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    if trackPlanes {
      configuration.planeDetection = [.horizontal, .vertical]
    }
    arView?.session.run(configuration, options: .removeExistingAnchors)
  }

  /// Start the `ARSession` when beginning to host or resolve.
  ///
  /// - Parameter arView: The `ARView` instance for this session.
  func startSession(arView: ARView) {
    self.arView = arView
    // Only show planes in hosting mode.
    runSession(trackPlanes: resolvedAnchorIds.isEmpty)
  }

  /// Called when the user taps the "Begin hosting" button. Proceeds to host after checking the
  /// privacy notice.
  func beginHostingButtonPressed() {
    resolvedAnchorIds = []
    checkPrivacyNotice()
  }

  /// Called when the user taps a point on the `ARView`. In the appropriate state, places an anchor
  /// by raycasting to hit a plane.
  ///
  /// - Parameter point: The point that was tapped within the `ARView`'s coordinate space.
  func tapPoint(_ point: CGPoint) {
    guard let arView, let frame = arView.session.currentFrame,
      frame.camera.trackingState == .normal, resolvedAnchorIds.isEmpty, !placedAnchor
    else { return }

    // Prefer existing planes to estimated ones.
    let results =
      arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
      + arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .vertical)
      + arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
      + arView.raycast(from: point, allowing: .estimatedPlane, alignment: .vertical)
    guard let result = results.first else { return }

    isOnHorizontalPlane = (result.targetAlignment == .horizontal)
    let anchorTransform: simd_float4x4
    if isOnHorizontalPlane {
      // Rotate raycast result around y axis to face user.
      // Compute angle between camera position and raycast result's z axis.
      let anchorFromCamera = simd_mul(simd_inverse(result.worldTransform), frame.camera.transform)
      let x = anchorFromCamera.columns.3[0]
      let z = anchorFromCamera.columns.3[2]
      // Angle from the z axis, measured counterclockwise.
      let angle = atan2f(x, z)
      let rotation = simd_quatf(angle: angle, axis: simd_make_float3(0, 1, 0))
      anchorTransform = simd_mul(result.worldTransform, simd_matrix4x4(rotation))
    } else {
      anchorTransform = result.worldTransform
    }
    let anchor = ARAnchor(transform: anchorTransform)
    runSession(trackPlanes: false)  // Disable planes when anchor is placed.
    arView.session.add(anchor: anchor)
    placedAnchor = true
    messageLabel = "Save the object here by capturing it from all sides"
  }

  private static func string(from quality: GARFeatureMapQuality) -> String {
    switch quality {
    case .good:
      return "Good"
    case .sufficient:
      return "Sufficient"
    default:
      return "Insufficient"
    }
  }

  /// Called to process each tracking frame when an anchor is placed but not yet hosted.
  ///
  /// - Parameters:
  ///   - anchor: The current snapshot of the anchor to host.
  ///   - quality: The current feature map quality.
  ///   - averageQuality: The average of the mapping qualities displayed on the indicator.
  ///   - distance: The distance to the anchor.
  /// - Returns: `true` if the anchor was hosted, `false` otherwise.
  func processFrame(
    anchor: ARAnchor, quality: GARFeatureMapQuality, averageQuality: Float, distance: Float
  ) -> Bool {
    guard let garSession, hostFuture == nil else { return false }
    debugLabel =
      "Current mapping quality: \(CloudAnchorManager.string(from: quality))"
    if distance > Constants.maxDistance {
      messageLabel = "You are too far; come closer"
    } else if distance < Constants.minDistance {
      messageLabel = "You are too close; move backward"
    } else {
      messageLabel = "Save the object here by capturing it from all sides"
    }

    if averageQuality > Constants.featureMapQualityThreshold {
      do {
        hostFuture = try garSession.hostCloudAnchor(anchor, ttlDays: 1) {
          [weak self] anchorId, cloudState in
          guard let self else { return }
          if cloudState == .success {
            self.showAnchorNameDialog = true
            self.anchorNameDialogField = ""
          }
          self.messageLabel = "Finished: \(CloudAnchorManager.string(from: cloudState))"
          if let anchorId {
            self.debugLabel = "Anchor \(anchorId) created"
          } else {
            self.debugLabel = "Anchor failed to host"
          }
        }
        messageLabel = "Processing..."
        debugLabel = "Feature map quality is sufficient, triggering hosting"
      } catch {
        print("Failed to start hosting process: \(error)")
      }
      return true
    }

    return false
  }

  private func backButtonPressed() {
    guard let page = navigationPath.last else { return }
    if page == .host || page == .resolve {
      reset()
    }
  }

  /// Called when the user hits the "Begin resolving" button.
  func beginResolvingButtonPressed() {
    navigationPath.append(.resolvePicker)
  }

  /// Called when the user hits the "Resolve" button. Proceeds to resolve after checking the privacy
  /// notice.
  ///
  /// - Parameter anchorIds: The list of anchor IDs to resolve.
  func resolveButtonPressed(anchorIds: [String]) {
    resolvedAnchorIds = anchorIds
    checkPrivacyNotice()
  }

  /// Called when the user explicitly accepts the privacy notice.
  func acceptPrivacyNotice() {
    UserDefaults.standard.setValue(true, forKey: Constants.privacyNoticeUserDefaultsKey)
    privacyNoticeAccepted()
  }

  private func privacyNoticeAccepted() {
    if resolvedAnchorIds.isEmpty {
      hostAnchor()
    } else {
      resolveAnchors()
    }
  }

  private func checkPrivacyNotice() {
    if UserDefaults.standard.bool(forKey: Constants.privacyNoticeUserDefaultsKey) {
      privacyNoticeAccepted()
    } else {
      showPrivacyNotice = true
    }
  }

  /// Stores a newly hosted anchor's info after the user enters a name for it.
  func saveAnchor() {
    guard let anchorId = hostFuture?.resultCloudIdentifier, !anchorNameDialogField.isEmpty else {
      return
    }
    var timeDictionary =
      (UserDefaults.standard.dictionary(forKey: Constants.timeDictionaryUserDefaultsKey)
        as? [String: Date]) ?? [:]
    var anchorIdDictionary =
      (UserDefaults.standard.dictionary(forKey: Constants.anchorIdDictionaryUserDefaultsKey)
        as? [String: String]) ?? [:]
    timeDictionary[anchorNameDialogField] = Date()
    anchorIdDictionary[anchorNameDialogField] = anchorId
    UserDefaults.standard.setValue(timeDictionary, forKey: Constants.timeDictionaryUserDefaultsKey)
    UserDefaults.standard.setValue(
      anchorIdDictionary, forKey: Constants.anchorIdDictionaryUserDefaultsKey)
  }

  /// Gets the list of stored anchors, sorted by age, and removes any more than a day old.
  func fetchAndPruneAnchors() -> [AnchorInfo] {
    var timeDictionary =
      (UserDefaults.standard.dictionary(forKey: Constants.timeDictionaryUserDefaultsKey)
        as? [String: Date]) ?? [:]
    var anchorIdDictionary =
      (UserDefaults.standard.dictionary(forKey: Constants.anchorIdDictionaryUserDefaultsKey)
        as? [String: String]) ?? [:]
    var infos: [AnchorInfo] = []
    let now = Date()
    for (name, time) in timeDictionary.sorted(by: { $0.1.compare($1.1) == .orderedDescending }) {
      let timeInterval = now.timeIntervalSince(time)
      if timeInterval >= 86400 {
        timeDictionary.removeValue(forKey: name)
        anchorIdDictionary.removeValue(forKey: name)
        continue
      }
      guard let anchorId = anchorIdDictionary[name] else { continue }
      let age =
        timeInterval >= 3600
        ? "\(Int(floor(timeInterval / 3600)))h" : "\(Int(floor(timeInterval / 60)))m"
      infos.append(AnchorInfo(id: anchorId, name: name, age: age))
    }
    UserDefaults.standard.setValue(timeDictionary, forKey: Constants.timeDictionaryUserDefaultsKey)
    UserDefaults.standard.setValue(
      anchorIdDictionary, forKey: Constants.anchorIdDictionaryUserDefaultsKey)
    return infos
  }

  private static func string(from cloudState: GARCloudAnchorState) -> String {
    switch cloudState {
    case .none:
      return "None"
    case .success:
      return "Success"
    case .errorInternal:
      return "ErrorInternal"
    case .errorNotAuthorized:
      return "ErrorNotAuthorized"
    case .errorResourceExhausted:
      return "ErrorResourceExhausted"
    case .errorHostingDatasetProcessingFailed:
      return "ErrorHostingDatasetProcessingFailed"
    case .errorCloudIdNotFound:
      return "ErrorCloudIdNotFound"
    case .errorResolvingSdkVersionTooNew:
      return "ErrorResolvingSdkVersionTooNew"
    case .errorResolvingSdkVersionTooOld:
      return "ErrorResolvingSdkVersionTooOld"
    case .errorHostingServiceUnavailable:
      return "ErrorHostingServiceUnavailable"
    default:
      // Not handling deprecated enum values that will never be returned.
      return "Unknown"
    }
  }

  private func resolveAnchors() {
    navigationPath.append(.resolve)
    guard createGARSession(), let garSession else {
      messageLabel = "Resolve failed"
      debugLabel = "Failed to init GARSession"
      return
    }
    messageLabel = "Resolving..."
    debugLabel = "Attempting to resolve \(resolvedAnchorIds.count) anchors"
    for anchorId in resolvedAnchorIds {
      do {
        resolveFutures.append(
          try garSession.resolveCloudAnchor(anchorId) { [weak self] anchor, cloudState in
            guard let self else { return }
            if cloudState == .success {
              self.debugLabel = "Resolved \(anchorId), continuing to refine pose"
            } else {
              self.debugLabel =
                "Failed to resolve \(anchorId): "
                + CloudAnchorManager.string(from: cloudState)
            }
            if self.resolveFutures.allSatisfy({ $0.state == .done }) {
              self.messageLabel = "Resolve finished"
            }
          })
      } catch {
        debugLabel = "Failed to start resolving operation: \(error)"
      }
    }
  }

  private func hostAnchor() {
    placedAnchor = false
    navigationPath.append(.host)
    guard createGARSession() else {
      messageLabel = "Host failed"
      debugLabel = "Failed to init GARSession"
      return
    }
    messageLabel = "Tap to place an object."
    debugLabel = "Tap a vertical or horizontal plane..."
  }

  private func reset() {
    for resolveFuture in resolveFutures {
      resolveFuture.cancel()
    }
    resolveFutures.removeAll()
    hostFuture?.cancel()
    hostFuture = nil
    arView?.session.pause()
    arView = nil
    garSession = nil
  }
}
