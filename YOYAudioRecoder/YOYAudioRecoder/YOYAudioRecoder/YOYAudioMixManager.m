//
//  YOYAudioMixManager.m
//  YOYAudioRecoder
//
//  Created by Tommy on 2018/9/26.
//  Copyright © 2018年 Tommy. All rights reserved.
//

#import "YOYAudioMixManager.h"

@interface YOYAudioMixManager()

@property(nonatomic,strong)YOYCachePathManager *pathManager;

@end

@implementation YOYAudioMixManager

/**
 创建该类的一个单例
 
 @return 单例
 */
+(YOYAudioMixManager *)sharedAudioMixManager{
    
    static YOYAudioMixManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
    
}

/**
 录音完成后 转 m4a格式的方法
 
 @param audioPath 源文件在沙盒的路径
 @param finishBlock 转换m4a完成时候的回调
 */
-(void)translateAudioToM4aForOneAudio:(NSString *)audioPath finish:(void(^)(NSError *error,NSString *resultPath))finishBlock{
    float volume = 1.0f;
    if ([self.audioMixManagerDelegate respondsToSelector:@selector(volumeForOneAudio)]) {
        volume = [self.audioMixManagerDelegate volumeForOneAudio];
    }
    [self regenerateOneAudio:audioPath withVolume:volume finish:^(NSError *error, NSString *resultPath) {
        if (finishBlock) {
            finishBlock(error,resultPath);
        }
    }];
}

#pragma mark 工具方法

/**
 合并多段音频
 增加音频时长
 对应的合并完成的回调方法为：didFinishMixAudio:withError:
 
 @param originalAudioArray 存放音频路径的数组
 */
-(void)mixAudio:(NSArray <NSString *>*)originalAudioArray{
    
    if ((originalAudioArray.count <= 0) || (!originalAudioArray)) {
        if ([self.audioMixManagerDelegate respondsToSelector:@selector(didFinishMixAudio:withError:)]) {
            NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:nil];
            [self.audioMixManagerDelegate didFinishMixAudio:nil withError:error];
        }
    }else if (originalAudioArray.count == 1) {
        if ([self.audioMixManagerDelegate respondsToSelector:@selector(didFinishMixAudio:withError:)]) {
            NSString *resultPath = [originalAudioArray firstObject];
            [self.audioMixManagerDelegate didFinishMixAudio:resultPath withError:nil];
        }
    }else{
        NSString *firstPath = originalAudioArray[0];
        NSString *secondPath = originalAudioArray[1];
        [self firstPath:firstPath secondPath:secondPath finish:^(NSError *error, NSString *resultPath) {
            if (error) {
                if ([self.audioMixManagerDelegate respondsToSelector:@selector(didFinishMixAudio:withError:)]) {
                    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:nil];
                    [self.audioMixManagerDelegate didFinishMixAudio:nil withError:error];
                }
            }else{
                NSMutableArray *audioMutableArray = [NSMutableArray arrayWithArray:originalAudioArray];
                [audioMutableArray removeObjectAtIndex:0];
                [audioMutableArray removeObjectAtIndex:0];
                [audioMutableArray insertObject:resultPath atIndex:0];
                [self mixAudio:audioMutableArray];
            }
        }];
    }
}

/**
 两段音频合并成一段音频
 增加音频时长
 
 @param path 第一段录音
 @param secondPath 第二段录音
 @param finishBlock 完成时候的回调
 */
