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

#import "ResolveLobbyViewController.h"

#import "ResolveViewController.h"

static NSInteger const KDayToSeconds = 24 * 60 * 60;
static NSInteger const KHourToSeconds = 60 * 60;
static NSInteger const KHourToMinutes = 60;
static NSInteger const KMinutesToSeconds = 60;
static float const kNicknameCornerRadius = 4;
static float const kResolveCornerRadius = 8;
static NSString *const kTableIdentifier = @"tableIdentifier";
static NSString *const kNicknameTimeStampDictionary = @"NicknameTimeStampDictionary";
static NSString *const kNicknameAnchorIdDictionary = @"NicknameAnchorIdDictionary";

@interface ResolveLobbyViewController () <UITableViewDataSource,
                                          UITableViewDelegate,
                                          UITextFieldDelegate,
                                          UIGestureRecognizerDelegate>

@property(nonatomic) NSMutableDictionary<NSString *, NSDate *> *nicknameToTimestamps;
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *nicknameToAnchorIds;
@property(nonatomic) NSMutableArray<NSString *> *sortedNicknames;
@property(nonatomic) NSMutableSet<NSString *> *tableViewAnchorIds;
@property(nonatomic) NSMutableSet<NSString *> *selectedNicknames;
@property(nonatomic) NSMutableArray<NSString *> *inputAnchorIds;

@end

#pragma mark - Overriding UIViewController
@implementation ResolveLobbyViewController

- (void)initProperty {
    _tableViewAnchorIds = [NSMutableSet set];
    _selectedNicknames = [NSMutableSet set];
    _inputAnchorIds = [NSMutableArray array];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  [self initProperty];
  [self.nicknameButton.layer setBorderWidth:1.0f];
  [self.nicknameButton.layer setBorderColor:[[UIColor grayColor] CGColor]];
  self.nicknameButton.layer.cornerRadius = kNicknameCornerRadius;
  self.nicknameTableView.delegate = self;
  self.nicknameTableView.dataSource = self;
  self.nicknameTableView.hidden = YES;
  self.resolveButton.layer.cornerRadius = kResolveCornerRadius;
  [self startObservingNicknames];
  self.anchorIdsField.delegate = self;
  UITapGestureRecognizer *tapGestureRecognizer =
      [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
  tapGestureRecognizer.delegate = self;
  [self.view addGestureRecognizer:tapGestureRecognizer];
}

- (IBAction)nicknameButtonPressed:(id)sender {
  self.nicknameTableView.hidden = ![self.nicknameTableView isHidden];
  [self.nicknameTableView setEditing:YES animated:YES];
}

- (IBAction)resolveButtonPressed:(id)sender {
  [self.view endEditing:YES];
  // Accept anchor ids from nicknameTableView or anchorIdsField.
  if (self.anchorIdsField.text && self.anchorIdsField.text.length > 0) {
    [self.inputAnchorIds removeAllObjects];
    self.inputAnchorIds = [[self.anchorIdsField.text componentsSeparatedByString:@","] mutableCopy];
  }

  __weak ResolveLobbyViewController *weakSelf = self;
  [self sendPrivacyAlert:^(BOOL shouldContinue) {
    if (shouldContinue) {
      ResolveViewController *resolveViewController =
          [weakSelf.storyboard instantiateViewControllerWithIdentifier:@"ResolveViewController"];
      if ([self.inputAnchorIds count] > 0) {
        resolveViewController.anchorIds = self.inputAnchorIds;
      } else {
        resolveViewController.anchorIds = [self.tableViewAnchorIds allObjects];
      }
      [weakSelf.navigationController pushViewController:resolveViewController animated:YES];
    }
  }];
}

#pragma mark - Helper Methods

- (void)startObservingNicknames {
  NSMutableDictionary<NSString *, NSDate *> *table1 = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kNicknameTimeStampDictionary] mutableCopy];
  NSMutableDictionary<NSString *, NSString *> *table2 = [[[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kNicknameAnchorIdDictionary] mutableCopy];
  if (!table1 || !table2) {
    return;
  }
  self.nicknameToTimestamps = table1;
  self.nicknameToAnchorIds = table2;

  for (NSString *key in [self.nicknameToTimestamps allKeys]) {
    if ([[NSDate date] timeIntervalSinceDate:self.nicknameToTimestamps[key]] > KDayToSeconds) {
      [self.nicknameToTimestamps removeObjectForKey:key];
      [self.nicknameToAnchorIds removeObjectForKey:key];
    }
  }

  self.sortedNicknames =
      [[self.nicknameToTimestamps keysSortedByValueUsingComparator:^NSComparisonResult(
                                      NSDate *_Nonnull obj1, NSDate *_Nonnull obj2) {
        return
            [[NSDate date] timeIntervalSinceDate:obj1] - [[NSDate date] timeIntervalSinceDate:obj2];
      }] mutableCopy];

  [[NSUserDefaults standardUserDefaults] setObject:self.nicknameToTimestamps
                                            forKey:kNicknameTimeStampDictionary];
  [[NSUserDefaults standardUserDefaults] setObject:self.nicknameToAnchorIds
                                            forKey:kNicknameAnchorIdDictionary];
  [[NSUserDefaults standardUserDefaults] synchronize];

  [self.nicknameTableView reloadData];
}

- (void)updateNicknameButtonText {
  NSString *showSelectedNames =
      [[self.selectedNicknames allObjects] componentsJoinedByString:@", "];
  [self.nicknameButton setTitle:showSelectedNames forState:UIControlStateNormal];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
  [self.view endEditing:YES];
}

#pragma mark - UITableView data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.nicknameToTimestamps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                 reuseIdentifier:kTableIdentifier];

  NSString *nickname = [self.sortedNicknames objectAtIndex:indexPath.row];

  NSString *time = @"";
  double interval = [[NSDate date] timeIntervalSinceDate:self.nicknameToTimestamps[nickname]];
  int hours = floor(interval / KHourToSeconds);
  int minutes = round(interval / KMinutesToSeconds - hours * KHourToMinutes);
  if (hours > 0) {
    time = [time stringByAppendingString:[NSString stringWithFormat:@"%dh", hours]];
  } else {
    time = [time stringByAppendingString:[NSString stringWithFormat:@"%dm", minutes]];
  }
  time = [time stringByAppendingString:@" ago"];

  cell.textLabel.text = nickname;
  cell.detailTextLabel.text = time;
  cell.tintColor = [UIColor blueColor];
  return cell;
}

#pragma mark - UITableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [self.nicknameTableView cellForRowAtIndexPath:indexPath];
  [self.tableViewAnchorIds addObject:self.nicknameToAnchorIds[cell.textLabel.text]];
  [self.selectedNicknames addObject:cell.textLabel.text];
  [self updateNicknameButtonText];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [self.nicknameTableView cellForRowAtIndexPath:indexPath];
  [self.tableViewAnchorIds removeObject:self.nicknameToAnchorIds[cell.textLabel.text]];
  [self.selectedNicknames removeObject:cell.textLabel.text];
  [self updateNicknameButtonText];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
  // A check box visualization.
  return 3;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  [textField resignFirstResponder];
  return YES;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
  // Only respond to touch events outside of the table view.
  return !CGRectContainsPoint(self.nicknameTableView.bounds,
                              [touch locationInView:self.nicknameTableView]);
}

@end
