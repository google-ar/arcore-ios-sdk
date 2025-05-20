// swift-tools-version: 5.7
//
// Copyright 2024 Google LLC
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

import PackageDescription

let package = Package(
  name: "ARCore", platforms: [.iOS(.v13)],
  products: [
    .library(name: "ARCoreCloudAnchors", targets: ["CloudAnchors"]),
    .library(name: "ARCoreGeospatial", targets: ["Geospatial"]),
    .library(name: "ARCoreGARSession", targets: ["GARSession"]),
    .library(name: "ARCoreAugmentedFaces", targets: ["AugmentedFaces"]),
    .library(name: "ARCoreSemantics", targets: ["Semantics"]),
  ],
  dependencies: [
    .package(url: "https://github.com/firebase/nanopb.git", "2.30909.0"..<"2.30911.0"),
    .package(url: "https://github.com/google/GoogleDataTransport.git", "10.0.0"..<"11.0.0"),
    .package(url: "https://github.com/google/gtm-session-fetcher.git", "2.1.0"..<"4.0.0"),
    .package(
      url: "https://github.com/firebase/firebase-ios-sdk.git", .upToNextMajor(from: "11.0.0")),
  ],
  targets: [
    .binaryTarget(
      name: "ARCoreBase", url: "https://dl.google.com/arcore/swiftpm/1.49.0/Base.zip",
      checksum: "908d2bc6af00ef035ff1f6290e9ca259d3873fafc02c4898b405ce07dbca4b13"
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
      url: "https://dl.google.com/arcore/swiftpm/1.49.0/CloudAnchors.zip",
      checksum: "f4356c5f0067cbf33de1bb878cd3b3df0939184bbade315024b840f9a91f2b49"
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
      name: "ARCoreGeospatial", url: "https://dl.google.com/arcore/swiftpm/1.49.0/Geospatial.zip",
      checksum: "64730991f34453633cecd96f9b9c2df14b5a8835b85aad0beb1891cf113ceea7"
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
      name: "ARCoreGARSession", url: "https://dl.google.com/arcore/swiftpm/1.49.0/GARSession.zip",
      checksum: "7dfb3ac045ed9f394a43886004136b39ffe28f9bb9788bffa0d214351d527ffc"
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
      url: "https://dl.google.com/arcore/swiftpm/1.49.0/AugmentedFaces.zip",
      checksum: "1bcc88d496886080c5d7b1cc2129b33207af9ab7c30fe167f415678c321e8c25"
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
      name: "ARCoreSemantics", url: "https://dl.google.com/arcore/swiftpm/1.49.0/Semantics.zip",
      checksum: "02e2d50af296f7d6f8c185021f039542f71fb0c95f215497ea0be6e70455f277"
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
      name: "ARCoreTFShared", url: "https://dl.google.com/arcore/swiftpm/1.49.0/TFShared.zip",
      checksum: "e6aae292251b0b550a54785cbd91ca6c5f2d7908d1384fa311b4931ab0ba7e1d"
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
