//
//  VideoProcessor.m
//  _idx_MPPGraphGPUData_0DFDF1DB_ios_min11.0
//
//  Created by Vladislav Maltsev on 25.11.2022.
//

#import "VideoProcessor.h"

#import "mediapipe/objc/MPPGraph.h"

static const char* kVideoProcessorQueueLabel = "com.videoprocessor";
static const char* kInputStream = "input_video";
static const char* kOutputStream = "output_video";

@interface VideoProcessor () <MPPGraphDelegate>

@property(nonatomic) MPPGraph* graph;

@end

@implementation VideoProcessor {
    dispatch_queue_t _videoQueue;
}

- (id)init {
    if (self = [super init]) {
        dispatch_queue_attr_t qosAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        _videoQueue = dispatch_queue_create(kVideoProcessorQueueLabel, qosAttribute);
    }
    return self;
}

- (void)dealloc {
    self.graph.delegate = nil;
    [self.graph cancel];
    [self.graph closeAllInputStreamsWithError:nil];
    [self.graph waitUntilDoneWithError:nil];
}

- (void)startProcessingWithGraphName:(NSString *)graphName {
    if (self.graph == nil) {
        self.graph = [self loadGraphFromResourse:graphName];
    }

    NSError* error;
    if (![self.graph startWithError:&error]) {
        [self failedWith:@"Coudln't start processing grapch"
               errorCode:kProcessingGraphNotStarted
         underlyingError:error];
    }
}

- (void)stopProcessing {
    [self.graph cancel];
    [self.graph closeAllInputStreamsWithError:nil];
    [self.graph waitUntilDoneWithError:nil];
    self.graph = nil;
}

- (MPPGraph*)loadGraphFromResourse:(NSString*)resource {
    NSError* configLoadError = nil;
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    if (!resource || resource.length == 0) {
        return nil;
    }

    NSURL* graphURL = [bundle URLForResource:resource withExtension:@"binarypb__"];
    if (!graphURL) {
        [self failedWith:[NSString stringWithFormat:@"File %@.binarypb not found", resource]
               errorCode:kFailedToLoadProcessingGraph
         underlyingError:configLoadError];

        return nil;
    }

    NSData* data = [NSData dataWithContentsOfURL:graphURL options:0 error:&configLoadError];

    if (!data) {
        [self failedWith:[NSString stringWithFormat:@"Failed to load %@.binarypb", resource]
               errorCode:kFailedToLoadProcessingGraph
         underlyingError:configLoadError];

        return nil;
    }

    mediapipe::CalculatorGraphConfig config;
    config.ParseFromArray(data.bytes, data.length);

    MPPGraph* newGraph = [[MPPGraph alloc] initWithGraphConfig:config];
    [newGraph addFrameOutputStream:kOutputStream outputPacketType:MPPPacketTypePixelBuffer];
    newGraph.maxFramesInFlight = 2;
    newGraph.delegate = self;

    return newGraph;
}

- (void)processFrame:(CVPixelBufferRef)frame timestamp:(CMTime)timestamp {
    Float64 seconds = CMTimeGetSeconds(timestamp);
    mediapipe::Timestamp graphTimestamp(static_cast<mediapipe::TimestampBaseType>(mediapipe::Timestamp::kTimestampUnitsPerSecond * seconds));
    [self.graph sendPixelBuffer:frame intoStream:kInputStream packetType:MPPPacketTypePixelBuffer timestamp:graphTimestamp];
}

- (void)failedWith:(NSString*)message
         errorCode:(VideoProcessorError)code
   underlyingError:(NSError*)underlyingError {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    if (message != nil) {
        [userInfo setObject:message forKey:NSDebugDescriptionErrorKey];
    }
    if (underlyingError != nil) {
        [userInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
    }

    NSError* error = [NSError errorWithDomain:kVideoProcessorErrorDomain
                      code:code
                      userInfo:userInfo];
    [self.delegate videoProcessor:self didFailedWithError:error];
}

- (void)mediapipeGraph:(MPPGraph *)graph didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer fromStream:(const std::string &)streamName timestamp:(const mediapipe::Timestamp &)timestamp {

    if (streamName == kOutputStream) {
        CMTime time = CMTimeMakeWithSeconds(timestamp.Microseconds(), 1e6);
        [self.delegate videoProcessor:self didProcessFrame:pixelBuffer timestamp: time];
    }
}

@end
