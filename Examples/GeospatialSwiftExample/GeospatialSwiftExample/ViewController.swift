//
//  VRViewController.swift
//  NFR
//
//  Created by Артeмий Шлесберг on 24.01.2023.
//

import Foundation
import UIKit
import ARKit
import ARCore
import CoreLocation
import SceneKit
import SceneKit.ModelIO

class ViewController: UIViewController {
    
    let kHorizontalAccuracyLowThreshold: CLLocationAccuracy = 10
    let kHorizontalAccuracyHighThreshold: CLLocationAccuracy = 20
    let kOrientationYawAccuracyLowThreshold: CLLocationDirectionAccuracy = 15
    let kOrientationYawAccuracyHighThreshold: CLLocationDirectionAccuracy = 25
    
    let kLocalizationFailureTime: TimeInterval = 3 * 60.0
    let kDurationNoTerrainAnchorResult: TimeInterval = 10
    
    let kMaxAnchors = 5
    
    let kPretrackingMessage = "Localizing your device to set anchor."
    let kLocalizationTip = "Point your camera at buildings, stores, and signs near you."
    let kLocalizationComplete = "Localization complete."
    let kLocalizationFailureMessage = "Localization not possible.\nClose and open the app to restart."
    let kGeospatialTransformFormat = "LAT/LONG: %.6f°, %.6f°\n    ACCURACY: %.2fm\nALTITUDE: %.2fm\n    ACCURACY: %.2fm\nORIENTATION: [%.1f, %.1f, %.1f, %.1f]\n    YAW ACCURACY: %.1f°"
    
    let kFontSize: CGFloat = 14.0
    
    let kSavedAnchorsUserDefaultsKey = "anchors"
    let kPrivacyNoticeUserDefaultsKey = "privacy_notice_acknowledged"
    let kPrivacyNoticeTitle = "AR in the real world"
    let kPrivacyNoticeText = "To power this session, Google will process visual data from your camera."
    let kPrivacyNoticeLearnMoreURL = "https://developers.google.com/ar/data-privacy"
    
    let kVPSAvailabilityNoticeUserDefaultsKey = "VPS_availability_notice_acknowledged"
    let kVPSAvailabilityTitle = "VPS not available"
    let kVPSAvailabilityText = "Your current location does not have VPS coverage. Your session will be using your GPS signal only if VPS is not available."
    
    enum LocalizationState: Int {
        case pretracking = 0
        case localizing = 1
        case localized = 2
        case failed = -1
    }
    
    /** Location manager used to request and check for location permissions. */
    var locationManager: CLLocationManager!
    
    /** ARKit session. */
    var arSession: ARSession!
    
    /**
     * ARCore session, used for geospatial localization. Created after obtaining location permission.
     */
    var garSession: GARSession?
    
    /** A view that shows an AR enabled camera feed and 3D content. */
    weak var scnView: ARSCNView!
    
    /** SceneKit scene used for rendering markers. */
    var scene: SCNScene!
    
    /** Label used to show Earth tracking state at top of screen. */
    weak var trackingLabel: UILabel!
    
    /** Label used to show status at bottom of screen. */
    weak var statusLabel: UILabel!
    
    /** Label used to show hint that tap screen to create anchors. */
    weak var tapScreenLabel: UILabel!
    
    /** Button used to place a new geospatial anchor. */
    weak var addAnchorButton: UIButton!
    
    /** UISwitch for creating WGS84 anchor or Terrain anchor. */
    weak var terrainAnchorSwitch: UISwitch!
    
    /** Label of terrainAnchorSwitch. */
    weak var switchLabel: UILabel!
    
    /** Button used to clear all existing anchors. */
    weak var clearAllAnchorsButton: UIButton!
    
    /** The most recent GARFrame. */
    var garFrame: GARFrame!
    
    /** Dictionary mapping anchor IDs to SceneKit nodes. */
    var markerNodes: [UUID : SCNNode] = [:]
    
    /** The last time we started attempting to localize. Used to implement failure timeout. */
    var lastStartLocalizationDate: Date?
    
    /** Dictionary mapping terrain anchor IDs to time we started resolving. */
    var terrainAnchorIDToStartTime: [UUID : Date] = [:]
    
    /** Set of finished terrain anchor IDs to remove at next frame update. */
    var anchorIDsToRemove: Set<UUID> = []
    
