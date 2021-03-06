//
//  YOYAudioMixManager.h
//  YOYAudioRecoder
//
//  Created by Tommy on 2018/9/26.
//  Copyright © 2018年 Tommy. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "YOYCachePathManager.h"
#import "YOYAudioRecoderHeader.h"

@protocol YOYAudioMixManagerDelegate <NSObject>

/**
 录音在转m4a类型的时候，自定义设置音量大小，默认是1.0f
 
 @return 音量
 */
-(float)volumeForOneAudio;

/**
 合并多段音频，并增加时长
 完成合并时候的回调
 @param resultPath 最终合并完的音频，所在的沙盒路劲
 @param error 合并过程中是否出错
 */
-(void)didFinishMixAudio:(NSString *)resultPath withError:(NSError *)error;

@end

@interface YOYAudioMixManager : NSObject

@property(nonatomic,assign)id<YOYAudioMixManagerDelegate>audioMixManagerDelegate;

/**
 创建该类的一个单例
 
 @return 单例
 */
+(YOYAudioMixManager *)sharedAudioMixManager;

/**
 录音完成后 转 m4a格式的方法
 
 @param audioPath 源文件在沙盒的路径
 @param finishBlock 转换m4a完成时候的回调
 */
-(void)translateAudioToM4aForOneAudio:(NSString *)audioPath finish:(void(^)(NSError *error,NSString *resultPath))finishBlock;

#pragma mark 工具方法

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
-(void)interceptAnAudio:(NSString *)anAudioPath withTime:(float)time force:(BOOL)isForce finish:(void(^)(NSError *error,NSString *resultPath))finishBlock;

/**
 合并多段音频
 增加音频时长
 对应的合并完成的回调方法为：didFinishMixAudio:withError:
 
 @param originalAudioArray 存放音频路径的数组
 */
-(void)mixAudio:(NSArray <NSString *>*)originalAudioArray;

/**
 根据音量，重新生成单段的音频，格式为.m4a
 
 @param originalAudioPath 录音源文件在沙盒中的路径
 @param volume 音量
 @param finishBlock 完成时候的回调
 */
-(void)regenerateOneAudio:(NSString *)originalAudioPath withVolume:(float)volume finish:(void(^)(NSError *error,NSString *resultPath))finishBlock;

/**
 音频合成，两段音频合并成一段音频，音频时长不会增加
 
 @param anAudioPath 第一段录音
 @param otherAudioPath 另一段录音
 @param finishBlock 完成时候的回调
 */
- (void)audioMixWithAudioPath:(NSString *)anAudioPath anotherAudioPath:(NSString *)otherAudioPath finish:(void(^)(NSError *error,NSString *resultPath))finishBlock;

/**
 将音频流pcm文件转成wav文件
 
 @param pcmPath 音频流pcm源文件
 @param wavPath 目标wav文件在沙盒中的路径
 @param sampleRate 采样率
 @param channels 通道数
 @param byteRate 位数
 @param finishBlock 完成时候的回调
 */
-(void)translateAudioFromPCMFile:(NSString *)pcmPath toWAVFile:(NSString *)wavPath sampleRate:(int)sampleRate channels:(int)channels byteRate:(int)byteRate finish:(void (^)(void))finishBlock;



@end

