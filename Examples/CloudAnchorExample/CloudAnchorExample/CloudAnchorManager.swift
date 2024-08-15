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
import AVFoundation
import Combine
import CoreGraphics
import FirebaseDatabase
import Foundation
import RealityKit

/// Model object for hosting and resolving Cloud Anchors.
class CloudAnchorManager: ObservableObject {
  private enum Constants {
    /// Fill in your own API Key here.
    static let apiKey = "your-api-key"
    /// The starting message when neither hosting nor resolving.
    static let startingMessage = "Tap HOST or RESOLVE to begin."
    /// Message to display if resolving is taking longer than expected.
    static let stillResolvingMessage =
      "Still resolving the anchor. Please make sure you're looking at where the Cloud Anchor was "
      + "hosted. Or, try to re-join the room."
    /// User defaults key for storing privacy notice acceptance.
    static let privacyNoticeUserDefaultsKey = "PrivacyNoticeAccepted"
    /// Show a message if resolving takes too long.
    static let resolveTimerDelay: TimeInterval = 10
    /// Firebase Database key for the list of rooms.
    static let hotspotListKey = "hotspot_list"
    /// Firebase Database key for the Cloud Anchor ID.
    static let anchorIdKey = "hosted_anchor_id"
    /// Firebase Database key for the timestamp when the room was last updated.
    static let updatedAtKey = "updated_at_timestamp"
    /// Firebase Database key for the most recently added room code as a number.
    static let lastRoomKey = "last_room_code"
    /// Firebase Database key for the room code of the room as a string.
    static let displayNameKey = "display_name"
  }

  @Published var hosting = false
  @Published var resolving = false
  @Published var roomCode = ""
  @Published var message = Constants.startingMessage
  @Published var showPrivacyNotice = false
  @Published var showCameraPermissionDeniedAlert = false
  @Published var showRoomCodeDialog = false
  @Published var roomCodeDialogField = ""
  @Published var showErrorAlert = false
  @Published var errorAlertTitle = ""
  @Published var errorAlertMessage = ""
  @Published var fatalError = false

  // Don't run the `ARSession` until we deliberately call `maybeRunSession()`.
  let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
  var garSession: GARSession?
  private let reference = Database.database().reference()
  private var roomChild: DatabaseReference {
    return reference.child(Constants.hotspotListKey).child(roomCode)
  }

  private var sessionRunning = false
  private var resolveOnChecksPassed = false

  private var hostedAnchor: ARAnchor?
  private var hostFuture: GARHostCloudAnchorFuture?
  private var resolveFuture: GARResolveCloudAnchorFuture?
  private var resolveTimer: Timer?

  init() {
    do {
      garSession = try GARSession(apiKey: Constants.apiKey, bundleIdentifier: nil)
    } catch {
      showErrorAlert("Failed to create the GARSession: \(error)", fatal: true)
      return
    }
    let configuration = GARSessionConfiguration()
    configuration.cloudAnchorMode = .enabled
    var error: NSError? = nil
    garSession?.setConfiguration(configuration, error: &error)
    if let error {
      showErrorAlert("Failed to configure the GARSession: \(error)", fatal: true)
    }
  }

  /// Runs the `ARSession` if it isn't running already.
  private func maybeRunSession() {
    guard !sessionRunning else { return }
    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    configuration.planeDetection = .horizontal
    arView.session.run(configuration)
    sessionRunning = true
  }

  /// Shows an error popup with a custom error message.
  ///
  /// - Parameters
  ///   - errorAlertMessage: The message to display in the alert.
  ///   - fatal: If `true`, all UI interaction will be disabled.
  private func showErrorAlert(_ errorAlertMessage: String, fatal: Bool = false) {
    errorAlertTitle = fatal ? "Fatal error occurred" : "An error occurred"
    self.errorAlertMessage = errorAlertMessage
    showErrorAlert = true
    if fatal {
      fatalError = true
      message = errorAlertTitle
    }
  }

