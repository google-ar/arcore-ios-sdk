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

#import <ARCore/ARCore.h>
#import <FirebaseDatabase/FirebaseDatabase.h>

@interface CloudAnchorManager ()

// A SCNView which has an ARSession. Used to receive delegate messages and update the GARSession.
@property(nonatomic, weak) ARSCNView *sceneView;

// A GARSession which is used to host and resolve cloud anchors. Delegate methods are called on the
// delegate of the class instance.
@property(nonatomic, strong) GARSession *gSession;

// A FIRDatabaseReference used to record information about rooms and cloud anchors.
@property(nonatomic, strong) FIRDatabaseReference *firebaseReference;

@end

@implementation CloudAnchorManager

- (instancetype)initWithARSceneView:(id)sceneView {
  if ((self = [super init])) {
    _sceneView = sceneView;
    _sceneView.session.delegate = self;

    self.firebaseReference = [[FIRDatabase database] reference];

    self.gSession = [GARSession sessionWithAPIKey:@"your-api-key"
                                 bundleIdentifier:nil
                                            error:nil];
    self.gSession.delegateQueue = dispatch_get_main_queue();
  }

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

  // Pass message to delegate for state management
  [self.delegate cloudAnchorManager:self didUpdateFrame:garFrame];
}

#pragma mark - Public

- (void)createRoom {
  __weak CloudAnchorManager *weakSelf = self;
  [[self.firebaseReference child:@"last_room_code"]
      runTransactionBlock:^FIRTransactionResult *(FIRMutableData *currentData) {
        CloudAnchorManager *strongSelf = weakSelf;

        NSNumber *roomNumber = currentData.value;

        if (!roomNumber || [roomNumber isEqual:[NSNull null]]) {
          roomNumber = @0;
        }

        NSInteger roomNumberInt = [roomNumber integerValue];
        roomNumberInt++;
        NSNumber *newRoomNumber = [NSNumber numberWithInteger:roomNumberInt];

        long long timestampInteger = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        NSNumber *timestamp = [NSNumber numberWithLongLong:timestampInteger];

        NSDictionary<NSString *, NSObject *> *room = @{
                                                      @"display_name" : [newRoomNumber stringValue],
                                                      @"updated_at_timestamp" : timestamp,
                                                      };

        [[[strongSelf.firebaseReference child:@"hotspot_list"]
            child:[newRoomNumber stringValue]] setValue:room];

        currentData.value = newRoomNumber;

        return [FIRTransactionResult successWithValue:currentData];
      } andCompletionBlock:^(NSError * _Nullable error,
                            BOOL committed,
                            FIRDataSnapshot * _Nullable snapshot) {
        CloudAnchorManager *strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }

        if (error) {
          [strongSelf.delegate cloudAnchorManager:strongSelf failedToCreateRoomWithError:error];
        } else {
          [strongSelf.delegate cloudAnchorManager:strongSelf
                                      createdRoom:[(NSNumber *)snapshot.value stringValue]];
        }
      }];
}

- (void)updateRoom:(NSString *)roomCode withAnchor:(GARAnchor *)anchor {
  [[[[self.firebaseReference child:@"hotspot_list"] child:roomCode] child:@"hosted_anchor_id"]
      setValue:anchor.cloudIdentifier];
  long long timestampInteger = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
  NSNumber *timestamp = [NSNumber numberWithLongLong:timestampInteger];
  [[[[self.firebaseReference child:@"hotspot_list"] child:roomCode]
      child:@"updated_at_timestamp"] setValue:timestamp];
}

- (void)resolveAnchorWithRoomCode:(NSString *)roomCode
                       completion:(void (^)(GARAnchor *))completion {
  __weak CloudAnchorManager *weakSelf = self;
  [[[self.firebaseReference child:@"hotspot_list"] child:roomCode]
      observeEventType:FIRDataEventTypeValue
      withBlock:^(FIRDataSnapshot * _Nonnull snapshot) {
        CloudAnchorManager *strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }

        NSString *anchorId = nil;
        if ([snapshot.value isKindOfClass:[NSDictionary class]]) {
          NSDictionary<NSString *, NSObject *> *value = (NSDictionary *)snapshot.value;
          anchorId = (NSString *)value[@"hosted_anchor_id"];
        }

        if (anchorId) {
          [[[strongSelf.firebaseReference child:@"hotspot_list"] child:roomCode]
              removeAllObservers];

          // Now that we have the anchor ID from firebase, we resolve the anchor.
          // Success and failure of this call is handled by the delegate methods
          // session:didResolveAnchor and session:didFailToResolveAnchor appropriately.
          completion([strongSelf.gSession resolveCloudAnchorWithIdentifier:anchorId error:nil]);
        }
      }];
}

- (void)stopResolvingAnchorWithRoomCode:(NSString *)roomCode {
  [[[self.firebaseReference child:@"hotspot_list"] child:roomCode] removeAllObservers];
}

- (GARAnchor *)hostCloudAnchor:(ARAnchor *)arAnchor error:(NSError **)error {
  // To share an anchor, we call host anchor here on the ARCore session.
  // session:didHostAnchor: session:didFailToHostAnchor: will get called appropriately.
  return [self.gSession hostCloudAnchor:arAnchor error:error];
}

- (void)removeAnchor:(GARAnchor *)anchor {
  [self.gSession removeAnchor:anchor];
}

@end
