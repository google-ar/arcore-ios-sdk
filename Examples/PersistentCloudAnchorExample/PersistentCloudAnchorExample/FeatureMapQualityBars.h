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

#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

/** A visualization of the feature map quality around the environment of the anchor. */
@interface FeatureMapQualityBars : SCNNode

/**
 * Initialize a FeatureMapQualityBars object.
 *
 * @param radius The radius of the bars.
 * @param isHorizontal Whether the anchor is created on horizontal or vertical plane.
 */
- (instancetype)initWithRadius:(double)radius isHorizontal:(BOOL)isHorizontal;

/**
 * Update the color of feature map quality bars .
 *
 * @param angle The rotation angle between projected anchorTCamera and x axis.
 * @param featureMapQuality The feature map quality value.
 */
- (void)updateVisualization:(float)angle featureMapQuality:(int)featureMapQuality;

/** Gets the average of mapping qualities of the bars. */
- (float)featureMapQualityAvg;

@end

NS_ASSUME_NONNULL_END
