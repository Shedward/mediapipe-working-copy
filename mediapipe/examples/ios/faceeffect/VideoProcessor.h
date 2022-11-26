//
//  VideoProcessor.h
//  _idx_MPPGraphGPUData_0DFDF1DB_ios_min11.0
//
//  Created by Vladislav Maltsev on 25.11.2022.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class VideoProcessor;

static NSString* kVideoProcessorErrorDomain = @"com.FaceEffect.VideoProcessor";
typedef NS_ENUM(NSInteger, VideoProcessorError) {
    kFailedToLoadProcessingGraph = 100,
    kProcessingGraphNotStarted
};

@protocol VideoProcessorDelegate <NSObject>

- (void)videoProcessor:(VideoProcessor*)processor didProcessFrame:(CVPixelBufferRef)frame timestamp:(CMTime)timestamp;
- (void)videoProcessor:(VideoProcessor*)processor didFailedWithError:(NSError*)error;

@end


@interface VideoProcessor : NSObject

@property (weak) id<VideoProcessorDelegate> delegate;

- (void)startProcessingWithGraphName:(NSString*)graphName;
- (void)stopProcessing;
- (void)processFrame:(CVPixelBufferRef)frame timestamp:(CMTime)timestamp;

@end

NS_ASSUME_NONNULL_END