    /** The current localization state. */
    var localizationState: LocalizationState = .pretracking
    
    /** Whether we have restored anchors saved from the previous session. */
    var restoredSavedAnchors = false
    
    /** Whether the last anchor is terrain anchor. */
    var islastClickedTerrainAnchorButton = false
    
    /** Whether it is Terrain anchor mode. */
    var isTerrainAnchorMode = false
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        markerNodes = [:]
        terrainAnchorIDToStartTime = [:]
        anchorIDsToRemove = []
        
        let scnView = ARSCNView()
        scnView.translatesAutoresizingMaskIntoConstraints = false
        scnView.automaticallyUpdatesLighting = true
        scnView.autoenablesDefaultLighting = true
        self.scnView = scnView
        self.scene = self.scnView.scene
        self.arSession = self.scnView.session
        self.scnView.delegate = self
        self.scnView.debugOptions = [.showFeaturePoints]
        
        self.view.addSubview(self.scnView)
        
        let font = UIFont.systemFont(ofSize: kFontSize)
        let boldFont = UIFont.boldSystemFont(ofSize: kFontSize)
        
        let trackingLabel = UILabel()
        trackingLabel.translatesAutoresizingMaskIntoConstraints = false
        trackingLabel.font = font
        trackingLabel.textColor = UIColor.white
        trackingLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        trackingLabel.numberOfLines = 6
        self.trackingLabel = trackingLabel
        self.scnView.addSubview(trackingLabel)
        
        let tapScreenLabel = UILabel()
        tapScreenLabel.translatesAutoresizingMaskIntoConstraints = false
        tapScreenLabel.font = boldFont
        tapScreenLabel.textColor = UIColor.white
        tapScreenLabel.numberOfLines = 2
        tapScreenLabel.textAlignment = .center
        tapScreenLabel.text = "TAP ON SCREEN TO CREATE ANCHOR"
        tapScreenLabel.isHidden = true
        self.tapScreenLabel = tapScreenLabel
        self.scnView.addSubview(tapScreenLabel)
        
        let statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = font
        statusLabel.textColor = UIColor.white
        statusLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        statusLabel.numberOfLines = 2
        self.statusLabel = statusLabel
        self.scnView.addSubview(statusLabel)
        
