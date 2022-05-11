/*
 * Copyright 2018 Google LLC. All Rights Reserved.
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

#import "ExampleViewController.h"

#import "CloudAnchorManager.h"

#import <dispatch/dispatch.h>

#import <ARKit/ARKit.h>
#import <ModelIO/ModelIO.h>
#import <SceneKit/ModelIO.h>

#import <ARCore/ARCore.h>

typedef NS_ENUM(NSInteger, HelloARState) {
  HelloARStateDefault,
  HelloARStateCreatingRoom,
  HelloARStateRoomCreated,
  HelloARStateHosting,
  HelloARStateHostingFinished,
  HelloARStateEnterRoomCode,
  HelloARStateResolving,
  HelloARStateResolvingFinished,
  HelloARStateCloudAnchorManagerInitFail
};

static NSString * const kPrivacyNoticeKey = @"PrivacyNoticeAccepted";
static NSString * const kPrivacyAlertTitle = @"Experience it together";
static NSString * const kPrivacyAlertMessage = @"To power this session, Google will process visual "
    "data from your camera.";
static NSString * const kPrivacyAlertContinueButtonText = @"Start now";
static NSString * const kPrivacyAlertLearnMoreButtonText = @"Learn more";
static NSString * const kPrivacyAlertBackButtonText = @"Not now";
static NSString * const kPrivacyAlertLinkURL =
    @"https://developers.google.com/ar/data-privacy";

@interface ExampleViewController () <ARSCNViewDelegate,
                                     CloudAnchorManagerDelegate,
                                     GARSessionDelegate>

@property(nonatomic, strong) ARAnchor *arAnchor;
@property(nonatomic, strong) GARAnchor *garAnchor;
@property(nonatomic, strong) NSTimer *resolveTimer;
// Node representing resolved GARAnchor. Updated when anchor changes.
@property(nonatomic, strong) SCNNode *resolvedAnchorNode;

@property(nonatomic, assign) HelloARState state;

@property(nonatomic, strong) NSString *roomCode;
@property(nonatomic, strong) NSString *message;

// Cloud Anchor Manager manages interaction between Firebase, GARSession, and ARSession.
@property(nonatomic, strong) CloudAnchorManager *cloudAnchorManager;

@end

@implementation ExampleViewController

- (void)dealloc {
  if (_resolveTimer) {
    [_resolveTimer invalidate];
  }
}

#pragma mark - Overriding UIViewController

- (BOOL)prefersStatusBarHidden {
  return YES;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  [self.messageLabel setNumberOfLines:3];

  self.cloudAnchorManager = [[CloudAnchorManager alloc] initWithARSceneView:self.sceneView];
  if (self.cloudAnchorManager == nil) {
    [self enterState:HelloARStateCloudAnchorManagerInitFail];
    return;
  }

  self.cloudAnchorManager.delegate = self;
  self.sceneView.delegate = self;

  [self enterState:HelloARStateDefault];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (touches.count < 1 || self.state != HelloARStateRoomCreated) {
    return;
  }

  UITouch *touch = [[touches allObjects] firstObject];
  CGPoint touchLocation = [touch locationInView:self.sceneView];

  NSArray *hitTestResults =
      [self.sceneView hitTest:touchLocation
                        types:ARHitTestResultTypeExistingPlaneUsingExtent |
                              ARHitTestResultTypeEstimatedHorizontalPlane];

  if (hitTestResults.count > 0) {
    ARHitTestResult *result = [hitTestResults firstObject];
    [self addAnchorWithTransform:result.worldTransform];
  }
}

#pragma mark - Anchor Hosting / Resolving

- (void)resolveAnchorWithRoomCode:(NSString *)roomCode {
  self.roomCode = roomCode;
  [self enterState:HelloARStateResolving];
  [self.cloudAnchorManager resolveAnchorWithRoomCode:roomCode completion:^(GARAnchor *anchor) {
    self.garAnchor = anchor;
  }];
}

- (void)addAnchorWithTransform:(matrix_float4x4)transform {
  self.arAnchor = [[ARAnchor alloc] initWithTransform:transform];
  [self.sceneView.session addAnchor:self.arAnchor];

  self.garAnchor = [self.cloudAnchorManager hostCloudAnchor:self.arAnchor error:nil];
  [self enterState:HelloARStateHosting];
}


# pragma mark - Actions

- (IBAction)hostButtonPressed {
  if (self.state == HelloARStateDefault) {
    __weak ExampleViewController *weakSelf = self;
    [self checkPrivacyNotice:^(BOOL shouldContinue) {
      if (shouldContinue) {
        [weakSelf enterState:HelloARStateCreatingRoom];
        [weakSelf.cloudAnchorManager createRoom];
      }
    }];
  } else {
    [self enterState:HelloARStateDefault];
  }
}

- (IBAction)resolveButtonPressed {
  if (self.state == HelloARStateDefault) {
    __weak ExampleViewController *weakSelf = self;
    [self checkPrivacyNotice:^(BOOL shouldContinue) {
      if (shouldContinue) {
        [weakSelf enterState:HelloARStateEnterRoomCode];
      }
    }];
  } else {
    [self enterState:HelloARStateDefault];
  }
}

#pragma mark - CloudAnchorManagerDelegate

- (void)cloudAnchorManager:(CloudAnchorManager *)manager createdRoom:(NSString *)roomCode {
  self.roomCode = roomCode;
  [self enterState:HelloARStateRoomCreated];
}

- (void)cloudAnchorManager:(CloudAnchorManager *)manager
    failedToCreateRoomWithError:(NSError *)error {
  [self enterState:HelloARStateDefault];
}

- (void)cloudAnchorManager:(CloudAnchorManager *)manager
            didUpdateFrame:(GARFrame *)garFrame
                     error:(NSError *)error {
  if (error) {
    self.message =
        [NSString stringWithFormat:
                      @"garFrame is returned as a nil in "
                      @"CloudAnchorManager:sessioin:session:didUPdateFrame: Error description: %@",
                      [error localizedDescription]];
    [self updateMessageLabel];
    return;
  }
  for (GARAnchor *garAnchor in garFrame.updatedAnchors) {
    if ([garAnchor isEqual:self.garAnchor] && self.resolvedAnchorNode) {
      self.resolvedAnchorNode.simdTransform = garAnchor.transform;
      self.resolvedAnchorNode.hidden = !garAnchor.hasValidTransform;
    }
  }
}

- (void)cloudAnchorManager:(CloudAnchorManager *)manager
    resolveCloudAnchorReturnNilWithError:(NSError *)error {
  self.message = [NSString
      stringWithFormat:@"Resolved Cloud Anchor returned nil"
                       @"GARSession:resolveCloudAnchorWithIdentifier Error description: %@",
                       [error localizedDescription]];
  [self updateMessageLabel];
  self.garAnchor = nil;
  [self enterState:HelloARStateResolvingFinished];
}

#pragma mark - GARSessionDelegate

- (void)session:(GARSession *)session didHostAnchor:(GARAnchor *)anchor {
  if (self.state != HelloARStateHosting || ![anchor isEqual:self.garAnchor]) {
    return;
  }
  self.garAnchor = anchor;
  [self.cloudAnchorManager updateRoom:self.roomCode withAnchor:anchor];
  [self enterState:HelloARStateHostingFinished];
}

- (void)session:(GARSession *)session didFailToHostAnchor:(GARAnchor *)anchor {
  if (self.state != HelloARStateHosting || ![anchor isEqual:self.garAnchor]) {
    return;
  }
  self.garAnchor = anchor;
  [self enterState:HelloARStateHostingFinished];
}

- (void)session:(GARSession *)session didResolveAnchor:(GARAnchor *)anchor {
  if (self.state != HelloARStateResolving || ![anchor isEqual:self.garAnchor]) {
    return;
  }

  self.garAnchor = anchor;
  self.resolvedAnchorNode = [self andyNode];
  self.resolvedAnchorNode.simdTransform = anchor.transform;
  [self.sceneView.scene.rootNode addChildNode:self.resolvedAnchorNode];
  [self enterState:HelloARStateResolvingFinished];
}

- (void)session:(GARSession *)session didFailToResolveAnchor:(GARAnchor *)anchor {
  if (self.state != HelloARStateResolving || ![anchor isEqual:self.garAnchor]) {
    return;
  }
  self.garAnchor = anchor;
  [self enterState:HelloARStateResolvingFinished];
}

# pragma mark - Helper Methods

- (BOOL)privacyNoticeAccepted {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kPrivacyNoticeKey];
}

- (void)setPrivacyNoticeAccepted:(BOOL)accepted {
  [[NSUserDefaults standardUserDefaults] setBool:accepted forKey:kPrivacyNoticeKey];
}

- (void)runSession {
  ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc] init];
  [configuration setWorldAlignment:ARWorldAlignmentGravity];
  [configuration setPlaneDetection:ARPlaneDetectionHorizontal];

  [self.sceneView.session runWithConfiguration:configuration];
}

- (void)checkPrivacyNotice:(void (^)(BOOL shouldContinue))completion {
  __weak ExampleViewController *weakSelf = self;
  void (^innerCompletion)(BOOL shouldContinue) = ^(BOOL shouldContinue) {
    if (shouldContinue) {
      [weakSelf setPrivacyNoticeAccepted:YES];
      [weakSelf runSession];
    }
    completion(shouldContinue);
  };

  if ([self privacyNoticeAccepted]) {
    innerCompletion(YES);
    return;
  }

  UIAlertController *alertController =
      [UIAlertController alertControllerWithTitle:kPrivacyAlertTitle
                                          message:kPrivacyAlertMessage
                                   preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction *okAction =
      [UIAlertAction actionWithTitle:kPrivacyAlertContinueButtonText
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
        innerCompletion(YES);
      }];
  UIAlertAction *learnMoreAction =
      [UIAlertAction actionWithTitle:kPrivacyAlertLearnMoreButtonText
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kPrivacyAlertLinkURL]
                                           options:@{}
                                 completionHandler:nil];
        innerCompletion(NO);
      }];
  UIAlertAction *cancelAction =
      [UIAlertAction actionWithTitle:kPrivacyAlertBackButtonText
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
        innerCompletion(NO);
      }];
  [alertController addAction:okAction];
  [alertController addAction:learnMoreAction];
  [alertController addAction:cancelAction];
  [self presentViewController:alertController animated:NO completion:^{}];
}

- (void)resolveTimerFired {
  if (self.state == HelloARStateResolving) {
    self.message = @"Still resolving the anchor. Please make sure you're looking at where the "
        "Cloud Anchor was hosted. Or, try to re-join the room.";
    [self updateMessageLabel];
  }
}

- (void)updateMessageLabel {
  [self.messageLabel setText:self.message];
  self.roomCodeLabel.text = [NSString stringWithFormat:@"Room: %@", self.roomCode];
}

- (void)toggleButton:(UIButton *)button enabled:(BOOL)enabled title:(NSString *)title {
  button.enabled = enabled;
  [button setTitle:title forState:UIControlStateNormal];
}

- (NSString *)cloudStateString:(GARCloudAnchorState)cloudState {
  switch (cloudState) {
    case GARCloudAnchorStateNone:
      return @"None";
    case GARCloudAnchorStateSuccess:
      return @"Success";
    case GARCloudAnchorStateErrorInternal:
      return @"ErrorInternal";
    case GARCloudAnchorStateTaskInProgress:
      return @"TaskInProgress";
    case GARCloudAnchorStateErrorNotAuthorized:
      return @"ErrorNotAuthorized";
    case GARCloudAnchorStateErrorResourceExhausted:
      return @"ErrorResourceExhausted";
    case GARCloudAnchorStateErrorHostingDatasetProcessingFailed:
      return @"ErrorHostingDatasetProcessingFailed";
    case GARCloudAnchorStateErrorCloudIdNotFound:
      return @"ErrorCloudIdNotFound";
    case GARCloudAnchorStateErrorResolvingSdkVersionTooNew:
      return @"ErrorResolvingSdkVersionTooNew";
    case GARCloudAnchorStateErrorResolvingSdkVersionTooOld:
      return @"ErrorResolvingSdkVersionTooOld";
    case GARCloudAnchorStateErrorHostingServiceUnavailable:
      return @"ErrorHostingServiceUnavailable";
    default:
      return @"Unknown";
  }
}

- (void)showRoomCodeDialog {
  UIAlertController *alertController =
      [UIAlertController alertControllerWithTitle:@"ENTER ROOM CODE"
                                          message:@""
                                   preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction *okAction =
      [UIAlertAction actionWithTitle:@"OK"
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
                               NSString *roomCode = alertController.textFields[0].text;
                               if ([roomCode length] == 0) {
                                 [self enterState:HelloARStateDefault];
                               } else {
                                 [self resolveAnchorWithRoomCode:roomCode];
                               }
                             }];
  UIAlertAction *cancelAction =
      [UIAlertAction actionWithTitle:@"CANCEL"
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
                               [self enterState:HelloARStateDefault];
                             }];
  [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.keyboardType = UIKeyboardTypeNumberPad;
  }];
  [alertController addAction:okAction];
  [alertController addAction:cancelAction];
  [self presentViewController:alertController animated:NO completion:^{}];
}

- (void)enterState:(HelloARState)state {
  switch (state) {
    case HelloARStateCloudAnchorManagerInitFail:
      [self toggleButton:self.hostButton enabled:NO title:@"HOST disabled"];
      [self toggleButton:self.resolveButton enabled:NO title:@"RESOLVE disabled"];
      break;
    case HelloARStateDefault:
      if (self.arAnchor) {
        [self.sceneView.session removeAnchor:self.arAnchor];
        self.arAnchor = nil;
      }
      if (self.resolvedAnchorNode) {
        [self.resolvedAnchorNode removeFromParentNode];
        self.resolvedAnchorNode = nil;
      }
      if (self.garAnchor) {
        [self.cloudAnchorManager removeAnchor:self.garAnchor];
        self.garAnchor = nil;
      }
      if (self.state == HelloARStateCreatingRoom) {
        self.message = @"Failed to create room. Tap HOST or RESOLVE to begin.";
      } else {
        self.message = @"Tap HOST or RESOLVE to begin.";
      }
      if (self.state == HelloARStateEnterRoomCode) {
        [self dismissViewControllerAnimated:NO completion:^{}];
      } else if (self.state == HelloARStateResolving) {
        [self.cloudAnchorManager stopResolvingAnchorWithRoomCode:self.roomCode];
        if (self.resolveTimer) {
          [self.resolveTimer invalidate];
          self.resolveTimer = nil;
        }
      }
      [self toggleButton:self.hostButton enabled:YES title:@"HOST"];
      [self toggleButton:self.resolveButton enabled:YES title:@"RESOLVE"];
      self.roomCode = @"";
      break;
    case HelloARStateCreatingRoom:
      self.message = @"Creating room...";
      [self toggleButton:self.hostButton enabled:NO title:@"HOST"];
      [self toggleButton:self.resolveButton enabled:NO title:@"RESOLVE"];
      break;
    case HelloARStateRoomCreated:
      self.message = @"Tap on a plane to create anchor and host.";
      [self toggleButton:self.hostButton enabled:YES title:@"CANCEL"];
      [self toggleButton:self.resolveButton enabled:NO title:@"RESOLVE"];
      break;
    case HelloARStateHosting:
      self.message = @"Hosting anchor...";
      break;
    case HelloARStateHostingFinished:
      self.message =
          [NSString stringWithFormat:@"Finished hosting: %@",
                                     [self cloudStateString:self.garAnchor.cloudState]];
      break;
    case HelloARStateEnterRoomCode:
      [self showRoomCodeDialog];
      break;
    case HelloARStateResolving: {
      [self dismissViewControllerAnimated:NO completion:^{}];
      self.message = @"Resolving anchor...";
      [self toggleButton:self.hostButton enabled:NO title:@"HOST"];
      [self toggleButton:self.resolveButton enabled:YES title:@"CANCEL"];
      __weak ExampleViewController *weakSelf = self;
      self.resolveTimer = [NSTimer scheduledTimerWithTimeInterval:10.
                                                          repeats:NO
                                                            block:^(NSTimer *timer) {
                                                                    [weakSelf resolveTimerFired];
                                                                  }];
    } break;
    case HelloARStateResolvingFinished:
      if (self.resolveTimer) {
        [self.resolveTimer invalidate];
        self.resolveTimer = nil;
      }
      self.message =
          [NSString stringWithFormat:@"Finished resolving: %@",
                                     [self cloudStateString:self.garAnchor.cloudState]];
      break;
  }
  self.state = state;
  [self updateMessageLabel];
}

// Helper method to generate an SCNNode with Android geometry.
- (SCNNode *)andyNode {
  SCNScene *scene = [SCNScene sceneNamed:@"example.scnassets/andy.scn"];
  return [[scene rootNode] childNodeWithName:@"andy" recursively:NO];
}

#pragma mark - ARSCNViewDelegate

- (nullable SCNNode *)renderer:(id<SCNSceneRenderer>)renderer
                 nodeForAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]] == NO) {
    return [self andyNode];
  } else {
    return [[SCNNode alloc] init];
  }
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
      didAddNode:(SCNNode *)node
       forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    CGFloat width = planeAnchor.extent.x;
    CGFloat height = planeAnchor.extent.z;
    SCNPlane *plane = [SCNPlane planeWithWidth:width height:height];

    plane.materials.firstObject.diffuse.contents =
        [UIColor colorWithRed:0.0f green:0.0f blue:1.0f alpha:0.7f];

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

@end
