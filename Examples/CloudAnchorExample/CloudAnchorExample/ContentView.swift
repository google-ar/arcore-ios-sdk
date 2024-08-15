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

/// View for hosting and resolving Cloud Anchors.
struct ContentView: View {
  @StateObject private var manager = CloudAnchorManager()

  var body: some View {
    ZStack {
      ARViewContainer(manager: manager)
        .ignoresSafeArea()
        .onTapGesture { manager.tapPoint(point: $0) }
      VStack {
        HStack {
          Button {
            manager.hostButtonPressed()
          } label: {
            Text(manager.hosting && !manager.roomCode.isEmpty ? "CANCEL" : "HOST")
              .padding(.vertical)
              .padding(.horizontal)
              .contentShape(Rectangle())
          }
          .disabled(manager.resolving || (manager.hosting && manager.roomCode.isEmpty))
          Button {
            manager.resolveButtonPressed()
          } label: {
            Text(manager.resolving ? "CANCEL" : "RESOLVE")
              .padding(.vertical)
              .padding(.horizontal)
              .contentShape(Rectangle())
          }
          .disabled(manager.hosting)
          Spacer()
          ZStack {
            Rectangle()
              .frame(width: 120, height: 40)
              .background(.ultraThinMaterial)
            Text("  Room: \(manager.roomCode)")
              .foregroundStyle(.white)
              .frame(width: 120, height: 40, alignment: .leading)
          }
        }
        Spacer()
        ZStack {
          Rectangle()
            .frame(height: 100, alignment: .bottom)
            .background(.ultraThinMaterial)
          Text(manager.message)
            .foregroundStyle(.white)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
      }
      .ignoresSafeArea(edges: .bottom)
    }
    .disabled(manager.fatalError)
    .alert("Experience it together", isPresented: $manager.showPrivacyNotice) {
      Button(role: .destructive) {
        manager.privacyNoticeAccepted()
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
    .alert("ENTER ROOM CODE", isPresented: $manager.showRoomCodeDialog) {
      TextField("", text: $manager.roomCodeDialogField).keyboardType(.numberPad)
      Button(role: .destructive) {
        manager.roomCodeEntered()
      } label: {
        Text("OK")
      }
      Button(role: .cancel) {
      } label: {
        Text("CANCEL")
      }
    }
    .alert("Camera permission required", isPresented: $manager.showCameraPermissionDeniedAlert) {
    } message: {
      Text(
        "Camera permission has been denied or restricted. Please fix by going to the Settings app.")
    }
    .alert(manager.errorAlertTitle, isPresented: $manager.showErrorAlert) {
    } message: {
      Text(manager.errorAlertMessage)
    }
  }
}

#Preview {
  ContentView()
}