- (void)firstPath:(NSString *)path secondPath:(NSString *)secondPath finish:(void(^)(NSError *error,NSString *resultPath))finishBlock{
    
    AVURLAsset *audioAsset1 = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    AVURLAsset *audioAsset2 = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:secondPath]];
    
    AVMutableComposition *composition = [AVMutableComposition composition];
    
    // 音频通道
    AVMutableCompositionTrack *audioTrack1 = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:0];
    AVMutableCompositionTrack *audioTrack2 = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:0];
    
    // 音频采集通道
    AVAssetTrack *audioAssetTrack1 = [[audioAsset1 tracksWithMediaType:AVMediaTypeAudio] firstObject];
    AVAssetTrack *audioAssetTrack2 = [[audioAsset2 tracksWithMediaType:AVMediaTypeAudio] firstObject];
    
    [audioTrack1 insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioAsset1.duration) ofTrack:audioAssetTrack1 atTime:kCMTimeZero error:nil];
    [audioTrack2 insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioAsset2.duration) ofTrack:audioAssetTrack2 atTime:audioAsset1.duration error:nil];
    
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetAppleM4A];
    NSString *targetPath = [self.pathManager savedPathForM4aAudio];
    session.outputURL = [NSURL fileURLWithPath:targetPath];
    session.outputFileType = AVFileTypeAppleM4A;
    session.shouldOptimizeForNetworkUse = YES;
    [session exportAsynchronouslyWithCompletionHandler:^{
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        if ([defaultManager fileExistsAtPath:targetPath]) {
            if (finishBlock) {
                finishBlock(nil,targetPath);
            }
        }else{
            NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:nil];
            if (finishBlock) {
                finishBlock(error,nil);
            }
        }
    }];
}

/**
 音频截取
 isForce为No的情况下：若时间不足，不予截取；时间足够，给予截取；
 isForce为YES的情况下：若时间不足，添加空白音在末尾；若时间足够，给予截取；
 返回的格式为.m4a
 
 @param anAudioPath 源录音文件
 @param time 截取的总共时间
 @param isForce 是否强制截取
 @param finishBlock 完成时候的回调
 */
-(void)interceptAnAudio:(NSString *)anAudioPath withTime:(float)time force:(BOOL)isForce finish:(void(^)(NSError *error,NSString *resultPath))finishBlock{
    
    __weak YOYAudioMixManager *weakSelf = self;
    AVURLAsset *audioAsset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:anAudioPath] options:nil];
    float totalTime = CMTimeGetSeconds(audioAsset.duration);
    
    if (isForce) {
        /// 强制截取
        if (totalTime < time) {
            /// 时间不足，末尾添加空白音
            NSString *blankPath = [[NSBundle mainBundle] pathForResource:@"blankAudio.m4a" ofType:nil];
            float needAddTime = time - (int)totalTime;
            [self interceptAnAudio:blankPath withTime:needAddTime force:YES finish:^(NSError *error, NSString *resultPath) {
                if (error) {
                    if (finishBlock) {
                        finishBlock(error,resultPath);
                    }
                }else{
                    /// 进行空白音添加
                    [weakSelf firstPath:anAudioPath secondPath:resultPath finish:^(NSError *error, NSString *resultPath) {
                        if (finishBlock) {
                            finishBlock(error,resultPath);
                        }
                    }];
                }
            }];
            
        }else if (totalTime == time){
            /// 时间相等，无需截取
            if (finishBlock) {
                finishBlock(nil,anAudioPath);
            }
        }else{
            /// 时间充足进行截取
            AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:audioAsset presetName:AVAssetExportPresetAppleM4A];
            NSString *targetPath = [self.pathManager savedPathForM4aAudio];
            exportSession.outputURL = [NSURL fileURLWithPath:targetPath];
            exportSession.outputFileType = AVFileTypeAppleM4A;
            exportSession.shouldOptimizeForNetworkUse = YES;
            CMTimeRange exportTimeRange = CMTimeRangeFromTimeToTime(CMTimeMake(0, 1), CMTimeMake(time, 1));
            exportSession.timeRange = exportTimeRange;
            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                
                NSFileManager *file = [NSFileManager defaultManager];
                if ([file fileExistsAtPath:targetPath]) {
                    if (finishBlock) {
                        finishBlock(nil,targetPath);
                    }
                }else{
                    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:nil];
                    if (finishBlock) {
                        finishBlock(error,nil);
                    }
                }
            }];
        }
    }else{
        /// 非强制截取
        if (totalTime <= time) {
            /// 时间不足，不予截取
            if (finishBlock) {
                finishBlock(nil,anAudioPath);
            }
        }else{
            /// 时间充足，给予截取
            AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:audioAsset presetName:AVAssetExportPresetAppleM4A];
            NSString *targetPath = [self.pathManager savedPathForM4aAudio];
            exportSession.outputURL = [NSURL fileURLWithPath:targetPath];
            exportSession.outputFileType = AVFileTypeAppleM4A;
            exportSession.shouldOptimizeForNetworkUse = YES;
            CMTimeRange exportTimeRange = CMTimeRangeFromTimeToTime(CMTimeMake(0, 1), CMTimeMake(time, 1));
            exportSession.timeRange = exportTimeRange;
            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                
                NSFileManager *file = [NSFileManager defaultManager];
                if ([file fileExistsAtPath:targetPath]) {
                    if (finishBlock) {
                        finishBlock(nil,targetPath);
                    }
                }else{
                    NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:nil];
                    if (finishBlock) {
                        finishBlock(error,nil);
                    }
                }
            }];
            
        }
    }
}

