/*
 * Copyright 2019 Google LLC. All Rights Reserved.
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

#import "CloudAnchorManager.h"

#import <Foundation/Foundation.h>

#import <ARCore/ARCore.h>

@interface CloudAnchorManager ()

// An ARSession from ARSCNView.
@property(nonatomic, weak) ARSession *session;

// A GARSession which is used to host and resolve cloud anchors. Delegate methods are called on the
// delegate of the class instance.
@property(nonatomic, strong) GARSession *gSession;

@end

@implementation CloudAnchorManager

- (instancetype)initWithARSession:(id)session {
  if ((self = [super init])) {
    _session = session;
    _session.delegate = self;

    self.gSession = [GARSession sessionWithAPIKey:@"your-api-key" bundleIdentifier:nil error:nil];
    self.gSession.delegateQueue = dispatch_get_main_queue();
  }

  GARSessionConfiguration *configuration = [[GARSessionConfiguration alloc] init];
  configuration.cloudAnchorMode = GARCloudAnchorModeEnabled;
  [self.gSession setConfiguration:configuration error:nil];

  return self;
}

- (void)setDelegate:(id<CloudAnchorManagerDelegate>)delegate {
  _delegate = delegate;
  self.gSession.delegate = delegate;
}

#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  // Forward ARKit's update to ARCore session
  GARFrame *garFrame = [self.gSession update:frame error:nil];
  int featureMapQuality = [self getFeatureMapQuality:frame];
  // Pass message to delegate for state management
  [self.delegate cloudAnchorManager:self
                     didUpdateFrame:garFrame
                           tracking:frame.camera.trackingState == ARTrackingStateNormal
                    cameraTransform:frame.camera.transform
                            anchors:(NSArray<ARAnchor *> *)frame.anchors
                  featureMapQuality:featureMapQuality];
}

#pragma mark - Helper Methods

- (int)getFeatureMapQuality:(ARFrame *)frame {
  NSError *error = nil;
  // Can pass in ANY valid camera pose to the mapping quality API. Ideally, the pose should
  // represent users’ expected perspectives.
  GARFeatureMapQuality quality =
      [self.gSession estimateFeatureMapQualityForHosting:frame.camera.transform error:&error];
  // GARSession errors have codes that are negative integers. Quality values are >= 0.
  int code = error ? (int)error.code : (int)quality;
  return code;
}

#pragma mark - Public

- (GARAnchor *)hostCloudAnchor:(ARAnchor *)arAnchor error:(NSError **)error {
  // To share an anchor, we call host anchor here on the ARCore session.
  // session:didHostAnchor: session:didFailToHostAnchor: will get called appropriately.
  // Creating a Cloud Anchor with lifetime  = 1 day. This is configurable up to 365 days.
  // If you want TTL > 1, please use the constructor sessionWithError: and use setAuthToken:.
  // Details can be found in
  // https://developers.google.com/ar/develop/ios/persistent-cloud-anchors
  return [self.gSession hostCloudAnchor:arAnchor TTLDays:1 error:error];
}

- (GARAnchor *)resolveAnchorWithAnchorId:(NSString *)anchorId error:(NSError **)error {
  // To resolve an anchor, we call resolve anchor here on the ARCore session.
  // session:didResolveAnchor: session:didFailToResolveAnchor: will get called appropriately.
  return [self.gSession resolveCloudAnchorWithIdentifier:anchorId error:error];
}

- (void)removeAnchor:(GARAnchor *)anchor {
  [self.gSession removeAnchor:anchor];
}

@end
