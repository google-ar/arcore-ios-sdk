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

#import "FeatureMapQualityBar.h"
#import <Foundation/Foundation.h>

static float const kCapsuleRadius = 0.006;
static float const kCapsuleHeight = 0.03;

@interface FeatureMapQualityBar ()

@property(nonatomic) SCNNode *capsuleNode;
@property(nonatomic) int featureMapQuality;

@end  // interface FeatureMapQualityBar()

@implementation FeatureMapQualityBar

- (instancetype)initWithRadius:(double)radius angle:(double)angle isHorizontal:(BOOL)isHorizontal {
  if ((self = [super init])) {
    SCNCapsule *capsule = [SCNCapsule capsuleWithCapRadius:kCapsuleRadius height:kCapsuleHeight];
    capsule.materials.firstObject.diffuse.contents = [UIColor whiteColor];
    _capsuleNode = [SCNNode nodeWithGeometry:capsule];
    if (isHorizontal) {
      _capsuleNode.position =
          SCNVector3Make(radius * cos(angle), kCapsuleHeight / 2, radius * sin(angle));
    } else {
      _capsuleNode.position =
          SCNVector3Make(radius * cos(angle), radius * sin(angle), -kCapsuleHeight / 2);
      _capsuleNode.eulerAngles = SCNVector3Make(-M_PI / 2, 0, 0);
    }
    [self addChildNode:_capsuleNode];
  }
  return self;
}

- (void)updateVisualization:(int)featureMapQuality {
  [self updateQuality:featureMapQuality];

  self.capsuleNode.geometry.firstMaterial.diffuse.contents =
      [FeatureMapQualityBar colorForQuality:self.featureMapQuality];
}

- (void)updateQuality:(int)featureMapQuality {
  switch (featureMapQuality) {
    case 1:
      self.featureMapQuality = MAX(1, self.featureMapQuality);
      break;
    case 2:
      self.featureMapQuality = MAX(2, self.featureMapQuality);
      break;
    default:
      self.featureMapQuality = MAX(0, self.featureMapQuality);
  }
}

- (float)quality {
  switch (self.featureMapQuality) {
    case 1:
      return 0.5f;
    case 2:
      return 1.0f;
    default:
      return 0.f;
  }
}

+ (UIColor *)colorForQuality:(int)quality {
  switch (quality) {
    case 1:
      return [UIColor yellowColor];
    case 2:
      return [UIColor greenColor];
    default:
      return [UIColor redColor];
  }
}

@end
