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

import UIKit
import SceneKit
import ARKit
import Firebase
import ARCore
import ModelIO

enum HelloARState {
  case `default`
  case creatingRoom
  case roomCreated
  case hosting
  case hostingFinished
  case enterRoomCode
  case resolving
  case resolvingFinished
}

class ExampleViewController: UIViewController {

  @IBOutlet var sceneView: ARSCNView!
  @IBOutlet var hostButton: UIButton!
  @IBOutlet var resolveButton: UIButton!
  @IBOutlet var roomCodeLabel: UILabel!
  @IBOutlet var messageLabel: UILabel!

  private var gSession: GARSession!

  private var firebaseReference: DatabaseReference!

  private var arAnchor: ARAnchor?
  private var garAnchor: GARAnchor?

  private var state: HelloARState = .default

  private var roomCode: String = ""
  private var message: String?

  //MARK: - Overriding UIViewController
  override var prefersStatusBarHidden: Bool {
    return true
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    firebaseReference = Database.database().reference()
    sceneView.delegate = self
    sceneView.session.delegate = self
    gSession = try! GARSession(apiKey: "your-api-key", bundleIdentifier: nil)
    gSession.delegate = self
    gSession.delegateQueue = DispatchQueue.main
    enter(state: .default)
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
    guard let touch = touches.first, state == .roomCreated else {
      return
    }

    let touchLocation = touch.location(in: sceneView)
    let hitTestResults = sceneView.hitTest(touchLocation, types: [.existingPlane, .existingPlaneUsingExtent, .estimatedHorizontalPlane])

    if let result = hitTestResults.first {
      addAnchor(transform: result.worldTransform)
    }
  }

  // MARK: - Anchor Hosting / Resolving
  func resolveAnchor(roomCode: String) {
    self.roomCode = roomCode
    enter(state: .resolving)
    firebaseReference.child("hotspot_list").child(roomCode).observe(.value) { (snapshot) in
      DispatchQueue.main.async { [weak self] in
        guard let strongSelf = self, strongSelf.state == .resolving, strongSelf.roomCode == roomCode else { return }

        if let anchorId: String = {
          if let value = snapshot.value as? [String: Any] {
            return value["hosted_anchor_id"] as? String
          }
          return nil
          }() {
          strongSelf.firebaseReference.child("hotspot_list").child(roomCode).removeAllObservers()
          strongSelf.resolveAnchor(identifier: anchorId)
        }

      }
    }
  }

  func resolveAnchor(identifier: String) {
    // Now that we have the anchor ID from firebase, we resolve the anchor.
    // Success and failure of this call is handled by the delegate methods
    // session:didResolveAnchor and session:didFailToResolveAnchor appropriately.
    do {
      garAnchor = try gSession?.resolveCloudAnchor(withIdentifier: identifier)
    } catch {
      print(error)
    }
  }

  func addAnchor(transform: matrix_float4x4) {
    let arAnchor = ARAnchor(transform: transform)
    self.arAnchor = arAnchor
    sceneView.session.add(anchor: arAnchor)

    // To share an anchor, we call host anchor here on the ARCore session.
    // session:disHostAnchor: session:didFailToHostAnchor: will get called appropriately.
    do {
      garAnchor = try gSession.hostCloudAnchor(arAnchor)
      enter(state: .hosting)
    } catch {
      print(error)
    }
  }

  // MARK: - Actions
  @IBAction func hostButtonPressed() {
    switch state {
    case .default:
      enter(state: .creatingRoom)
      createRoom()
    default:
      enter(state: .default)
    }
  }

  @IBAction func resolveButtonPressed() {
    switch state {
    case .default:
      enter(state: .enterRoomCode)
    default:
      enter(state: .default)
    }
  }
}

extension ExampleViewController: GARSessionDelegate {
  func session(_ session: GARSession, didHostAnchor anchor: GARAnchor) {
    guard state == .hosting, anchor == garAnchor else {
      return
    }
    garAnchor = anchor
    enter(state: .hostingFinished)
    firebaseReference.child("hotspot_list").child(roomCode).child("hosted_anchor_id").setValue(anchor.cloudIdentifier)
    let timestampInteger = NSDate().timeIntervalSince1970 * 1000
    let timestamp = NSNumber(value: timestampInteger)
    firebaseReference.child("hotspot_list").child(roomCode).child("updated_at_timestamp").setValue(timestamp)
  }

  func session(_ session: GARSession, didFailToHostAnchor anchor: GARAnchor) {
    guard state == .hosting, anchor == garAnchor else {
      return
    }
    self.garAnchor = anchor
    enter(state: .hostingFinished)
  }

  func session(_ session: GARSession, didResolve anchor: GARAnchor) {
    guard state == .resolving, anchor == garAnchor else {
      return
    }
    self.garAnchor = anchor
    let arAnchor = ARAnchor(transform: anchor.transform)
    self.arAnchor = ARAnchor(transform: anchor.transform)
    sceneView.session.add(anchor: arAnchor)
    enter(state: .resolvingFinished)
  }

  func session(_ session: GARSession, didFailToResolve anchor: GARAnchor) {
    guard state == .resolving, anchor == garAnchor else {
      return
    }
    self.garAnchor = anchor
    enter(state: .resolvingFinished)
  }
}

extension ExampleViewController: ARSessionDelegate {
  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    do {
      try gSession.update(frame)
    } catch {
      print(error)
    }
  }
}

//MARK: - Helper Methods
private extension ExampleViewController {
  func updateMessageLabel() {
    messageLabel.text = message
    roomCodeLabel.text = "Room: \(roomCode)"
  }

  func toggle(button: UIButton, isEnabled: Bool, title: String) {
    button.isEnabled = isEnabled
    button.setTitle(title, for: .normal)
  }

