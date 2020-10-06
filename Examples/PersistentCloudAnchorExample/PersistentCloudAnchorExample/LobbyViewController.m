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

#import "LobbyViewController.h"
#import "HostViewController.h"

static float const kCornerRadius = 8;

@implementation LobbyViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.hostButton.layer.cornerRadius = kCornerRadius;
  self.resolveButton.layer.cornerRadius = kCornerRadius;
}

- (IBAction)hostButtonPressed:(id)sender {
  __weak LobbyViewController *weakSelf = self;
  [self sendPrivacyAlert:^(BOOL shouldContinue) {
    if (shouldContinue) {
      UIViewController *hostViewController =
          [weakSelf.storyboard instantiateViewControllerWithIdentifier:@"HostViewController"];
      [weakSelf.navigationController pushViewController:hostViewController animated:YES];
    }
  }];
}

- (IBAction)resolveButtonPressed:(id)sender {
  UIViewController *resolveLobbyViewController =
          [self.storyboard instantiateViewControllerWithIdentifier:@"ResolveLobbyViewController"];
      [self.navigationController pushViewController:resolveLobbyViewController animated:YES];
}

@end
