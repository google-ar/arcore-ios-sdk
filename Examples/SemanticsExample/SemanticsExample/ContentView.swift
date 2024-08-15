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
import CoreGraphics
import RealityKit
import SwiftUI
import UIKit

/// View for testing the ARCore Semantics API.
struct ContentView: View {
  @State var fractions: [SemanticFraction] = [
    SemanticFraction(
      id: .unlabeled, name: "Unlabeled", color: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.5)
    ),
    SemanticFraction(
      id: .sky, name: "Sky", color: UIColor(red: 0.27, green: 0.50, blue: 0.70, alpha: 0.5)),
    SemanticFraction(
      id: .building, name: "Building",
      color: UIColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 0.5)),
    SemanticFraction(
      id: .tree, name: "Tree", color: UIColor(red: 0.13, green: 0.54, blue: 0.13, alpha: 0.5)),
    SemanticFraction(
      id: .road, name: "Road", color: UIColor(red: 0.54, green: 0.16, blue: 0.88, alpha: 0.5)),
    SemanticFraction(
      id: .sidewalk, name: "Sidewalk",
      color: UIColor(red: 0.95, green: 0.13, blue: 0.90, alpha: 0.5)),
    SemanticFraction(
      id: .terrain, name: "Terrain", color: UIColor(red: 0.59, green: 0.98, blue: 0.59, alpha: 0.5)),
    SemanticFraction(
      id: .structure, name: "Structure",
      color: UIColor(red: 0.82, green: 0.70, blue: 0.54, alpha: 0.5)),
    SemanticFraction(
      id: .object, name: "Object", color: UIColor(red: 0.86, green: 0.86, blue: 0.0, alpha: 0.5)),
    SemanticFraction(
      id: .vehicle, name: "Vehicle", color: UIColor(red: 0.06, green: 0.06, blue: 0.90, alpha: 0.5)),
    SemanticFraction(
      id: .person, name: "Person", color: UIColor(red: 1.0, green: 0.03, blue: 0.0, alpha: 0.5)),
    SemanticFraction(
      id: .water, name: "Water", color: UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.5)),
  ]
  @State var semanticImage: CGImage?
  @State var showLegend = false
  @State var semanticsEnabled = true

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      ARViewContainer(
        semanticsEnabled: semanticsEnabled, fractions: fractions, semanticImage: $semanticImage
      )
      .ignoresSafeArea()
      .onTapGesture {
        semanticsEnabled.toggle()
      }
      if let semanticImage {
        GeometryReader { proxy in
          Image(semanticImage, scale: 1, orientation: .right, label: Text("Semantic Image"))
            .resizable()
            .scaledToFill()
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
      }
      VStack(alignment: .leading, spacing: 5) {
        if showLegend {
          ForEach(fractions) { fraction in
            SemanticLabel(fraction: fraction)
          }
        }
        Button {
          showLegend.toggle()
        } label: {
          Text(showLegend ? "Hide Legend" : "Show Legend")
        }
        .padding(5)
        .frame(maxWidth: .infinity)
      }
      .background(Color(white: 0, opacity: 0.8).ignoresSafeArea(edges: []))
      .frame(width: 150)
    }
  }
}

#Preview {
  ContentView()
}
