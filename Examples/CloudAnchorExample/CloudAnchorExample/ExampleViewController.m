/*
 * Copyright 2018 Google Inc. All Rights Reserved.
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

#import <dispatch/dispatch.h>

#import <ARKit/ARKit.h>
#import <FirebaseDatabase/FirebaseDatabase.h>
#import <ARCore/ARCore.h>
#import <ModelIO/ModelIO.h>
#import <SceneKit/ModelIO.h>

typedef NS_ENUM(NSInteger, HelloARState) {
  HelloARStateDefault,
  HelloARStateCreatingRoom,
  HelloARStateRoomCreated,
  HelloARStateHosting,
  HelloARStateHostingFinished,
  HelloARStateEnterRoomCode,
  HelloARStateResolving,
  HelloARStateResolvingFinished
};

@interface ExampleViewController () <ARSCNViewDelegate, ARSessionDelegate, GARSessionDelegate>

@property(nonatomic, strong) GARSession *gSession;

@property(nonatomic, strong) FIRDatabaseReference *firebaseReference;

@property(nonatomic, strong) ARAnchor *arAnchor;
@property(nonatomic, strong) GARAnchor *garAnchor;

@property(nonatomic, assign) HelloARState state;

@property(nonatomic, strong) NSString *roomCode;
@property(nonatomic, strong) NSString *message;

@end

@implementation ExampleViewController

#pragma mark - Overriding UIViewController

- (BOOL)prefersStatusBarHidden {
  return YES;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.firebaseReference = [[FIRDatabase database] reference];
  self.sceneView.delegate = self;
  self.sceneView.session.delegate = self;
  self.gSession = [GARSession sessionWithAPIKey:@"your-api-key"
                               bundleIdentifier:nil
                                          error:nil];
  self.gSession.delegate = self;
  self.gSession.delegateQueue = dispatch_get_main_queue();
  [self enterState:HelloARStateDefault];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];
  [configuration setWorldAlignment:ARWorldAlignmentGravity];
  [configuration setPlaneDetection:ARPlaneDetectionHorizontal];

  [self.sceneView.session runWithConfiguration:configuration];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  [self.sceneView.session pause];
}


- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (touches.count < 1 || self.state != HelloARStateRoomCreated) {
    return;
  }

  UITouch *touch = [[touches allObjects] firstObject];
  CGPoint touchLocation = [touch locationInView:self.sceneView];

  NSArray *hitTestResults =
  [self.sceneView hitTest:touchLocation
                    types:ARHitTestResultTypeExistingPlane |
                          ARHitTestResultTypeExistingPlaneUsingExtent |
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
  __weak ExampleViewController *weakSelf = self;
  [[[self.firebaseReference child:@"hotspot_list"] child:roomCode]
      observeEventType:FIRDataEventTypeValue
             withBlock:^(FIRDataSnapshot *snapshot) {

               dispatch_async(dispatch_get_main_queue(), ^{
                 ExampleViewController *strongSelf = weakSelf;
                 if (strongSelf == nil || strongSelf.state != HelloARStateResolving ||
                     ![strongSelf.roomCode isEqualToString:roomCode]) {
                   return;
                 }

                 NSString *anchorId = nil;
                 if ([snapshot.value isKindOfClass:[NSDictionary class]]) {
                   NSDictionary *value = (NSDictionary *)snapshot.value;
                   anchorId = value[@"hosted_anchor_id"];
                 }

                 if (anchorId) {
                   [[[strongSelf.firebaseReference child:@"hotspot_list"] child:roomCode]
                       removeAllObservers];
                   [strongSelf resolveAnchorWithIdentifier:anchorId];
                 }
               });
             }];
}

- (void)resolveAnchorWithIdentifier:(NSString *)identifier {
  // Now that we have the anchor ID from firebase, we resolve the anchor.
  // Success and failure of this call is handled by the delegate methods
  // session:didResolveAnchor and session:didFailToResolveAnchor appropriately.
  self.garAnchor = [self.gSession resolveCloudAnchorWithIdentifier:identifier error:nil];
}

- (void)addAnchorWithTransform:(matrix_float4x4)transform {
  self.arAnchor = [[ARAnchor alloc] initWithTransform:transform];
  [self.sceneView.session addAnchor:self.arAnchor];

  // To share an anchor, we call host anchor here on the ARCore session.
  // session:disHostAnchor: session:didFailToHostAnchor: will get called appropriately.
  self.garAnchor = [self.gSession hostCloudAnchor:self.arAnchor error:nil];
  [self enterState:HelloARStateHosting];
}


# pragma mark - Actions

- (IBAction)hostButtonPressed {
  if (self.state == HelloARStateDefault) {
    [self enterState:HelloARStateCreatingRoom];
    [self createRoom];
  } else {
    [self enterState:HelloARStateDefault];
  }
}

- (IBAction)resolveButtonPressed {
  if (self.state == HelloARStateDefault) {
    [self enterState:HelloARStateEnterRoomCode];
  } else {
    [self enterState:HelloARStateDefault];
  }
}

#pragma mark - GARSessionDelegate

- (void)session:(GARSession *)session didHostAnchor:(GARAnchor *)anchor {
  if (self.state != HelloARStateHosting || ![anchor isEqual:self.garAnchor]) {
    return;
  }
  self.garAnchor = anchor;
  [self enterState:HelloARStateHostingFinished];
  [[[[self.firebaseReference child:@"hotspot_list"] child:self.roomCode] child:@"hosted_anchor_id"]
      setValue:anchor.cloudIdentifier];
  long long timestampInteger = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
  NSNumber *timestamp = [NSNumber numberWithLongLong:timestampInteger];
  [[[[self.firebaseReference child:@"hotspot_list"] child:self.roomCode]
      child:@"updated_at_timestamp"] setValue:timestamp];
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
  self.arAnchor = [[ARAnchor alloc] initWithTransform:anchor.transform];
  [self.sceneView.session addAnchor:self.arAnchor];
  [self enterState:HelloARStateResolvingFinished];
}

- (void)session:(GARSession *)session didFailToResolveAnchor:(GARAnchor *)anchor {
  if (self.state != HelloARStateResolving || ![anchor isEqual:self.garAnchor]) {
    return;
  }
  self.garAnchor = anchor;
  [self enterState:HelloARStateResolvingFinished];
}


#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  // Forward ARKit's update to ARCore session
  [self.gSession update:frame error:nil];
}


# pragma mark - Helper Methods

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
    case GARCloudAnchorStateErrorServiceUnavailable:
      return @"ErrorServiceUnavailable";
    case GARCloudAnchorStateErrorHostingDatasetProcessingFailed:
      return @"ErrorHostingDatasetProcessingFailed";
    case GARCloudAnchorStateErrorCloudIdNotFound:
      return @"ErrorCloudIdNotFound";
    case GARCloudAnchorStateErrorResolvingSdkVersionTooNew:
      return @"ErrorResolvingSdkVersionTooNew";
    case GARCloudAnchorStateErrorResolvingSdkVersionTooOld:
      return @"ErrorResolvingSdkVersionTooOld";
    case GARCloudAnchorStateErrorResolvingLocalizationNoMatch:
      return @"ErrorResolvingLocalizationNoMatch";
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
    case HelloARStateDefault:
      if (self.arAnchor) {
        [self.sceneView.session removeAnchor:self.arAnchor];
        self.arAnchor = nil;
      }
      if (self.garAnchor) {
        [self.gSession removeAnchor:self.garAnchor];
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
        [[[self.firebaseReference child:@"hotspot_list"] child:self.roomCode] removeAllObservers];
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
    case HelloARStateResolving:
      [self dismissViewControllerAnimated:NO completion:^{}];
      self.message = @"Resolving anchor...";
      [self toggleButton:self.hostButton enabled:NO title:@"HOST"];
      [self toggleButton:self.resolveButton enabled:YES title:@"CANCEL"];
      break;
    case HelloARStateResolvingFinished:
      self.message =
          [NSString stringWithFormat:@"Finished resolving: %@",
                                     [self cloudStateString:self.garAnchor.cloudState]];
      break;
  }
  self.state = state;
  [self updateMessageLabel];
}

- (void)createRoom {
  __weak ExampleViewController *weakSelf = self;
  [[self.firebaseReference child:@"last_room_code"]
      runTransactionBlock:^FIRTransactionResult *(FIRMutableData *currentData) {
        ExampleViewController *strongSelf = weakSelf;

        NSNumber *roomNumber = currentData.value;

        if (!roomNumber || [roomNumber isEqual:[NSNull null]]) {
          roomNumber = @0;
        }

        NSInteger roomNumberInt = [roomNumber integerValue];
        roomNumberInt++;
        NSNumber *newRoomNumber = [NSNumber numberWithInteger:roomNumberInt];

        long long timestampInteger = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        NSNumber *timestamp = [NSNumber numberWithLongLong:timestampInteger];

        NSDictionary *room = @{
                              @"display_name" : [newRoomNumber stringValue],
                              @"updated_at_timestamp" : timestamp,
                              };

        [[[strongSelf.firebaseReference child:@"hotspot_list"]
            child:[newRoomNumber stringValue]] setValue:room];

        currentData.value = newRoomNumber;

        return [FIRTransactionResult successWithValue:currentData];
      } andCompletionBlock:^(NSError *error, BOOL committed, FIRDataSnapshot *snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (error) {
            [weakSelf roomCreationFailed];
          } else {
            [weakSelf roomCreated:[(NSNumber *)snapshot.value stringValue]];
          }
        });
      }];
}

- (void)roomCreated:(NSString *)roomCode {
  self.roomCode = roomCode;
  [self enterState:HelloARStateRoomCreated];
}

- (void)roomCreationFailed {
  [self enterState:HelloARStateDefault];
}

#pragma mark - ARSCNViewDelegate

- (nullable SCNNode *)renderer:(id<SCNSceneRenderer>)renderer
                 nodeForAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]] == NO) {
    SCNScene *scene = [SCNScene sceneNamed:@"example.scnassets/andy.scn"];
    return [[scene rootNode] childNodeWithName:@"andy" recursively:NO];
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
        [UIColor colorWithRed:0.0f green:0.0f blue:1.0f alpha:0.3f];

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