        let addAnchorButton = UIButton(type: .system)
        addAnchorButton.translatesAutoresizingMaskIntoConstraints = false
        addAnchorButton.setTitle("ADD CAMERA ANCHOR", for: .normal)
        addAnchorButton.titleLabel?.font = boldFont
        addAnchorButton.addTarget(self, action: #selector(addAnchorButtonPressed), for: .touchUpInside)
        addAnchorButton.isHidden = true
        self.addAnchorButton = addAnchorButton
        self.view.addSubview(addAnchorButton)
        
        let terrainAnchorSwitch = UISwitch()
        terrainAnchorSwitch.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(terrainAnchorSwitch)
        self.terrainAnchorSwitch = terrainAnchorSwitch
        
        let switchLabel = UILabel()
        switchLabel.translatesAutoresizingMaskIntoConstraints = false
        switchLabel.font = boldFont
        switchLabel.textColor = UIColor.white
        switchLabel.numberOfLines = 1
        switchLabel.text = "TERRAIN ANCHOR"
        self.switchLabel = switchLabel
        self.view.addSubview(switchLabel)
        
        let clearAllAnchorsButton = UIButton(type: .system)
        clearAllAnchorsButton.translatesAutoresizingMaskIntoConstraints = false
        clearAllAnchorsButton.setTitle("CLEAR ALL ANCHORS", for: .normal)
        clearAllAnchorsButton.titleLabel?.font = boldFont
        clearAllAnchorsButton.addTarget(self, action: #selector(clearAllAnchorsButtonPressed), for: .touchUpInside)
        clearAllAnchorsButton.isHidden = true
        self.clearAllAnchorsButton = clearAllAnchorsButton
        self.view.addSubview(clearAllAnchorsButton)
        
        // Add constraints for the ARSCNView
        self.scnView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.scnView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.scnView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.scnView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        
        // Add constraints for the tracking label
        self.trackingLabel.leadingAnchor.constraint(equalTo: self.scnView.leadingAnchor).isActive = true
        self.trackingLabel.trailingAnchor.constraint(equalTo: self.scnView.trailingAnchor).isActive = true
        self.trackingLabel.topAnchor.constraint(equalTo: self.scnView.topAnchor).isActive = true
        self.trackingLabel.heightAnchor.constraint(equalToConstant: 100.0).isActive = true
        
        // Add constraints for the tap screen label
        self.tapScreenLabel.centerXAnchor.constraint(equalTo: self.scnView.centerXAnchor).isActive = true
        self.tapScreenLabel.centerYAnchor.constraint(equalTo: self.scnView.centerYAnchor).isActive = true
        
        // Add constraints for the status label
        self.statusLabel.leadingAnchor.constraint(equalTo: self.scnView.leadingAnchor).isActive = true
        self.statusLabel.trailingAnchor.constraint(equalTo: self.scnView.trailingAnchor).isActive = true
        self.statusLabel.bottomAnchor.constraint(equalTo: self.scnView.bottomAnchor).isActive = true
        self.statusLabel.heightAnchor.constraint(equalToConstant: 100.0).isActive = true
        
        // Add constraints for the add anchor button
        self.addAnchorButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        self.addAnchorButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -50.0).isActive = true
        
        // Add constraints for the terrain anchor switch
        self.terrainAnchorSwitch.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20.0).isActive = true
        self.terrainAnchorSwitch.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -20.0).isActive = true
        
        self.switchLabel.topAnchor.constraint(equalTo: statusLabel.topAnchor).isActive = true
        self.switchLabel.rightAnchor.constraint(equalTo: terrainAnchorSwitch.leftAnchor).isActive = true
        self.switchLabel.heightAnchor.constraint(equalToConstant: 40).isActive = true
        
        self.clearAllAnchorsButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        self.clearAllAnchorsButton.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let privacyNoticeAcknowledged = UserDefaults.standard.bool(forKey: kPrivacyNoticeUserDefaultsKey)
        if privacyNoticeAcknowledged {
            setUpARSession()
            return
        }
        
        let alertController = UIAlertController(title: kPrivacyNoticeTitle, message: kPrivacyNoticeText, preferredStyle: .alert)
        let getStartedAction = UIAlertAction(title: "Get started", style: .default) { [unowned self] (action) in
            UserDefaults.standard.set(true, forKey: self.kPrivacyNoticeUserDefaultsKey)
            self.setUpARSession()
        }
        let learnMoreAction = UIAlertAction(title: "Learn more", style: .default) { [unowned self] (action) in
            UIApplication.shared.open(URL(string: self.kPrivacyNoticeLearnMoreURL)!, options: [:], completionHandler: nil)
        }
        alertController.addAction(getStartedAction)
        alertController.addAction(learnMoreAction)
        present(alertController, animated: false, completion: nil)
    }
    
    func showVPSUnavailableNotice() {
        let alertController = UIAlertController(title: kVPSAvailabilityTitle, message: kVPSAvailabilityText, preferredStyle: .alert)
        let continueAction = UIAlertAction(title: "Continue", style: .default) { (action) in
        }
        alertController.addAction(continueAction)
        present(alertController, animated: false, completion: nil)
    }
    
    func setUpARSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = .horizontal
        arSession.delegate = self
        arSession.run(configuration)
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    func checkLocationPermission() {
        let authorizationStatus: CLAuthorizationStatus = locationManager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            if self.locationManager.accuracyAuthorization != .fullAccuracy {
                setErrorStatus("Location permission not granted with full accuracy.")
                return
            }
            // Request device location for check VPS availability.
            self.locationManager.requestLocation()
            setUpGARSession()
        } else if authorizationStatus == .notDetermined {
            // The app is responsible for obtaining the location permission prior to configuring the ARCore
            // session. ARCore will not cause the location permission system prompt.
            self.locationManager.requestWhenInUseAuthorization()
        } else {
            setErrorStatus("Location permission denied or restricted.")
        }
    }
    
    func setErrorStatus(_ message: String) {
        statusLabel.text = message
        addAnchorButton.isHidden = true
        tapScreenLabel.isHidden = true
        clearAllAnchorsButton.isHidden = true
    }
    
    //- MARK: Creating node
    func markerNode(isTerrainAnchor: Bool) -> SCNNode {
        let objURL = Bundle.main.url(forResource: "geospatial_marker", withExtension: "obj")!
        let markerAsset = MDLAsset(url: objURL)
        let markerObject = markerAsset.object(at: 0) as! MDLMesh
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: MDLScatteringFunction())
        let textureURL = isTerrainAnchor ? Bundle.main.url(forResource: "spatial-marker-yellow", withExtension: "png") : Bundle.main.url(forResource: "spatial-marker-baked", withExtension: "png")
        let materialProperty = MDLMaterialProperty(name: "texture", semantic: MDLMaterialSemantic.baseColor, url: textureURL)
        material.setProperty(materialProperty)
        for submesh in markerObject.submeshes as! [MDLSubmesh] {
            submesh.material = material
        }
        
        return SCNNode(mdlObject: markerObject)
    }
    
    func setUpGARSession() {
        if garSession != nil {
            return
        }
        do {
            garSession = try GARSession(apiKey: "api_key", bundleIdentifier: nil)
        }
        catch {
            setErrorStatus("Failed to create GARSession: \(error)")
            return
        }
        
        var error: NSError?
        
        localizationState = .failed
        
        if garSession?.isGeospatialModeSupported(.enabled) != true {
            setErrorStatus("GARGeospatialModeEnabled is not supported on this device.")
            return
        }
        
        let configuration = GARSessionConfiguration()
        configuration.geospatialMode = .enabled
        garSession?.setConfiguration(configuration, error: &error)
        if error != nil {
            setErrorStatus("Failed to configure GARSession: \(error!.code)")
            return
        }
        
        localizationState = .pretracking
        lastStartLocalizationDate = Date()
    }
    
    func checkVPSAvailabilityWithCoordinate(_ coordinate: CLLocationCoordinate2D) {
        self.garSession?.checkVPSAvailability(coordinate: coordinate, completionHandler: { [weak self] in
            if $0 != GARVPSAvailability.available {
                self?.showVPSUnavailableNotice()
            }
        })
    }
    
    func addSavedAnchors() {
        let defaults = UserDefaults.standard
        guard let savedAnchors = defaults.array(forKey: kSavedAnchorsUserDefaultsKey) as? [[String: NSNumber]] else { return }
        
        for savedAnchor in savedAnchors {
            // Ignore the stored anchors that contain heading for backwards-compatibility.
            if savedAnchor["heading"] != nil {
                continue
            }
            let latitude = savedAnchor["latitude"]?.doubleValue ?? 0
            let longitude = savedAnchor["longitude"]?.doubleValue ?? 0
            let eastUpSouthQTarget = simd_quatf(
                vector: simd_float4(x: savedAnchor["x"]?.floatValue ?? 0,
                                    y: savedAnchor["y"]?.floatValue ?? 0,
                                    z: savedAnchor["z"]?.floatValue ?? 0,
                                    w: savedAnchor["w"]?.floatValue ?? 0)
            )
            if let altitude = savedAnchor["altitude"]?.doubleValue {
                self.addAnchorWithCoordinate(
                    CLLocationCoordinate2DMake(latitude, longitude),
                    altitude: altitude,
                    eastUpSouthQTarget: eastUpSouthQTarget,
                    shouldSave: false
                )
            } else {
                self.addTerrainAnchorWithCoordinate(
                    CLLocationCoordinate2DMake(latitude, longitude),
                    eastUpSouthQTarget: eastUpSouthQTarget,
                    shouldSave: false
                )
            }
        }
    }
    
    func updateLocalizationState() {
        // This will be nil if not currently tracking.
        let geospatialTransform = self.garFrame.earth?.cameraGeospatialTransform
        let now = Date()
        
        if self.garFrame.earth?.earthState != .enabled {
            self.localizationState = .failed
        } else if self.garFrame.earth?.trackingState != .tracking {
            self.localizationState = .pretracking
        } else {
            if self.localizationState == .pretracking {
                self.localizationState = .localizing
            } else if self.localizationState == .localizing {
                if let geospatialTransform = geospatialTransform,
                   geospatialTransform.horizontalAccuracy <= kHorizontalAccuracyLowThreshold,
                   geospatialTransform.orientationYawAccuracy <= kOrientationYawAccuracyLowThreshold {
                    self.localizationState = .localized
                    if !self.restoredSavedAnchors {
                        self.addSavedAnchors()
                        self.restoredSavedAnchors = true
                    }
                } else if now.timeIntervalSince(self.lastStartLocalizationDate ?? Date()) >= kLocalizationFailureTime {
                    self.localizationState = .failed
                }
            } else {
                // Use higher thresholds for exiting 'localized' state to avoid flickering state changes.
                if (geospatialTransform == nil ||
                    geospatialTransform!.horizontalAccuracy > kHorizontalAccuracyHighThreshold ||
                    geospatialTransform!.orientationYawAccuracy > kOrientationYawAccuracyHighThreshold) {
                    self.localizationState = .localizing
                    self.lastStartLocalizationDate = now;
                }
            }
        }
    }
    
    func updateMarkerNodes() {
        var currentAnchorIDs = Set<UUID>()
        
        // Add/update nodes for tracking anchors.
        for anchor in garFrame.anchors {
            if anchor.trackingState != .tracking {
                continue
            }
            var node = markerNodes[anchor.identifier]
            
            if node == nil {
                // Only render resolved Terrain anchors and Geospatial anchors.
                if anchor.terrainState == .success {
                    node = markerNode(isTerrainAnchor: true)
                } else if anchor.terrainState == .none {
                    node = markerNode(isTerrainAnchor: false)
                }
                markerNodes[anchor.identifier] = node
                scene.rootNode.addChildNode(node!)
            }
            // Rotate the virtual object 180 degrees around the Y axis to make the object face the GL
            // camera -Z axis, since camera Z axis faces toward users.
            let rotationYquat = simd_quaternion(Float.pi, simd_float3(0, 1, 0))
            node?.simdTransform = matrix_multiply(anchor.transform, simd_matrix4x4(rotationYquat))
            node?.isHidden = (localizationState != .localized)
            currentAnchorIDs.insert(anchor.identifier)
        }
        
        // Remove nodes for anchors that are no longer tracking.
        for anchorID in markerNodes.keys {
            if !currentAnchorIDs.contains(anchorID) {
                if let node = markerNodes[anchorID] {
                    node.removeFromParentNode()
                    markerNodes.removeValue(forKey: anchorID)
                }
            }
        }
    }
    
    func string(fromGAREarthState earthState: GAREarthState) -> String {
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
    
    
    func updateTrackingLabel() {
        if self.localizationState == .failed {
            if self.garFrame.earth?.earthState != .enabled {
                let earthState = self.garFrame.earth?.earthState
                self.trackingLabel.text = "Bad EarthState: \(String(describing: earthState))"
            } else {
                self.trackingLabel.text = ""
            }
            return
        }
        
        if self.garFrame.earth?.trackingState == .paused {
            self.trackingLabel.text = "Not tracking."
            return
        }
        
        guard let geospatialTransform = self.garFrame.earth?.cameraGeospatialTransform else { return }
        
        let cameraQuaternion = geospatialTransform.eastUpSouthQTarget
        
        self.trackingLabel.text = String(format: kGeospatialTransformFormat, geospatialTransform.coordinate.latitude, geospatialTransform.coordinate.longitude, geospatialTransform.horizontalAccuracy, geospatialTransform.altitude, geospatialTransform.verticalAccuracy, cameraQuaternion.vector[0], cameraQuaternion.vector[1], cameraQuaternion.vector[2], cameraQuaternion.vector[3], geospatialTransform.orientationYawAccuracy)
    }
    
    func updateStatusLabelAndButtons() {
        switch localizationState {
        case .localized:
            for key in anchorIDsToRemove {
                terrainAnchorIDToStartTime.removeValue(forKey: key)
            }
            anchorIDsToRemove.removeAll()
            var message: String?
            for anchor in garFrame.anchors {
                if anchor.terrainState == .none {
                    continue
                }
                if terrainAnchorIDToStartTime[anchor.identifier] != nil {
                    message = "Terrain anchor state: \(terrainStateString(anchor.terrainState))"
                    let now = Date()
                    if anchor.terrainState == .taskInProgress {
                        if now.timeIntervalSince(terrainAnchorIDToStartTime[anchor.identifier]!) >= kDurationNoTerrainAnchorResult {
                            message = "Still resolving the terrain anchor. Please make sure you're in an area that has VPS coverage."
                            anchorIDsToRemove.insert(anchor.identifier)
                        }
                    } else {
                        anchorIDsToRemove.insert(anchor.identifier)
                    }
                }
            }
            if let message = message {
                statusLabel.text = message
            } else if garFrame.anchors.isEmpty {
                statusLabel.text = kLocalizationComplete
            } else if !islastClickedTerrainAnchorButton {
                statusLabel.text = "Num anchors: \(garFrame.anchors.count)"
            }
            clearAllAnchorsButton.isHidden = garFrame.anchors.isEmpty
            addAnchorButton.isHidden = garFrame.anchors.count >= kMaxAnchors
            tapScreenLabel.isHidden = garFrame.anchors.count >= kMaxAnchors
        case .pretracking:
            statusLabel.text = kPretrackingMessage
        case .localizing:
            statusLabel.text = kLocalizationTip
            addAnchorButton.isHidden = true
            tapScreenLabel.isHidden = true
            clearAllAnchorsButton.isHidden = true
        case .failed:
            statusLabel.text = kLocalizationFailureMessage
            addAnchorButton.isHidden = true
            tapScreenLabel.isHidden = true
            clearAllAnchorsButton.isHidden = true
        }
        isTerrainAnchorMode = terrainAnchorSwitch.isOn
    }
    
    func updateWithGARFrame(_ garFrame: GARFrame) {
        self.garFrame = garFrame
        updateLocalizationState()
        updateMarkerNodes()
        updateTrackingLabel()
        updateStatusLabelAndButtons()
    }
    
    func terrainStateString(_ terrainAnchorState: GARTerrainAnchorState) -> String {
        switch terrainAnchorState {
        case .none:
            return "None"
        case .success:
            return "Success"
        case .errorInternal:
            return "ErrorInternal"
        case .taskInProgress:
            return "TaskInProgress"
        case .errorNotAuthorized:
            return "ErrorNotAuthorized"
        case .errorUnsupportedLocation:
            return "UnsupportedLocation"
        default:
            return "Unknown"
        }
    }
    
    func addAnchorWithCoordinate(_ coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, eastUpSouthQTarget: simd_quatf, shouldSave: Bool) {
        do {
            try garSession?.createAnchor(coordinate: coordinate, altitude: altitude, eastUpSouthQAnchor: eastUpSouthQTarget)
        } catch {
            print("Error adding anchor: \(error)")
            return
        }
        if shouldSave {
            let defaults = UserDefaults.standard
            let savedAnchors = defaults.array(forKey: kSavedAnchorsUserDefaultsKey) as? [[String: Any]] ?? []
            let newSavedAnchors = savedAnchors + [
                [
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude,
                    "altitude": altitude,
                    "x": eastUpSouthQTarget.vector[0],
                    "y": eastUpSouthQTarget.vector[1],
                    "z": eastUpSouthQTarget.vector[2],
                    "w": eastUpSouthQTarget.vector[3]
                ]
            ]
            defaults.set(newSavedAnchors, forKey: kSavedAnchorsUserDefaultsKey)
        }
    }
    
    func addTerrainAnchorWithCoordinate(_ coordinate: CLLocationCoordinate2D, eastUpSouthQTarget: simd_quatf, shouldSave: Bool) {
        
        
        do {
            try garSession?.createAnchorOnTerrain(coordinate: coordinate, altitudeAboveTerrain: 0, eastUpSouthQAnchor: eastUpSouthQTarget)
        } catch {
            print("Error adding anchor: \(error)")
            return
        }
        if shouldSave {
            let defaults = UserDefaults.standard
            let savedAnchors = defaults.array(forKey: kSavedAnchorsUserDefaultsKey) as? [[String: Any]] ?? []
            let newSavedAnchors = savedAnchors + [
                [
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude,
                    "x": eastUpSouthQTarget.vector[0],
                    "y": eastUpSouthQTarget.vector[1],
                    "z": eastUpSouthQTarget.vector[2],
                    "w": eastUpSouthQTarget.vector[3]
                ]
            ]
            defaults.set(newSavedAnchors, forKey: kSavedAnchorsUserDefaultsKey)
        }
    }
    
    @objc func addAnchorButtonPressed() {

        // Update the quaternion from landscape orientation to portrait orientation.
        let rotationZquat = simd_quaternion(Float.pi / 2, simd_float3(0, 0, 1))
        
        guard let geospatialTransform = self.garFrame.earth?.cameraGeospatialTransform
              else {
                  print("Error: now geospatialTransform")
                  return
              }
        let eastUpSouthQPortraitCamera = simd_mul(geospatialTransform.eastUpSouthQTarget, rotationZquat)
        
        if self.isTerrainAnchorMode {
            addTerrainAnchorWithCoordinate(geospatialTransform.coordinate,
                                           eastUpSouthQTarget: eastUpSouthQPortraitCamera,
                                           shouldSave: true)
        } else {
            addAnchorWithCoordinate(geospatialTransform.coordinate,
                                    altitude: geospatialTransform.altitude,
                                    eastUpSouthQTarget: eastUpSouthQPortraitCamera,
                                    shouldSave: true)
        }
        self.islastClickedTerrainAnchorButton = self.isTerrainAnchorMode
    }
    
    @objc func clearAllAnchorsButtonPressed() {
        for anchor in self.garFrame.anchors {
            self.garSession?.remove(anchor)
        }
        for node in self.markerNodes.values {
            node.removeFromParentNode()
        }
        self.markerNodes.removeAll()
        UserDefaults.standard.removeObject(forKey: kSavedAnchorsUserDefaultsKey)
        self.islastClickedTerrainAnchorButton = false
    }
    
    // -MARK: Adding anchor from touch projection
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let touchLocation = touch.location(in: self.scnView)

        
        guard let query = self.scnView.raycastQuery(from: touchLocation, allowing: .existingPlaneGeometry, alignment: .horizontal) else {
            print("Failed to get a raycast query")
            return
        }
        let rayCastResults = arSession.raycast(query)
        
        if let result = rayCastResults.first {
            do {
                let geospatialTransform = try self.garSession?.geospatialTransform(transform: result.worldTransform)
                guard let geospatialTransform = geospatialTransform else {
                    print("No transform")
                    return
                }
                geospatialTransform.eastUpSouthQTarget
                if self.isTerrainAnchorMode {
                    addTerrainAnchorWithCoordinate(geospatialTransform.coordinate,
                                                   eastUpSouthQTarget: geospatialTransform.eastUpSouthQTarget,
                                                   shouldSave: true)
                } else {
                    addAnchorWithCoordinate(geospatialTransform.coordinate,
                                            altitude: geospatialTransform.altitude,
                                            eastUpSouthQTarget: geospatialTransform.eastUpSouthQTarget,
                                            shouldSave: true)
                }
                self.islastClickedTerrainAnchorButton = self.isTerrainAnchorMode
            } catch {
                print("Error adding convert transform to GARGeospatialTransform: (error)")
            }
        }
    }
}

