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

#import "FeatureMapQualityRing.h"
#import <Foundation/Foundation.h>

static float const kPipeRadius = 0.001;

@implementation FeatureMapQualityRing

- (instancetype)initWithRadius:(double)radius isHorizontal:(BOOL)isHorizontal {
  if ((self = [super init])) {
    SCNTorus *torus = [SCNTorus torusWithRingRadius:radius pipeRadius:kPipeRadius];
    torus.firstMaterial.diffuse.contents = [FeatureMapQualityRing createUIImage];
    SCNNode *torusNode = [SCNNode nodeWithGeometry:torus];
    if (!isHorizontal) {
      torusNode.eulerAngles = SCNVector3Make(-M_PI / 2, 0, 0);
    }
    [self addChildNode:torusNode];
  }
  return self;
}

/** Create the texture image for torus node. */
+ (UIImage *)createUIImage {
  CGSize imageSize = CGSizeMake(100, 100);
  CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
  UIGraphicsBeginImageContextWithOptions(imageRect.size, NO, 0);

  CGContextRef context = UIGraphicsGetCurrentContext();

  // Create a transparent background.
  CGContextClearRect(context, imageRect);

  CGRect smallRect = CGRectMake(imageSize.width / 4, 0.0f, imageSize.width / 2, imageSize.height);
  CGContextSetFillColorWithColor(context, [UIColor.whiteColor CGColor]);
  CGContextFillRect(context, smallRect);

  UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();

  return image;
}

@end
