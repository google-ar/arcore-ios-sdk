/*
 * Copyright 2021 Google LLC. All Rights Reserved.
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

#import "ViewController.h"

#import <ARKit/ARKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <ModelIO/ModelIO.h>
#import <SceneKit/ModelIO.h>
#import <SceneKit/SceneKit.h>
#import <UIKit/UIKit.h>

#include <simd/simd.h>

#import <ARCore/ARCore.h>

// Thresholds for 'good enough' accuracy. These can be tuned for the application. We use both 'low'
// and 'high' values here to avoid flickering state changes.
static const CLLocationAccuracy kHorizontalAccuracyLowThreshold = 10;
static const CLLocationAccuracy kHorizontalAccuracyHighThreshold = 20;
static const CLLocationDirectionAccuracy kHeadingAccuracyLowThreshold = 15;
static const CLLocationDirectionAccuracy kHeadingAccuracyHighThreshold = 25;

// Time after which the app gives up if good enough accuracy is not achieved.
static const NSTimeInterval kLocalizationFailureTime = 3 * 60.0;
// Time after showing resolving terrain anchors no result yet message.
static const NSTimeInterval kDurationNoTerrainAnchorResult = 10;

// This sample allows up to 5 simultaneous anchors, although in principal ARCore supports an
// unlimited number.
static const NSUInteger kMaxAnchors = 5;

static NSString *const kPretrackingMessage = @"Localizing your device to set anchor.";
static NSString *const kLocalizationTip =
    @"Point your camera at buildings, stores, and signs near you.";
static NSString *const kLocalizationComplete = @"Localization complete.";
static NSString *const kLocalizationFailureMessage =
    @"Localization not possible.\nClose and open the app to restart.";
static NSString *const kGeospatialTransformFormat =
    @"LAT/LONG: %.6f°, %.6f°\n    ACCURACY: %.2fm\nALTITUDE: %.2fm\n    ACCURACY: %.2fm\n"
     "HEADING: %.1f°\n    ACCURACY: %.1f°";

static const CGFloat kFontSize = 14.0;

// Anchor coordinates are persisted between sessions.
static NSString *const kSavedAnchorsUserDefaultsKey = @"anchors";

// Show privacy notice before using features.
static NSString *const kPrivacyNoticeUserDefaultsKey = @"privacy_notice_acknowledged";

// Title of the privacy notice prompt.
static NSString *const kPrivacyNoticeTitle = @"AR in the real world";

// Content of the privacy notice prompt.
static NSString *const kPrivacyNoticeText =
    @"To power this session, Google will process visual data from your camera.";

// Link to learn more about the privacy content.
static NSString *const kPrivacyNoticeLearnMoreURL =
    @"https://developers.google.com/ar/data-privacy";

// Show VPS availability notice before using features.
static NSString *const kVPSAvailabilityNoticeUserDefaultsKey = @"VPS_availability_notice_acknowledged";

// Title of the VPS availability notice prompt.
static NSString *const kVPSAvailabilityTitle = @"VPS not available";

// Content of the VPS availability notice prompt.
static NSString *const kVPSAvailabilityText =
    @"Your current location does not have VPS coverage. Your session will be using your GPS signal only if VPS is not available.";

typedef NS_ENUM(NSInteger, LocalizationState) {
  LocalizationStatePretracking = 0,
  LocalizationStateLocalizing = 1,
  LocalizationStateLocalized = 2,
  LocalizationStateFailed = -1,
};

@interface ViewController () <ARSessionDelegate, ARSCNViewDelegate, CLLocationManagerDelegate>

/** Location manager used to request and check for location permissions. */
@property(nonatomic) CLLocationManager *locationManager;

/** ARKit session. */
@property(nonatomic) ARSession *arSession;

/**
 * ARCore session, used for geospatial localization. Created after obtaining location permission.
 */
@property(nonatomic) GARSession *garSession;

/** A view that shows an AR enabled camera feed and 3D content. */
@property(nonatomic, weak) ARSCNView *scnView;

/** SceneKit scene used for rendering markers. */
@property(nonatomic) SCNScene *scene;

/** Label used to show Earth tracking state at top of screen. */
@property(nonatomic, weak) UILabel *trackingLabel;

/** Label used to show status at bottom of screen. */
@property(nonatomic, weak) UILabel *statusLabel;

/** Label used to show hint that tap screen to create anchors. */
@property(nonatomic, weak) UILabel *tapScreenLabel;

/** Button used to place a new geospatial anchor. */
@property(nonatomic, weak) UIButton *addAnchorButton;

/** UISwitch for creating WGS84 anchor or Terrain anchor. */
@property(nonatomic, weak) UISwitch *terrainAnchorSwitch;

/** Label of terrainAnchorSwitch. */
@property(nonatomic, weak) UILabel *switchLabel;

/** Button used to clear all existing anchors. */
@property(nonatomic, weak) UIButton *clearAllAnchorsButton;

/** The most recent GARFrame. */
@property(nonatomic) GARFrame *garFrame;

