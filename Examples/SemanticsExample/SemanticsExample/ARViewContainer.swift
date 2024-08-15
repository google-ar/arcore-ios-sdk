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
import CoreVideo
import RealityKit
import SwiftUI
import UIKit

/// SwiftUI wrapper for an `ARView` and all rendering code.
struct ARViewContainer: UIViewRepresentable {
  let semanticsEnabled: Bool
  let fractions: [SemanticFraction]
  @Binding var semanticImage: CGImage?

  /// Coordinator to act as `ARSessionDelegate` for `ARView`.
  class Coordinator: NSObject, ARSessionDelegate {
    private let fractions: [SemanticFraction]
    @Binding private var semanticImage: CGImage?
    private let colorMap: [UInt8: UIColor]
    fileprivate let arView = ARView(
      frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private let garSession: GARSession?
    private var semanticData: Data?
    private var semanticImageContext: CGContext?

    init(fractions: [SemanticFraction], semanticImage: Binding<CGImage?>) {
      self.fractions = fractions
      var colorMap: [UInt8: UIColor] = [:]
      for fraction in fractions {
        colorMap[UInt8(fraction.id.rawValue)] = fraction.color
      }
      self.colorMap = colorMap
      _semanticImage = semanticImage
      do {
        garSession = try GARSession.session()
      } catch let error as NSError {
        print("Failed to create GARSession: \(error)")
        garSession = nil
      }
      super.init()
      setSemanticsEnabled(true)
      arView.session.delegate = self
      let configuration = ARWorldTrackingConfiguration()
      configuration.worldAlignment = .gravity
      arView.session.run(configuration)
    }

    fileprivate func setSemanticsEnabled(_ enabled: Bool) {
      guard let garSession else { return }
      guard garSession.isSemanticModeSupported(.enabled) else {
        print("Semantics is not supported by the given device/OS version.")
        return
      }
      var error: NSError? = nil
      let configuration = GARSessionConfiguration()
      configuration.semanticMode = enabled ? .enabled : .disabled
      garSession.setConfiguration(configuration, error: &error)
      if let error {
        print("Failed to configure GARSession: \(error)")
      }
      if !enabled {
        for fraction in fractions {
          fraction.fraction = 0
        }
      }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      guard let garSession else { return }
      guard let garFrame = try? garSession.update(frame) else { return }
      guard let image = garFrame.semanticImage else {
        semanticImage = nil
        return
      }

      if semanticData == nil {
        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)
        semanticData = Data(repeating: 0, count: width * height * 4)
        semanticData?.withUnsafeMutableBytes { pointer in
          semanticImageContext = CGContext(
            data: pointer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrderDefault.rawValue)
        }
      }
      guard semanticData != nil, let semanticImageContext else { return }

      CVPixelBufferLockBaseAddress(image, .readOnly)
      guard let baseAddress = CVPixelBufferGetBaseAddress(image) else { return }
      let totalBytes = CVPixelBufferGetDataSize(image)
      let labelBuffer = UnsafeRawBufferPointer(start: baseAddress, count: totalBytes)
        .assumingMemoryBound(to: UInt8.self)

      semanticData?.withUnsafeMutableBytes { pointer in
        let dataBuffer = pointer.assumingMemoryBound(to: UInt8.self)
        for i in 0..<totalBytes {
          var red: CGFloat = 0
          var green: CGFloat = 0
          var blue: CGFloat = 0
          var alpha: CGFloat = 0
          guard let color = self.colorMap[labelBuffer[i]],
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
          else { continue }
          // Bounds checking makes this too slow when building without optimizations.
          dataBuffer[i * 4] = UInt8(red * 255)
          dataBuffer[i * 4 + 1] = UInt8(green * 255)
          dataBuffer[i * 4 + 2] = UInt8(blue * 255)
          dataBuffer[i * 4 + 3] = UInt8(alpha * 255)
        }
      }

      CVPixelBufferUnlockBaseAddress(image, [])

      semanticImage = semanticImageContext.makeImage()

      for fraction in fractions {
        fraction.fraction = garFrame.fraction(for: fraction.id)
      }
    }
  }

  func makeUIView(context: Context) -> ARView {
    return context.coordinator.arView
  }

  func updateUIView(_ uiView: ARView, context: Context) {
    context.coordinator.setSemanticsEnabled(semanticsEnabled)
  }

  func makeCoordinator() -> Coordinator {
    return Coordinator(fractions: fractions, semanticImage: $semanticImage)
  }
}
