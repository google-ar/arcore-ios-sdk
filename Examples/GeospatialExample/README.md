# Geospatial API sample app for iOS

This sample app shows how to use the ARCore Geospatial API for iOS.

# Setup

## Install the SDK

You can install the SDK using either CocoaPods or Swift Package Manager.

### Installing the SDK using CocoaPods.

Run the following command from the directory with Podfile:

```
$ pod install
```

Open the resulting `.xcworkspace` file (not the project file).

### Installing the SDK using Swift Package Manager.

Open the Xcode project file and add a dependency on the 'ARCoreGeospatial'
product of the ARCore package.

## Change the bundle ID

Change the app's bundle ID so you can sign the app with your development team.

## Obtain an API key

Before you can start using the Geospatial API, you will need to register an
API key in the
[Google Developer Console](https://console.developers.google.com/) for your
cloud project and enable the [ARCore API](https://console.cloud.google.com/apis/library/arcore).
Make sure your API key is either unrestricted by app, or allows your specific
bundle ID.

You will need to paste your API key into `ViewController.m` (search for
`sessionWithAPIKey:`).
