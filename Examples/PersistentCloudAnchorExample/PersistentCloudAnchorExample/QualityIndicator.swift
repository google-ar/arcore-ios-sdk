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
import RealityKit
import UIKit
import simd

/// Convenience class mapping quality indicator.
struct QualityIndicator {
  private enum Constants {
    /// Radius of ring around anchor.
    static let radius: Float = 0.2
    /// Pipe radius of ring around anchor.
    static let pipeRadius: Float = 0.001
    /// Number of subdivisions around the ring.
    static let ringSegmentCount = 32
    /// Number of subdivisions around the ring pipe.
    static let pipeSegmentCount = 32
    /// Material for ring.
    static let ringMaterial = UnlitMaterial(color: .white)
    /// Radius of quality indicator capsules.
    static let capsuleRadius: Float = 0.006
    /// Height of quality indicator capsules.
    static let capsuleHeight: Float = 0.03
    /// Number of quality indicators for anchor on horizontal plane.
    static let horizontalBarCount = 25
    /// Number of quality indicators for anchor on vertical plane.
    static let verticalBarCount = 21
    /// Angular spacing around anchor of quality indicators (in radians).
    static let barSpacing: Float = (Float.pi / 180) * 7.5
    /// Angular offset of first quality indicator in vertical plane case (in radians).
    static let verticalAngleOffset = Float.pi / 12

    /// Gets the color to be used for a given mapping quality.
    static func color(for quality: GARFeatureMapQuality) -> UIColor {
      switch quality {
      case .good:
        return .green
      case .sufficient:
        return .yellow
      default:
        return .red
      }
    }
  }

  private class Bar {
    private var quality: GARFeatureMapQuality = .insufficient
    private let model: ModelEntity

    init(parent: Entity, angle: Float, isOnHorizontalPlane: Bool) {
      let capsuleWidth = Constants.capsuleRadius * 2
      // Capsule shape = box with rounded corners.
      let resource = MeshResource.generateBox(
        size: simd_make_float3(capsuleWidth, Constants.capsuleHeight, capsuleWidth),
        cornerRadius: Constants.capsuleRadius)
      model = ModelEntity(mesh: resource, materials: [UnlitMaterial(color: .white)])
      if isOnHorizontalPlane {
        // Standing up on top of z-x plane.
        model.position = simd_make_float3(
          Constants.radius * cos(angle), Constants.capsuleHeight / 2, Constants.radius * sin(angle))
      } else {
        // Standing up on top of x-y plane, pointing toward negative z.
        model.position = simd_make_float3(
          Constants.radius * cos(angle), Constants.radius * sin(angle), -Constants.capsuleHeight / 2
        )
        model.orientation = simd_quatf(angle: Float.pi / 2, axis: simd_make_float3(1, 0, 0))
      }
      parent.addChild(model)
    }

    func updateQuality(_ quality: GARFeatureMapQuality) {
      if quality.rawValue > self.quality.rawValue {
        self.quality = quality
      }
      model.model?.materials = [UnlitMaterial(color: Constants.color(for: self.quality))]
    }

    func qualityValue() -> Float {
      switch quality {
      case .good:
        return 1
      case .sufficient:
        return 0.5
      default:
        return 0
      }
    }
  }

  private let isOnHorizontalPlane: Bool
  private var bars: [Bar] = []

  /// Initializes a new quality indicator.
  ///
  /// - Parameters:
  ///   - parent: The anchor entity to attach child nodes to.
  ///   - isOnHorizontalPlane: `true` if the anchor is attached to a horizontal plane, `false` if
  ///     vertical.
  init(parent: Entity, isOnHorizontalPlane: Bool) {
    self.isOnHorizontalPlane = isOnHorizontalPlane

    if isOnHorizontalPlane {
      for i in 0...(Constants.horizontalBarCount - 1) {
        bars.append(
          Bar(parent: parent, angle: Constants.barSpacing * Float(i), isOnHorizontalPlane: true))
      }
    } else {
      for i in 0...(Constants.verticalBarCount - 1) {
        bars.append(
          Bar(
            parent: parent, angle: Constants.verticalAngleOffset + Constants.barSpacing * Float(i),
            isOnHorizontalPlane: false))
      }
    }

    guard let mesh = QualityIndicator.generateHalfTorus() else { return }
    let ring = ModelEntity(mesh: mesh, materials: [Constants.ringMaterial])
    if !isOnHorizontalPlane {
      // Rotate ring into x-y plane.
      ring.orientation = simd_quatf(angle: -Float.pi / 2, axis: simd_make_float3(1, 0, 0))
    }
    parent.addChild(ring)
  }

