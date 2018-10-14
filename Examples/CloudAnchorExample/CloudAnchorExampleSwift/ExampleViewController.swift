/*
 * Copyright 2018 Google Inc. All Rights Reserved.
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

import ARCore
import ARKit
import Dispatch
import FirebaseDatabase
import ModelIO
import SceneKit

enum HelloARState : Int {
  case `default`
  case creatingRoom
  case roomCreated
  case hosting
  case hostingFinished
  case enterRoomCode
  case resolving
  case resolvingFinished
}

@objc(ExampleViewController)
class ExampleViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, GARSessionDelegate {
  private var gSession: GARSession!
  private var firebaseReference: DatabaseReference!
  private var arAnchor: ARAnchor!
  private var garAnchor: GARAnchor!
  private var state: HelloARState!
  private var roomCode = ""
  private var message = ""

  @IBOutlet var sceneView: ARSCNView!
  @IBOutlet var hostButton: UIButton!
  @IBOutlet var resolveButton: UIButton!
  @IBOutlet var roomCodeLabel: UILabel!
  @IBOutlet var messageLabel: UILabel!

  // MARK: - Overriding UIViewController
  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    firebaseReference = Database.database().reference()
    sceneView.delegate = self
    sceneView.session.delegate = self
    try? gSession = GARSession(apiKey: "your-api-key", bundleIdentifier: nil)
    gSession.delegate = self
    gSession.delegateQueue = DispatchQueue.main
    enter(.default)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    configuration.planeDetection = .horizontal

    sceneView.session.run(configuration)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sceneView.session.pause()
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if touches.count < 1 || state != .roomCreated {
      return
    }

    let touch = Array(touches).first
    let touchLocation: CGPoint? = touch?.location(in: sceneView)

    let hitTestResults = sceneView.hitTest(touchLocation ?? CGPoint.zero, types: [.existingPlane, .existingPlaneUsingExtent, .estimatedHorizontalPlane])

    if hitTestResults.count > 0 {
      let result: ARHitTestResult? = hitTestResults.first
      if let aTransform = result?.worldTransform {
        addAnchor(withTransform: aTransform)
      }
    }
  }

  // MARK: - Anchor Hosting / Resolving
  func resolveAnchor(withRoomCode roomCode: String) {
    self.roomCode = roomCode
    enter(.resolving)
    weak var weakSelf: ExampleViewController? = self
    firebaseReference.child("hotspot_list").child(roomCode).observe(.value) { snapshot in

      DispatchQueue.main.async(execute: {
        let strongSelf: ExampleViewController? = weakSelf
        if strongSelf == nil || strongSelf?.state != .resolving || !(strongSelf?.roomCode == roomCode) {
          return
        }

        if let value = snapshot.value as? [AnyHashable: Any], let anchorId = value["hosted_anchor_id"] as? String {
          strongSelf?.firebaseReference.child("hotspot_list").child(roomCode).removeAllObservers()
          strongSelf?.resolveAnchor(withIdentifier: anchorId)
        }
      })
    }
  }

  func resolveAnchor(withIdentifier identifier: String) {
    // Now that we have the anchor ID from firebase, we resolve the anchor.
    // Success and failure of this call is handled by the delegate methods
    // session:didResolveAnchor and session:didFailToResolveAnchor appropriately.
    try? garAnchor = gSession.resolveCloudAnchor(withIdentifier: identifier)
  }

  func addAnchor(withTransform transform: matrix_float4x4) {
    arAnchor = ARAnchor(transform: transform)
    sceneView.session.add(anchor: arAnchor)

    // To share an anchor, we call host anchor here on the ARCore session.
    // session:didHostAnchor: session:didFailToHostAnchor: will get called appropriately.
    try? garAnchor = gSession.hostCloudAnchor(arAnchor)
    enter(.hosting)
  }

  // MARK: - Actions
  @IBAction func hostButtonPressed() {
    if state == .default {
      enter(.creatingRoom)
      createRoom()
    } else {
      enter(.default)
    }
  }

  @IBAction func resolveButtonPressed() {
    if state == .default {
      enter(.enterRoomCode)
    } else {
      enter(.default)
    }
  }

  // MARK: - GARSessionDelegate
  func session(_ session: GARSession, didHostAnchor anchor: GARAnchor) {
    if state != .hosting || !(anchor == garAnchor) {
      return
    }
    garAnchor = anchor
    enter(.hostingFinished)
    firebaseReference.child("hotspot_list").child(roomCode).child("hosted_anchor_id").setValue(anchor.cloudIdentifier)
    let timestampInteger = Int64(Date().timeIntervalSince1970 * 1000)
    let timestamp = timestampInteger
    firebaseReference.child("hotspot_list").child(roomCode).child("updated_at_timestamp").setValue(timestamp)
  }

  func session(_ session: GARSession, didFailToHostAnchor anchor: GARAnchor) {
    if state != .hosting || !(anchor == garAnchor) {
      return
    }
    garAnchor = anchor
    enter(.hostingFinished)
  }

  func session(_ session: GARSession, didResolve anchor: GARAnchor) {
    if state != .resolving || !(anchor == garAnchor) {
      return
    }
    garAnchor = anchor
    arAnchor = ARAnchor(transform: anchor.transform)
    sceneView.session.add(anchor: arAnchor)
    enter(.resolvingFinished)
  }

  func session(_ session: GARSession, didFailToResolve anchor: GARAnchor) {
    if state != .resolving || !(anchor == garAnchor) {
      return
    }
    garAnchor = anchor
    enter(.resolvingFinished)
  }

  // MARK: - ARSessionDelegate
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Forward ARKit's update to ARCore session
    try! gSession.update(frame)
  }

  // MARK: - Helper Methods
  func updateMessageLabel() {
    messageLabel.text = message
    roomCodeLabel.text = "Room: \(roomCode)"
  }

  func toggle(_ button: UIButton?, enabled: Bool, title: String?) {
    button?.isEnabled = enabled
    button?.setTitle(title, for: .normal)
  }

  func cloudStateString(_ cloudState: GARCloudAnchorState) -> String {
    switch cloudState {
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
    case .errorResourceExhausted:
      return "ErrorResourceExhausted"
    case .errorServiceUnavailable:
      return "ErrorServiceUnavailable"
    case .errorHostingDatasetProcessingFailed:
      return "ErrorHostingDatasetProcessingFailed"
    case .errorCloudIdNotFound:
      return "ErrorCloudIdNotFound"
    case .errorResolvingSdkVersionTooNew:
      return "ErrorResolvingSdkVersionTooNew"
    case .errorResolvingSdkVersionTooOld:
      return "ErrorResolvingSdkVersionTooOld"
    case .errorResolvingLocalizationNoMatch:
      return "ErrorResolvingLocalizationNoMatch"
    }
  }

  func showRoomCodeDialog() {
    let alertController = UIAlertController(title: "ENTER ROOM CODE", message: "", preferredStyle: .alert)
    let okAction = UIAlertAction(title: "OK", style: .default, handler: { action in
      if let roomCode = alertController.textFields?[0].text, roomCode.count != 0 {
        self.resolveAnchor(withRoomCode: roomCode)
      } else {
        self.enter(.default)
      }
    })
    let cancelAction = UIAlertAction(title: "CANCEL", style: .default, handler: { action in
      self.enter(.default)
    })
    alertController.addTextField(configurationHandler: { textField in
      textField.keyboardType = .numberPad
    })
    alertController.addAction(okAction)
    alertController.addAction(cancelAction)
    present(alertController, animated: false) {
    }
  }

  func enter(_ state: HelloARState) {
    switch state {
    case .default:
      if let arAnchor = arAnchor {
        sceneView.session.remove(anchor: arAnchor)
        self.arAnchor = nil
      }
      if let garAnchor = garAnchor {
        gSession.remove(garAnchor)
        self.garAnchor = nil
      }
      if self.state == .creatingRoom {
        message = "Failed to create room. Tap HOST or RESOLVE to begin."
      } else {
        message = "Tap HOST or RESOLVE to begin."
      }
      if self.state == .enterRoomCode {
        dismiss(animated: false) {
        }
      } else if self.state == .resolving {
        firebaseReference.child("hotspot_list").child(roomCode).removeAllObservers()
      }
      toggle(hostButton, enabled: true, title: "HOST")
      toggle(resolveButton, enabled: true, title: "RESOLVE")
      roomCode = ""
    case .creatingRoom:
      message = "Creating room..."
      toggle(hostButton, enabled: false, title: "HOST")
      toggle(resolveButton, enabled: false, title: "RESOLVE")
    case .roomCreated:
      message = "Tap on a plane to create anchor and host."
      toggle(hostButton, enabled: true, title: "CANCEL")
      toggle(resolveButton, enabled: false, title: "RESOLVE")
    case .hosting:
      message = "Hosting anchor..."
    case .hostingFinished:
      message = "Finished hosting: \(cloudStateString(garAnchor.cloudState))"
    case .enterRoomCode:
      showRoomCodeDialog()
    case .resolving:
      dismiss(animated: false) {
      }
      message = "Resolving anchor..."
      toggle(hostButton, enabled: false, title: "HOST")
      toggle(resolveButton, enabled: true, title: "CANCEL")
    case .resolvingFinished:
      message = "Finished resolving: \(cloudStateString(garAnchor.cloudState))"
    }
    self.state = state
    updateMessageLabel()
  }

  func createRoom() {
    weak var weakSelf: ExampleViewController? = self
    firebaseReference.child("last_room_code").runTransactionBlock({ currentData in
      let strongSelf: ExampleViewController? = weakSelf

      var roomNumberInt = 0
      if let roomNumber = currentData.value as? NSNumber {
        roomNumberInt = roomNumber.intValue
      }

      roomNumberInt += 1
      let newRoomNumber = NSNumber(value: roomNumberInt)

      let timestamp = NSNumber(value: Date().timeIntervalSince1970 * 1000)

      let room = ["display_name": "\(newRoomNumber)", "updated_at_timestamp": timestamp] as [String : Any]

      strongSelf?.firebaseReference.child("hotspot_list").child("\(newRoomNumber)").setValue(room)

      currentData.value = newRoomNumber

      return TransactionResult.success(withValue: currentData)
    }, andCompletionBlock: { error, committed, snapshot in
      DispatchQueue.main.async(execute: {
        if error != nil {
          weakSelf?.roomCreationFailed()
        } else {
          weakSelf?.roomCreated("\(snapshot?.value as! NSNumber)")
        }
      })
    })
  }

  func roomCreated(_ roomCode: String) {
    self.roomCode = roomCode
    enter(.roomCreated)
  }

  func roomCreationFailed() {
    enter(.default)
  }

  // MARK: - ARSCNViewDelegate
  func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
    if (anchor is ARPlaneAnchor) == false {
      let scene = SCNScene(named: "example.scnassets/andy.scn")
      return scene?.rootNode.childNode(withName: "andy", recursively: false)
    } else {
      return SCNNode()
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    if (anchor is ARPlaneAnchor) {
      let planeAnchor = anchor as? ARPlaneAnchor

      let width = CGFloat(planeAnchor?.extent.x ?? 0.0)
      let height = CGFloat(planeAnchor?.extent.z ?? 0.0)
      let plane = SCNPlane(width: width, height: height)

      plane.materials.first?.diffuse.contents = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.3)

      let planeNode = SCNNode(geometry: plane)

      let x = CGFloat(planeAnchor?.center.x ?? 0.0)
      let y = CGFloat(planeAnchor?.center.y ?? 0.0)
      let z = CGFloat(planeAnchor?.center.z ?? 0.0)
      planeNode.position = SCNVector3Make(Float(x), Float(y), Float(z))
      planeNode.eulerAngles = SCNVector3Make(-.pi / 2, 0, 0)

      node.addChildNode(planeNode)
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    if (anchor is ARPlaneAnchor) {
      let planeAnchor = anchor as? ARPlaneAnchor

      let planeNode: SCNNode? = node.childNodes.first
      let plane = planeNode?.geometry as? SCNPlane

      let width = CGFloat(planeAnchor?.extent.x ?? 0.0)
      let height = CGFloat(planeAnchor?.extent.z ?? 0.0)
      plane?.width = width
      plane?.height = height

      let x = CGFloat(planeAnchor?.center.x ?? 0.0)
      let y = CGFloat(planeAnchor?.center.y ?? 0.0)
      let z = CGFloat(planeAnchor?.center.z ?? 0.0)
      planeNode?.position = SCNVector3Make(Float(x), Float(y), Float(z))
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    if (anchor is ARPlaneAnchor) {
      let planeNode: SCNNode? = node.childNodes.first
      planeNode?.removeFromParentNode()
    }
  }
}

