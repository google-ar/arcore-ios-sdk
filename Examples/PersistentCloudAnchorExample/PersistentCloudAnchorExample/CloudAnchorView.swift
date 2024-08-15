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

/// View for hosting or resolving anchors.
struct CloudAnchorView: View {
  @EnvironmentObject var manager: CloudAnchorManager

  var body: some View {
    ZStack {
      ARViewContainer()
        .ignoresSafeArea()
        .onTapGesture { manager.tapPoint($0) }
      VStack {
        Spacer()
          .frame(height: 50)
        ZStack {
          Rectangle()
          Text(manager.messageLabel)
            .frame(width: 233, height: 50)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .lineLimit(3)
            .multilineTextAlignment(.center)
        }
        .frame(width: 243, height: 60)
        .opacity(0.5)
        Spacer()
        ZStack {
          Rectangle()
          Text(manager.debugLabel)
            .padding(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .lineLimit(5)
            .multilineTextAlignment(.leading)
        }
        .frame(height: 100)
        .opacity(0.5)
      }
      .ignoresSafeArea(edges: .bottom)
    }
    .alert("Enter name", isPresented: $manager.showAnchorNameDialog) {
      TextField("", text: $manager.anchorNameDialogField)
      Button(role: .destructive) {
        manager.saveAnchor()
      } label: {
        Text("OK")
      }
    } message: {
      Text("Enter a name for your anchor ID (to be stored in local app storage)")
    }
  }
}