extension ViewController: CLLocationManagerDelegate {
    func locationManager(_ locationManager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        checkLocationPermission()
    }

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ locationManager: CLLocationManager) {
        checkLocationPermission()
    }

    func locationManager(_ locationManager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            self.checkVPSAvailabilityWithCoordinate(location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error get location: \(error)")
    }
}

extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        return SCNNode()
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            let width = CGFloat(planeAnchor.extent.x)
            let height = CGFloat(planeAnchor.extent.z)
            let plane = SCNPlane(width: width, height: height)
            
            plane.materials.first?.diffuse.contents = UIColor(red: 0, green: 0, blue: 1, alpha: 0.7)
            
            let planeNode = SCNNode(geometry: plane)
            
            let x = CGFloat(planeAnchor.center.x)
            let y = CGFloat(planeAnchor.center.y)
            let z = CGFloat(planeAnchor.center.z)
            planeNode.position = SCNVector3(x, y, z)
            
            planeNode.eulerAngles = SCNVector3(-Double.pi/2, 0, 0)
            
            node.addChildNode(planeNode)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            if let planeNode = node.childNodes.first, let plane = planeNode.geometry as? SCNPlane {
                plane.width = CGFloat(planeAnchor.extent.x)
                plane.height = CGFloat(planeAnchor.extent.z)
                planeNode.position = SCNVector3Make(planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if let _ = anchor as? ARPlaneAnchor {
            if let planeNode = node.childNodes.first {
                planeNode.removeFromParentNode()
            }
        }
    }
}

extension ViewController: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let garSession = self.garSession , self.localizationState != .failed else {
            return
        }
        do {
            let garFrame = try garSession.update(frame)
            self.updateWithGARFrame(garFrame)
        } catch {
            print("Failed updating GARFrame: \(error)")
        }
        
    }
}
