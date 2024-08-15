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
import CoreGraphics
import CoreLocation
import Foundation
import RealityKit
import simd

/// Model object for using the Geospatial API and placing Geospatial anchors.
class GeospatialManager: NSObject, ObservableObject, CLLocationManagerDelegate {
  /// Different types of Geospatial anchors you can place with the app.
  enum AnchorType: Int {
    case geospatial = 0
    case terrain = 1
    case rooftop = 2
  }

  private enum Constants {
    /// Fill in your own API Key here.
    static let apiKey = "your-api-key"
    /// User defaults key for storing privacy notice acceptance.
    static let privacyNoticeUserDefaultsKey = "privacy_notice_acknowledged"
    /// User defaults key for storing saved anchors.
    static let savedAnchorsUserDefaultsKey = "anchors"
    /// Maximum number of anchors you can place at one time.
    static let maxAnchorCount = 20
    /// Horizontal accuracy threshold (meters) for being considered localized with "high accuracy".
    static let horizontalAccuracyLowThreshold: CLLocationAccuracy = 10
    /// Horizontal accuracy threshold (meters) for being considered to lose "high accuracy"
    /// localization.
    static let horizontalAccuracyHighThreshold: CLLocationAccuracy = 20
    /// Orientation yaw accuracy threshold (degrees) for being considered localized with
    /// "high accuracy".
    static let orientationYawAccuracyLowThreshold: CLLocationDirectionAccuracy = 15
    /// Orientation yaw accuracy threshold (degrees) for being considered to lose "high accuracy"
    /// localization.
    static let orientationYawAccuracyHighThreshold: CLLocationDirectionAccuracy = 25
    /// Give up localizing with high accuracy after 3 minutes.
    static let localizationFailureTime: TimeInterval = 180
  }

  @Published var trackingLabel = ""
  @Published var statusLabel = ""
  @Published var tapScreenVisible = false
  @Published var clearAnchorsVisible = false
  @Published var anchorModeVisible = false
  @Published var showPrivacyNotice = !UserDefaults.standard.bool(
    forKey: Constants.privacyNoticeUserDefaultsKey)
  @Published var showVPSUnavailableNotice = false
  @Published var anchorType = AnchorType.geospatial

  @Published var streetscapeGeometryEnabled = true {
    willSet {
      if newValue != streetscapeGeometryEnabled {
        toggleStreetscapeGeometry(enabled: newValue)
      }
    }
  }

  let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
  private var locationManager: CLLocationManager?
  private var garSession: GARSession?

  private var pendingFutures: [UUID: GARFuture] = [:]
  private var anchors: [GARAnchor] = []
  var anchorTypes: [UUID: AnchorType] = [:]
  var earthTracking = false
  var highAccuracy = false
  private var addedSavedAnchors = false
  private var localizationFailed = false
  private var lastStartDate: Date? = nil
  private var resolveErrorMessage: String? = nil

  override init() {
    super.init()
    if !showPrivacyNotice {
      setupARSession()
    }
  }

  private func toggleStreetscapeGeometry(enabled: Bool) {
    guard let garSession else { return }
    let configuration = GARSessionConfiguration()
    configuration.geospatialMode = .enabled
    configuration.streetscapeGeometryMode = enabled ? .enabled : .disabled
    var error: NSError?
    garSession.setConfiguration(configuration, error: &error)
    if let error {
      print("Failed to toggle Streetscape Geometry configuration: \(error)")
    }
  }

