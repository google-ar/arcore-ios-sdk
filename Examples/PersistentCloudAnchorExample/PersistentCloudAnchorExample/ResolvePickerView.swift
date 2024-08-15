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

/// View for choosing which anchors to resolve.
struct ResolvePickerView: View {
  @EnvironmentObject var manager: CloudAnchorManager

  @State private var expanded = false
  @State private var anchorIdSelection = Set<String>()
  @State private var anchorIdsField = ""
  @State private var anchorInfos = [AnchorInfo]()

  private var anchorIds: [String] {
    if !anchorIdsField.isEmpty {
      return anchorIdsField.components(separatedBy: ",")
    }
    return Array(anchorIdSelection)
  }

  private func dropDownLabel() -> String {
    if anchorIdSelection.isEmpty {
      return "Select"
    }
    return
      anchorInfos
      .filter({ anchorIdSelection.contains($0.id) })
      .map({ $0.name })
      .joined(separator: ",")
  }

  private func updateAnchorInfos() {
    anchorInfos = manager.fetchAndPruneAnchors()
    // Remove any anchor IDs from selection that are no longer in the list.
    anchorIdSelection = Set<String>(
      anchorInfos.map({ $0.id }).filter({ anchorIdSelection.contains($0) }))
  }

  var body: some View {
    VStack {
      Text("Resolve anchor(s)")
        .frame(height: 35)
        .font(.system(size: 27, weight: .bold))
      Text("Choose up to 40 anchors to resolve at once")
        .frame(width: 195, height: 41)
        .font(.system(size: 17))
        .multilineTextAlignment(.center)
      Text("Select from anchors previously hosted from this device")
        .frame(width: 295, height: 42)
        .font(.system(size: 14))
      DisclosureGroup(
        isExpanded: $expanded,
        content: {},
        label: {
          Text(dropDownLabel())
            .lineLimit(1)
            .padding(.leading)
        }
      )
      .frame(width: 295, height: 30)
      if expanded {
        List(anchorInfos, selection: $anchorIdSelection) { anchorInfo in
          HStack {
            Text(anchorInfo.name)
            Spacer()
            Text("\(anchorInfo.age) ago")
              .foregroundStyle(.secondary)
          }
        }
        .frame(width: 295, height: 150)
        .environment(\.editMode, .constant(.active))
        .listStyle(.plain)
      } else {
        VStack {
          Text("---------Or---------")
            .font(.system(size: 19))
            .frame(height: 23)
          Text("Enter anchor ID(s), separated by commas")
            .font(.system(size: 14))
            .frame(width: 295, height: 30)
          TextField("", text: $anchorIdsField)
            .textFieldStyle(.roundedBorder)
            .frame(width: 295, height: 30)
        }
        .frame(width: 295, height: 150)
      }
      Button {
        manager.resolveButtonPressed(anchorIds: anchorIds)
      } label: {
        Text("Resolve")
          .font(.system(size: 20))
          .frame(width: 175)
          .foregroundStyle(.white)
      }
      .disabled(anchorIdsField.isEmpty && anchorIdSelection.isEmpty)
      .buttonStyle(.borderedProminent)
    }
    .onAppear {
      // Refresh anchor info every time the view appears on screen.
      updateAnchorInfos()
    }
  }
}
