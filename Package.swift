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
      name: "ARCoreBase", url: "https://dl.google.com/arcore/swiftpm/1.50.0/Base.zip",
      checksum: "4d1dd1831aeef4af03b37acd8ee2f77385b1286defc199a287165ee9dbffe1bf"
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
      url: "https://dl.google.com/arcore/swiftpm/1.50.0/CloudAnchors.zip",
      checksum: "bc987efd933d23031f20f45c8865e547fbbe97be94808b9b108902b87e0192ac"
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
      name: "ARCoreGeospatial", url: "https://dl.google.com/arcore/swiftpm/1.50.0/Geospatial.zip",
      checksum: "4ed16f5809ff3a0a458f798f50b0f3f399943bc482b1f3b0138bd870e10cc742"
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
      name: "ARCoreGARSession", url: "https://dl.google.com/arcore/swiftpm/1.50.0/GARSession.zip",
      checksum: "7c5b963af65b706e12071aba330b8800bb3c92c2b20000e53726f1f64b650a5b"
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
      url: "https://dl.google.com/arcore/swiftpm/1.50.0/AugmentedFaces.zip",
      checksum: "356a5cd619fcb889ebc628c45fe2d97404b06b0a9d82aea1f19b329cbdc71228"
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
      name: "ARCoreSemantics", url: "https://dl.google.com/arcore/swiftpm/1.50.0/Semantics.zip",
      checksum: "223ceda0c349e1c13dc497ac28a9ef115c79a1e2ffb9c24b01dd2d6f27f2dc09"
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
      name: "ARCoreTFShared", url: "https://dl.google.com/arcore/swiftpm/1.50.0/TFShared.zip",
      checksum: "a6dd9cf450ffda64ad87c15942c3ccb2a9f9ed2dfead5be40a84cea3c89fc926"
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
