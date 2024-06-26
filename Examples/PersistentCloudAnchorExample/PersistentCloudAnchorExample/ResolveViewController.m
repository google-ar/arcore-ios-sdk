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

#import "ResolveViewController.h"

static NSString *const kDebugMessagePrefix = @"Debug panel\n";

@interface ResolveViewController () <ARSCNViewDelegate, CloudAnchorManagerDelegate>

// Nodes representing resolved GARAnchors. Updated when anchor changes.
@property(nonatomic, strong) NSMutableDictionary<NSUUID *, SCNNode *> *idToResolvedAnchorNodes;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, GARResolveCloudAnchorFuture *> *idToFutures;

@end

#pragma mark - Overriding UIViewController

@implementation ResolveViewController

- (void)initProperty {
  _idToResolvedAnchorNodes = [NSMutableDictionary dictionary];
  _idToFutures = [NSMutableDictionary dictionary];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  [self initProperty];
  [self.messageLabel setNumberOfLines:3];
  [self.debugLabel setNumberOfLines:5];
  self.cloudAnchorManager = [[CloudAnchorManager alloc] initWithARSession:self.sceneView.session];
  self.cloudAnchorManager.delegate = self;
  self.sceneView.delegate = self;
  [self runSession];
  [self enterState:ResolveStateDefault];
  [self resolveAnchors:self.anchorIds];
}

#pragma mark - Anchor Resolving

- (void)handleResolveAnchor:(GARAnchor *)anchor
                 cloudState:(GARCloudAnchorState)cloudState
                   anchorId:(NSString *)anchorId {
  if (self.state != ResolveStateResolving || ![self.idToFutures objectForKey:anchorId]) {
    return;
  }

  if (cloudState == GARCloudAnchorStateSuccess) {
    SCNNode *node = [self cloudAnchorNode];
    node.simdTransform = anchor.transform;
    [self.sceneView.scene.rootNode addChildNode:node];
    self.idToResolvedAnchorNodes[anchor.identifier] = node;
    self.debugMessage = [NSString
        stringWithFormat:@"Resolved %@ continuing to refine pose.",
                         [[self.idToResolvedAnchorNodes allKeys] componentsJoinedByString:@", "]];
    [self updateMessageLabel];
  }
  [self updateResolveStatus];
}

// Encourage the user to look at a previously mapped area.
- (void)resolveAnchors:(NSArray<NSString *> *)anchorIds {
  [self enterState:ResolveStateResolving];
  __weak ResolveViewController *weakSelf = self;
  for (NSString *anchorId in anchorIds) {
    self.idToFutures[anchorId] = [self.cloudAnchorManager
        resolveAnchorWithAnchorId:anchorId
                       completion:^(GARAnchor *anchor, GARCloudAnchorState cloudState) {
                         [weakSelf handleResolveAnchor:anchor
                                            cloudState:cloudState
                                              anchorId:anchorId];
                       }
                            error:nil];
  }
}

#pragma mark - Helper Methods

- (void)runSession {
  ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc] init];
  [configuration setWorldAlignment:ARWorldAlignmentGravity];
  [configuration setPlaneDetection:ARPlaneDetectionHorizontal];

  [self.sceneView.session runWithConfiguration:configuration];
}

- (void)enterState:(ResolveState)state {
  switch (state) {
    case ResolveStateDefault:
      self.message = @"Look at the location you expect to see the AR experience appear.";
      int num = [self.anchorIds count];
      self.debugMessage = [NSString stringWithFormat:@"Attempting to resolve %d/40 anchors", num];
      NSLog(@"Attempting to resolve %d out of 40 anchors: %@", num,
            [self.anchorIds componentsJoinedByString:@", "]);
      break;
    case ResolveStateResolving: {
      self.message = @"Resolving...";
      self.debugMessage = @"To cancel the resolve, call removeAnchor";
      // TODO(b/251453188): Fix unused variable
      __weak ResolveViewController *__unused weakSelf = self;

    } break;
    case ResolveStateFinished:
      self.message = [NSString stringWithFormat:@"Resolve Finished: \n"];

      for (NSString *anchorId in [self.idToFutures allKeys]) {
        self.message = [self.message
            stringByAppendingString:
                [NSString
                    stringWithFormat:@"%@ ", [self cloudStateString:self.idToFutures[anchorId]
                                                                        .resultCloudAnchorState]]];
      }
      self.debugMessage = [NSString
          stringWithFormat:
              @"Resolved %@ continuing to refine pose.\nTo stop refining, call removeAnchor.",
              [[self.idToResolvedAnchorNodes allKeys] componentsJoinedByString:@", "]];
      break;
  }
  self.state = state;
  [self updateMessageLabel];
}

- (void)updateMessageLabel {
  [self.messageLabel setText:self.message];
  [self.debugLabel setText:[kDebugMessagePrefix stringByAppendingString:self.debugMessage]];
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
    case GARCloudAnchorStateErrorCloudIdNotFound:
      return @"ErrorCloudIdNotFound";
    default:
      return @"Unknown";
  }
}

// Helper method to generate an SCNNode with Android geometry.
- (SCNNode *)cloudAnchorNode {
  SCNScene *scene = [SCNScene sceneNamed:@"example.scnassets/cloud_anchor.scn"];
  return [[scene rootNode] childNodeWithName:@"cloud_anchor" recursively:NO];
}

- (void)updateResolveStatus {
  BOOL allFinished = YES;
  for (NSString *anchorId in [self.idToFutures allKeys]) {
    if (self.idToFutures[anchorId].state == GARFutureStatePending) {
      allFinished = NO;
      break;
    }
  }
  if (allFinished) {
    [self enterState:ResolveStateFinished];
  }
}

#pragma mark - CloudAnchorManagerDelegate

- (void)cloudAnchorManager:(CloudAnchorManager *)manager
            didUpdateFrame:(GARFrame *)garFrame
                  tracking:(BOOL)tracking
           cameraTransform:(simd_float4x4)cameraTransform
                   anchors:(NSArray<ARAnchor *> *)anchors
         featureMapQuality:(int)featureMapQuality {
  if (self.state == ResolveStateResolving) {
    for (GARAnchor *garAnchor in garFrame.updatedAnchors) {
      if ([self.idToResolvedAnchorNodes objectForKey:garAnchor.identifier]) {
        self.idToResolvedAnchorNodes[garAnchor.identifier].simdTransform = garAnchor.transform;
        self.idToResolvedAnchorNodes[garAnchor.identifier].hidden = !garAnchor.hasValidTransform;
      }
    }
  }
}

#pragma mark - ARSCNViewDelegate

- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
  if ([anchor isKindOfClass:[ARPlaneAnchor class]] == NO) {
    return [self cloudAnchorNode];
  } else {
    return nil;
  }
}

@end
