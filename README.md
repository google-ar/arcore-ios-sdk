# Google ARCore SDK For iOS

Copyright (c) 2018 Google LLC. All rights reserved.

This SDK provides access to all ARCore cross-platform features like cloud
anchors.

Please note we do not accept pull requests.

## Quickstart

For Cloud Anchors see the
[Quickstart for Cloud Anchors with iOS](https://developers.google.com/ar/develop/ios/cloud-anchors-quickstart-ios).
For Augmented faces see the
[Quickstart for Augmented Faces with iOS](https://developers.google.com/ar/develop/ios/augmented-faces/quickstart).
For Geospatial see the
[Quickstart for Geospatial with iOS](https://developers.google.com/ar/develop/ios/geospatial/quickstart)

## API Reference

See the
[ARCore iOS API Reference](https://developers.google.com/ar/reference/ios).

## Examples

Sample apps are available for download at
https://github.com/google-ar/arcore-ios-sdk/tree/master/Examples. Be sure to
follow any instructions in README files.

## Release Notes

The SDK release notes are available on the
[releases](https://github.com/google-ar/arcore-ios-sdk/releases) page.

## Installation

ARCore requires a deployment target that is >= 11.0. Also, you must be building
with at least version 15.0 of the iOS SDK. ARCore binaries no longer contain
bitcode, which is deprecated with Xcode 14, so if you are building with Xcode 13
then you must disable bitcode for your project. The SDK can be installed using
either CocoaPods or Swift Package Manager; see below for details.

### Using Swift Package Manager

Starting with the 1.36.0 release, ARCore officially supports installation via
[Swift Package Manager](https://swift.org/package-manager/):

1.  Go to **File** > **Add Packages** and enter the package URL:
    `https://github.com/google-ar/arcore-ios-sdk`
1.  Set the **Dependency Rule** to be **Up to Next Minor Version** and select
    the latest release of ARCore.
1.  Select the desired ARCore libraries to include. Libraries can also be added
    later via **Build Phases** > **Link Binary With Libraries**.
1.  Add the flag `-ObjC` to **Other Linker Flags**. It is recommended to set
    **Other Linker Flags** to `$(inherited) -ObjC`.
1.  Make sure that the **Enable Modules** and **Link Frameworks Automatically**
    build settings are set to **Yes**, because ARCore relies on auto-linking.
1.  Make sure that **Enable Bitcode** is set to **No**, because ARCore binaries
    do not contain bitcode.

### Additional Steps

Before you can start using the ARCore Cloud Anchors API or the ARCore Geospatial
API, you will need to create a project in the
[Google Developer Console](https://console.developers.google.com/) and enable
the [ARCore API](https://console.cloud.google.com/apis/library/arcore).

## User privacy requirements

See the
[User privacy requirements](https://developers.google.com/ar/develop/privacy-requirements).

## Additional Terms

You must disclose the use of ARCore, and how it collects and processes data.
This can be done by displaying a prominent link to the site "How Google uses
data when you use our partners' sites or apps", (located at
www.google.com/policies/privacy/partners/, or any other URL Google may provide
from time to time).

## License and Terms of Service

By using the ARCore SDK for iOS, you accept Google's ARCore Additional Terms of
Service at
[https://developers.google.com/ar/develop/terms](https://developers.google.com/ar/develop/terms)

## Deprecation policy

Apps built with **ARCore SDK 1.12.0 or higher** are covered by the
[Cloud Anchor API deprecation policy](//developers.google.com/ar/distribute/deprecation-policy).

Apps built with **ARCore SDK 1.11.0 or lower** will be unable to host or resolve
Cloud Anchors beginning December 2020 due to the SDK's use of an older,
deprecated ARCore Cloud Anchor service.
