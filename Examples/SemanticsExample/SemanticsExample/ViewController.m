/*
 * Copyright 2023  Google LLC. All Rights Reserved.
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

#import "ViewController.h"

#import <ARKit/ARKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <simd/simd.h>

#import <ARCore/ARCore.h>

@interface ViewController () <ARSessionDelegate>

/** ARCore session, used for geospatial localization. */
@property(nonatomic) GARSession *garSession;

/** ARKit session. */
@property(nonatomic) ARSession *arSession;

/** A view that shows an AR enabled camera feed and 3D content. */
@property(nonatomic, weak) ARSCNView *scnView;

/** Context for drawing semantic images. */
@property(nonatomic) CGContextRef semanticImageContext;

/** UIImage for drawing semantic images. */
@property(nonatomic) UIImage *semanticUiImage;

/** Buffer for semantics data. */
@property(nonatomic) NSMutableData *semanticData;

/** Image view for semantic images. */
@property(nonatomic) UIImageView *imageView;

/** Legend for semantic color labels. */
@property(nonatomic) UIStackView *colorLegend;

/** Semantic label fractions for each label. Updated each frame. */
@property(nonatomic) NSMutableArray<NSNumber *> *labelFractions;

/** Current semantics mode. */
@property(nonatomic) GARSemanticMode semanticMode;

/** Default colors for visualizing semantic labeling image. */
@property(nonatomic) NSArray<UIColor *> *colorMap;

