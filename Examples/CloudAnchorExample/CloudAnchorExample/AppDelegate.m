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

#import "AppDelegate.h"

#import <FirebaseCore/FirebaseCore.h>

#import "ExampleViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [UIApplication sharedApplication].idleTimerDisabled = YES;

  self.window = [[UIWindow alloc] init];

  [FIRApp configure];

  UIStoryboard* storyBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
  ExampleViewController* viewController = [storyBoard instantiateInitialViewController];
  self.window.rootViewController = viewController;

  [self.window makeKeyAndVisible];

  return YES;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application
  supportedInterfaceOrientationsForWindow:(UIWindow *)window {
  return UIInterfaceOrientationMaskPortrait;
}

@end
