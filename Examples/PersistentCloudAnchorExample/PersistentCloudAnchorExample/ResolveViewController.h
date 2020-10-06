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

#import <ARKit/ARKit.h>
#import <SceneKit/SceneKit.h>
#import <UIKit/UIKit.h>

#import "CloudAnchorManager.h"

#import <Foundation/Foundation.h>

#import <ARCore/ARCore.h>

/** Possible values of ResolveViewController state. */
typedef NS_ENUM(NSInteger, ResolveState) {
  ResolveStateDefault,
  ResolveStateResolving,
  ResolveStateFinished
};

NS_ASSUME_NONNULL_BEGIN

/** ViewController for the resolve cloud anchor view. */
@interface ResolveViewController : UIViewController

@property(nonatomic, strong) IBOutlet ARSCNView *sceneView;
@property(nonatomic, strong) IBOutlet UILabel *messageLabel;
@property(nonatomic, strong) IBOutlet UILabel *debugLabel;
@property(nonatomic, assign) ResolveState state;
@property(nonatomic, strong) NSString *message;
@property(nonatomic, strong) NSString *debugMessage;
// Cloud Anchor Manager manages interaction between GARSession and ARSession.
@property(nonatomic, strong) CloudAnchorManager *cloudAnchorManager;
// Values passed from ResolveLobbyViewController.
@property(nonatomic, strong) NSArray<NSString *> *anchorIds;

@end

NS_ASSUME_NONNULL_END