  /// Called when the user taps on the `ARView` to place an anchor.
  ///
  /// - Parameter point: The point the user tapped on within the `ARView`'s coordinate space.
  func tapPoint(_ point: CGPoint) {
    guard let garSession, !localizationFailed,
      anchors.count + pendingFutures.count < Constants.maxAnchorCount
    else { return }

    guard
      let raycastQuery = arView.makeRaycastQuery(
        from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
    else { return }
    if streetscapeGeometryEnabled {
      do {
        let results = try garSession.raycastStreetscapeGeometry(
          origin: raycastQuery.origin, direction: raycastQuery.direction)
        guard let result = results.first else { return }
        let geospatialTransform = try garSession.geospatialTransform(
          transform: result.worldTransform)
        switch anchorType {
        case .geospatial:
          let anchor = try garSession.createAnchor(
            geometry: result.streetscapeGeometry, transform: result.worldTransform)
          // Don't save anchors on Streetscape Geometry between sessions.
          anchors.append(anchor)
          anchorTypes[anchor.identifier] = .geospatial
        case .terrain:
          addTerrainAnchor(
            coordinate: geospatialTransform.coordinate,
            eastUpSouthQTarget: simd_quaternion(0, 0, 0, 1), save: true)
        case .rooftop:
          addRooftopAnchor(
            coordinate: geospatialTransform.coordinate,
            eastUpSouthQTarget: simd_quaternion(0, 0, 0, 1), save: true)
        }

      } catch {
        print("Error adding anchor on StreetscapeGeometry: \(error)")
      }
    } else {
      let results = arView.session.raycast(raycastQuery)
      guard let result = results.first else { return }
      let geospatialTransform: GARGeospatialTransform
      do {
        geospatialTransform = try garSession.geospatialTransform(transform: result.worldTransform)
      } catch {
        print("Error converting transform to Geospatial transform: \(error)")
        return
      }
      switch anchorType {
      case .geospatial:
        addAnchor(
          coordinate: geospatialTransform.coordinate, altitude: geospatialTransform.altitude,
          eastUpSouthQTarget: geospatialTransform.eastUpSouthQTarget, save: true)
      case .terrain:
        addTerrainAnchor(
          coordinate: geospatialTransform.coordinate,
          eastUpSouthQTarget: geospatialTransform.eastUpSouthQTarget, save: true)
      case .rooftop:
        addRooftopAnchor(
          coordinate: geospatialTransform.coordinate,
          eastUpSouthQTarget: geospatialTransform.eastUpSouthQTarget, save: true)
      }
    }
  }

  private func saveAnchor(
    coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance,
    eastUpSouthQTarget: simd_quatf, anchorType: AnchorType
  ) {
    var savedAnchors =
      (UserDefaults.standard.array(forKey: Constants.savedAnchorsUserDefaultsKey)
        as? [[String: NSNumber]]) ?? []
    var anchor = [
      "latitude": NSNumber(floatLiteral: coordinate.latitude),
      "longitude": NSNumber(floatLiteral: coordinate.longitude),
      "type": NSNumber(integerLiteral: anchorType.rawValue),
      "x": NSNumber(floatLiteral: Double(eastUpSouthQTarget.vector[0])),
      "y": NSNumber(floatLiteral: Double(eastUpSouthQTarget.vector[1])),
      "z": NSNumber(floatLiteral: Double(eastUpSouthQTarget.vector[2])),
      "w": NSNumber(floatLiteral: Double(eastUpSouthQTarget.vector[3])),
    ]
    if anchorType == .geospatial {
      anchor["altitude"] = NSNumber(floatLiteral: altitude)
    }
    savedAnchors.append(anchor)
    UserDefaults.standard.setValue(savedAnchors, forKey: Constants.savedAnchorsUserDefaultsKey)
  }

  private func addSavedAnchors() {
    let savedAnchors =
      (UserDefaults.standard.array(forKey: Constants.savedAnchorsUserDefaultsKey)
        as? [[String: NSNumber]]) ?? []
    for anchor in savedAnchors {
      // Ignore the stored anchors that contain heading for backwards-compatibility.
      if anchor["heading"] != nil {
        continue
      }
      let coordinate = CLLocationCoordinate2D(
        latitude: anchor["latitude"]?.doubleValue ?? 0,
        longitude: anchor["longitude"]?.doubleValue ?? 0)
      let eastUpSouthQTarget = simd_quaternion(
        anchor["x"]?.floatValue ?? 0,
        anchor["y"]?.floatValue ?? 0,
        anchor["z"]?.floatValue ?? 0,
        anchor["w"]?.floatValue ?? 0)
      guard let anchorType = AnchorType(rawValue: anchor["type"]?.intValue ?? 0) else { continue }
      switch anchorType {
      case .geospatial:
        let altitude = anchor["altitude"]?.doubleValue ?? 0
        addAnchor(
          coordinate: coordinate, altitude: altitude, eastUpSouthQTarget: eastUpSouthQTarget,
          save: false)
      case .terrain:
        addTerrainAnchor(
          coordinate: coordinate, eastUpSouthQTarget: eastUpSouthQTarget, save: false)
      case .rooftop:
        addRooftopAnchor(
          coordinate: coordinate, eastUpSouthQTarget: eastUpSouthQTarget, save: false)
      }
    }
  }

  private func addAnchor(
    coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance,
    eastUpSouthQTarget: simd_quatf, save: Bool
  ) {
    guard let garSession else { return }
    do {
      let anchor = try garSession.createAnchor(
        coordinate: coordinate, altitude: altitude, eastUpSouthQAnchor: eastUpSouthQTarget)
      anchors.append(anchor)
      anchorTypes[anchor.identifier] = .geospatial
      if save {
        saveAnchor(
          coordinate: coordinate, altitude: altitude, eastUpSouthQTarget: eastUpSouthQTarget,
          anchorType: .geospatial)
      }
    } catch {
      print("Error adding anchor: \(error)")
      return
    }
  }

  private static func string(from terrainState: GARTerrainAnchorState) -> String {
    switch terrainState {
    case .none:
      return "None"
    case .success:
      return "Success"
    case .errorInternal:
      return "ErrorInternal"
    case .errorNotAuthorized:
      return "ErrorNotAuthorized"
    case .errorUnsupportedLocation:
      return "ErrorUnsupportedLocation"
    default:
      // Not handling any deprecated values that will never be returned.
      return "Unknown"
    }
  }

  private func addTerrainAnchor(
    coordinate: CLLocationCoordinate2D, eastUpSouthQTarget: simd_quatf, save: Bool
  ) {
    guard let garSession else { return }
    do {
      let futureId = UUID()
      pendingFutures[futureId] = try garSession.createAnchorOnTerrain(
        coordinate: coordinate, altitudeAboveTerrain: 0, eastUpSouthQAnchor: eastUpSouthQTarget
      ) { anchor, terrainState in
        self.pendingFutures.removeValue(forKey: futureId)
        guard terrainState == .success, let anchor else {
          self.resolveErrorMessage =
            "Error resolving terrain anchor: \(GeospatialManager.string(from: terrainState))"
          return
        }
        self.anchors.append(anchor)
        self.anchorTypes[anchor.identifier] = .terrain
        if save {
          self.saveAnchor(
            coordinate: coordinate, altitude: 0, eastUpSouthQTarget: eastUpSouthQTarget,
            anchorType: .terrain)
        }
      }
    } catch let error as NSError {
      print("Error adding terrain anchor: \(error)")
      if error.code == GARSessionError.resourceExhausted.rawValue {
        statusLabel =
          "Too many terrain and rooftop anchors have already been held. "
          + "Clear all anchors to create new ones."
      }
    }
  }

  private static func string(from rooftopState: GARRooftopAnchorState) -> String {
    switch rooftopState {
    case .none:
      return "None"
    case .success:
      return "Success"
    case .errorInternal:
      return "ErrorInternal"
    case .errorNotAuthorized:
      return "ErrorNotAuthorized"
    case .errorUnsupportedLocation:
      return "ErrorUnsupportedLocation"
    @unknown default:
      return "Unknown"
    }
  }

  private func addRooftopAnchor(
    coordinate: CLLocationCoordinate2D, eastUpSouthQTarget: simd_quatf, save: Bool
  ) {
    guard let garSession else { return }
    do {
      let futureId = UUID()
      pendingFutures[futureId] = try garSession.createAnchorOnRooftop(
        coordinate: coordinate, altitudeAboveRooftop: 0, eastUpSouthQAnchor: eastUpSouthQTarget
      ) { anchor, rooftopState in
        self.pendingFutures.removeValue(forKey: futureId)
        guard rooftopState == .success, let anchor else {
          self.resolveErrorMessage =
            "Error resolving rooftop anchor: \(GeospatialManager.string(from: rooftopState))"
          return
        }
        self.anchors.append(anchor)
        self.anchorTypes[anchor.identifier] = .rooftop
        if save {
          self.saveAnchor(
            coordinate: coordinate, altitude: 0, eastUpSouthQTarget: eastUpSouthQTarget,
            anchorType: .rooftop)
        }
      }
    } catch let error as NSError {
      print("Error adding rooftop anchor: \(error)")
      if error.code == GARSessionError.resourceExhausted.rawValue {
        statusLabel =
          "Too many terrain and rooftop anchors have already been held. "
          + "Clear all anchors to create new ones."
      }
    }
  }

  /// Called when the user taps the button to clear all anchors. Removes all anchors from the
  /// session and clears stored anchors.
  func clearAllAnchors() {
    for (_, future) in pendingFutures {
      future.cancel()
    }
    pendingFutures.removeAll()
    for anchor in anchors {
      garSession?.remove(anchor)
    }
    anchors.removeAll()
    anchorTypes.removeAll()
    UserDefaults.standard.removeObject(forKey: Constants.savedAnchorsUserDefaultsKey)
  }

  private func updateLocalizationState(_ garFrame: GARFrame) {
    guard let earth = garFrame.earth, let lastStartDate else { return }

    if earth.earthState != .enabled {
      localizationFailed = true
      return
    }

    guard let geospatialTransform = earth.cameraGeospatialTransform,
      earth.trackingState == .tracking
    else {
      earthTracking = false
      return
    }

    earthTracking = true
    let now = Date()

    if highAccuracy {
      if geospatialTransform.horizontalAccuracy > Constants.horizontalAccuracyHighThreshold
        || geospatialTransform.orientationYawAccuracy
          > Constants.orientationYawAccuracyHighThreshold
      {
        highAccuracy = false
        self.lastStartDate = now
      }
      return
    }

    if geospatialTransform.horizontalAccuracy < Constants.horizontalAccuracyLowThreshold
      && geospatialTransform.orientationYawAccuracy < Constants.orientationYawAccuracyLowThreshold
    {
      highAccuracy = true
      if !addedSavedAnchors {
        addSavedAnchors()
        addedSavedAnchors = true
      }
    } else if now.timeIntervalSince(lastStartDate) >= Constants.localizationFailureTime {
      localizationFailed = true
    }
  }

  private static func string(from earthState: GAREarthState) -> String {
    switch earthState {
    case .errorInternal:
      return "ERROR_INTERNAL"
    case .errorNotAuthorized:
      return "ERROR_NOT_AUTHORIZED"
    case .errorResourceExhausted:
      return "ERROR_RESOURCE_EXHAUSTED"
    default:
      return "ENABLED"
    }
  }

  private func updateTrackingLabel(_ garFrame: GARFrame) {
    guard let earth = garFrame.earth else { return }

    if localizationFailed {
      if earth.earthState != .enabled {
        trackingLabel = "Bad EarthState: \(GeospatialManager.string(from: earth.earthState))"
      } else {
        trackingLabel = ""
      }
      return
    }

    guard let geospatialTransform = earth.cameraGeospatialTransform,
      earth.trackingState == .tracking
    else {
      trackingLabel = "Not tracking."
      return
    }

    trackingLabel = String(
      format:
        "LAT/LONG: %.6f°, %.6f°\n    ACCURACY: %.2fm\nALTITUDE: %.2fm\n    ACCURACY: %.2fm\n"
        + "ORIENTATION: [%.1f, %.1f, %.1f, %.1f]\n    YAW ACCURACY: %.1f°",
      arguments: [
        geospatialTransform.coordinate.latitude, geospatialTransform.coordinate.longitude,
        geospatialTransform.horizontalAccuracy, geospatialTransform.altitude,
        geospatialTransform.verticalAccuracy, geospatialTransform.eastUpSouthQTarget.vector[0],
        geospatialTransform.eastUpSouthQTarget.vector[1],
        geospatialTransform.eastUpSouthQTarget.vector[2],
        geospatialTransform.eastUpSouthQTarget.vector[3],
        geospatialTransform.orientationYawAccuracy,
      ])
  }

  private func updateStatusLabelAndButtons(_ garFrame: GARFrame) {
    if localizationFailed {
      statusLabel = "Localization not possible.\nClose and open the app to restart."
      tapScreenVisible = false
      clearAnchorsVisible = false
      anchorModeVisible = false
      return
    }

    if !earthTracking {
      statusLabel = "Localizing your device to set anchor."
      tapScreenVisible = false
      clearAnchorsVisible = false
      return
    }

    if !highAccuracy {
      statusLabel = "Point your camera at buildings, stores, and signs near you."
      tapScreenVisible = false
      clearAnchorsVisible = false
      return
    }

    let anchorCount = anchors.count + pendingFutures.count

    if let resolveErrorMessage {
      statusLabel = resolveErrorMessage
    } else if anchors.isEmpty {
      statusLabel = "Localization complete."
    } else {
      statusLabel = "Num anchors: \(anchorCount)/\(Constants.maxAnchorCount)"
    }

    clearAnchorsVisible = (anchorCount > 0)
    tapScreenVisible = (anchorCount < Constants.maxAnchorCount)
    anchorModeVisible = true
  }

  /// Feeds the latest `ARFrame` to the `GARSession` and updates the UI state.
  func update(_ frame: ARFrame) -> GARFrame? {
    guard let garSession, !localizationFailed else { return nil }
    guard let garFrame = try? garSession.update(frame) else { return nil }

    updateLocalizationState(garFrame)
    updateTrackingLabel(garFrame)
    updateStatusLabelAndButtons(garFrame)

    return garFrame
  }

  /// Called when the user accepts the privacy notice.
  func acceptPrivacyNotice() {
    UserDefaults.standard.setValue(true, forKey: Constants.privacyNoticeUserDefaultsKey)
    setupARSession()
  }

  private func setupARSession() {
    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    // Optional. It will help the dynamic alignment of terrain anchors on ground.
    configuration.planeDetection = .horizontal
    arView.session.run(configuration)

    locationManager = CLLocationManager()
    // This will cause `locationManagerDidChangeAuthorization()` to be called asynchronously on the
    // main thread. After obtaining location permission, we will set up the ARCore session.
    locationManager?.delegate = self
  }

  private func setErrorStatus(_ message: String) {
    statusLabel = message
    tapScreenVisible = false
    clearAnchorsVisible = false
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      if manager.accuracyAuthorization != .fullAccuracy {
        setErrorStatus("Location permission not granted with full accuracy.")
        return
      }
      setupGARSession()
      // Request device location for checking VPS availability.
      manager.requestLocation()
    case .notDetermined:
      // The app is responsible for obtaining the location permission prior to configuring the
      // ARCore session. ARCore will not cause the location permission system prompt.
      manager.requestWhenInUseAuthorization()
    default:
      setErrorStatus("Location permission denied or restricted.")
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let location = locations.last, let garSession {
      garSession.checkVPSAvailability(coordinate: location.coordinate) { availability in
        if availability != .available {
          self.showVPSUnavailableNotice = true
        }
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    print("Location manager failed: \(error)")
  }

  private func setupGARSession() {
    guard garSession == nil else { return }

    let session: GARSession
    do {
      session = try GARSession(apiKey: Constants.apiKey, bundleIdentifier: nil)
    } catch let error as NSError {
      setErrorStatus("Failed to create GARSession: \(error.code)")
      return
    }

    if !session.isGeospatialModeSupported(.enabled) {
      setErrorStatus("The Geospatial API is not supported on this device.")
      return
    }

    let configuration = GARSessionConfiguration()
    configuration.geospatialMode = .enabled
    configuration.streetscapeGeometryMode = streetscapeGeometryEnabled ? .enabled : .disabled
    var error: NSError?
    session.setConfiguration(configuration, error: &error)
    if let error {
      setErrorStatus("Failed to configure GARSession: \(error.code)")
    }

    garSession = session
    lastStartDate = Date()
  }
}
