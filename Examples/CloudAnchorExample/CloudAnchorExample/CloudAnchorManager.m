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

    _firebaseReference = [[FIRDatabase database] reference];

    NSError *error = nil;

    _gSession = [GARSession sessionWithAPIKey:@"your-api-key" bundleIdentifier:nil error:&error];

    if (_gSession == nil) {
      NSString *alertWindowTitle = @"A fatal error occurred. Will disable the UI interaction.";
      NSString *alertMessage =
          [NSString stringWithFormat:@"Failed to create session. Error description: %@",
                                     [error localizedDescription]];
      [self popupAlertWindowOnError:alertWindowTitle alertMessage:alertMessage];
      return nil;
    }

    GARSessionConfiguration *configuration = [[GARSessionConfiguration alloc] init];
    configuration.cloudAnchorMode = GARCloudAnchorModeEnabled;
    [_gSession setConfiguration:configuration error:&error];

    if (error) {
      NSString *alertWindowTitle = @"A fatal error occurred. Will disable the UI interaction.";
      NSString *alertMessage =
          [NSString stringWithFormat:@"Failed to configure session. Error description: %@",
                                     [error localizedDescription]];
      [self popupAlertWindowOnError:alertWindowTitle alertMessage:alertMessage];
      return nil;
    }
  }
  return self;
}

#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  // Forward ARKit's update to ARCore session
  NSError *error = nil;
  GARFrame *garFrame = [self.gSession update:frame error:&error];

  // Error in frame update is not fatal. We pass error information to delegate.
  // Pass message to delegate for state management
  [self.delegate cloudAnchorManager:self didUpdateFrame:garFrame error:error];
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

        [[[strongSelf.firebaseReference child:@"hotspot_list"] child:[newRoomNumber stringValue]]
            setValue:room];

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
          NSString *alertWindowTitle = @"An error occurred";
          NSString *alertMessage =
              [NSString stringWithFormat:@"CloudAnchorManager:createRoom: Error description: %@",
                                         [error localizedDescription]];
          [self popupAlertWindowOnError:alertWindowTitle alertMessage:alertMessage];

          [strongSelf.delegate cloudAnchorManager:strongSelf failedToCreateRoomWithError:error];
        } else {
          [strongSelf.delegate cloudAnchorManager:strongSelf
                                      createdRoom:[(NSNumber *)snapshot.value stringValue]];
        }
      }];
}

- (void)updateRoom:(NSString *)roomCode withAnchorId:(NSString *)anchorId {
  [[[[self.firebaseReference child:@"hotspot_list"] child:roomCode] child:@"hosted_anchor_id"]
      setValue:anchorId];
  long long timestampInteger = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
  NSNumber *timestamp = [NSNumber numberWithLongLong:timestampInteger];
  [[[[self.firebaseReference child:@"hotspot_list"] child:roomCode] child:@"updated_at_timestamp"]
      setValue:timestamp];
}

- (void)doResolveAnchor:(FIRDataSnapshot *)snapshot
               roomCode:(NSString *)roomCode
             completion:(void (^)(GARAnchor *, GARCloudAnchorState))completion {
  NSString *anchorId = nil;
  if ([snapshot.value isKindOfClass:[NSDictionary class]]) {
    NSDictionary<NSString *, NSObject *> *value = (NSDictionary *)snapshot.value;
    anchorId = (NSString *)value[@"hosted_anchor_id"];
  }

  if (anchorId) {
    [[[self.firebaseReference child:@"hotspot_list"] child:roomCode] removeAllObservers];

    // Now that we have the anchor ID from firebase, we resolve the anchor.
    NSError *error = nil;
    GARResolveCloudAnchorFuture *garFuture =
        [self.gSession resolveCloudAnchorWithIdentifier:anchorId
                                      completionHandler:completion
                                                  error:&error];

    // Synchronous failure.
    if (garFuture == nil) {
      NSString *alertWindowTitle = @"An error occurred";
      NSString *alertMessage = [NSString
          stringWithFormat:@"Error resolving cloud anchor: %@", [error localizedDescription]];
      [self popupAlertWindowOnError:alertWindowTitle alertMessage:alertMessage];
    }

    // Pass message to delegate for state management
    [self.delegate cloudAnchorManager:self startedResolvingCloudAnchor:garFuture error:error];
  }
}

- (void)resolveAnchorWithRoomCode:(NSString *)roomCode
                       completion:(void (^)(GARAnchor *, GARCloudAnchorState))completion {
  __weak CloudAnchorManager *weakSelf = self;
  [[[self.firebaseReference child:@"hotspot_list"] child:roomCode]
      observeEventType:FIRDataEventTypeValue
             withBlock:^(FIRDataSnapshot *_Nonnull snapshot) {
               [weakSelf doResolveAnchor:snapshot roomCode:roomCode completion:completion];
             }];
}

- (void)stopResolvingAnchorWithRoomCode:(NSString *)roomCode {
  [[[self.firebaseReference child:@"hotspot_list"] child:roomCode] removeAllObservers];
}

- (GARHostCloudAnchorFuture *)hostCloudAnchor:(ARAnchor *)arAnchor
                                   completion:(void (^)(NSString *, GARCloudAnchorState))completion
                                        error:(NSError **)error {
  return [self.gSession hostCloudAnchor:arAnchor
                                TTLDays:1
                      completionHandler:completion
                                  error:error];
}

- (void)removeAnchor:(GARAnchor *)anchor {
  [self.gSession removeAnchor:anchor];
}

- (void)popupAlertWindowOnError:(NSString *)alertWindowTitle alertMessage:(NSString *)alertMessage {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:alertWindowTitle
                                            message:alertMessage
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action){
                                                          }];

    [alert addAction:defaultAction];

    id rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
      rootViewController =
          ((UINavigationController *)rootViewController).viewControllers.firstObject;
    }
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
      rootViewController = ((UITabBarController *)rootViewController).selectedViewController;
    }

    [rootViewController presentViewController:alert animated:YES completion:nil];
  });
}

@end