/** Dictionary mapping anchor IDs to SceneKit nodes. */
@property(nonatomic) NSMutableDictionary<NSUUID *, SCNNode *> *markerNodes;

/** The last time we started attempting to localize. Used to implement failure timeout. */
@property(nonatomic) NSDate *lastStartLocalizationDate;

/** Dictionary mapping terrain anchor IDs to time we started resolving. */
@property(nonatomic) NSMutableDictionary<NSUUID *, NSDate *> *terrainAnchorIDToStartTime;

/** Set of finished terrain anchor IDs to remove at next frame update. */
@property(nonatomic) NSMutableSet<NSUUID *> *anchorIDsToRemove;

/** The current localization state. */
@property(nonatomic) LocalizationState localizationState;

/** Whether we have restored anchors saved from the previous session. */
@property(nonatomic) BOOL restoredSavedAnchors;

/** Whether the last anchor is terrain anchor. */
@property(nonatomic) BOOL islastClickedTerrainAnchorButton;

/** Whether it is Terrain anchor mode. */
@property(nonatomic) BOOL isTerrainAnchorMode;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.markerNodes = [NSMutableDictionary dictionary];
  self.terrainAnchorIDToStartTime = [NSMutableDictionary dictionary];
  self.anchorIDsToRemove = [NSMutableSet set];

  ARSCNView *scnView = [[ARSCNView alloc] init];
  scnView = [[ARSCNView alloc] init];
  scnView.translatesAutoresizingMaskIntoConstraints = NO;
  scnView.automaticallyUpdatesLighting = YES;
  scnView.autoenablesDefaultLighting = YES;
  self.scnView = scnView;
  self.scene = self.scnView.scene;
  self.arSession = self.scnView.session;
  self.scnView.delegate = self;
  self.scnView.debugOptions = ARSCNDebugOptionShowFeaturePoints;

  [self.view addSubview:self.scnView];

  UIFont *font = [UIFont systemFontOfSize:kFontSize];
  UIFont *boldFont = [UIFont boldSystemFontOfSize:kFontSize];

  UILabel *trackingLabel = [[UILabel alloc] init];
  trackingLabel.translatesAutoresizingMaskIntoConstraints = NO;
  trackingLabel.font = font;
  trackingLabel.textColor = UIColor.whiteColor;
  trackingLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:.5];
  trackingLabel.numberOfLines = 6;
  self.trackingLabel = trackingLabel;
  [self.scnView addSubview:trackingLabel];

  UILabel *tapScreenLabel = [[UILabel alloc] init];
  tapScreenLabel.translatesAutoresizingMaskIntoConstraints = NO;
  tapScreenLabel.font = boldFont;
  tapScreenLabel.textColor = UIColor.whiteColor;
  tapScreenLabel.numberOfLines = 2;
  tapScreenLabel.textAlignment = NSTextAlignmentCenter;
  tapScreenLabel.text = @"TAP ON SCREEN TO CREATE ANCHOR";
  tapScreenLabel.hidden = YES;
  self.tapScreenLabel = tapScreenLabel;
  [self.scnView addSubview:tapScreenLabel];

  UILabel *statusLabel = [[UILabel alloc] init];
  statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  statusLabel.font = font;
  statusLabel.textColor = UIColor.whiteColor;
  statusLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:.5];
  statusLabel.numberOfLines = 2;
  self.statusLabel = statusLabel;
  [self.scnView addSubview:statusLabel];

  UIButton *addAnchorButton = [UIButton buttonWithType:UIButtonTypeSystem];
  addAnchorButton.translatesAutoresizingMaskIntoConstraints = NO;
  [addAnchorButton setTitle:@"ADD CAMERA ANCHOR" forState:UIControlStateNormal];
  addAnchorButton.titleLabel.font = boldFont;
  [addAnchorButton addTarget:self
                      action:@selector(addAnchorButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
  addAnchorButton.hidden = YES;
  self.addAnchorButton = addAnchorButton;
  [self.view addSubview:addAnchorButton];

  UISwitch *terrainAnchorSwitch = [[UISwitch alloc] init];
  terrainAnchorSwitch.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:terrainAnchorSwitch];
  self.terrainAnchorSwitch = terrainAnchorSwitch;

  UILabel *switchLabel = [[UILabel alloc] init];
  switchLabel.translatesAutoresizingMaskIntoConstraints = NO;
  switchLabel.font = boldFont;
  switchLabel.textColor = UIColor.whiteColor;
  switchLabel.numberOfLines = 1;
  self.switchLabel = switchLabel;
  [self.scnView addSubview:switchLabel];
  self.switchLabel.text = @"TERRAIN";

  UIButton *clearAllAnchorsButton = [UIButton buttonWithType:UIButtonTypeSystem];
  clearAllAnchorsButton.translatesAutoresizingMaskIntoConstraints = NO;
  [clearAllAnchorsButton setTitle:@"CLEAR ALL ANCHORS" forState:UIControlStateNormal];
  clearAllAnchorsButton.titleLabel.font = boldFont;
  [clearAllAnchorsButton addTarget:self
                            action:@selector(clearAllAnchorsButtonPressed)
                  forControlEvents:UIControlEventTouchUpInside];
  clearAllAnchorsButton.hidden = YES;
  self.clearAllAnchorsButton = clearAllAnchorsButton;
  [self.view addSubview:clearAllAnchorsButton];

  [self.scnView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
  [self.scnView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
  [self.scnView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [self.scnView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  [trackingLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor].active =
      YES;
  [trackingLabel.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [trackingLabel.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
  [trackingLabel.heightAnchor constraintEqualToConstant:140].active = YES;

  [tapScreenLabel.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor].active = YES;
  [tapScreenLabel.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [tapScreenLabel.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
  [tapScreenLabel.heightAnchor constraintEqualToConstant:20].active = YES;

  [statusLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
      .active = YES;
  [statusLabel.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [statusLabel.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
  [statusLabel.heightAnchor constraintEqualToConstant:160].active = YES;

  [addAnchorButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
      .active = YES;
  [addAnchorButton.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  [terrainAnchorSwitch.topAnchor constraintEqualToAnchor:self.statusLabel.topAnchor].active = YES;
  [terrainAnchorSwitch.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  [switchLabel.topAnchor constraintEqualToAnchor:self.statusLabel.topAnchor].active = YES;
  [switchLabel.rightAnchor constraintEqualToAnchor:self.terrainAnchorSwitch.leftAnchor].active =
      YES;
  [switchLabel.heightAnchor constraintEqualToConstant:40].active = YES;

  [clearAllAnchorsButton.bottomAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
      .active = YES;
  [clearAllAnchorsButton.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  BOOL privacyNoticeAcknowledged =
      [[NSUserDefaults standardUserDefaults] boolForKey:kPrivacyNoticeUserDefaultsKey];
  if (privacyNoticeAcknowledged) {
    [self setUpARSession];
    return;
  }

  UIAlertController *alertController =
      [UIAlertController alertControllerWithTitle:kPrivacyNoticeTitle
                                          message:kPrivacyNoticeText
                                   preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction *getStartedAction = [UIAlertAction
      actionWithTitle:@"Get started"
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kPrivacyNoticeUserDefaultsKey];
                [self setUpARSession];
              }];
  UIAlertAction *learnMoreAction = [UIAlertAction
      actionWithTitle:@"Learn more"
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
                [[UIApplication sharedApplication]
                              openURL:[NSURL URLWithString:kPrivacyNoticeLearnMoreURL]
                              options:@{}
                    completionHandler:nil];
              }];
  [alertController addAction:getStartedAction];
  [alertController addAction:learnMoreAction];
  [self presentViewController:alertController animated:NO completion:nil];
}

- (void)showVPSUnavailableNotice {
  UIAlertController *alertController =
      [UIAlertController alertControllerWithTitle:kVPSAvailabilityTitle
                                          message:kVPSAvailabilityText
                                   preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction *continueAction = [UIAlertAction
      actionWithTitle:@"Continue"
                style:UIAlertActionStyleDefault
              handler:^(UIAlertAction *action) {
              }];
  [alertController addAction:continueAction];
  [self presentViewController:alertController animated:NO completion:nil];
}

- (void)setUpARSession {
  ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc] init];
  configuration.worldAlignment = ARWorldAlignmentGravity;
  // Optional. It will help the dynamic alignment of terrain anchors on ground.
  configuration.planeDetection = ARPlaneDetectionHorizontal;
  self.arSession.delegate = self;
  // Start AR session - this will prompt for camera permissions the first time.
  [self.arSession runWithConfiguration:configuration];

  self.locationManager = [[CLLocationManager alloc] init];
  // This will cause either |locationManager:didChangeAuthorizationStatus:| or
  // |locationManagerDidChangeAuthorization:| (depending on iOS version) to be called asynchronously
  // on the main thread. After obtaining location permission, we will set up the ARCore session.
  self.locationManager.delegate = self;
}

- (void)checkLocationPermission {
  CLAuthorizationStatus authorizationStatus;
  if (@available(iOS 14.0, *)) {
    authorizationStatus = self.locationManager.authorizationStatus;
  } else {
    authorizationStatus = [CLLocationManager authorizationStatus];
  }
  if (authorizationStatus == kCLAuthorizationStatusAuthorizedAlways ||
      authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
    if (@available(iOS 14.0, *)) {
      if (self.locationManager.accuracyAuthorization != CLAccuracyAuthorizationFullAccuracy) {
        [self setErrorStatus:@"Location permission not granted with full accuracy."];
        return;
      }
    }
    // Request device location for check VPS availability.
    [self.locationManager requestLocation];
    [self setUpGARSession];
  } else if (authorizationStatus == kCLAuthorizationStatusNotDetermined) {
    // The app is responsible for obtaining the location permission prior to configuring the ARCore
    // session. ARCore will not cause the location permission system prompt.
    [self.locationManager requestWhenInUseAuthorization];
  } else {
    [self setErrorStatus:@"Location permission denied or restricted."];
  }
}

- (void)setErrorStatus:(NSString *)message {
  self.statusLabel.text = message;
  self.addAnchorButton.hidden = YES;
  self.tapScreenLabel.hidden = YES;
  self.clearAllAnchorsButton.hidden = YES;
}

- (SCNNode *)markerNodeIsTerrainAnchor:(BOOL)isTerrainAnchor {
  NSURL *objURL = [[NSBundle mainBundle] URLForResource:@"geospatial_marker" withExtension:@"obj"];
  MDLAsset *markerAsset = [[MDLAsset alloc] initWithURL:objURL];
  MDLMesh *markerObject = (MDLMesh *)[markerAsset objectAtIndex:0];
  MDLMaterial *material = [[MDLMaterial alloc] initWithName:@"baseMaterial"
                                         scatteringFunction:[[MDLScatteringFunction alloc] init]];
  NSURL *textureURL =
      isTerrainAnchor
          ? [[NSBundle mainBundle] URLForResource:@"spatial-marker-yellow" withExtension:@"png"]
          : [[NSBundle mainBundle] URLForResource:@"spatial-marker-baked" withExtension:@"png"];
  MDLMaterialProperty *materialPropetry =
      [[MDLMaterialProperty alloc] initWithName:@"texture"
                                       semantic:MDLMaterialSemanticBaseColor
                                            URL:textureURL];
  [material setProperty:materialPropetry];
  for (MDLSubmesh *submesh in markerObject.submeshes) {
    submesh.material = material;
  }
  return [SCNNode nodeWithMDLObject:markerObject];
}

- (void)setUpGARSession {
  if (self.garSession) {
    return;
  }

  NSError *error = nil;
  self.garSession = [GARSession sessionWithAPIKey:@"your-api-key"
                                 bundleIdentifier:nil
                                            error:&error];
  if (error) {
    [self setErrorStatus:[NSString
                             stringWithFormat:@"Failed to create GARSession: %d", (int)error.code]];
    return;
  }

  self.localizationState = LocalizationStateFailed;

  if (![self.garSession isGeospatialModeSupported:GARGeospatialModeEnabled]) {
    [self setErrorStatus:@"GARGeospatialModeEnabled is not supported on this device."];
    return;
  }

  GARSessionConfiguration *configuration = [[GARSessionConfiguration alloc] init];
  configuration.geospatialMode = GARGeospatialModeEnabled;
  [self.garSession setConfiguration:configuration error:&error];
  if (error) {
    [self setErrorStatus:[NSString stringWithFormat:@"Failed to configure GARSession: %d",
                                                    (int)error.code]];
    return;
  }

  self.localizationState = LocalizationStatePretracking;
  self.lastStartLocalizationDate = [NSDate date];
}

- (void)checkVPSAvailabilityWithCoordinate:(CLLocationCoordinate2D)coordinate {
  [self.garSession checkVPSAvailabilityAtCoordinate:coordinate
                                  completionHandler:^(GARVPSAvailability availability) {
                                    if (availability != GARVPSAvailabilityAvailable) {
                                      [self showVPSUnavailableNotice];
                                    }
                                  }];
}

- (void)addSavedAnchors {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray<NSDictionary<NSString *, NSNumber *> *> *savedAnchors =
      [defaults arrayForKey:kSavedAnchorsUserDefaultsKey];
  for (NSDictionary<NSString *, NSNumber *> *savedAnchor in savedAnchors) {
    CLLocationDegrees latitude = savedAnchor[@"latitude"].doubleValue;
    CLLocationDegrees longitude = savedAnchor[@"longitude"].doubleValue;
    CLLocationDirection heading;
    simd_quatf eastUpSouthQTarget = simd_quaternion(0.f, 0.f, 0.f, 1.f);
    BOOL useHeading = [savedAnchor objectForKey:@"heading"];
    if (useHeading) {
      heading = savedAnchor[@"heading"].doubleValue;
    } else {
      eastUpSouthQTarget = simd_quaternion(
          (simd_float4){savedAnchor[@"x"].floatValue, savedAnchor[@"y"].floatValue,
                        savedAnchor[@"z"].floatValue, savedAnchor[@"w"].floatValue});
    }
    if ([savedAnchor objectForKey:@"altitude"]) {
      CLLocationDistance altitude = savedAnchor[@"altitude"].doubleValue;
      [self addAnchorWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
                           altitude:altitude
                            heading:heading
                 eastUpSouthQTarget:eastUpSouthQTarget
                         useHeading:useHeading
                         shouldSave:NO];
    } else {
      [self addTerrainAnchorWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
                                   heading:heading
                        eastUpSouthQTarget:eastUpSouthQTarget
                                useHeading:useHeading
                                shouldSave:NO];
    }
  }
}

- (void)updateLocalizationState {
  // This will be nil if not currently tracking.
  GARGeospatialTransform *geospatialTransform = self.garFrame.earth.cameraGeospatialTransform;
  NSDate *now = [NSDate date];

  if (self.garFrame.earth.earthState != GAREarthStateEnabled) {
    self.localizationState = LocalizationStateFailed;
  } else if (self.garFrame.earth.trackingState != GARTrackingStateTracking) {
    self.localizationState = LocalizationStatePretracking;
  } else {
    if (self.localizationState == LocalizationStatePretracking) {
      self.localizationState = LocalizationStateLocalizing;
    } else if (self.localizationState == LocalizationStateLocalizing) {
      if (geospatialTransform != nil &&
          geospatialTransform.horizontalAccuracy <= kHorizontalAccuracyLowThreshold &&
          geospatialTransform.headingAccuracy <= kHeadingAccuracyLowThreshold) {
        self.localizationState = LocalizationStateLocalized;
        if (!self.restoredSavedAnchors) {
          [self addSavedAnchors];
          self.restoredSavedAnchors = YES;
        }
      } else if ([now timeIntervalSinceDate:self.lastStartLocalizationDate] >=
                 kLocalizationFailureTime) {
        self.localizationState = LocalizationStateFailed;
      }
    } else {
      // Use higher thresholds for exiting 'localized' state to avoid flickering state changes.
      if (geospatialTransform == nil ||
          geospatialTransform.horizontalAccuracy > kHorizontalAccuracyHighThreshold ||
          geospatialTransform.headingAccuracy > kHeadingAccuracyHighThreshold) {
        self.localizationState = LocalizationStateLocalizing;
        self.lastStartLocalizationDate = now;
      }
    }
  }
}

- (void)updateMarkerNodes {
  NSMutableSet<NSUUID *> *currentAnchorIDs = [NSMutableSet set];

  // Add/update nodes for tracking anchors.
  for (GARAnchor *anchor in self.garFrame.anchors) {
    if (anchor.trackingState != GARTrackingStateTracking) {
      continue;
    }
    SCNNode *node = self.markerNodes[anchor.identifier];
    if (!node) {
      // Only render resolved Terrain Anchors and Geospatial anchors.
      if (anchor.terrainState == GARTerrainAnchorStateSuccess) {
        node = [self markerNodeIsTerrainAnchor:YES];
      } else if (anchor.terrainState == GARTerrainAnchorStateNone) {
        node = [self markerNodeIsTerrainAnchor:NO];
      }
      self.markerNodes[anchor.identifier] = node;
      [self.scene.rootNode addChildNode:node];
    }
    node.simdTransform = anchor.transform;
    node.hidden = (self.localizationState != LocalizationStateLocalized);
    [currentAnchorIDs addObject:anchor.identifier];
  }

  // Remove nodes for anchors that are no longer tracking.
  for (NSUUID *anchorID in self.markerNodes.allKeys) {
    if (![currentAnchorIDs containsObject:anchorID]) {
      SCNNode *node = self.markerNodes[anchorID];
      [node removeFromParentNode];
      [self.markerNodes removeObjectForKey:anchorID];
    }
  }
}

- (NSString *)stringFromGAREarthState:(GAREarthState)earthState {
  switch (earthState) {
    case GAREarthStateErrorInternal:
      return @"ERROR_INTERNAL";
    case GAREarthStateErrorNotAuthorized:
      return @"ERROR_NOT_AUTHORIZED";
    case GAREarthStateErrorResourceExhausted:
      return @"ERROR_RESOURCE_EXHAUSTED";
    default:
      return @"ENABLED";
  }
}

- (void)updateTrackingLabel {
  if (self.localizationState == LocalizationStateFailed) {
    if (self.garFrame.earth.earthState != GAREarthStateEnabled) {
      NSString *earthState = [self stringFromGAREarthState:self.garFrame.earth.earthState];
      self.trackingLabel.text = [NSString stringWithFormat:@"Bad EarthState: %@", earthState];
    } else {
      self.trackingLabel.text = @"";
    }
    return;
  }

  if (self.garFrame.earth.trackingState == GARTrackingStatePaused) {
    self.trackingLabel.text = @"Not tracking.";
    return;
  }

  // This can't be nil if currently tracking and in a good EarthState.
  GARGeospatialTransform *geospatialTransform = self.garFrame.earth.cameraGeospatialTransform;

  // Display heading in range [-180, 180], with 0=North, instead of [0, 360), as required by the
  // type CLLocationDirection.
  double heading = geospatialTransform.heading;
  if (heading > 180) {
    heading -= 360;
  }

  // Note: the altitude value here is relative to the WGS84 ellipsoid (equivalent to
  // |CLLocation.ellipsoidalAltitude|).
  self.trackingLabel.text = [NSString
      stringWithFormat:kGeospatialTransformFormat, geospatialTransform.coordinate.latitude,
                       geospatialTransform.coordinate.longitude,
                       geospatialTransform.horizontalAccuracy, geospatialTransform.altitude,
                       geospatialTransform.verticalAccuracy, heading,
                       geospatialTransform.headingAccuracy];
}

- (void)updateStatusLabelAndButtons {
  switch (self.localizationState) {
    case LocalizationStateLocalized: {
      [self.terrainAnchorIDToStartTime removeObjectsForKeys:[self.anchorIDsToRemove allObjects]];
      [self.anchorIDsToRemove removeAllObjects];
      NSString *message = nil;
      // If there is a new terrain anchor state, show terrain anchor state.
      for (GARAnchor *anchor in self.garFrame.anchors) {
        if (anchor.terrainState == GARTerrainAnchorStateNone) {
          continue;
        }

        if (self.terrainAnchorIDToStartTime[anchor.identifier] != nil) {
          message = [NSString stringWithFormat:@"Terrain Anchor State: %@",
                                               [self terrainStateString:anchor.terrainState]];

          NSDate *now = [NSDate date];
          if (anchor.terrainState == GARTerrainAnchorStateTaskInProgress) {
            if ([now timeIntervalSinceDate:self.terrainAnchorIDToStartTime[anchor.identifier]] >=
                kDurationNoTerrainAnchorResult) {
              message = @"Still resolving the terrain anchor. Please make sure you\'re "
                        @"in an area that has VPS coverage.";
              [self.anchorIDsToRemove addObject:anchor.identifier];
            }
          } else {
            // Remove it if task has finished.
            [self.anchorIDsToRemove addObject:anchor.identifier];
          }
        }
      }
      if (message != nil) {
        self.statusLabel.text = message;
      } else if (self.garFrame.anchors.count == 0) {
        self.statusLabel.text = kLocalizationComplete;
      } else if (!self.islastClickedTerrainAnchorButton) {
        self.statusLabel.text =
            [NSString stringWithFormat:@"Num anchors: %d", (int)self.garFrame.anchors.count];
      }
      self.clearAllAnchorsButton.hidden = (self.garFrame.anchors.count == 0);
      self.addAnchorButton.hidden = (self.garFrame.anchors.count >= kMaxAnchors);
      self.tapScreenLabel.hidden = (self.garFrame.anchors.count >= kMaxAnchors);
      break;
    }
    case LocalizationStatePretracking:
      self.statusLabel.text = kPretrackingMessage;
      break;
    case LocalizationStateLocalizing:
      self.statusLabel.text = kLocalizationTip;
      self.addAnchorButton.hidden = YES;
      self.tapScreenLabel.hidden = YES;
      self.clearAllAnchorsButton.hidden = YES;
      break;
    case LocalizationStateFailed:
      self.statusLabel.text = kLocalizationFailureMessage;
      self.addAnchorButton.hidden = YES;
      self.tapScreenLabel.hidden = YES;
      self.clearAllAnchorsButton.hidden = YES;
      break;
  }
  self.isTerrainAnchorMode = self.terrainAnchorSwitch.isOn;
}

- (NSString *)terrainStateString:(GARTerrainAnchorState)terrainAnchorState {
  switch (terrainAnchorState) {
    case GARTerrainAnchorStateNone:
      return @"None";
    case GARTerrainAnchorStateSuccess:
      return @"Success";
    case GARTerrainAnchorStateErrorInternal:
      return @"ErrorInternal";
    case GARTerrainAnchorStateTaskInProgress:
      return @"TaskInProgress";
    case GARTerrainAnchorStateErrorNotAuthorized:
      return @"ErrorNotAuthorized";
    case GARTerrainAnchorStateErrorUnsupportedLocation:
      return @"UnsupportedLocation";
    default:
      return @"Unknown";
  }
}

- (void)updateWithGARFrame:(GARFrame *)garFrame {
  self.garFrame = garFrame;
  [self updateLocalizationState];
  [self updateMarkerNodes];
  [self updateTrackingLabel];
  [self updateStatusLabelAndButtons];
}

- (void)addAnchorWithCoordinate:(CLLocationCoordinate2D)coordinate
                       altitude:(CLLocationDistance)altitude
                        heading:(CLLocationDirection)heading
             eastUpSouthQTarget:(simd_quatf)eastUpSouthQTarget
                     useHeading:(BOOL)useHeading
                     shouldSave:(BOOL)shouldSave {
  simd_quatf eastUpSouthQAnchor;
  if (useHeading) {
    // The arrow of the 3D model points towards the Z-axis, while heading is measured clockwise from
    // North.
    float angle = (M_PI / 180) * (180 - heading);
    eastUpSouthQAnchor = simd_quaternion(angle, simd_make_float3(0, 1, 0));
  } else {
    eastUpSouthQAnchor = eastUpSouthQTarget;
  }
  // The return value of |createAnchorWithCoordinate:altitude:eastUpSouthQAnchor:error:| is just the
  // first snapshot of the anchor (which is immutable). Use the updated snapshots in
  // |GARFrame.anchors| to get updated values on a frame-by-frame basis.
  NSError *error = nil;
  [self.garSession createAnchorWithCoordinate:coordinate
                                     altitude:altitude
                           eastUpSouthQAnchor:eastUpSouthQAnchor
                                        error:&error];
  if (error) {
    NSLog(@"Error adding anchor: %@", error);
    return;
  }

  if (shouldSave) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSDictionary<NSString *, NSNumber *> *> *savedAnchors =
        [defaults arrayForKey:kSavedAnchorsUserDefaultsKey] ?: @[];
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *newSavedAnchors =
        [savedAnchors mutableCopy];
    if (useHeading) {
      [newSavedAnchors addObject:@{
        @"latitude" : @(coordinate.latitude),
        @"longitude" : @(coordinate.longitude),
        @"altitude" : @(altitude),
        @"heading" : @(heading),
      }];
    } else {
      [newSavedAnchors addObject:@{
        @"latitude" : @(coordinate.latitude),
        @"longitude" : @(coordinate.longitude),
        @"altitude" : @(altitude),
        @"x" : @(eastUpSouthQTarget.vector[0]),
        @"y" : @(eastUpSouthQTarget.vector[1]),
        @"z" : @(eastUpSouthQTarget.vector[2]),
        @"w" : @(eastUpSouthQTarget.vector[3]),
      }];
    }
    [defaults setObject:newSavedAnchors forKey:kSavedAnchorsUserDefaultsKey];
  }
}

- (void)addTerrainAnchorWithCoordinate:(CLLocationCoordinate2D)coordinate
                               heading:(CLLocationDirection)heading
                    eastUpSouthQTarget:(simd_quatf)eastUpSouthQTarget
                            useHeading:(BOOL)useHeading
                            shouldSave:(BOOL)shouldSave {
  simd_quatf eastUpSouthQAnchor;
  if (useHeading) {
    // The arrow of the 3D model points towards the Z-axis, while heading is measured clockwise from
    // North.
    float angle = (M_PI / 180) * (180 - heading);
    eastUpSouthQAnchor = simd_quaternion(angle, simd_make_float3(0, 1, 0));
  } else {
    eastUpSouthQAnchor = eastUpSouthQTarget;
  }

  // The return value of |createAnchorWithCoordinate:altitude:eastUpSouthQAnchor:error:| is just the
  // first snapshot of the anchor (which is immutable). Use the updated snapshots in
  // |GARFrame.anchors| to get updated values on a frame-by-frame basis.
  NSError *error = nil;
  GARAnchor *anchor = [self.garSession createAnchorWithCoordinate:coordinate
                                             altitudeAboveTerrain:0
                                               eastUpSouthQAnchor:eastUpSouthQAnchor
                                                            error:&error];
  if (error) {
    NSLog(@"Error adding anchor: %@", error);
    if (error.code == GARSessionErrorCodeResourceExhausted) {
      self.statusLabel.text =
          @"Too many terrain anchors have already been held. Clear all anchors to create new ones.";
    }
    return;
  }
  self.terrainAnchorIDToStartTime[anchor.identifier] = [NSDate date];
  if (shouldSave) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSDictionary<NSString *, NSNumber *> *> *savedAnchors =
        [defaults arrayForKey:kSavedAnchorsUserDefaultsKey] ?: @[];
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *newSavedAnchors =
        [savedAnchors mutableCopy];
    if (useHeading) {
      [newSavedAnchors addObject:@{
        @"latitude" : @(coordinate.latitude),
        @"longitude" : @(coordinate.longitude),
        @"heading" : @(heading),
      }];
    } else {
      [newSavedAnchors addObject:@{
        @"latitude" : @(coordinate.latitude),
        @"longitude" : @(coordinate.longitude),
        @"x" : @(eastUpSouthQTarget.vector[0]),
        @"y" : @(eastUpSouthQTarget.vector[1]),
        @"z" : @(eastUpSouthQTarget.vector[2]),
        @"w" : @(eastUpSouthQTarget.vector[3]),
      }];
    }
    [defaults setObject:newSavedAnchors forKey:kSavedAnchorsUserDefaultsKey];
  }
}

- (void)addAnchorButtonPressed {
  // This button will be hidden if not currently tracking, so this can't be nil.
  GARGeospatialTransform *geospatialTransform = self.garFrame.earth.cameraGeospatialTransform;
  if (self.isTerrainAnchorMode) {
    [self addTerrainAnchorWithCoordinate:geospatialTransform.coordinate
                                 heading:geospatialTransform.heading
                      eastUpSouthQTarget:simd_quaternion(0.f, 0.f, 0.f, 1.f)
                              useHeading:YES
                              shouldSave:YES];
  } else {
    [self addAnchorWithCoordinate:geospatialTransform.coordinate
                         altitude:geospatialTransform.altitude
                          heading:geospatialTransform.heading
               eastUpSouthQTarget:simd_quaternion(0.f, 0.f, 0.f, 1.f)
                       useHeading:YES
                       shouldSave:YES];
  }
  self.islastClickedTerrainAnchorButton = self.isTerrainAnchorMode;
}

- (void)clearAllAnchorsButtonPressed {
  for (GARAnchor *anchor in self.garFrame.anchors) {
    [self.garSession removeAnchor:anchor];
  }
  for (SCNNode *node in self.markerNodes.allValues) {
    [node removeFromParentNode];
  }
  [self.markerNodes removeAllObjects];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedAnchorsUserDefaultsKey];
  self.islastClickedTerrainAnchorButton = NO;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (touches.count < 1) {
    return;
  }
  if (self.garFrame.anchors.count >= kMaxAnchors) {
    return;
  }

  UITouch *touch = [[touches allObjects] firstObject];
  CGPoint touchLocation = [touch locationInView:self.scnView];
  NSArray<ARRaycastResult *> *rayCastResults = [self.arSession
      raycast:[self.scnView raycastQueryFromPoint:touchLocation
                                   allowingTarget:ARRaycastTargetExistingPlaneGeometry
                                        alignment:ARRaycastTargetAlignmentHorizontal]];

  if (rayCastResults.count > 0) {
    ARRaycastResult *result = rayCastResults.firstObject;
    NSError *error = nil;
    GARGeospatialTransform *geospatialTransform =
        [self.garSession geospatialTransformFromTransform:result.worldTransform error:&error];
    if (error) {
      NSLog(@"Error adding convert transform to GARGeospatialTransform: %@", error);
      return;
    }

    if (self.isTerrainAnchorMode) {
      [self addTerrainAnchorWithCoordinate:geospatialTransform.coordinate
                                   heading:0
                        eastUpSouthQTarget:geospatialTransform.eastUpSouthQTarget
                                useHeading:NO
                                shouldSave:YES];
    } else {
      [self addAnchorWithCoordinate:geospatialTransform.coordinate
                           altitude:geospatialTransform.altitude
                            heading:0
                 eastUpSouthQTarget:geospatialTransform.eastUpSouthQTarget
                         useHeading:NO
                         shouldSave:YES];
    }
    self.islastClickedTerrainAnchorButton = self.isTerrainAnchorMode;
  }
}

#pragma mark - CLLocationManagerDelegate

/** Authorization callback for iOS < 14. Deprecated, but needed until deployment target >= 14.0. */
- (void)locationManager:(CLLocationManager *)locationManager
    didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  [self checkLocationPermission];
}

/** Authorization callback for iOS 14. */
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)locationManager
    API_AVAILABLE(ios(14.0)) {
  [self checkLocationPermission];
}

- (void)locationManager:(CLLocationManager *)locationManager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
  CLLocation *location = locations.lastObject;
  if (location) {
    [self checkVPSAvailabilityWithCoordinate:location.coordinate];
  }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
   NSLog(@"Error get location: %@", error);
}

#pragma mark - ARSCNViewDelegate
- (nullable SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
  return [[SCNNode alloc] init];
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
      didAddNode:(SCNNode *)node
       forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    CGFloat width = planeAnchor.extent.x;
    CGFloat height = planeAnchor.extent.z;
    SCNPlane *plane = [SCNPlane planeWithWidth:width height:height];

    plane.materials.firstObject.diffuse.contents = [UIColor colorWithRed:0.0f
                                                                   green:0.0f
                                                                    blue:1.0f
                                                                   alpha:0.7f];

    SCNNode *planeNode = [SCNNode nodeWithGeometry:plane];

    CGFloat x = planeAnchor.center.x;
    CGFloat y = planeAnchor.center.y;
    CGFloat z = planeAnchor.center.z;
    planeNode.position = SCNVector3Make(x, y, z);
    planeNode.eulerAngles = SCNVector3Make(-M_PI / 2, 0, 0);

    [node addChildNode:planeNode];
  }
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
   didUpdateNode:(SCNNode *)node
       forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    SCNNode *planeNode = node.childNodes.firstObject;
    NSAssert([planeNode.geometry isKindOfClass:[SCNPlane class]],
             @"planeNode's child is not an SCNPlane--did something go wrong in "
             @"renderer:didAddNode:forAnchor:?");
    SCNPlane *plane = (SCNPlane *)planeNode.geometry;

    CGFloat width = planeAnchor.extent.x;
    CGFloat height = planeAnchor.extent.z;
    plane.width = width;
    plane.height = height;

    CGFloat x = planeAnchor.center.x;
    CGFloat y = planeAnchor.center.y;
    CGFloat z = planeAnchor.center.z;
    planeNode.position = SCNVector3Make(x, y, z);
  }
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
   didRemoveNode:(SCNNode *)node
       forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    SCNNode *planeNode = node.childNodes.firstObject;
    [planeNode removeFromParentNode];
  }
}

#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  if (self.garSession == nil || self.localizationState == LocalizationStateFailed) {
    return;
  }
  GARFrame *garFrame = [self.garSession update:frame error:nil];
  [self updateWithGARFrame:garFrame];
}

@end