/**
 音频合成，两段音频合并成一段音频，音频时长不会增加
 
 @param anAudioPath 第一段录音
 @param otherAudioPath 另一段录音
 @param finishBlock 完成时候的回调
 */
- (void)audioMixWithAudioPath:(NSString *)anAudioPath anotherAudioPath:(NSString *)otherAudioPath finish:(void(^)(NSError *error,NSString *resultPath))finishBlock{
    
    AVMutableComposition *composion = [AVMutableComposition composition];
    AVMutableCompositionTrack *anAudio = [composion addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *otherAudio = [composion addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    ///  添加第一段声音轨
    AVURLAsset *anAudioAsset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:anAudioPath] options:nil];
    AVAssetTrack *anAudioTrack = [[anAudioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    [anAudio insertTimeRange:CMTimeRangeMake(kCMTimeZero, anAudioAsset.duration) ofTrack:anAudioTrack atTime:kCMTimeZero error:nil];
    
    ///  添加另一段音轨
    AVURLAsset *otherAudioAsset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:otherAudioPath] options:nil];
    AVAssetTrack *otherAudioTrack = [[otherAudioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    [otherAudio insertTimeRange:CMTimeRangeMake(kCMTimeZero, otherAudioAsset.duration) ofTrack:otherAudioTrack atTime:kCMTimeZero error:nil];
    
    ///  生成输出文件-->.m4a格式
    NSString *targetPath = [self.pathManager savedPathForM4aAudio];
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composion presetName:AVAssetExportPresetAppleM4A];
    exportSession.outputURL = [NSURL fileURLWithPath:targetPath];
    exportSession.outputFileType = @"com.apple.m4a-audio";
    exportSession.shouldOptimizeForNetworkUse = YES;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        if ([[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
            ///  音频文件合成成功
            if (finishBlock) {
                finishBlock(nil,targetPath);
            }
        }else{
            ///  音频文件合成失败
            NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:-1 userInfo:nil];
            if (finishBlock) {
                finishBlock(error,nil);
            }
        }
    }];
    
}

/**
 根据音量，重新生成单段的音频，格式为.m4a
 
 @param originalAudioPath 录音源文件在沙盒中的路径
 @param volume 音量
 @param finishBlock 完成时候的回调
 */
-(void)regenerateOneAudio:(NSString *)originalAudioPath withVolume:(float)volume finish:(void(^)(NSError *error,NSString *resultPath))finishBlock{
    
    NSString *resultPath = [self.pathManager savedPathForM4aAudio];
    
    AVURLAsset *originalAudioAsset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:originalAudioPath] options:nil];
    AVAssetTrack *originalAudioTrack = [[originalAudioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    AVMutableAudioMixInputParameters *originalAudioParameter = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:originalAudioTrack];
    [originalAudioParameter setVolume:volume atTime:kCMTimeZero];
    
    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    audioMix.inputParameters = @[originalAudioParameter];
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:originalAudioAsset presetName:AVAssetExportPresetAppleM4A];
    exportSession.audioMix = audioMix;
    exportSession.outputURL = [NSURL fileURLWithPath:resultPath];
    exportSession.outputFileType = @"com.apple.m4a-audio";
    exportSession.shouldOptimizeForNetworkUse = YES;
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        
        if ([defaultManager fileExistsAtPath:resultPath]) {
            //            [defaultManager removeItemAtPath:originalAudioPath error:nil];
            if (finishBlock) {
                finishBlock(nil,resultPath);
            }
        }else{
            NSLog(@"录音转m4a格式失败");
            if (finishBlock) {
                NSError *error = [NSError errorWithDomain:NSMachErrorDomain code:999 userInfo:nil];
                finishBlock(error,nil);
            }
        }
        
    }];
}

