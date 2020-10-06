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

#import "FeatureMapQualityBars.h"
#import <Foundation/Foundation.h>
#import "FeatureMapQualityBar.h"

// The bar spacing is 7.5 degrees in radians and covering range is M_PI . This value can be updated.
static float const kHorizontalBarNum = 25;
// The bar spacing is 7.5 degrees in radians and covering range is 5 * M_PI / 6. This value can be
// updated.
static float const kVerticalBarNum = 21;
static float const kSpacingRad = M_PI * (7.5 / 180);

@interface FeatureMapQualityBars ()

/** The feature map quality bars array contains the indicator bars placed around the anchor. */
@property(nonatomic) NSMutableArray<FeatureMapQualityBar *> *qualityBars;
@property(nonatomic) BOOL isHorizontal;

@end  // interface FeatureMapQualityBars()

@implementation FeatureMapQualityBars

- (instancetype)initWithRadius:(double)radius isHorizontal:(BOOL)isHorizontal {
  if ((self = [super init])) {
    _qualityBars = [NSMutableArray array];
    _isHorizontal = isHorizontal;
    if (isHorizontal) {
      for (int i = 0; i < kHorizontalBarNum; i++) {
        double angle = i * kSpacingRad;
        FeatureMapQualityBar *qualityBar =
            [[FeatureMapQualityBar alloc] initWithRadius:radius
                                                   angle:angle
                                            isHorizontal:isHorizontal];
        [_qualityBars addObject:qualityBar];
        [self addChildNode:qualityBar];
      }
    } else {
      for (int i = 0; i < kVerticalBarNum; i++) {
        double angle = M_PI / 12 + i * kSpacingRad;
        FeatureMapQualityBar *qualityBar =
            [[FeatureMapQualityBar alloc] initWithRadius:radius
                                                   angle:angle
                                            isHorizontal:isHorizontal];

        [_qualityBars addObject:qualityBar];
        [self addChildNode:qualityBar];
      }
    }
  }
  return self;
}

- (void)updateVisualization:(float)angle featureMapQuality:(int)featureMapQuality {
  int barNum = self.isHorizontal ? kHorizontalBarNum : kVerticalBarNum;
  float angleWithGap = self.isHorizontal ? angle : angle - M_PI / 12;
  int barIndex = (int)(angleWithGap / kSpacingRad);
  if (barIndex >= 0 && barIndex < barNum) {
    FeatureMapQualityBar *qualityBar = self.qualityBars[barIndex];
    [qualityBar updateVisualization:featureMapQuality];
  }
}

- (float)featureMapQualityAvg {
  float sum = 0.f;
  for (FeatureMapQualityBar *qualityBar in self.qualityBars) {
    sum += [qualityBar quality];
  }
  return sum / self.qualityBars.count;
}

@end
