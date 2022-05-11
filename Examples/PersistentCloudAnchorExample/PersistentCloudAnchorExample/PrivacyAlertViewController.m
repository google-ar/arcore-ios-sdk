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

#import "PrivacyAlertViewController.h"

static NSString *const kPrivacyNoticeKey = @"PrivacyNoticeAccepted";
static NSString *const kPrivacyAlertTitle = @"Experience it together";
static NSString *const kPrivacyAlertMessage = @"To power this session, Google will process visual "
                                               "data from your camera.";
static NSString *const kPrivacyAlertContinueButtonText = @"Start now";
static NSString *const kPrivacyAlertLearnMoreButtonText = @"Learn more";
static NSString *const kPrivacyAlertBackButtonText = @"Not now";
static NSString *const kPrivacyAlertLinkURL =
    @"https://developers.google.com/ar/data-privacy";

@implementation PrivacyAlertViewController

- (void)sendPrivacyAlert:(void (^)(BOOL shouldContinue))completion {
  __weak PrivacyAlertViewController *weakSelf = self;
  void (^innerCompletion)(BOOL shouldContinue) = ^(BOOL shouldContinue) {
    if (shouldContinue) {
      [weakSelf setPrivacyNoticeAccepted:YES];
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
  UIAlertAction *okAction = [UIAlertAction actionWithTitle:kPrivacyAlertContinueButtonText
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction *action) {
                                                     innerCompletion(YES);
                                                   }];
  UIAlertAction *learnMoreAction =
      [UIAlertAction actionWithTitle:kPrivacyAlertLearnMoreButtonText
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
                               [[UIApplication sharedApplication]
                                             openURL:[NSURL URLWithString:kPrivacyAlertLinkURL]
                                             options:@{}
                                   completionHandler:nil];
                               innerCompletion(NO);
                             }];
  UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:kPrivacyAlertBackButtonText
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                         innerCompletion(NO);
                                                       }];
  [alertController addAction:okAction];
  [alertController addAction:learnMoreAction];
  [alertController addAction:cancelAction];
  [self presentViewController:alertController
                     animated:NO
                   completion:nil];
}

#pragma mark - Helper Methods

- (BOOL)privacyNoticeAccepted {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kPrivacyNoticeKey];
}

- (void)setPrivacyNoticeAccepted:(BOOL)accepted {
  [[NSUserDefaults standardUserDefaults] setBool:accepted forKey:kPrivacyNoticeKey];
}

@end
