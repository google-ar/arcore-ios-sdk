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

#import <UIKit/UIKit.h>

#import "PrivacyAlertViewController.h"

NS_ASSUME_NONNULL_BEGIN

/** ViewController for the resolve cloud anchor lobby view. */
@interface ResolveLobbyViewController : PrivacyAlertViewController

@property(nonatomic, strong) IBOutlet UIButton *nicknameButton;
@property(nonatomic, strong) IBOutlet UITableView *nicknameTableView;
@property(nonatomic, strong) IBOutlet UIButton *resolveButton;
@property(nonatomic, strong) IBOutlet UITextField *anchorIdsField;

- (IBAction)nicknameButtonPressed:(id)sender;

- (IBAction)resolveButtonPressed:(id)sender;

@end

NS_ASSUME_NONNULL_END
