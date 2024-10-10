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
import Foundation
import Metal
import SceneKit

/// Contains all objects needed to hold a face mesh. Used for multi-buffering.
private class FaceMesh {
  /// Metal buffer containing vertex positions.
  var mtlVertexBuffer: MTLBuffer?

  /// Metal buffer containing texture coordinates.
  var mtlTexBuffer: MTLBuffer?

  /// Metal buffer containing normal vectors.
  var mtlNormalBuffer: MTLBuffer?

  /// Buffer containing triangle indices.
  var indexBuffer: Data?

  /// SceneKit geometry source for vertex positions.
  var vertSource = SCNGeometrySource()

  /// SceneKit geometry source for texture coordinates.
  var texSource = SCNGeometrySource()

  /// SceneKit geometry source for normal vectors.
  var normSource = SCNGeometrySource()

  /// SceneKit element for triangle indices.
  var element = SCNGeometryElement()

  /// SceneKit geometry for the face mesh.
  var geometry = SCNGeometry()
}

/// Converts `GARAugmentedFace` meshes into `SCNGeometry`.
final public class FaceMeshGeometryConverter {

  /// Metal device used for allocating Metal buffers.
  private lazy var metalDevice = MTLCreateSystemDefaultDevice()

  /// Array of face meshes used for multiple-buffering.
  private let faceMeshes = [FaceMesh(), FaceMesh()]

  /// Index of which face mesh to use. Alternates every frame.
  private var frameCount: Int = 0

  /// Generates a `SCNGeometry` from a face mesh.
  ///
  /// - Parameters:
  ///   - face: The face mesh geometry.
  /// - Returns: The constructed geometry from a face mesh.
  public func geometryFromFace(_ face: GARAugmentedFace?) -> SCNGeometry? {
    guard let face = face else { return nil }

    frameCount += 1
    let faceMesh = faceMeshes[self.frameCount % self.faceMeshes.count]

    #if !targetEnvironment(simulator)

      let vertexSize = MemoryLayout.size(ofValue: face.mesh.vertices[0])
      let texSize = MemoryLayout.size(ofValue: face.mesh.textureCoordinates[0])
      let normSize = MemoryLayout.size(ofValue: face.mesh.normals[0])
      let idxSize = MemoryLayout.size(ofValue: face.mesh.triangleIndices[0])

      let vertexCount = Int(face.mesh.vertexCount)
      let triangleCount = Int(face.mesh.triangleCount)
      let indexCount = triangleCount * 3

      let vertBufSize: size_t = vertexSize * vertexCount
      let texBufSize: size_t = texSize * vertexCount
      let normalBufSize: size_t = normSize * vertexCount
      let idxBufSize: size_t = idxSize * indexCount

      var reallocateGeometry = false

      // Creates a vertex buffer and sets up a vertex source when the vertex buffer size changes.
      if faceMesh.mtlVertexBuffer?.length != vertBufSize {
        guard
          let vertexBuffer = metalDevice?.makeBuffer(
            length: vertBufSize,
            options: .storageModeShared)
        else { return nil }
        faceMesh.mtlVertexBuffer = vertexBuffer
        faceMesh.vertSource = SCNGeometrySource(
          buffer: vertexBuffer,
          vertexFormat: .float3,
          semantic: .vertex,
          vertexCount: vertexCount,
          dataOffset: 0,
          dataStride: vertexSize)
        reallocateGeometry = true
      }

      // Creates a texture buffer and sets up a texture source when the texture buffer size changes.
      if faceMesh.mtlTexBuffer?.length != texBufSize {
        guard
          let textureBuffer = metalDevice?.makeBuffer(
            length: texBufSize,
            options: .storageModeShared)
        else { return nil }
        faceMesh.mtlTexBuffer = textureBuffer
        faceMesh.texSource = SCNGeometrySource(
          buffer: textureBuffer,
          vertexFormat: .float2,
          semantic: .texcoord,
          vertexCount: vertexCount,
          dataOffset: 0,
          dataStride: texSize)
        reallocateGeometry = true
      }

      // Creates a normal buffer and sets up a normal source when the normal buffer size changes.
      if faceMesh.mtlNormalBuffer?.length != normalBufSize {
        guard
          let normalBuffer = metalDevice?.makeBuffer(
            length: normalBufSize,
            options: .storageModeShared)
        else { return nil }
        faceMesh.mtlNormalBuffer = normalBuffer
        faceMesh.normSource = SCNGeometrySource(
          buffer: normalBuffer,
          vertexFormat: .float3,
          semantic: .normal,
          vertexCount: vertexCount,
          dataOffset: 0,
          dataStride: normSize)
        reallocateGeometry = true
      }

      // Creates an index buffer and sets up an element when the index buffer size changes.
      if faceMesh.indexBuffer?.count != idxBufSize {
        let indexBuffer = Data(
          bytes: face.mesh.triangleIndices,
          count: idxBufSize)
        faceMesh.indexBuffer = indexBuffer
        faceMesh.element = SCNGeometryElement(
          data: indexBuffer as Data?,
          primitiveType: .triangles,
          primitiveCount: triangleCount,
          bytesPerIndex: idxSize)
        reallocateGeometry = true
      }

      // Copy the face mesh data into the appropriate buffers.
      if let vertexBuffer = faceMesh.mtlVertexBuffer,
        let textureBuffer = faceMesh.mtlTexBuffer,
        let normalBuffer = faceMesh.mtlNormalBuffer,
        var indexBuffer = faceMesh.indexBuffer
      {
        memcpy(vertexBuffer.contents(), face.mesh.vertices, vertBufSize)
        memcpy(textureBuffer.contents(), face.mesh.textureCoordinates, texBufSize)
        memcpy(normalBuffer.contents(), face.mesh.normals, normalBufSize)
        _ = indexBuffer.withUnsafeMutableBytes { pointer in
          memcpy(pointer.baseAddress, face.mesh.triangleIndices, idxBufSize)
        }
      }

      // If any of the sources or element changed, reallocate the geometry.
      if reallocateGeometry {
        let sources = [faceMesh.vertSource, faceMesh.texSource, faceMesh.normSource]
        faceMesh.geometry = SCNGeometry(sources: sources, elements: [faceMesh.element])
      }

    #endif

    return faceMesh.geometry
  }
}
