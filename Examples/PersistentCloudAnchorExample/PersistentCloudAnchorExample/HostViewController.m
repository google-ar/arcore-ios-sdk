/*
 * Copyright 2020 Google LLC. All Rights Reserved.
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

#import "HostViewController.h"

#import "FeatureMapQualityBars.h"
#import "FeatureMapQualityRing.h"
#import "HostViewController+Alert.h"

static float const kFeatureMapQualityThreshold = 0.6;
static float const kRadius = 0.2;
static float const kPlaneColor[] = {0.f, 0.f, 1.0f, 0.7f};
static float const kMaxDistance = 10;
static int const kSecToMilliseconds = 1000;
static NSString *const kDebugMessagePrefix = @"Debug panel\n";

@interface HostViewController () <ARSCNViewDelegate, CloudAnchorManagerDelegate, GARSessionDelegate>

@property(nonatomic) NSMutableArray<SCNNode *> *qualityBars;
@property(nonatomic) FeatureMapQualityBars *featureMapQualityBars;
@property(nonatomic) BOOL anchorPlaced;
@property(nonatomic) BOOL hitHorizontalPlane;
@property(nonatomic) NSUUID *anchorIdentifier;
@property(nonatomic) simd_float4x4 cameraTransform;
@property(nonatomic) NSDate *hostBeginDate;

@end

#pragma mark - Overriding UIViewController

@implementation HostViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  [self.messageLabel setNumberOfLines:3];
  [self.debugLabel setNumberOfLines:3];
  _hitHorizontalPlane = YES;
  self.cloudAnchorManager = [[CloudAnchorManager alloc] initWithARSession:self.sceneView.session];
  self.cloudAnchorManager.delegate = self;
  self.sceneView.delegate = self;
  [self runSession];
  [self enterState:HostStateDefault];
}

// Create an anchor using a hit test with plane.
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  if (touches.count < 1 || self.state != HostStateDefault) {
    return;
  }
  UITouch *touch = [[touches allObjects] firstObject];
  CGPoint touchLocation = [touch locationInView:self.sceneView];
  ARHitTestResultType hitTestResultTypes =
      ARHitTestResultTypeExistingPlaneUsingExtent | ARHitTestResultTypeEstimatedHorizontalPlane;
  if (@available(iOS 11.3, *)) {
    hitTestResultTypes = hitTestResultTypes | ARHitTestResultTypeEstimatedVerticalPlane;
  }
  NSArray<ARHitTestResult *> *hitTestResults = [self.sceneView hitTest:touchLocation
                                                                 types:hitTestResultTypes];

  if (hitTestResults.count > 0) {
    ARHitTestResult *result = [hitTestResults firstObject];
    if ([result.anchor isKindOfClass:[ARPlaneAnchor class]]) {
      ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)result.anchor;
      self.hitHorizontalPlane = planeAnchor.alignment == ARPlaneAnchorAlignmentHorizontal;
    }

    float angle = 0;
    if (self.hitHorizontalPlane) {
      // Rotate anchor around y axis to face user.
      // Compute angle between camera view ray and anchor's z axis.
      simd_float4x4 anchorTCamera =
          simd_mul(simd_inverse(result.worldTransform), self.cameraTransform);
      float x = anchorTCamera.columns[3][0];
      // TODO(b/251453188): Fix unused variable
      float __unused y = anchorTCamera.columns[3][1];
      float z = anchorTCamera.columns[3][2];
      // Angle from the z axis, measured counterclockwise.
      float angle = atan2f(x, z);
      angle = z > 0 ? angle : angle + M_PI;
    }
    SCNMatrix4 rotation = SCNMatrix4MakeRotation(angle, 0, 1, 0);
    matrix_float4x4 rotateAnchor = simd_mul(result.worldTransform, SCNMatrix4ToMat4(rotation));
    [self addAnchorWithTransform:rotateAnchor];
  }
  [self enterState:HostStateAnchorCreated];
  self.anchorPlaced = YES;
}

#pragma mark - Anchor Hosting

- (void)addAnchorWithTransform:(matrix_float4x4)transform {
  self.arAnchor = [[ARAnchor alloc] initWithTransform:transform];
  self.anchorIdentifier = self.arAnchor.identifier;
  [self.sceneView.session addAnchor:self.arAnchor];
}

#pragma mark - Helper Methods

- (void)runSession {
  ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc] init];
  [configuration setWorldAlignment:ARWorldAlignmentGravity];
  if (@available(iOS 11.3, *)) {
    [configuration setPlaneDetection:ARPlaneDetectionHorizontal | ARPlaneDetectionVertical];
  } else {
    [configuration setPlaneDetection:ARPlaneDetectionHorizontal];
  }

  [self.sceneView.session runWithConfiguration:configuration];
}

- (void)enterState:(HostState)state {
  switch (state) {
    case HostStateDefault:
      self.message = @"Tap to place an object.";
      self.debugMessage = @"Tap a vertical or horizontal plane...";
      break;
    case HostStateAnchorCreated:
      self.message = @"Save the object here by capturing it from all sides";
      self.debugMessage = @"Average mapping quality: ";
      break;
    case HostStateHosting:
      self.message = @"Processing...";
      self.debugMessage = @"GARFeatureMapQuality average has reached Sufficient-Good, triggering "
                          @"hostCloudAnchor:TTLDays:error";
      break;
    case HostStateFinished:
      self.message = [NSString
          stringWithFormat:@"Finished: %@", [self cloudStateString:self.garAnchor.cloudState]];
      self.debugMessage =
          [NSString stringWithFormat:@"Anchor %@ created", self.garAnchor.cloudIdentifier];
      break;
  }
  self.state = state;
  [self updateMessageLabel];
}

- (void)updateMessageLabel {
  [self.messageLabel setText:self.message];
  [self.debugLabel setText:[kDebugMessagePrefix stringByAppendingString:self.debugMessage]];
}

- (void)updateDebugMessageLabel:(int)quality {
  NSString *featureMapQualityMessage =
      [NSString stringWithFormat:[self.debugMessage stringByAppendingString:@"%@"],
                                 [self getStringFromQuality:quality]];
  [self.debugLabel setText:[kDebugMessagePrefix stringByAppendingString:featureMapQualityMessage]];
}

- (NSString *)getStringFromQuality:(int)quality {
  switch (quality) {
    case 1:
      return @"Sufficient";
    case 2:
      return @"Good";
    default:
      return @"Insufficient";
  }
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
    case GARCloudAnchorStateErrorHostingServiceUnavailable:
      return @"ErrorHostingServiceUnavailable";
    default:
      return @"Unknown";
  }
}

// Helper method to generate an SCNNode with Android geometry.
// Note: Horizontal and vertical planes have slightly different hosting UIs for better
// visualization.
- (SCNNode *)cloudAnchorNode {
  SCNScene *scene = [SCNScene sceneNamed:@"example.scnassets/cloud_anchor.scn"];
  SCNNode *anchorNode = [[scene rootNode] childNodeWithName:@"cloud_anchor" recursively:NO];
  // Adaptive UI is drawn here, using the values from the mapping quality API.
  FeatureMapQualityRing *ringNode =
      [[FeatureMapQualityRing alloc] initWithRadius:kRadius isHorizontal:self.hitHorizontalPlane];
  [anchorNode addChildNode:ringNode];
  self.featureMapQualityBars =
      [[FeatureMapQualityBars alloc] initWithRadius:kRadius isHorizontal:self.hitHorizontalPlane];
  [anchorNode addChildNode:self.featureMapQualityBars];
  return anchorNode;
}

#pragma mark - CloudAnchorManagerDelegate

- (void)cloudAnchorManager:(CloudAnchorManager *)manager
            didUpdateFrame:(GARFrame *)garFrame
                  tracking:(BOOL)tracking
           cameraTransform:(simd_float4x4)cameraTransform
                   anchors:(NSArray<ARAnchor *> *)anchors
         featureMapQuality:(int)featureMapQuality {
  if (self.state != HostStateAnchorCreated || !tracking) {
    return;
  }
  self.cameraTransform = cameraTransform;
  [self updateDebugMessageLabel:featureMapQuality];
  // Host Anchor automatically once the feature map quality exceeds the desired threshold.
  float avg = [self.featureMapQualityBars featureMapQualityAvg];
  NSLog(@"History of average mapping quality calls: %f", avg);
  if (avg > kFeatureMapQualityThreshold) {
    self.garAnchor = [self.cloudAnchorManager hostCloudAnchor:self.arAnchor error:nil];
    [self enterState:HostStateHosting];
    self.hostBeginDate = [NSDate date];
    return;
  }

  if (!self.featureMapQualityBars) {
    return;
  }
  for (ARAnchor *anchor in anchors) {
    if ([anchor.identifier isEqual:self.anchorIdentifier]) {
      simd_float4x4 anchorTCamera = simd_mul(simd_inverse(anchor.transform), cameraTransform);
      float x = anchorTCamera.columns[3][0];
      float y = anchorTCamera.columns[3][1];
      float z = anchorTCamera.columns[3][2];
      // Angle from the x axis, measured clockwise.
      float angle = self.hitHorizontalPlane ? atan2f(z, x) : atan2f(y, x);
      [self.featureMapQualityBars updateVisualization:angle featureMapQuality:featureMapQuality];
      float distance = self.hitHorizontalPlane ? sqrt(z * z + x * x) : sqrt(y * y + x * x);
      if (distance > kMaxDistance) {
        self.message = @"You are too far; come closer";
      } else if (distance < kRadius) {
        self.message = @"You are too close; move backward";
      } else {
        self.message = @"Save the object here by capturing it from all sides";
      }
      [self.messageLabel setText:self.message];
      break;
    }
  }
}

#pragma mark - ARSCNViewDelegate

- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]] == NO) {
    return [self cloudAnchorNode];
  } else {
    return [SCNNode node];
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

    plane.materials.firstObject.diffuse.contents = [UIColor colorWithRed:kPlaneColor[0]
                                                                   green:kPlaneColor[1]
                                                                    blue:kPlaneColor[2]
                                                                   alpha:kPlaneColor[3]];

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
    // Remove plane visualization after anchor placed.
    if (self.anchorPlaced) {
      SCNNode *planeNode = node.childNodes.firstObject;
      [planeNode removeFromParentNode];
    } else {
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
}

- (void)renderer:(id<SCNSceneRenderer>)renderer
    didRemoveNode:(SCNNode *)node
        forAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]]) {
    SCNNode *planeNode = node.childNodes.firstObject;
    [planeNode removeFromParentNode];
  }
}

#pragma mark - GARSessionDelegate

- (void)session:(GARSession *)session didHostAnchor:(GARAnchor *)anchor {
  self.garAnchor = anchor;
  [self enterState:HostStateFinished];
  double durationSec = [[NSDate date] timeIntervalSinceDate:self.hostBeginDate];
  NSLog(@"Time taken to complete hosting process: %f ms", durationSec * kSecToMilliseconds);
  [self sendSaveAlert:anchor.cloudIdentifier];
}

- (void)session:(GARSession *)session didFailToHostAnchor:(GARAnchor *)anchor {
  self.garAnchor = anchor;
  [self enterState:HostStateFinished];
}

@end