  func showRoomCodeDialog() {
    let alertController = UIAlertController.init(title: "ENTER ROOM CODE", message: "", preferredStyle: .alert)
    let okAction = UIAlertAction.init(title: "OK", style: .default) { [weak self] (action) in
      if let roomCode: String = alertController.textFields?.first?.text {
        if roomCode.isEmpty {
          self?.enter(state: .default)
        } else {
          self?.resolveAnchor(roomCode: roomCode)
        }
      }
    }

    let cancelAction = UIAlertAction.init(title: "CANCEL", style: .default) { [weak self] (action) in
      self?.enter(state: .default)
    }
    alertController.addTextField { (textField) in
      textField.keyboardType = .numberPad
    }
    alertController.addAction(okAction)
    alertController.addAction(cancelAction)
    present(alertController, animated: false, completion: nil)
  }

  func enter(state: HelloARState) {
    switch state {
    case .default:
      if let arAnchor = self.arAnchor {
        sceneView.session.remove(anchor: arAnchor)
        self.arAnchor = nil
      }

      if let garAnchor = self.garAnchor {
        gSession.remove(garAnchor)
        self.garAnchor = nil
      }

      if state == .creatingRoom {
        self.message = "Failed to create room. Tap HOST or RESOLVE to begin."
      } else {
        self.message = "Tap HOST or RESOLVE to begin."
      }

      if state == .enterRoomCode {
        dismiss(animated: false, completion: nil)
      } else if state == .resolving {
        firebaseReference.child("hotspot_list").child(roomCode).removeAllObservers()
      }
      toggle(button: hostButton, isEnabled: true, title: "HOST")
      toggle(button: resolveButton, isEnabled: true, title: "RESOLVE")
      roomCode = ""
    case .creatingRoom:
      message = "Creating room..."
      toggle(button: hostButton, isEnabled: false, title: "HOST")
      toggle(button: resolveButton, isEnabled: false, title: "RESOLVE")
    case .roomCreated:
      message = "Tap on a plane to create anchor and host."
      toggle(button: hostButton, isEnabled: true, title: "CANCEL")
      toggle(button: resolveButton, isEnabled: false, title: "RESOLVE")
    case .hosting:
      message = "Hosting anchor..."
    case .hostingFinished:
      message = "Finished hosting: \(garAnchor!.cloudState.cloudStateString)"
    case .enterRoomCode:
      showRoomCodeDialog()
    case .resolving:
      dismiss(animated: false, completion: nil)
      message = "Resolving anchor..."
      toggle(button: hostButton, isEnabled: false, title: "HOST")
      toggle(button: resolveButton, isEnabled: true, title: "CANCEL")
    case .resolvingFinished:
      message = "Finished resolving: \(garAnchor!.cloudState.cloudStateString)"
    }
    self.state = state
    updateMessageLabel()
  }

  func createRoom() {
    firebaseReference.child("last_room_code").runTransactionBlock({ [weak self] (currentData) -> TransactionResult in
      let roomNumber: NSNumber = currentData.value as? NSNumber ?? 0
      let newRoomNumber = NSNumber(value: roomNumber.intValue + 1)
      let timeStamp = NSNumber(value: NSDate().timeIntervalSince1970 * 1000)

      let room: [String: Any] = ["display_name": newRoomNumber.stringValue,
                                 "updated_at_timestamp": timeStamp]
      self?.firebaseReference.child("hotspot_list").child(newRoomNumber.stringValue).setValue(room)
      currentData.value = newRoomNumber

      return TransactionResult.success(withValue: currentData)
    }) { [weak self] (error, committed, snapshot) in
      DispatchQueue.main.async {
        if error != nil {
          self?.roomCreationFailed()
        } else {
          self?.roomCreated(roomCode: (snapshot?.value as! NSNumber).stringValue)
        }
      }
    }
  }

  func roomCreated(roomCode: String) {
    self.roomCode = roomCode
    enter(state: .roomCreated)
  }

  func roomCreationFailed() {
    enter(state: .default)
  }
}

extension ExampleViewController: ARSCNViewDelegate {
  // MARK: - ARSCNViewDelegate
  func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
    if anchor is ARPlaneAnchor {
      return SCNNode()
    } else {
      let scene = SCNScene(named: "example.scnassets/andy.scn")
      return scene?.rootNode.childNode(withName: "andy", recursively: false)
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let planeAnchor = anchor as? ARPlaneAnchor else {
      return
    }

    let width = CGFloat(planeAnchor.extent.x)
    let height = CGFloat(planeAnchor.extent.z)
    let plane = SCNPlane(width: width, height: height)

    plane.materials.first?.diffuse.contents = UIColor(red: 0, green: 0, blue: 1.0, alpha: 0.3)

    let planeNode = SCNNode(geometry: plane)

    planeNode.position = SCNVector3Make(planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z)
    planeNode.eulerAngles = SCNVector3Make(-Float.pi / 2 , 0, 0)
    node.addChildNode(planeNode)
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    guard let planeAnchor = anchor as? ARPlaneAnchor else {
      return
    }

    if let planeNode = node.childNodes.first, let plane = planeNode.geometry as? SCNPlane {
      let width = CGFloat(planeAnchor.extent.x)
      let height = CGFloat(planeAnchor.extent.z)
      plane.width = width
      plane.height = height
      planeNode.position = SCNVector3Make(planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z)
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    guard anchor is ARPlaneAnchor else {
      return
    }
    if let planeNode = node.childNodes.first {
      planeNode.removeFromParentNode()
    }
  }
}

private extension GARCloudAnchorState {
  var cloudStateString: String {
    switch self {
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
      return "ErrorResourceExhausted"
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
}
