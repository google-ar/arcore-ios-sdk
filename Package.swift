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
      name: "ARCoreBase", url: "https://dl.google.com/arcore/swiftpm/1.39.0/Base.zip",
      checksum: "a2245887bf36f30da2ea4c53ccbcd5a1a85dec146d26e210e666c6afb2e28865"
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
      url: "https://dl.google.com/arcore/swiftpm/1.39.0/CloudAnchors.zip",
      checksum: "93c58249a9fdb59c50ab5a6c4eb2a4cf1cab42737e7d00674f73e50ecc5f1762"
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
      name: "ARCoreGeospatial", url: "https://dl.google.com/arcore/swiftpm/1.39.0/Geospatial.zip",
      checksum: "3275057560df9bb5db6c4a5acf12d63b49cf1685166e06a0519510e333e07030"
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
      name: "ARCoreGARSession", url: "https://dl.google.com/arcore/swiftpm/1.39.0/GARSession.zip",
      checksum: "a570003edaddb74a4c12de4437a66a4edd5b886f77c662aaf56f528c6389496f"
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
      url: "https://dl.google.com/arcore/swiftpm/1.39.0/AugmentedFaces.zip",
      checksum: "1b7a99e863464a9d627b02c172a83553d24ff21adc197fd7252b8ed09bfecdf4"
    ),
    .target(
      name: "AugmentedFaces",
      dependencies: [
        "ARCoreAugmentedFaces",
        "Base",
        .product(name: "nanopb", package: "nanopb"),
      ],
      path: "AugmentedFaces",
      sources: ["dummy.m"],
      resources: [.copy("Resources/ARCoreFaceResources")],
      publicHeadersPath: "Sources"
    ),
  ]
)
