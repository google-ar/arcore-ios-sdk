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

// This sample allows up to 5 simultaneous anchors, although in principal ARCore supports an
// unlimited number.
static const NSUInteger kMaxAnchors = 5;

static NSString * const kLocalizationTip =
    @"Point your camera at buildings, stores, and signs near you.";
static NSString * const kLocalizationFailureMessage =
    @"Localization not possible.\nClose and open the app to restart.";
static NSString * const kGeospatialTransformFormat =
    @"LAT/LONG: %.6f°, %.6f°\n    ACCURACY: %.2fm\nALTITUDE: %.2fm\n    ACCURACY: %.2fm\n"
    "HEADING: %.1f°\n    ACCURACY: %.1f°";

static const CGFloat kFontSize = 18.0;

// Anchor coordinates are persisted between sessions.
static NSString * const kSavedAnchorsUserDefaultsKey = @"anchors";

// Show privacy notice before using features.
static NSString * const kPrivacyNoticeUserDefaultsKey = @"privacy_notice_acknowledged";

// Title of the privacy notice prompt.
static NSString * const kPrivacyNoticeTitle = @"AR in the real world";

// Content of the privacy notice prompt.
static NSString * const kPrivacyNoticeText =
    @"To power this session, Google will process visual data from your camera.";

// Link to learn more about the privacy content.
static NSString * const kPrivacyNoticeLearnMoreURL =
    @"https://developers.google.com/ar/data-privacy";

typedef NS_ENUM(NSInteger, LocalizationState) {
  LocalizationStateLocalizing = 0,
  LocalizationStateLocalized = 1,
  LocalizationStateFailed = -1,
};

@interface ViewController ()<ARSessionDelegate, CLLocationManagerDelegate>

/** Location manager used to request and check for location permissions. */
@property(nonatomic) CLLocationManager *locationManager;

/** ARKit session. */
@property(nonatomic) ARSession *arSession;

/**
 * ARCore session, used for geospatial localization. Created after obtaining location permission.
 */
@property(nonatomic) GARSession *garSession;

/** SceneKit scene used for rendering markers. */
@property(nonatomic) SCNScene *scene;

/** Label used to show Earth tracking state at top of screen. */
@property(nonatomic, weak) UILabel *trackingLabel;

/** Label used to show status at bottom of screen. */
@property(nonatomic, weak) UILabel *statusLabel;

/** Button used to place a new anchor. */
@property(nonatomic, weak) UIButton *addAnchorButton;

/** Button used to clear all existing anchors. */
@property(nonatomic, weak) UIButton *clearAllAnchorsButton;

/** The most recent GARFrame. */
@property(nonatomic) GARFrame *garFrame;

/** Dictionary mapping anchor IDs to SceneKit nodes. */
@property(nonatomic) NSMutableDictionary<NSUUID *, SCNNode *> *markerNodes;

/** The last time we started attempting to localize. Used to implement failure timeout. */
@property(nonatomic) NSDate *lastStartLocalizationDate;

/** The current localization state. */
@property(nonatomic) LocalizationState localizationState;

