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

import RealityKit
import SwiftUI

/// View for choosing hosting or resolving; root of navigation stack.
struct ContentView: View {
  @StateObject var manager = CloudAnchorManager()

  var body: some View {
    NavigationStack(path: $manager.navigationPath) {
      VStack {
        Text("Host a Cloud Anchor")
          .frame(height: 33)
          .font(.system(size: 27, weight: .bold))
        Text("Scan your space and create a new Cloud Anchor accessible by others")
          .frame(width: 315, height: 45.5)
          .font(.system(size: 19))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button {
          manager.beginHostingButtonPressed()
        } label: {
          Text("Begin hosting")
            .font(.system(size: 20))
            .padding(.horizontal)
            .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .padding(.vertical)
        Text("------------Or------------")
          .font(.system(size: 19))
        Text("Resolve Cloud Anchor(s)")
          .frame(height: 33)
          .font(.system(size: 27, weight: .bold))
          .padding(.top)
        Text("Localize this device against previously created Cloud Anchor(s)")
          .frame(width: 315, height: 45.5)
          .font(.system(size: 19))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button {
          manager.beginResolvingButtonPressed()
        } label: {
          Text("Begin resolving")
            .font(.system(size: 20))
            .padding(.horizontal)
            .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .padding(.vertical)
      }
      .navigationDestination(for: CloudAnchorManager.Page.self) { page in
        switch page {
        case .host:
          CloudAnchorView()
        case .resolve:
          CloudAnchorView()
        case .resolvePicker:
          ResolvePickerView()
        }
      }
    }
    .environmentObject(manager)
    .alert("Experience it together", isPresented: $manager.showPrivacyNotice) {
      Button(role: .destructive) {
        manager.acceptPrivacyNotice()
      } label: {
        Text("Start now")
      }
      Link("Learn more", destination: URL(string: "https://developers.google.com/ar/data-privacy")!)
      Button(role: .cancel) {
      } label: {
        Text("Not now")
      }
    } message: {
      Text("To power this session, Google will process visual data from your camera.")
    }
  }
}

#Preview {
  ContentView()
}
