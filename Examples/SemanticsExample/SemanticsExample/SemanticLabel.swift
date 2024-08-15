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

import SwiftUI

/// View for displaying a semantic label fraction and color box.
struct SemanticLabel: View {
  @ObservedObject var fraction: SemanticFraction
  @State var textHeight: CGFloat = 0

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      Rectangle()
        .foregroundStyle(Color(uiColor: fraction.color))
        .frame(width: textHeight * 0.7, height: textHeight * 0.7)
        .padding(.leading, 5)
      Text(fraction.name)
        .foregroundStyle(.white)
        .fixedSize()
        .padding(.leading, 5)
        .lineLimit(1)
        .overlay(
          GeometryReader { proxy in
            Color.clear.onAppear {
              textHeight = proxy.size.height
            }
          }
        )
      Spacer()
      Text(String(format: "%.2f", arguments: [fraction.fraction]))
        .foregroundStyle(.white)
        .padding(.trailing, 5)
    }
    .padding([.top, .bottom], 2.5)
  }
}
