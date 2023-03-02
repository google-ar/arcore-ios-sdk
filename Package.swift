// swift-tools-version: 5.5
/*
 * Copyright 2022 Google LLC
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

import PackageDescription

let package = Package(
  name: "ARCore", platforms: [.iOS(.v11)],
  products: [
    .library(name: "ARCoreCloudAnchors", targets: ["CloudAnchors"]),
    .library(name: "ARCoreGeospatial", targets: ["Geospatial"]),
    .library(name: "ARCoreGARSession", targets: ["GARSession"]),
    .library(name: "ARCoreAugmentedFaces", targets: ["AugmentedFaces"]),
  ],
  dependencies: [
    .package(url: "https://github.com/firebase/nanopb.git", "2.30909.0"..<"2.30910.0"),
    .package(
      url: "https://github.com/google/GoogleDataTransport.git", .upToNextMajor(from: "9.2.0")),
    .package(url: "https://github.com/google/gtm-session-fetcher.git", "2.1.0"..<"4.0.0"),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..<"11.0.0"),
  ],
  targets: [
    .binaryTarget(
      name: "ARCoreBase", url: "https://dl.google.com/arcore/swiftpm/1.36.0/Base.zip",
      checksum: "ce56efd4a30e0d65d95459fc4cd1ad186b56bb179095423400a4bd5ada807f85"
    ),
    .target(
      name: "Base",
      dependencies: [
        "ARCoreBase",
        .product(name: "nanopb", package: "nanopb"),
        .product(name: "GoogleDataTransport", package: "GoogleDataTransport"),
      ],
      path: "Base",
      sources: ["dummy.m"],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreCloudAnchors",
      url: "https://dl.google.com/arcore/swiftpm/1.36.0/CloudAnchors.zip",
      checksum: "548d25b408f9c21a5b20de64fd570a06e69c16fed10dea326ff045980ffee64d"
    ),
    .target(
      name: "CloudAnchors",
      dependencies: [
        "ARCoreCloudAnchors",
        "GARSession",
        .product(name: "GTMSessionFetcherCore", package: "gtm-session-fetcher"),
        .product(name: "nanopb", package: "nanopb"),
      ],
      path: "CloudAnchors",
      sources: ["dummy.m"],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreGeospatial", url: "https://dl.google.com/arcore/swiftpm/1.36.0/Geospatial.zip",
      checksum: "ee88f56df2c154f32a5bcb5c63208fef0ab021a83de7bb89208cbc5f193e20e7"
    ),
    .target(
      name: "Geospatial",
      dependencies: [
        "ARCoreGeospatial",
        "GARSession",
      ],
      path: "Geospatial",
      sources: ["dummy.m"],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreGARSession", url: "https://dl.google.com/arcore/swiftpm/1.36.0/GARSession.zip",
      checksum: "08b63e5d454a0063fbbe3102d09ec85a0c55426a1045dbf0cf5624aef9274e77"
    ),
    .target(
      name: "GARSession",
      dependencies: [
        "ARCoreGARSession",
        "Base",
        .product(name: "nanopb", package: "nanopb"),
        .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),
        .product(name: "GoogleDataTransport", package: "GoogleDataTransport"),
      ],
      path: "GARSession",
      sources: ["dummy.m"],
      resources: [.copy("Resources/ARCoreResources")],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreAugmentedFaces",
      url: "https://dl.google.com/arcore/swiftpm/1.36.0/AugmentedFaces.zip",
      checksum: "802d2c057b2a02d912db1d2450bdc70856e49b2fbf9eba2c7b8beb51f7cd1196"
    ),
    .target(
      name: "AugmentedFaces",
      dependencies: [
        "ARCoreAugmentedFaces",
        "Base",
        .product(name: "nanopb", package: "nanopb"),
        .product(name: "GoogleDataTransport", package: "GoogleDataTransport"),
      ],
      path: "AugmentedFaces",
      sources: ["dummy.m"],
      resources: [.copy("Resources/ARCoreFaceResources")],
      publicHeadersPath: "Sources"
    ),
  ]
)