  /// Update the quality indicator with a new quality value.
  ///
  /// - Parameters:
  ///   - quality: The new quality value.
  ///   - anchorFromCamera: The transform of the camera relative to the anchor.
  /// - Returns: A tuple containing the average mapping quality value (computed as a float) and the
  ///   cylindrical distance to the anchor.
  func update(quality: GARFeatureMapQuality, anchorFromCamera: simd_float4x4) -> (
    averageQuality: Float, distance: Float
  ) {
    let x = anchorFromCamera.columns.3[0]
    let y = anchorFromCamera.columns.3[1]
    let z = anchorFromCamera.columns.3[2]
    // Cylindrical distance in plane of quality indicator ring.
    let distance = isOnHorizontalPlane ? sqrtf(z * z + x * x) : sqrtf(y * y + x * x)
    let angle = isOnHorizontalPlane ? atan2f(z, x) : (atan2f(y, x) - Constants.verticalAngleOffset)
    let barIndex = Int(roundf(angle / Constants.barSpacing))
    if barIndex >= 0 && barIndex < bars.count {
      bars[barIndex].updateQuality(quality)
    }
    var sum: Float = 0
    for bar in bars {
      sum += bar.qualityValue()
    }
    let averageQuality = sum / Float(bars.count)
    return (averageQuality, distance)
  }

  private static func generateHalfTorus() -> MeshResource? {
    var descriptor = MeshDescriptor()

    // Vertices equally spaced around the ring and around the cross sections.
    var vertices: [simd_float3] = []
    for i in 0...Constants.ringSegmentCount {
      // Angle from x-axis, clockwise in z-x plane.
      let theta = Float.pi * (Float(i) / Float(Constants.ringSegmentCount))
      for j in 0...(Constants.pipeSegmentCount - 1) {
        // Angle around cross section.
        let phi = 2 * Float.pi * Float(j) / Float(Constants.pipeSegmentCount)
        // Radius for cylindrical coordinates.
        let r = Constants.radius + Constants.pipeRadius * cosf(phi)
        vertices.append(
          simd_make_float3(r * cosf(theta), Constants.pipeRadius * sinf(phi), r * sinf(theta)))
      }
    }
    descriptor.positions = MeshBuffers.Positions(vertices)

    var indices: [UInt32] = []
    for i in 0...(Constants.ringSegmentCount - 1) {
      for j in 0...(Constants.pipeSegmentCount - 1) {
        let iNext = i + 1
        let jNext = (j + 1) % Constants.pipeSegmentCount
        // Two triangles per rectangular region facing out.
        //     *-----* jNext
        //     |    /|
        //     | 2 / |
        //     |  /  |
        //     | / 1 |
        //     |/    |
        //     *-----* j
        //     i+1   i

        // Triangle #1.
        indices.append(UInt32(i * Constants.pipeSegmentCount + j))
        indices.append(UInt32(i * Constants.pipeSegmentCount + jNext))
        indices.append(UInt32(iNext * Constants.pipeSegmentCount + j))

        // Triangle #2.
        indices.append(UInt32(i * Constants.pipeSegmentCount + jNext))
        indices.append(UInt32(iNext * Constants.pipeSegmentCount + jNext))
        indices.append(UInt32(iNext * Constants.pipeSegmentCount + j))
      }
    }
    descriptor.primitives = .triangles(indices)

    return try? MeshResource.generate(from: [descriptor])
  }
}
