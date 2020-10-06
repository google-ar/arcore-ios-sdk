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

#import "HostViewController+Alert.h"

static NSString *const kSaveAnchorAlertTitle = @"Enter name";
static NSString *const kAlertMessage =
    @"Enter a name for your anchor ID(to be stored in local app storage)";
static NSString *const kSaveAnchorAlertOkButtonText = @"OK";
static NSString *const kNicknameTimeStampDictionary = @"NicknameTimeStampDictionary";
static NSString *const kNicknameAnchorIdDictionary = @"NicknameAnchorIdDictionary";

@implementation HostViewController (Alert)

- (void)sendSaveAlert:(NSString *)anchorId {
  UIAlertController *alertController =
      [UIAlertController alertControllerWithTitle:kSaveAnchorAlertTitle
                                          message:kAlertMessage
                                   preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction *okAction =
      [UIAlertAction actionWithTitle:kSaveAnchorAlertOkButtonText
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *action) {
                               NSString *anchorNickName = alertController.textFields[0].text;
                               if ([anchorNickName length] > 0) {
                                 [self saveAnchorNickName:anchorNickName anchorId:anchorId];
                               }
                             }];
  [alertController addAction:okAction];
  [alertController addTextFieldWithConfigurationHandler: ^(UITextField *textField) {
    NSDictionary<NSString *, NSDate *> *table = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kNicknameTimeStampDictionary];
    textField.placeholder = [NSString stringWithFormat:@"Anchor%lu", [table count] + 1];
  }];

  [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - Helper Methods

- (void)saveAnchorNickName:(NSString *)nickName anchorId:(NSString *)anchorId {
  NSMutableDictionary<NSString *, NSDate *> *table1 = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kNicknameTimeStampDictionary] mutableCopy];
  NSMutableDictionary<NSString *, NSDate *> *nickNameToTimeStampDictionary =
      table1 ? table1 : [[NSMutableDictionary alloc] init];

  NSMutableDictionary<NSString *, NSString *> *table2 = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kNicknameAnchorIdDictionary] mutableCopy];
  NSMutableDictionary<NSString *, NSString *> *nicknameAnchorIdDictionary =
      table2 ? table2 : [[NSMutableDictionary alloc] init];

  nickNameToTimeStampDictionary[nickName] = [NSDate date];
  nicknameAnchorIdDictionary[nickName] = anchorId;
  [[NSUserDefaults standardUserDefaults] setObject:nickNameToTimeStampDictionary
                                            forKey:kNicknameTimeStampDictionary];
  [[NSUserDefaults standardUserDefaults] setObject:nicknameAnchorIdDictionary
                                            forKey:kNicknameAnchorIdDictionary];

  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
