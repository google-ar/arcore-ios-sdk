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
static const CLLocationDirectionAccuracy kOrientationYawAccuracyLowThreshold = 15;
static const CLLocationDirectionAccuracy kOrientationYawAccuracyHighThreshold = 25;

// Time after which the app gives up if good enough accuracy is not achieved.
static const NSTimeInterval kLocalizationFailureTime = 3 * 60.0;
// Time after showing resolving terrain anchors no result yet message.
static const NSTimeInterval kDurationNoTerrainAnchorResult = 10;

// This sample allows up to |kMaxAnchors| simultaneous anchors, although in principal ARCore
// supports an unlimited number.
static const NSUInteger kMaxAnchors = 20;

static NSString *const kPretrackingMessage = @"Localizing your device to set anchor.";
static NSString *const kLocalizationTip =
    @"Point your camera at buildings, stores, and signs near you.";
static NSString *const kLocalizationComplete = @"Localization complete.";
static NSString *const kLocalizationFailureMessage =
    @"Localization not possible.\nClose and open the app to restart.";
static NSString *const kGeospatialTransformFormat =
    @"LAT/LONG: %.6f°, %.6f°\n    ACCURACY: %.2fm\nALTITUDE: %.2fm\n    ACCURACY: %.2fm\n"
     "ORIENTATION: [%.1f, %.1f, %.1f, %.1f]\n    YAW ACCURACY: %.1f°";

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
static NSString *const kVPSAvailabilityNoticeUserDefaultsKey =
    @"VPS_availability_notice_acknowledged";

// Title of the VPS availability notice prompt.
static NSString *const kVPSAvailabilityTitle = @"VPS not available";

// Content of the VPS availability notice prompt.
static NSString *const kVPSAvailabilityText =
    @"The Google Visual Positioning Service (VPS) is not available at your current location. "
    @"Location data may not be as accurate.";

typedef NS_ENUM(NSInteger, LocalizationState) {
  LocalizationStatePretracking = 0,
  LocalizationStateLocalizing = 1,
  LocalizationStateLocalized = 2,
  LocalizationStateFailed = -1,
};

