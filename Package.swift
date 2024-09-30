// swift-tools-version: 5.5
/*
 * Copyright 2024 Google LLC
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
  name: "ARCore", platforms: [.iOS(.v12)],
  products: [
    .library(name: "ARCoreCloudAnchors", targets: ["CloudAnchors"]),
    .library(name: "ARCoreGeospatial", targets: ["Geospatial"]),
    .library(name: "ARCoreGARSession", targets: ["GARSession"]),
    .library(name: "ARCoreAugmentedFaces", targets: ["AugmentedFaces"]),
    .library(name: "ARCoreSemantics", targets: ["Semantics"]),
  ],
  dependencies: [
    .package(url: "https://github.com/firebase/nanopb.git", "2.30910.0" ..< "2.30911.0"),
    .package(
      url: "https://github.com/google/GoogleDataTransport.git", .upToNextMajor(from: "9.2.0")),
    .package(url: "https://github.com/google/gtm-session-fetcher.git", "2.1.0"..<"4.0.0"),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..<"11.0.0"),
  ],
  targets: [
    .binaryTarget(
      name: "ARCoreBase", url: "https://dl.google.com/arcore/swiftpm/1.45.0/Base.zip",
      checksum: "a1c17b5fab235b97a3e96d7b249ca78ecde0cbe9c868b24b65a00af94f2dfb4b"
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
      url: "https://dl.google.com/arcore/swiftpm/1.45.0/CloudAnchors.zip",
      checksum: "a5232b391f5f84ebbc2321f3c49156220a4dee2edc2cfe5db6a745e1f0f8f6bd"
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
      name: "ARCoreGeospatial", url: "https://dl.google.com/arcore/swiftpm/1.45.0/Geospatial.zip",
      checksum: "ed6bb8155bdae259661d41b21c2c06a479b8d2d05796cad89eed32d40f478564"
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
      name: "ARCoreGARSession", url: "https://dl.google.com/arcore/swiftpm/1.45.0/GARSession.zip",
      checksum: "46ae76553c65018c549ee616be0bdef7492035137f797159d9b272495be3633f"
    ),
    .target(
      name: "GARSession",
      dependencies: [
        "ARCoreGARSession",
        "Base",
        .product(name: "nanopb", package: "nanopb"),
        .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),
      ],
      path: "GARSession",
      sources: ["dummy.m"],
      resources: [.copy("Resources/ARCoreResources")],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreAugmentedFaces",
      url: "https://dl.google.com/arcore/swiftpm/1.45.0/AugmentedFaces.zip",
      checksum: "3e81d128d4aa767254cf9ad87266a5e269f0d3cf6b85e44ce094c5f50d5c5f55"
    ),
    .target(
      name: "AugmentedFaces",
      dependencies: [
        "ARCoreAugmentedFaces",
        "Base",
        "TFShared",
        .product(name: "nanopb", package: "nanopb"),
      ],
      path: "AugmentedFaces",
      sources: ["dummy.m"],
      resources: [.copy("Resources/ARCoreFaceResources")],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreSemantics", url: "https://dl.google.com/arcore/swiftpm/1.45.0/Semantics.zip",
      checksum: "5e17cc0accfdb432aceb47f0f837343710795e9f9fe364e962ab5a28cbb17580"
    ),
    .target(
      name: "Semantics",
      dependencies: [
        "ARCoreSemantics",
        "GARSession",
        "TFShared",
      ],
      path: "Semantics",
      sources: ["dummy.m"],
      resources: [.copy("Resources/ARCoreCoreMLSemanticsResources")],
      publicHeadersPath: "Sources"
    ),
    .binaryTarget(
      name: "ARCoreTFShared", url: "https://dl.google.com/arcore/swiftpm/1.45.0/TFShared.zip",
      checksum: "31c480256501d66dedb290a33ef101f2c9abdb295a03db78736619ddd640a534"
    ),
    .target(
      name: "TFShared",
      dependencies: [
        "ARCoreTFShared",
        "Base",
      ],
      path: "TFShared",
      sources: ["dummy.m"],
      publicHeadersPath: "Sources"
    ),
  ]
)
