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

    _gSession.delegateQueue = dispatch_get_main_queue();
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

- (void)updateRoom:(NSString *)roomCode withAnchor:(GARAnchor *)anchor {
  [[[[self.firebaseReference child:@"hotspot_list"] child:roomCode] child:@"hosted_anchor_id"]
      setValue:anchor.cloudIdentifier];
  long long timestampInteger = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
  NSNumber *timestamp = [NSNumber numberWithLongLong:timestampInteger];
  [[[[self.firebaseReference child:@"hotspot_list"] child:roomCode] child:@"updated_at_timestamp"]
      setValue:timestamp];
}

- (void)resolveAnchorWithRoomCode:(NSString *)roomCode
                       completion:(void (^)(GARAnchor *))completion {
  __weak CloudAnchorManager *weakSelf = self;
  [[[self.firebaseReference child:@"hotspot_list"] child:roomCode]
      observeEventType:FIRDataEventTypeValue
             withBlock:^(FIRDataSnapshot *_Nonnull snapshot) {
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
                 // Synchronous failures will return nil. The causes may be invalid arguments, etc.
                 // Asynchronous failures (garAnchor is returned as a nonnull) is handled by
                 // session:didFailToResolveAnchor. Success is handled by the delegate methods
                 // session:didResolveAnchor. When garAnchor is returned as a nil, it means
                 // synchronous failures happened where no delegate is called. When garAnchor is
                 // returned as a nonnull, while some asynchronous failure happened, it is handled
                 // by session:didFailToResolveAnchor.
                 NSError *error = nil;
                 GARAnchor *garAnchor =
                     [strongSelf.gSession resolveCloudAnchorWithIdentifier:anchorId error:&error];

                 // Synchronous failure. Refer to the code
                 if (garAnchor == nil) {
                   NSString *alertWindowTitle = @"An error occurred";
                   NSString *alertMessage = [NSString
                       stringWithFormat:
                           @"GARAnchor is returned as a nil in "
                           @"CloudAnchorManager:resolveAnchorWithRoomCode. Error description: %@",
                           [error localizedDescription]];
                   [self popupAlertWindowOnError:alertWindowTitle alertMessage:alertMessage];

                   // Synchronous error in GARSession:resolveCloudAnchorWithIdentifier.
                   // Pass message to delegate for state management
                   [self.delegate cloudAnchorManager:self
                       resolveCloudAnchorReturnNilWithError:error];

                   return;
                 }

                 completion(garAnchor);
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