typedef NS_ENUM(NSInteger, AnchorType) {
  AnchorTypeGeospatial = 0,
  AnchorTypeTerrain = 1,
  AnchorTypeRooftop = 2,
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

/** UISwitch for enabling or disabling Streetscape Geometry. */
@property(nonatomic, weak) UISwitch *streetscapeGeometrySwitch;

/** UIButton to select the anchor mode. */
@property(nonatomic, weak) UIButton *anchorModeSelector;

/** The current type of anchor to create. */
@property(nonatomic) AnchorType anchorMode;

/** Label of streetscapeGeometrySwitch. */
@property(nonatomic, weak) UILabel *switchLabel;

/** Button used to clear all existing anchors. */
@property(nonatomic, weak) UIButton *clearAllAnchorsButton;

/** The most recent GARFrame. */
@property(nonatomic) GARFrame *garFrame;

/** Dictionary mapping anchor IDs to SceneKit nodes. */
@property(nonatomic) NSMutableDictionary<NSUUID *, SCNNode *> *markerNodes;

/** The last time we started attempting to localize. Used to implement failure timeout. */
@property(nonatomic) NSDate *lastStartLocalizationDate;

/** Error message, if any, of last attempted anchor resolution */
@property(nonatomic) NSString *resolveAnchorErrorMessage;

/** The current localization state. */
@property(nonatomic) LocalizationState localizationState;

/** Whether we have restored anchors saved from the previous session. */
@property(nonatomic) BOOL restoredSavedAnchors;

/**
 * Will we restore the saved anchors this frame, keep track of this to avoid the race condition
 * where the frame.anchors is used after the anchor is added.
 */
@property(nonatomic) BOOL willRestoreSavedAnchors;

/** Whether the last anchor is terrain anchor. */
@property(nonatomic) BOOL islastClickedTerrainAnchorButton;

/** Parent SceneKit node of all StreetscapeGeometries */
@property(nonatomic) SCNNode *streetscapeGeometryParentNode;

/** Dictionary mapping StreetscapeGeometry IDs to SceneKit nodes. */
@property(nonatomic) NSMutableDictionary<NSUUID *, SCNNode *> *streetscapeGeometryNodes;

/** Is StreetscapeGeometry enabled */
@property(nonatomic) BOOL isStreetscapeGeometryEnabled;

/** ARKit plane nodes */
@property(nonatomic) NSMutableSet *planeNodes;

/** Active futures for resolving terrain or rooftop anchors. */
@property(nonatomic) int activeFutures;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.markerNodes = [NSMutableDictionary dictionary];

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

  self.planeNodes = [NSMutableSet set];
  self.activeFutures = 0;

  self.streetscapeGeometryParentNode = [SCNNode node];
  self.streetscapeGeometryParentNode.hidden = NO;
  [self.scene.rootNode addChildNode:self.streetscapeGeometryParentNode];
  self.streetscapeGeometryNodes = [[NSMutableDictionary alloc] init];
  self.isStreetscapeGeometryEnabled = YES;

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

  UISwitch *streetscapeGeometrySwitch = [[UISwitch alloc] init];
  streetscapeGeometrySwitch.translatesAutoresizingMaskIntoConstraints = NO;
  [streetscapeGeometrySwitch setOn:YES];
  [self.view addSubview:streetscapeGeometrySwitch];
  self.streetscapeGeometrySwitch = streetscapeGeometrySwitch;

  UIButton *anchorModeSelector = [UIButton buttonWithType:UIButtonTypeSystem];
  [anchorModeSelector setTitle:@"ANCHOR SETTINGS" forState:UIControlStateNormal];
  [anchorModeSelector setImage:[UIImage systemImageNamed:@"gearshape.fill"]
                      forState:UIControlStateNormal];
  anchorModeSelector.hidden = YES;
  anchorModeSelector.titleLabel.font = boldFont;
  anchorModeSelector.translatesAutoresizingMaskIntoConstraints = NO;
  anchorModeSelector.menu = [self anchorSettingsMenu];
  anchorModeSelector.showsMenuAsPrimaryAction = YES;
  [self.view addSubview:anchorModeSelector];
  self.anchorModeSelector = anchorModeSelector;

  UILabel *switchLabel = [[UILabel alloc] init];
  switchLabel.translatesAutoresizingMaskIntoConstraints = NO;
  switchLabel.font = boldFont;
  switchLabel.textColor = UIColor.whiteColor;
  switchLabel.numberOfLines = 1;
  self.switchLabel = switchLabel;
  [self.scnView addSubview:switchLabel];
  self.switchLabel.text = @"SHOW GEOMETRY";

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

  [streetscapeGeometrySwitch.bottomAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor]
      .active = YES;
  [streetscapeGeometrySwitch.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active =
      YES;

  [anchorModeSelector.topAnchor constraintEqualToAnchor:self.statusLabel.topAnchor].active = YES;
  [anchorModeSelector.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  [switchLabel.bottomAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor].active = YES;
  [switchLabel.rightAnchor constraintEqualToAnchor:self.streetscapeGeometrySwitch.leftAnchor]
      .active = YES;
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
  UIAlertAction *continueAction = [UIAlertAction actionWithTitle:@"Continue"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action){
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
  self.tapScreenLabel.hidden = YES;
  self.clearAllAnchorsButton.hidden = YES;
}

- (UIMenu *)anchorSettingsMenu {
  void (^setAnchorMode)(__kindof UIAction *action) = ^(__kindof UIAction *action) {
    if ([action.title isEqualToString:@"Rooftop"]) {
      self.anchorMode = AnchorTypeRooftop;
    } else if ([action.title isEqualToString:@"Terrain"]) {
      self.anchorMode = AnchorTypeTerrain;
    } else {
      self.anchorMode = AnchorTypeGeospatial;
    }
    self.anchorModeSelector.menu = [self anchorSettingsMenu];
  };

  NSArray<UIAction *> *menuItems = @[
    [UIAction
        actionWithTitle:[NSString stringWithFormat:@"%@%@",
                                                   (self.anchorMode == AnchorTypeGeospatial) ? @"✓ "
                                                                                             : @"",
                                                   @"Geospatial"]
                  image:nil
             identifier:nil
                handler:setAnchorMode],
    [UIAction
        actionWithTitle:[NSString
                            stringWithFormat:@"%@%@",
                                             (self.anchorMode == AnchorTypeTerrain) ? @"✓ " : @"",
                                             @"Terrain"]
                  image:nil
             identifier:nil
                handler:setAnchorMode],
    [UIAction
        actionWithTitle:[NSString
                            stringWithFormat:@"%@%@",
                                             (self.anchorMode == AnchorTypeRooftop) ? @"✓ " : @"",
                                             @"Rooftop"]
                  image:nil
             identifier:nil
                handler:setAnchorMode]

  ];
  return [UIMenu menuWithTitle:@"Anchor Type" children:menuItems];
}

- (SCNNode *)markerNodeForAnchorType:(AnchorType)anchorType {
  NSURL *objURL = [[NSBundle mainBundle] URLForResource:@"geospatial_marker" withExtension:@"obj"];
  MDLAsset *markerAsset = [[MDLAsset alloc] initWithURL:objURL];
  MDLMesh *markerObject = (MDLMesh *)[markerAsset objectAtIndex:0];
  MDLMaterial *material = [[MDLMaterial alloc] initWithName:@"baseMaterial"
                                         scatteringFunction:[[MDLScatteringFunction alloc] init]];
  NSURL *textureURL =
      (anchorType == AnchorTypeGeospatial)
          ? [[NSBundle mainBundle] URLForResource:@"spatial-marker-baked" withExtension:@"png"]
          : [[NSBundle mainBundle] URLForResource:@"spatial-marker-yellow" withExtension:@"png"];
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
  configuration.streetscapeGeometryMode = self.isStreetscapeGeometryEnabled
                                              ? GARStreetscapeGeometryModeEnabled
                                              : GARStreetscapeGeometryModeDisabled;
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
    // Ignore the stored anchors that contain heading for backwards-compatibility.
    if ([savedAnchor objectForKey:@"heading"]) {
      continue;
    }
    CLLocationDegrees latitude = savedAnchor[@"latitude"].doubleValue;
    CLLocationDegrees longitude = savedAnchor[@"longitude"].doubleValue;
    simd_quatf eastUpSouthQTarget =
        simd_quaternion((simd_float4){savedAnchor[@"x"].floatValue, savedAnchor[@"y"].floatValue,
                                      savedAnchor[@"z"].floatValue, savedAnchor[@"w"].floatValue});
    if (AnchorTypeTerrain == [savedAnchor objectForKey:@"type"].intValue) {
      [self addTerrainAnchorWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
                        eastUpSouthQTarget:eastUpSouthQTarget
                                shouldSave:NO];
    } else if (AnchorTypeRooftop == [savedAnchor objectForKey:@"type"].intValue) {
      [self addRooftopAnchorWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
                        eastUpSouthQTarget:eastUpSouthQTarget
                                shouldSave:NO];
    } else {
      CLLocationDistance altitude = savedAnchor[@"altitude"].doubleValue;
      [self addAnchorWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
                           altitude:altitude
                 eastUpSouthQTarget:eastUpSouthQTarget
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
          geospatialTransform.orientationYawAccuracy <= kOrientationYawAccuracyLowThreshold) {
        self.localizationState = LocalizationStateLocalized;
        if (!self.restoredSavedAnchors) {
          self.willRestoreSavedAnchors = YES;
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
          geospatialTransform.orientationYawAccuracy > kOrientationYawAccuracyHighThreshold) {
        self.localizationState = LocalizationStateLocalizing;
        self.lastStartLocalizationDate = now;
      }
    }
  }
}

- (void)saveAnchor:(CLLocationCoordinate2D)coordinate
    eastUpSouthQTarget:(simd_quatf)eastUpSouthQTarget
            anchorType:(AnchorType)anchorType
              altitude:(CLLocationDistance)altitude {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray<NSDictionary<NSString *, NSNumber *> *> *savedAnchors =
      [defaults arrayForKey:kSavedAnchorsUserDefaultsKey] ?: @[];
  NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *newSavedAnchors =
      [savedAnchors mutableCopy];

  NSMutableDictionary *anchorProperties = [NSMutableDictionary dictionaryWithDictionary:@{
    @"latitude" : @(coordinate.latitude),
    @"longitude" : @(coordinate.longitude),
    @"type" : @(anchorType),
    @"x" : @(eastUpSouthQTarget.vector[0]),
    @"y" : @(eastUpSouthQTarget.vector[1]),
    @"z" : @(eastUpSouthQTarget.vector[2]),
    @"w" : @(eastUpSouthQTarget.vector[3]),
  }];

  if (anchorType == AnchorTypeGeospatial) {
    [anchorProperties setObject:@(altitude) forKey:@"altitude"];
  }

  [newSavedAnchors addObject:anchorProperties];
  [defaults setObject:newSavedAnchors forKey:kSavedAnchorsUserDefaultsKey];
}

- (void)addMarkerNode:(GARAnchor *)anchor anchorType:(AnchorType)anchorType {
  SCNNode *node = self.markerNodes[anchor.identifier];

  node = [self markerNodeForAnchorType:anchorType];
  self.markerNodes[anchor.identifier] = node;
  [self.scene.rootNode addChildNode:node];

  [self updateMarkerNode:anchor];
}

- (void)updateMarkerNode:(GARAnchor *)anchor {
  SCNNode *node = self.markerNodes[anchor.identifier];

  if (!node) {
    return;
  }
  // Rotate the virtual object 180 degrees around the Y axis to make the object face the GL
  // camera -Z axis, since camera Z axis faces toward users.
  simd_quatf rotationYquat = simd_quaternion(M_PI, (simd_float3){0, 1, 0});
  node.simdTransform = matrix_multiply(anchor.transform, simd_matrix4x4(rotationYquat));
  node.hidden = (self.localizationState != LocalizationStateLocalized);

  // Scale up anchors which are far from the camera.
  SCNNode *cameraPosition = [SCNNode node];
  cameraPosition.simdTransform = self.arSession.currentFrame.camera.transform;
  float distance = simd_distance(cameraPosition.simdPosition, node.simdPosition);
  float scale = 1.0f + (simd_clamp(distance, 5.0f, 20.0f) - 5.0f) / 15.0f;
  node.simdScale = simd_make_float3(scale, scale, scale);
}

- (void)updateMarkerNodes {
  NSMutableSet<NSUUID *> *currentAnchorIDs = [NSMutableSet set];
  @synchronized(self) {
    for (GARAnchor *anchor in self.garFrame.anchors) {
      [self updateMarkerNode:anchor];
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

    // Add saved anchors separately since they will not be present until the next GARFrame.
    if (self.willRestoreSavedAnchors) {
      [self addSavedAnchors];
      self.willRestoreSavedAnchors = NO;
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

  simd_quatf cameraQuaternion = geospatialTransform.eastUpSouthQTarget;

  // Note: the altitude value here is relative to the WGS84 ellipsoid (equivalent to
  // |CLLocation.ellipsoidalAltitude|).
  self.trackingLabel.text = [NSString
      stringWithFormat:kGeospatialTransformFormat, geospatialTransform.coordinate.latitude,
                       geospatialTransform.coordinate.longitude,
                       geospatialTransform.horizontalAccuracy, geospatialTransform.altitude,
                       geospatialTransform.verticalAccuracy, cameraQuaternion.vector[0],
                       cameraQuaternion.vector[1], cameraQuaternion.vector[2],
                       cameraQuaternion.vector[3], geospatialTransform.orientationYawAccuracy];
}

- (void)updateStatusLabelAndButtons {
  switch (self.localizationState) {
    case LocalizationStateLocalized: {
      if (self.resolveAnchorErrorMessage != nil) {
        self.statusLabel.text = self.resolveAnchorErrorMessage;
      } else if (self.garFrame.anchors.count == 0) {
        self.statusLabel.text = kLocalizationComplete;
      } else if (!self.islastClickedTerrainAnchorButton) {
        self.statusLabel.text = [NSString
            stringWithFormat:@"Num anchors: %d/%lu",
                             (int)self.garFrame.anchors.count + self.activeFutures, kMaxAnchors];
      }
      self.clearAllAnchorsButton.hidden = (self.garFrame.anchors.count == 0);
      self.tapScreenLabel.hidden =
          (self.garFrame.anchors.count + self.activeFutures >= kMaxAnchors);
      self.anchorModeSelector.hidden = NO;
      break;
    }
    case LocalizationStatePretracking:
      self.statusLabel.text = kPretrackingMessage;
      break;
    case LocalizationStateLocalizing:
      self.statusLabel.text = kLocalizationTip;
      self.tapScreenLabel.hidden = YES;
      self.clearAllAnchorsButton.hidden = YES;
      break;
    case LocalizationStateFailed:
      self.statusLabel.text = kLocalizationFailureMessage;
      self.tapScreenLabel.hidden = YES;
      self.clearAllAnchorsButton.hidden = YES;
      self.anchorModeSelector.hidden = YES;
      break;
  }

  if (self.isStreetscapeGeometryEnabled != self.streetscapeGeometrySwitch.isOn) {
    self.isStreetscapeGeometryEnabled = self.streetscapeGeometrySwitch.isOn;
    NSError *error = nil;
    GARSessionConfiguration *configuration = [[GARSessionConfiguration alloc] init];
    configuration.geospatialMode = GARGeospatialModeEnabled;
    configuration.streetscapeGeometryMode = self.isStreetscapeGeometryEnabled
                                                ? GARStreetscapeGeometryModeEnabled
                                                : GARStreetscapeGeometryModeDisabled;
    [self.garSession setConfiguration:configuration error:&error];
    if (self.isStreetscapeGeometryEnabled) {
      self.streetscapeGeometryParentNode.hidden = NO;
    } else {
      self.streetscapeGeometryParentNode.hidden = YES;
    }
  }

  for (SCNNode *node in self.planeNodes) {
    if (node) {
      node.hidden = self.isStreetscapeGeometryEnabled;
    }
  }
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

- (NSString *)rooftopStateString:(GARRooftopAnchorState)rooftopAnchorState {
  switch (rooftopAnchorState) {
    case GARRooftopAnchorStateNone:
      return @"None";
    case GARRooftopAnchorStateSuccess:
      return @"Success";
    case GARRooftopAnchorStateErrorInternal:
      return @"ErrorInternal";
    case GARRooftopAnchorStateErrorNotAuthorized:
      return @"ErrorNotAuthorized";
    case GARRooftopAnchorStateErrorUnsupportedLocation:
      return @"UnsupportedLocation";
    default:
      return @"Unknown";
  }
}

- (SCNNode *)streetscapeGeometryToSCNNode:(GARStreetscapeGeometry *)streetscapeGeometry {
  GARMesh *mesh = streetscapeGeometry.mesh;
  NSData *data = [NSData dataWithBytes:mesh.vertices length:mesh.vertexCount * sizeof(GARVertex)];

  // Vertices are stored in a packed float array.
  SCNGeometrySource *vertices =
      [SCNGeometrySource geometrySourceWithData:data
                                       semantic:SCNGeometrySourceSemanticVertex
                                    vectorCount:mesh.vertexCount
                                floatComponents:YES
                            componentsPerVector:3
                              bytesPerComponent:4
                                     dataOffset:0
                                     dataStride:12];

  NSData *triangleData = [NSData dataWithBytes:mesh.triangles
                                        length:mesh.triangleCount * sizeof(GARIndexTriangle)];
  SCNGeometryElement *indices =
      [SCNGeometryElement geometryElementWithData:triangleData
                                    primitiveType:SCNGeometryPrimitiveTypeTriangles
                                   primitiveCount:mesh.triangleCount
                                    bytesPerIndex:4];

  SCNGeometry *geometry = [SCNGeometry geometryWithSources:@[ vertices ] elements:@[ indices ]];

  SCNMaterial *material = geometry.materials.firstObject;
  if (streetscapeGeometry.type == GARStreetscapeGeometryTypeTerrain) {
    material.diffuse.contents = [UIColor colorWithRed:0 green:.5 blue:0 alpha:.7];
    material.doubleSided = NO;
  } else {
    NSArray<UIColor *> *buildingColors = @[
      [UIColor colorWithRed:.7 green:0. blue:.7 alpha:.8],
      [UIColor colorWithRed:.7 green:.7 blue:0 alpha:.8],
      [UIColor colorWithRed:.0 green:.7 blue:.7 alpha:.8],
    ];

    UIColor *randomColor = buildingColors[arc4random() % buildingColors.count];
    material.diffuse.contents = randomColor;
    material.blendMode = SCNBlendModeReplace;
    material.doubleSided = NO;
  }

  SCNGeometry *lineGeometry = [SCNGeometry geometryWithSources:@[ vertices ] elements:@[ indices ]];
  SCNMaterial *lineMaterial = lineGeometry.materials.firstObject;
  lineMaterial.fillMode = SCNFillModeLines;
  lineMaterial.diffuse.contents = [UIColor blackColor];
  SCNNode *node = [SCNNode nodeWithGeometry:geometry];
  [node addChildNode:[SCNNode nodeWithGeometry:lineGeometry]];
  return node;
}

- (void)renderStreetscapeGeometries {
  NSArray<GARStreetscapeGeometry *> *streetscapeGeometries = [self.garFrame streetscapeGeometries];
  if (streetscapeGeometries) {
    self.streetscapeGeometryParentNode.hidden =
        (self.localizationState != LocalizationStateLocalized);

    // Add new streetscapeGeometries which are appearing for the first time.
    for (GARStreetscapeGeometry *streetscapeGeometry in streetscapeGeometries) {
      NSUUID *identifier = streetscapeGeometry.identifier;
      if (![self.streetscapeGeometryNodes objectForKey:identifier]) {
        SCNNode *node = [self streetscapeGeometryToSCNNode:streetscapeGeometry];
        [self.streetscapeGeometryNodes setObject:node forKey:identifier];
        [self.streetscapeGeometryParentNode addChildNode:node];
      }

      SCNNode *node = [self.streetscapeGeometryNodes objectForKey:streetscapeGeometry.identifier];
      node.simdTransform = streetscapeGeometry.meshTransform;

      // Hide geometries if not actively tracking.
      if (streetscapeGeometry.trackingState == GARTrackingStateTracking) {
        node.hidden = NO;
      } else if (streetscapeGeometry.trackingState == GARTrackingStatePaused) {
        node.hidden = YES;
      } else {
        // Removed permanently stopped geometries.
        [self.streetscapeGeometryNodes[identifier] removeFromParentNode];
        [self.streetscapeGeometryNodes removeObjectForKey:identifier];
      }
    }
  }
}

- (void)updateWithGARFrame:(GARFrame *)garFrame {
  self.garFrame = garFrame;
  [self updateLocalizationState];
  [self updateMarkerNodes];
  [self updateTrackingLabel];
  [self updateStatusLabelAndButtons];
  [self renderStreetscapeGeometries];
}

- (void)addAnchorWithCoordinate:(CLLocationCoordinate2D)coordinate
                       altitude:(CLLocationDistance)altitude
             eastUpSouthQTarget:(simd_quatf)eastUpSouthQTarget
                     shouldSave:(BOOL)shouldSave {
  // The return value of |createAnchorWithCoordinate:altitude:eastUpSouthQAnchor:error:| is just the
  // first snapshot of the anchor (which is immutable). Use the updated snapshots in
  // |GARFrame.anchors| to get updated values on a frame-by-frame basis.
  NSError *error = nil;
  GARAnchor *anchor = [self.garSession createAnchorWithCoordinate:coordinate
                                                         altitude:altitude
                                               eastUpSouthQAnchor:eastUpSouthQTarget
                                                            error:&error];
  if (error) {
    NSLog(@"Error adding anchor: %@", error);
    return;
  }

  [self addMarkerNode:anchor anchorType:AnchorTypeGeospatial];
  if (shouldSave) {
    [self saveAnchor:coordinate
        eastUpSouthQTarget:eastUpSouthQTarget
                anchorType:AnchorTypeGeospatial
                  altitude:altitude];
  }
}

- (void)addTerrainAnchorWithCoordinate:(CLLocationCoordinate2D)coordinate
                    eastUpSouthQTarget:(simd_quatf)eastUpSouthQTarget
                            shouldSave:(BOOL)shouldSave {
  NSError *error = nil;
  [self.garSession
      createAnchorWithCoordinate:coordinate
            altitudeAboveTerrain:0
              eastUpSouthQAnchor:eastUpSouthQTarget
               completionHandler:^void(GARAnchor *anchor, GARTerrainAnchorState state) {
                 if (state != GARTerrainAnchorStateSuccess) {
                   self.resolveAnchorErrorMessage =
                       [NSString stringWithFormat:@"Error resolving terrain anchor: %@",
                                                  [self terrainStateString:state]];
                 } else {
                   self.activeFutures--;
                   [self addMarkerNode:anchor anchorType:AnchorTypeTerrain];

                   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     if (shouldSave) {
                       [self saveAnchor:coordinate
                           eastUpSouthQTarget:eastUpSouthQTarget
                                   anchorType:AnchorTypeTerrain
                                     altitude:-1.0];
                     }
                   });
                 }
               }
                           error:&error];

  if (error) {
    NSLog(@"Error adding anchor: %@", error);
    if (error.code == GARSessionErrorCodeResourceExhausted) {
      self.statusLabel.text = @"Too many terrain and rooftop anchors have already been held. Clear "
                              @"all anchors to create new ones.";
    }
    return;
  }
  self.activeFutures++;
}

- (void)addRooftopAnchorWithCoordinate:(CLLocationCoordinate2D)coordinate
                    eastUpSouthQTarget:(simd_quatf)eastUpSouthQTarget
                            shouldSave:(BOOL)shouldSave {
  NSError *error = nil;
  [self.garSession
      createAnchorWithCoordinate:coordinate
            altitudeAboveRooftop:0
              eastUpSouthQAnchor:eastUpSouthQTarget
               completionHandler:^void(GARAnchor *anchor, GARRooftopAnchorState state) {
                 self.activeFutures--;
                 if (state != GARRooftopAnchorStateSuccess) {
                   self.resolveAnchorErrorMessage =
                       [NSString stringWithFormat:@"Error resolving rooftop anchor: %@",
                                                  [self rooftopStateString:state]];
                 } else {
                   [self addMarkerNode:anchor anchorType:AnchorTypeRooftop];
                   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     if (shouldSave) {
                       [self saveAnchor:coordinate
                           eastUpSouthQTarget:eastUpSouthQTarget
                                   anchorType:AnchorTypeRooftop
                                     altitude:-1.0];
                     }
                   });
                 }
               }
                           error:&error];

  if (error) {
    NSLog(@"Error adding anchor: %@", error);
    if (error.code == GARSessionErrorCodeResourceExhausted) {
      self.statusLabel.text = @"Too many terrain and rooftop anchors have already been held. Clear "
                              @"all anchors to create new ones.";
    }
    return;
  }
  self.activeFutures++;
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
  if (self.garFrame.anchors.count + self.activeFutures >= kMaxAnchors) {
    return;
  }

  NSError *error = nil;
  UITouch *touch = [[touches allObjects] firstObject];
  CGPoint touchLocation = [touch locationInView:self.scnView];
  ARRaycastQuery *raycastQuery =
      [self.scnView raycastQueryFromPoint:touchLocation
                           allowingTarget:ARRaycastTargetExistingPlaneGeometry
                                alignment:ARRaycastTargetAlignmentHorizontal];

  if (self.streetscapeGeometrySwitch.isOn) {
    NSArray<GARStreetscapeGeometryRaycastResult *> *results =
        [self.garSession raycastStreetscapeGeometry:raycastQuery.origin
                                          direction:raycastQuery.direction
                                              error:&error];
    if (error) {
      NSLog(@"Error raycasting StreetscapeGeometry: %@", error);
      return;
    }

    if (results.count == 0) {
      return;
    }
    GARStreetscapeGeometryRaycastResult *result = results[0];
    GARGeospatialTransform *geospatialTransform =
        [self.garSession geospatialTransformFromTransform:result.worldTransform error:&error];
    if (error) {
      NSLog(@"Error adding convert transform to GARGeospatialTransform: %@", error);
      return;
    }

    switch (self.anchorMode) {
      case AnchorTypeGeospatial: {
        GARAnchor *anchor =
            [self.garSession createAnchorOnStreetscapeGeometry:result.streetscapeGeometry
                                                     transform:result.worldTransform
                                                         error:&error];
        if (error) {
          NSLog(@"Error adding streetscape geometry anchor: %@", error);
          return;
        }
        // Don't save anchors on StreetscapeGeometry between sessions.
        [self addMarkerNode:anchor anchorType:AnchorTypeGeospatial];
        return;
      }
      case AnchorTypeTerrain:
        // Terrain anchors will be positioned using both the Streetscape Geometry terrain data as
        // well as any local ARKit planes, and may appear in a different location to geospatial
        // anchors placed at the same location on the terrain mesh.
        [self addTerrainAnchorWithCoordinate:geospatialTransform.coordinate
                          eastUpSouthQTarget:simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f)
                                  shouldSave:YES];
        return;
      case AnchorTypeRooftop:
        [self addRooftopAnchorWithCoordinate:geospatialTransform.coordinate
                          eastUpSouthQTarget:simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f)
                                  shouldSave:YES];
        return;
    }

  } else {
    NSArray<ARRaycastResult *> *rayCastResults = [self.arSession raycast:raycastQuery];
    if (rayCastResults.count == 0) {
      return;
    }

    ARRaycastResult *result = rayCastResults.firstObject;
    GARGeospatialTransform *geospatialTransform =
        [self.garSession geospatialTransformFromTransform:result.worldTransform error:&error];
    if (error) {
      NSLog(@"Error adding convert transform to GARGeospatialTransform: %@", error);
      return;
    }

    switch (self.anchorMode) {
      case AnchorTypeGeospatial:
        [self addAnchorWithCoordinate:geospatialTransform.coordinate
                             altitude:geospatialTransform.altitude
                   eastUpSouthQTarget:geospatialTransform.eastUpSouthQTarget
                           shouldSave:YES];
        return;
      case AnchorTypeTerrain:
        [self addTerrainAnchorWithCoordinate:geospatialTransform.coordinate
                          eastUpSouthQTarget:geospatialTransform.eastUpSouthQTarget
                                  shouldSave:YES];
        return;
      case AnchorTypeRooftop:
        [self addRooftopAnchorWithCoordinate:geospatialTransform.coordinate
                          eastUpSouthQTarget:geospatialTransform.eastUpSouthQTarget
                                  shouldSave:YES];
        return;
    }
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
- (void)renderer:(id<SCNSceneRenderer>)renderer
      didAddNode:(SCNNode *)node
       forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    ARSCNPlaneGeometry *planeGeometry =
        [ARSCNPlaneGeometry planeGeometryWithDevice:self.scnView.device];
    [planeGeometry updateFromPlaneGeometry:planeAnchor.geometry];
    planeGeometry.materials.firstObject.diffuse.contents = [UIColor colorWithRed:0.0f
                                                                           green:0.0f
                                                                            blue:1.0f
                                                                           alpha:0.7f];
    SCNNode *planeNode = [SCNNode nodeWithGeometry:planeGeometry];

    [node addChildNode:planeNode];
    [self.planeNodes addObject:planeNode];
  }
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
    didUpdateNode:(SCNNode *)node
        forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    SCNNode *planeNode = node.childNodes.firstObject;
    [(ARSCNPlaneGeometry *)planeNode.geometry updateFromPlaneGeometry:planeAnchor.geometry];
  }
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
    didRemoveNode:(SCNNode *)node
        forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    SCNNode *planeNode = node.childNodes.firstObject;
    [planeNode removeFromParentNode];
    [self.planeNodes removeObject:planeNode];
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