/**
 将音频流pcm文件转成wav文件
 
 @param pcmPath 音频流pcm源文件
 @param wavPath 目标wav文件在沙盒中的路径
 @param sampleRate 采样率
 @param channels 通道数
 @param byteRate 位数
 @param finishBlock 完成时候的回调
 */
-(void)translateAudioFromPCMFile:(NSString *)pcmPath toWAVFile:(NSString *)wavPath sampleRate:(int)sampleRate channels:(int)channels byteRate:(int)byteRate finish:(void (^)(void))finishBlock{
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSData *audioData = [NSData dataWithContentsOfFile:pcmPath];
    NSDictionary *fileDic = [fileManager attributesOfItemAtPath:pcmPath error:nil];
    unsigned long long size = [[fileDic objectForKey:NSFileSize] longLongValue];
    
    NSData *header = WriteWavFileHeader(size-44,size-8,sampleRate,channels,byteRate);
    NSMutableData *wavDatas = [[NSMutableData alloc] init];
    [wavDatas appendData:header];
    [wavDatas appendData:audioData];
    
    if (![fileManager fileExistsAtPath:wavPath]) {
        [fileManager createFileAtPath:wavPath contents:nil attributes:nil];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:wavPath];
    [fileHandle writeData:wavDatas];
    [fileHandle closeFile];
    [fileManager removeItemAtPath:pcmPath error:nil];
    if (finishBlock) {
        finishBlock();
    }
}

/// 放回wav的头文件信息
NSData* WriteWavFileHeader(long totalAudioLen, long totalDataLen, long longSampleRate,int channels, long byteRate)
{
    Byte  header[44];
    header[0] = 'R';  // RIFF/WAVE header
    header[1] = 'I';
    header[2] = 'F';
    header[3] = 'F';
    header[4] = (Byte) (totalDataLen & 0xff);  //file-size (equals file-size - 8)
    header[5] = (Byte) ((totalDataLen >> 8) & 0xff);
    header[6] = (Byte) ((totalDataLen >> 16) & 0xff);
    header[7] = (Byte) ((totalDataLen >> 24) & 0xff);
    header[8] = 'W';  // Mark it as type "WAVE"
    header[9] = 'A';
    header[10] = 'V';
    header[11] = 'E';
    header[12] = 'f';  // Mark the format section 'fmt ' chunk
    header[13] = 'm';
    header[14] = 't';
    header[15] = ' ';
    header[16] = 16;   // 4 bytes: size of 'fmt ' chunk, Length of format data.  Always 16
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    header[20] = 1;  // format = 1 ,Wave type PCM
    header[21] = 0;
    header[22] = (Byte) channels;  // channels
    header[23] = 0;
    header[24] = (Byte) (longSampleRate & 0xff);
    header[25] = (Byte) ((longSampleRate >> 8) & 0xff);
    header[26] = (Byte) ((longSampleRate >> 16) & 0xff);
    header[27] = (Byte) ((longSampleRate >> 24) & 0xff);
    header[28] = (Byte) (byteRate & 0xff);
    header[29] = (Byte) ((byteRate >> 8) & 0xff);
    header[30] = (Byte) ((byteRate >> 16) & 0xff);
    header[31] = (Byte) ((byteRate >> 24) & 0xff);
    header[32] = (Byte) (2 * 16 / 8); // block align
    header[33] = 0;
    header[34] = 16; // bits per sample
    header[35] = 0;
    header[36] = 'd'; //"data" marker
    header[37] = 'a';
    header[38] = 't';
    header[39] = 'a';
    header[40] = (Byte) (totalAudioLen & 0xff);  //data-size (equals file-size - 44).
    header[41] = (Byte) ((totalAudioLen >> 8) & 0xff);
    header[42] = (Byte) ((totalAudioLen >> 16) & 0xff);
    header[43] = (Byte) ((totalAudioLen >> 24) & 0xff);
    return [[NSData alloc] initWithBytes:header length:44];;
}



#pragma mark 私有方法

- (YOYCachePathManager *)pathManager{
    if (!_pathManager) {
        _pathManager = [YOYCachePathManager sharedCachePathManager];
        [_pathManager createCacheFileDirWithPath:nil];
    }
    return _pathManager;
}


@end