/** Whether we have restored anchors saved from the previous session. */
@property(nonatomic) BOOL restoredSavedAnchors;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.markerNodes = [NSMutableDictionary dictionary];

  ARSCNView *scnView = [[ARSCNView alloc] init];
  scnView.translatesAutoresizingMaskIntoConstraints = NO;
  scnView.automaticallyUpdatesLighting = YES;
  scnView.autoenablesDefaultLighting = YES;
  self.scene = scnView.scene;
  self.arSession = scnView.session;
  [self.view addSubview:scnView];

  UIFont *font = [UIFont systemFontOfSize:kFontSize];
  UIFont *boldFont = [UIFont boldSystemFontOfSize:kFontSize];

  UILabel *trackingLabel = [[UILabel alloc] init];
  trackingLabel.translatesAutoresizingMaskIntoConstraints = NO;
  trackingLabel.font = font;
  trackingLabel.textColor = UIColor.whiteColor;
  trackingLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:.5];
  trackingLabel.numberOfLines = 6;
  self.trackingLabel = trackingLabel;
  [scnView addSubview:trackingLabel];

  UILabel *statusLabel = [[UILabel alloc] init];
  statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  statusLabel.font = font;
  statusLabel.textColor = UIColor.whiteColor;
  statusLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:.5];
  statusLabel.numberOfLines = 2;
  self.statusLabel = statusLabel;
  [scnView addSubview:statusLabel];

  UIButton *addAnchorButton = [UIButton buttonWithType:UIButtonTypeSystem];
  addAnchorButton.translatesAutoresizingMaskIntoConstraints = NO;
  [addAnchorButton setTitle:@"ADD ANCHOR" forState:UIControlStateNormal];
  addAnchorButton.titleLabel.font = boldFont;
  [addAnchorButton addTarget:self
                      action:@selector(addAnchorButtonPressed)
            forControlEvents:UIControlEventTouchUpInside];
  addAnchorButton.hidden = YES;
  self.addAnchorButton = addAnchorButton;
  [self.view addSubview:addAnchorButton];

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

  [scnView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
  [scnView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
  [scnView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [scnView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  [trackingLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor]
      .active = YES;
  [trackingLabel.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [trackingLabel.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
  [trackingLabel.heightAnchor constraintEqualToConstant:140].active = YES;

  [statusLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
      .active = YES;
  [statusLabel.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [statusLabel.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
  [statusLabel.heightAnchor constraintEqualToConstant:80].active = YES;

  [addAnchorButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
      .active = YES;
  [addAnchorButton.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  [clearAllAnchorsButton.bottomAnchor
      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor].active = YES;
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
  UIAlertAction *getStartedAction = [UIAlertAction actionWithTitle:@"Get started"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction *action) {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrivacyNoticeUserDefaultsKey];
    [self setUpARSession];
  }];
  UIAlertAction *learnMoreAction = [UIAlertAction actionWithTitle:@"Learn more"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kPrivacyNoticeLearnMoreURL]
                                       options:@{}
                             completionHandler:nil];
  }];
  [alertController addAction:getStartedAction];
  [alertController addAction:learnMoreAction];
  [self presentViewController:alertController animated:NO completion:nil];
}

- (void)setUpARSession {
  ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc] init];
  configuration.worldAlignment = ARWorldAlignmentGravity;
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
  self.clearAllAnchorsButton.hidden = YES;
}

- (SCNNode *)markerNode {
  NSURL *objURL = [[NSBundle mainBundle] URLForResource:@"geospatial_marker" withExtension:@"obj"];
  MDLAsset *markerAsset = [[MDLAsset alloc] initWithURL:objURL];
  MDLMesh *markerObject = (MDLMesh *)[markerAsset objectAtIndex:0];
  MDLMaterial *material = [[MDLMaterial alloc] initWithName:@"baseMaterial"
                                         scatteringFunction:[[MDLScatteringFunction alloc] init]];
  NSURL *textureURL = [[NSBundle mainBundle] URLForResource:@"spatial-marker-baked"
                                              withExtension:@"png"];
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
    [self setErrorStatus:[NSString stringWithFormat:@"Failed to create GARSession: %d",
                                                    (int)error.code]];
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

  self.localizationState = LocalizationStateLocalizing;
  self.lastStartLocalizationDate = [NSDate date];
}

- (void)addSavedAnchors {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray<NSDictionary<NSString *, NSNumber *> *> *savedAnchors =
      [defaults arrayForKey:kSavedAnchorsUserDefaultsKey];
  for (NSDictionary<NSString *, NSNumber *> *savedAnchor in savedAnchors) {
    CLLocationDegrees latitude = savedAnchor[@"latitude"].doubleValue;
    CLLocationDegrees longitude = savedAnchor[@"longitude"].doubleValue;
    CLLocationDistance altitude = savedAnchor[@"altitude"].doubleValue;
    CLLocationDirection heading = savedAnchor[@"heading"].doubleValue;
    [self addAnchorWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
                         altitude:altitude
                          heading:heading
                       shouldSave:NO];
  }
}

- (void)updateLocalizationState {
  // This will be nil if not currently tracking.
  GARGeospatialTransform *geospatialTransform = self.garFrame.earth.cameraGeospatialTransform;
  NSDate *now = [NSDate date];

  if (self.garFrame.earth.earthState != GAREarthStateEnabled) {
    self.localizationState = LocalizationStateFailed;
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
    // self.localizationState == LocalizationStateLocalized.
    // Use higher thresholds for exiting 'localized' state to avoid flickering state changes.
    if (geospatialTransform == nil ||
        geospatialTransform.horizontalAccuracy > kHorizontalAccuracyHighThreshold ||
        geospatialTransform.headingAccuracy > kHeadingAccuracyHighThreshold) {
      self.localizationState = LocalizationStateLocalizing;
      self.lastStartLocalizationDate = now;
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
      node = [self markerNode];
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
  self.trackingLabel.text =
      [NSString stringWithFormat:kGeospatialTransformFormat,
          geospatialTransform.coordinate.latitude, geospatialTransform.coordinate.longitude,
          geospatialTransform.horizontalAccuracy, geospatialTransform.altitude,
          geospatialTransform.verticalAccuracy, heading, geospatialTransform.headingAccuracy];
}

- (void)updateStatusLabelAndButtons {
  switch (self.localizationState) {
    case LocalizationStateLocalized:
      self.statusLabel.text = [NSString stringWithFormat:@"Num anchors: %d",
                                                         (int)self.garFrame.anchors.count];
      self.clearAllAnchorsButton.hidden = (self.garFrame.anchors.count == 0);
      self.addAnchorButton.hidden = (self.garFrame.anchors.count >= kMaxAnchors);
      break;
    case LocalizationStateLocalizing:
      self.statusLabel.text = kLocalizationTip;
      self.addAnchorButton.hidden = YES;
      self.clearAllAnchorsButton.hidden = YES;
      break;
    case LocalizationStateFailed:
      self.statusLabel.text = kLocalizationFailureMessage;
      self.addAnchorButton.hidden = YES;
      self.clearAllAnchorsButton.hidden = YES;
      break;
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
                     shouldSave:(BOOL)shouldSave {
  // The arrow of the 3D model points towards the Z-axis, while heading is measured clockwise from
  // North.
  float angle = (M_PI / 180) * (180 - heading);
  simd_quatf eastUpSouthQAnchor = simd_quaternion(angle, simd_make_float3(0, 1, 0));

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
    [newSavedAnchors addObject:@{
      @"latitude": @(coordinate.latitude),
      @"longitude": @(coordinate.longitude),
      @"altitude": @(altitude),
      @"heading": @(heading),
    }];
    [defaults setObject:newSavedAnchors forKey:kSavedAnchorsUserDefaultsKey];
  }
}

- (void)addAnchorButtonPressed {
  // This button will be hidden if not currently tracking, so this can't be nil.
  GARGeospatialTransform *geospatialTransform = self.garFrame.earth.cameraGeospatialTransform;
  [self addAnchorWithCoordinate:geospatialTransform.coordinate
                       altitude:geospatialTransform.altitude
                        heading:geospatialTransform.heading
                     shouldSave:YES];
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

#pragma mark - ARSessionDelegate

-(void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  if (self.garSession == nil || self.localizationState == LocalizationStateFailed) {
    return;
  }
  GARFrame *garFrame = [self.garSession update:frame error:nil];
  [self updateWithGARFrame:garFrame];
}

@end