/** Labels corresponding to `GARSemanticLabel` classes. */
@property(nonatomic) NSArray<NSString *> *colorLabels;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  ARSCNView *scnView = [[ARSCNView alloc] init];
  scnView.translatesAutoresizingMaskIntoConstraints = NO;
  self.scnView = scnView;
  self.arSession = self.scnView.session;
  [self.view addSubview:self.scnView];

  self.imageView = [[UIImageView alloc] initWithImage:nil];
  self.imageView.contentMode = UIViewContentModeScaleAspectFill;
  self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.scnView addSubview:self.imageView];

  // Align the semantic UIImageView with the AR scene view to ensure the semantic image overlays the
  // physical world.
  [self.imageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
  [self.imageView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor].active = YES;
  [self.imageView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
  [self.imageView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;

  [self.scnView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
  [self.scnView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
  [self.scnView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
  [self.scnView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;

  // Setup default color labels.
  self.colorMap = @[
    [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:.5],     // unlabeled
    [UIColor colorWithRed:0.27 green:0.50 blue:0.70 alpha:.5],  // sky
    [UIColor colorWithRed:0.27 green:0.27 blue:0.27 alpha:.5],  // building
    [UIColor colorWithRed:0.13 green:0.54 blue:0.13 alpha:.5],  // tree
    [UIColor colorWithRed:0.54 green:0.16 blue:0.88 alpha:.5],  // road
    [UIColor colorWithRed:0.95 green:0.13 blue:0.90 alpha:.5],  // sidewalk
    [UIColor colorWithRed:0.59 green:0.98 blue:0.59 alpha:.5],  // terrain
    [UIColor colorWithRed:0.82 green:0.70 blue:0.54 alpha:.5],  // structure
    [UIColor colorWithRed:0.86 green:0.86 blue:0.0 alpha:.5],   // object
    [UIColor colorWithRed:0.06 green:0.06 blue:0.90 alpha:.5],  // vehicle
    [UIColor colorWithRed:1.0 green:0.03 blue:0.0 alpha:.5],    // person
    [UIColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:.5],     // water
  ];

  self.colorLabels = @[
    @"Unlabeled",
    @"Sky",
    @"Building",
    @"Tree",
    @"Road",
    @"Sidewalk",
    @"Terrain",
    @"Structure",
    @"Object",
    @"Vehicle",
    @"Person",
    @"Water",
  ];

  // Add a color legend to understand each category.
  self.colorLegend = [self addLegend];
  [self.colorLegend setHidden:YES];

  self.labelFractions = [NSMutableArray arrayWithCapacity:self.colorLabels.count];
  for (int i = 0; i < self.colorLabels.count; i++) {
    [self.labelFractions addObject:@(0.0)];
  }

  UIButton *toggleLegend = [UIButton buttonWithType:UIButtonTypeSystem];
  toggleLegend.translatesAutoresizingMaskIntoConstraints = NO;
  toggleLegend.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.8];
  [toggleLegend setTitle:@"Show Legend" forState:UIControlStateNormal];
  [toggleLegend addTarget:self
                   action:@selector(toggleLegend:)
         forControlEvents:UIControlEventTouchDown];

  [self.view addSubview:toggleLegend];

  [toggleLegend.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
      .active = YES;
  [toggleLegend.leftAnchor constraintEqualToAnchor:self.colorLegend.leftAnchor].active = YES;
  [toggleLegend.rightAnchor constraintEqualToAnchor:self.colorLegend.rightAnchor].active = YES;

  [self.colorLegend.bottomAnchor constraintEqualToAnchor:toggleLegend.topAnchor].active = YES;

  // Enable/disable semantics on screen tap.
  UITapGestureRecognizer *tapGesture =
      [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleSemantics:)];
  [self.scnView addGestureRecognizer:tapGesture];

  [self.view sendSubviewToBack:self.scnView];
}

/** Toggles color legend visibility. */
- (void)toggleLegend:(UIButton *)sender {
  if (self.colorLegend.isHidden) {
    [self.colorLegend setHidden:NO];
    [sender setTitle:@"Hide Legend" forState:UIControlStateNormal];
  } else {
    [self.colorLegend setHidden:YES];
    [sender setTitle:@"Show Legend" forState:UIControlStateNormal];
  }
}

/** Updates semantic label fractions on legend. */
- (void)updateLegendFractions {
  for (int i = 0; i < self.colorLabels.count; i++) {
    UIView *colorView = self.colorLegend.arrangedSubviews[i];
    UILabel *fraction = colorView.subviews[2];
    fraction.text = [NSString stringWithFormat:@"%.2f", self.labelFractions[i].floatValue];
  }
}

/** Returns a box showing the semantic label's name and default color. */
- (UIView *)colorView:(NSString *)name color:(UIColor *)color {
  UIView *containerView = [[UIView alloc] init];
  UILabel *label = [[UILabel alloc] init];
  UILabel *fraction = [[UILabel alloc] init];
  UIView *box = [[UIView alloc] init];
  containerView.translatesAutoresizingMaskIntoConstraints = NO;
  box.translatesAutoresizingMaskIntoConstraints = NO;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  fraction.translatesAutoresizingMaskIntoConstraints = NO;

  label.text = name;
  label.textColor = UIColor.whiteColor;
  fraction.textColor = UIColor.whiteColor;
  fraction.text = @"0.00";

  box.backgroundColor = color;

  [containerView addSubview:box];
  [containerView addSubview:label];
  [containerView addSubview:fraction];

  CGFloat padding = 5;

  [containerView.heightAnchor constraintEqualToAnchor:label.heightAnchor constant:padding].active =
      YES;
  [containerView.widthAnchor constraintEqualToConstant:150].active = YES;
  [containerView.rightAnchor constraintEqualToAnchor:fraction.rightAnchor constant:padding].active =
      YES;

  [label.leftAnchor constraintEqualToAnchor:box.rightAnchor constant:padding].active = YES;
  [label.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor].active = YES;

  [fraction.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor].active = YES;

  [box.leftAnchor constraintEqualToAnchor:containerView.leftAnchor constant:padding].active = YES;
  [box.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor].active = YES;
  [box.heightAnchor constraintEqualToAnchor:label.heightAnchor multiplier:.7].active = YES;
  [box.widthAnchor constraintEqualToAnchor:box.heightAnchor].active = YES;

  return containerView;
}

/** Adds legend to view for semantic label colors. */
- (UIStackView *)addLegend {
  UIStackView *colorLegend = [[UIStackView alloc] init];
  colorLegend.translatesAutoresizingMaskIntoConstraints = NO;
  colorLegend.axis = UILayoutConstraintAxisVertical;
  colorLegend.spacing = 5;
  colorLegend.distribution = UIStackViewDistributionFillEqually;
  [self.view addSubview:colorLegend];

  [colorLegend.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;

  UIView *background = [[UIView alloc] initWithFrame:colorLegend.frame];
  background.translatesAutoresizingMaskIntoConstraints = NO;
  background.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.8];
  background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [colorLegend addSubview:background];

  for (int i = 0; i < self.colorMap.count; i++) {
    UIColor *color = self.colorMap[i];
    [colorLegend addArrangedSubview:[self colorView:self.colorLabels[i] color:color]];
  }

  return colorLegend;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];

  self.semanticMode = GARSemanticModeEnabled;
  [self setUpARSession];
  [self setUpGARSession];
}

/** Initializes ARKit session. */
- (void)setUpARSession {
  ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc] init];
  configuration.worldAlignment = ARWorldAlignmentGravity;

  self.arSession.delegate = self;
  [self.arSession runWithConfiguration:configuration];
}

/** Initializes GARSession with the required `GARSemanticModeEnabled`. */
- (void)setUpGARSession {
  NSError *error = nil;
  self.garSession = [GARSession sessionWithError:&error];

  if (error) {
    NSLog(@"Failed to create GARSession: %d", (int)error.code);
    return;
  }
  [self configureSemantics:self.semanticMode];
}

/** Configure GARSession with given GARSemanticMode. */
- (void)configureSemantics:(GARSemanticMode)semanticMode {
  if (![self.garSession isSemanticModeSupported:GARSemanticModeEnabled]) {
    NSLog(@"Semantics is not supported by the given device/OS version.");
    return;
  }

  GARSessionConfiguration *configuration = [[GARSessionConfiguration alloc] init];
  configuration.semanticMode = semanticMode;
  NSError *error;
  [self.garSession setConfiguration:configuration error:&error];
  if (error) {
    NSLog(@"Failed to configure GARSession: %d", (int)error.code);
  }
}

/** Toggles semantics mode. */
- (void)toggleSemantics:(UITapGestureRecognizer *)recognizer {
  if (self.semanticMode == GARSemanticModeEnabled) {
    self.semanticMode = GARSemanticModeDisabled;
    self.imageView.image = nil;
    for (int i = 0; i < self.labelFractions.count; i++) {
      self.labelFractions[i] = @(0.0);
    }
    [self updateLegendFractions];
  } else {
    self.semanticMode = GARSemanticModeEnabled;
  }

  [self configureSemantics:self.semanticMode];
}

/** Initializes the semantic image buffers with the given dimensions. */
- (void)initializeSemanticImageWithWidth:(size_t)width height:(size_t)height {
  // UIImageView for rendering semantic image. The semantic image pixels are 8-bit class labels, and
  // are converted to some default colors for visualization.
  self.semanticData = [NSMutableData dataWithLength:(width * height * 4)];
  self.semanticImageContext =
      CGBitmapContextCreate((void *)self.semanticData.mutableBytes, width, height,
                            /* bitsPerComponent= */ 8,
                            /* bytesPerRow= */ width * 4, CGColorSpaceCreateDeviceRGB(),
                            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
}

/** Updates the UI with the latest semantic data. */
- (void)updateSemantics:(GARFrame *)garFrame {
  CVPixelBufferRef pixelBuffer = garFrame.semanticImage;
  if (!pixelBuffer) {
    NSLog(@"Semantic images are not yet available.");
    return;
  }

  if (!self.semanticData) {
    [self initializeSemanticImageWithWidth:CVPixelBufferGetWidth(pixelBuffer)
                                    height:CVPixelBufferGetHeight(pixelBuffer)];
  }

  // CVPixelBuffer base address must be locked before access.
  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
  uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t totalBytes = CVPixelBufferGetDataSize(pixelBuffer);

  // Copy GARFrame's semantic data to be rendered by a UIImage.
  for (size_t i = 0; i < totalBytes; i++) {
    CGFloat red, green, blue, alpha;
    [self.colorMap[baseAddress[i]] getRed:&red green:&green blue:&blue alpha:&alpha];

    uint8_t *semanticData = (uint8_t *)self.semanticData.mutableBytes;

    semanticData[i * 4 + 0] = red * 255;
    semanticData[i * 4 + 1] = green * 255;
    semanticData[i * 4 + 2] = blue * 255;
    semanticData[i * 4 + 3] = alpha * 255;
  }

  // |GARFrame#acquireSemanticImage:error| implicitly retains the semantic image. It must be
  // released here.
  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

  CGImageRef imageRef = CGBitmapContextCreateImage(self.semanticImageContext);
  UIImage *image = [UIImage imageWithCGImage:imageRef
                                       scale:1.0
                                 orientation:UIImageOrientationRight];
  CGImageRelease(imageRef);

  self.imageView.image = image;

  // Update the semantic label fractions.
  for (int i = 0; i < self.colorLabels.count; i++) {
    self.labelFractions[i] = @([garFrame fractionForSemanticLabel:(GARSemanticLabel)i]);
  }
}

- (void)dealloc {
  CGContextRelease(self.semanticImageContext);
}

#pragma mark - ARSessionDelegate

/** ARKit delege update which passes frame updates to GARSession. */
- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
  if (self.garSession == nil) {
    return;
  }
  GARFrame *garFrame = [self.garSession update:frame error:nil];
  [self updateSemantics:garFrame];
  [self updateLegendFractions];
}

@end
