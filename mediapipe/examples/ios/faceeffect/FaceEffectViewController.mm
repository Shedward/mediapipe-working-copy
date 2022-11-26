// Copyright 2020 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "FaceEffectViewController.h"
#import "VideoProcessor.h"

#import "mediapipe/objc/MPPCameraInputSource.h"
#import "mediapipe/objc/MPPGraph.h"
#import "mediapipe/objc/MPPLayerRenderer.h"

#include <map>
#include <string>
#include <utility>

#include "mediapipe/framework/formats/matrix_data.pb.h"
#include "mediapipe/framework/calculator_framework.h"
#include "mediapipe/modules/face_geometry/protos/face_geometry.pb.h"

static NSString* const kGraphName = @"face_effect_gpu";

static const char* kInputStream = "input_video";
static const char* kOutputStream = "output_video";
static const char* kVideoQueueLabel = "com.google.mediapipe.example.videoQueue";

static const BOOL kUseFaceDetectionInputSource = NO;
static const int kMatrixTranslationZIndex = 14;

static const int kSelectedEffectIdAxis = 0;
static const int kSelectedEffectIdFacepaint = 1;
static const int kSelectedEffectIdGlasses = 2;

@interface FaceEffectViewController () <MPPInputSourceDelegate, VideoProcessorDelegate>
@end

@implementation FaceEffectViewController {
  /// Handle tap gestures.
  UITapGestureRecognizer* _tapGestureRecognizer;
  int _selectedEffectId;

  /// Handles camera access via AVCaptureSession library.
  MPPCameraInputSource* _cameraSource;

  /// Inform the user when camera is unavailable.
  IBOutlet UILabel* _noCameraLabel;
  /// Inform the user about how to switch between effects.
  UILabel* _effectSwitchingHintLabel;
  /// Display the camera preview frames.
  IBOutlet UIView* _liveView;
  /// Render frames in a layer.
  MPPLayerRenderer* _renderer;
  /// Process camera frames on this queue.
  dispatch_queue_t _videoQueue;
  /// Processor
  VideoProcessor* _processor;
}

#pragma mark - Cleanup methods

#pragma mark - UIViewController methods

- (void)viewDidLoad {
  [super viewDidLoad];

  _effectSwitchingHintLabel.hidden = YES;
  _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                  action:@selector(handleTap)];
  [self.view addGestureRecognizer:_tapGestureRecognizer];

  // By default, render the axis effect for the face detection input source and the glasses effect
  // for the face landmark input source.
  if (kUseFaceDetectionInputSource) {
    _selectedEffectId = kSelectedEffectIdAxis;
  } else {
    _selectedEffectId = kSelectedEffectIdFacepaint;
  }

  _renderer = [[MPPLayerRenderer alloc] init];
  _renderer.layer.frame = _liveView.layer.bounds;
  [_liveView.layer insertSublayer:_renderer.layer atIndex:0];
  _renderer.frameScaleMode = MPPFrameScaleModeFillAndCrop;
  _renderer.mirrored = NO;

  dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(
      DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, /*relative_priority=*/0);
  _videoQueue = dispatch_queue_create(kVideoQueueLabel, qosAttribute);

  _cameraSource = [[MPPCameraInputSource alloc] init];
  [_cameraSource setDelegate:self queue:_videoQueue];
  _cameraSource.sessionPreset = AVCaptureSessionPresetHigh;
  _cameraSource.cameraPosition = AVCaptureDevicePositionFront;
  // The frame's native format is rotated with respect to the portrait orientation.
  _cameraSource.orientation = AVCaptureVideoOrientationPortrait;
  _cameraSource.videoMirrored = YES;
  _processor = [[VideoProcessor alloc] init];
  _processor.delegate = self;
}

// In this application, there is only one ViewController which has no navigation to other view
// controllers, and there is only one View with live display showing the result of running the
// MediaPipe graph on the live video feed. If more view controllers are needed later, the graph
// setup/teardown and camera start/stop logic should be updated appropriately in response to the
// appearance/disappearance of this ViewController, as viewWillAppear: can be invoked multiple times
// depending on the application navigation flow in that case.
- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  [_cameraSource requestCameraAccessWithCompletionHandler:^void(BOOL granted) {
    if (granted) {
      [self startGraphAndCamera];
      dispatch_async(dispatch_get_main_queue(), ^{
        _noCameraLabel.hidden = YES;
      });
    }
  }];
}

- (void)startGraphAndCamera {
  // Start running self.graph.
    [_processor startProcessingWithGraphName:kGraphName];

  // Start fetching frames from the camera.
  dispatch_async(_videoQueue, ^{
    [_cameraSource start];
  });
}

#pragma mark - UITapGestureRecognizer methods

// We use the tap gesture recognizer to switch between face effects. This allows users to try
// multiple pre-bundled face effects without a need to recompile the app.
- (void)handleTap {
  dispatch_async(_videoQueue, ^{
    // Avoid switching the Axis effect for the face detection input source.
    if (kUseFaceDetectionInputSource) {
      return;
    }

    // Looped effect order: glasses -> facepaint -> axis -> glasses -> ...
    switch (_selectedEffectId) {
      case kSelectedEffectIdAxis: {
        _selectedEffectId = kSelectedEffectIdGlasses;
        break;
      }

      case kSelectedEffectIdFacepaint: {
        _selectedEffectId = kSelectedEffectIdAxis;
        break;
      }

      case kSelectedEffectIdGlasses: {
        _selectedEffectId = kSelectedEffectIdFacepaint;
        break;
      }
    }
  });
}

#pragma mark - VideoProcessorDelegate methods

- (void)videoProcessor:(VideoProcessor *)processor didProcessFrame:(CVPixelBufferRef)frame timestamp:(CMTime)timestamp {
    CVPixelBufferRetain(frame);
    dispatch_async(dispatch_get_main_queue(), ^{
        _effectSwitchingHintLabel.hidden = kUseFaceDetectionInputSource;
        [_renderer renderPixelBuffer:frame];
        CVPixelBufferRelease(frame);
    });
}

- (void)videoProcessor:(VideoProcessor *)processor didFailedWithError:(NSError *)error {
    NSLog(@"Video processor error: %@", error);
}

#pragma mark - MPPInputSourceDelegate methods

// Must be invoked on _videoQueue.
- (void)processVideoFrame:(CVPixelBufferRef)imageBuffer
                timestamp:(CMTime)timestamp
               fromSource:(MPPInputSource*)source {
  if (source != _cameraSource) {
    NSLog(@"Unknown source: %@", source);
    return;
  }

  [_processor processFrame:imageBuffer timestamp:timestamp];
}

@end
