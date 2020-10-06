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

/** A bar showing the Feature Map Quality at a specific camera viewpoint. */
@interface FeatureMapQualityBar : SCNNode

/**
 * Initialize a FeatureMapQualityBar object.
 *
 * @param radius The distance between the anchor and bar.
 * @param angle The angle of bar relative to the anchor in radians.
 * @param isHorizontal Whether the anchor is created on horizontal or vertical plane.
 */
- (instancetype)initWithRadius:(double)radius angle:(double)angle isHorizontal:(BOOL)isHorizontal;

/**
 * Update the color of FeatureMapQualityBar.
 *
 * @param featureMapQuality The mapping quality value.
 */
- (void)updateVisualization:(int)featureMapQuality;

/** Get the quality value of the bar. */
- (float)quality;

@end

NS_ASSUME_NONNULL_END
