// swift-tools-version: 5.5
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
  name: "ARCore", platforms: [.iOS(.v12)],
  products: [
    .library(name: "ARCoreCloudAnchors", targets: ["CloudAnchors"]),
    .library(name: "ARCoreGeospatial", targets: ["Geospatial"]),
    .library(name: "ARCoreGARSession", targets: ["GARSession"]),
    .library(name: "ARCoreAugmentedFaces", targets: ["AugmentedFaces"]),
    .library(name: "ARCoreSemantics", targets: ["Semantics"]),
  ],
  dependencies: [
    .package(url: "https://github.com/firebase/nanopb.git", "2.30909.0"..<"2.30911.0"),
    .package(
      url: "https://github.com/google/GoogleDataTransport.git", .upToNextMajor(from: "9.2.0")),
    .package(url: "https://github.com/google/gtm-session-fetcher.git", "2.1.0"..<"4.0.0"),
    .package(url: "https://github.com/firebase/firebase-ios-sdk.git", "8.0.0"..<"11.0.0"),
  ],
  targets: [
    .binaryTarget(
      name: "ARCoreBase", url: "https://dl.google.com/arcore/swiftpm/1.46.0/Base.zip",
      checksum: "71087330b6935f5496ae64eb2404afb7fecdb823c55f5ce8736d8ec521a0bf1d"
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
      url: "https://dl.google.com/arcore/swiftpm/1.46.0/CloudAnchors.zip",
      checksum: "dc383fc4148aaa3cb94ce86be52f0b465967367423b2430739face905bc548be"
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
      name: "ARCoreGeospatial", url: "https://dl.google.com/arcore/swiftpm/1.46.0/Geospatial.zip",
      checksum: "b9f0bc8a454a28149d2fffc55f88ec773181dc646682f303c520178df21f0365"
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
      name: "ARCoreGARSession", url: "https://dl.google.com/arcore/swiftpm/1.46.0/GARSession.zip",
      checksum: "13c0c0bd2b738917a4a4fb4ae11b78bbe939737c7dccb626318921e537bc9570"
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
      url: "https://dl.google.com/arcore/swiftpm/1.46.0/AugmentedFaces.zip",
      checksum: "994a30c2c726e1048b17c82edcea97771e4487253cda605b96600ca9dddd6918"
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
      name: "ARCoreSemantics", url: "https://dl.google.com/arcore/swiftpm/1.46.0/Semantics.zip",
      checksum: "af39c088348d83b87e3e4619eb613cdebd4cc22c3264952ca3cfb114f4831c4b"
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
      name: "ARCoreTFShared", url: "https://dl.google.com/arcore/swiftpm/1.46.0/TFShared.zip",
      checksum: "21d448280900ee03e74298043bbd44344c570d7144a25af2e48bdf4baa7515b7"
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