  /// Resets all hosting and resolving state so the user can start over.
  private func reset() {
    // Reset hosting state.
    hostFuture?.cancel()
    hostFuture = nil
    if let hostedAnchor {
      arView.session.remove(anchor: hostedAnchor)
      self.hostedAnchor = nil
    }

    // Reset resolving state.
    resolveFuture?.cancel()
    if let garAnchor = resolveFuture?.resultAnchor {
      garSession?.remove(garAnchor)
    }
    resolveFuture = nil
    roomChild.removeAllObservers()
    resolveTimer?.invalidate()
    resolveTimer = nil

    // Reset UI state.
    hosting = false
    resolving = false
    roomCode = ""
    message = Constants.startingMessage
  }

  /// Converts a `GARCloudAnchorState` enum to a string for display.
  ///
  /// - Parameter cloudState: The enum value to convert to a string.
  private static func stringFromCloudState(_ cloudState: GARCloudAnchorState) -> String {
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

  /// Continues the flow after successfully obtaining or verifying that the privacy notice has
  /// been accepted and the camera permission has been granted.
  private func checksPassed() {
    maybeRunSession()
    if resolveOnChecksPassed {
      roomCodeDialogField = ""
      showRoomCodeDialog = true
    } else {
      host()
    }
  }

  /// Checks the camera permission, and requests if it wasn't previously granted or denied.
  private func checkCameraPermission() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      checksPassed()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        if granted {
          self?.checksPassed()
        }
      }
    default:
      showCameraPermissionDeniedAlert = true
    }
  }

  /// Checks the acceptance of the privacy notice and granting of the camera permission.
  private func checkPrivacyNoticeAndCameraPermission() {
    if UserDefaults.standard.bool(forKey: Constants.privacyNoticeUserDefaultsKey) {
      checkCameraPermission()
    } else {
      showPrivacyNotice = true
    }
  }

  /// Called when the user taps on the button to accept the privacy notice. Records this in
  /// `UserDefaults` and checks the camera permission.
  func privacyNoticeAccepted() {
    UserDefaults.standard.setValue(true, forKey: Constants.privacyNoticeUserDefaultsKey)
    checkCameraPermission()
  }

  /// Called when the user taps the HOST/CANCEL button. If already hosting, cancels hosting.
  /// Otherwise, proceeds to host after checking the privacy notice and camera permission.
  func hostButtonPressed() {
    if hosting {
      reset()
    } else {
      resolveOnChecksPassed = false
      checkPrivacyNoticeAndCameraPermission()
    }
  }

  /// Updates the UI and Firebase when the hosting operation finishes.
  ///
  /// - Parameters
  ///   - cloudId: The newly created Cloud Anchor ID, if hosting was successful.
  ///   - cloudState: The result enum.
  private func finishHosting(cloudId: String?, cloudState: GARCloudAnchorState) {
    message = "Finished hosting: \(CloudAnchorManager.stringFromCloudState(cloudState))"
    guard let cloudId else { return }
    // Store new Cloud Anchor ID in room.
    roomChild.child(Constants.anchorIdKey).setValue(cloudId)
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    roomChild.child(Constants.updatedAtKey).setValue(NSNumber(integerLiteral: timestamp))
  }

  /// Called when the user taps a point on the `ARView`. In the appropriate state, places an
  /// anchor by raycasting to hit a plane, and then attempt to host the anchor.
  ///
  /// - Parameter point: The point that was tapped within the `ARView`'s coordinate space.
  func tapPoint(point: CGPoint) {
    guard hosting, !roomCode.isEmpty, hostFuture == nil else { return }
    // Prefer existing planes to estimated ones.
    let results =
      arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
      + arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
    guard let result = results.first else { return }
    let anchor = ARAnchor(transform: result.worldTransform)
    do {
      hostFuture = try garSession?.hostCloudAnchor(anchor, ttlDays: 1) {
        [weak self] cloudId, cloudState in
        self?.finishHosting(cloudId: cloudId, cloudState: cloudState)
      }
    } catch {
      showErrorAlert("Failed to host anchor: \(error)")
      reset()
      return
    }
    hostedAnchor = anchor
    arView.session.add(anchor: anchor)
    message = "Hosting anchor..."
  }

  /// Starts the hosting process by creating a room code.
  private func host() {
    hosting = true
    message = "Creating room..."
    reference.child(Constants.lastRoomKey).runTransactionBlock { mutableData in
      // Add one to previous last room code.
      var roomNumber = (mutableData.value as? NSNumber)?.intValue ?? 0
      roomNumber += 1
      let timestamp = Int(Date().timeIntervalSince1970 * 1000)
      let room =
        [
          Constants.displayNameKey: "\(roomNumber)",
          Constants.updatedAtKey: NSNumber(integerLiteral: timestamp),
        ] as NSDictionary
      // Add room for new room code, with anchor ID not filled in.
      self.reference.child(Constants.hotspotListKey).child("\(roomNumber)").setValue(room)
      // Increment stored last room code.
      mutableData.value = NSNumber(integerLiteral: roomNumber)
      return .success(withValue: mutableData)
    } andCompletionBlock: { error, committed, snapshot in
      guard let value = (snapshot?.value as? NSNumber) else {
        self.showErrorAlert("Failed to create room: \(error?.localizedDescription ?? "")")
        self.reset()
        return
      }
      self.roomCode = value.stringValue
      self.message = "Tap on a plane to create anchor and host."
    }
  }

  /// Called when the user taps the RESOLVE/CANCEL button. If already resolving, cancels
  /// resolving. Otherwise, proceeds to ask the user for the room code after checking the privacy
  /// notice and camera permission.
  func resolveButtonPressed() {
    if resolving {
      reset()
    } else {
      resolveOnChecksPassed = true
      checkPrivacyNoticeAndCameraPermission()
    }
  }

  /// Called when the user accepts the entered room code. Calls `resolve()`.
  func roomCodeEntered() {
    if !roomCodeDialogField.isEmpty {
      resolve()
    }
  }

  /// Updates the UI after the resolving process finishes.
  ///
  /// - Parameter cloudState: The result enum.
  private func finishResolving(cloudState: GARCloudAnchorState) {
    message = "Finished resolving: \(CloudAnchorManager.stringFromCloudState(cloudState))"
    resolveTimer?.invalidate()
    resolveTimer = nil
  }

  /// Attempts to resolve the anchor after fetching the ID from Firebase.
  ///
  /// - Parameter snapshot: Snapshot of room node.
  private func resolve(snapshot: DataSnapshot) {
    guard let value = (snapshot.value as? [String: Any]),
      let anchorId = (value[Constants.anchorIdKey] as? String)
    else {
      self.showErrorAlert("Failed to fetch anchor ID from room code")
      self.reset()
      return
    }
    do {
      self.resolveFuture = try self.garSession?.resolveCloudAnchor(anchorId) {
        [weak self] anchor, cloudState in
        self?.finishResolving(cloudState: cloudState)
      }
    } catch {
      self.showErrorAlert("Failed to resolve anchor: \(error)")
      self.reset()
    }
  }

  /// Starts the resolving process by fetching the anchor ID from Firebase.
  private func resolve() {
    resolving = true
    roomCode = roomCodeDialogField
    message = "Resolving anchor..."
    resolveTimer = Timer.scheduledTimer(
      withTimeInterval: Constants.resolveTimerDelay, repeats: false
    ) { [weak self] timer in
      self?.message = Constants.stillResolvingMessage
    }
    roomChild.observeSingleEvent(of: .value) { [weak self] snapshot in
      self?.resolve(snapshot: snapshot)
    }
  }
}
