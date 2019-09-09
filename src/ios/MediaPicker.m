/********* MediaPicker.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import "DmcPickerViewController.h"
@interface MediaPicker : CDVPlugin <DmcPickerDelegate>{
  // Member variables go here.
    NSString* callbackId;
}

- (void)getMedias:(CDVInvokedUrlCommand*)command;
- (void)takePhoto:(CDVInvokedUrlCommand*)command;
- (void)extractThumbnail:(CDVInvokedUrlCommand*)command;

@end

@implementation MediaPicker

- (void)getMedias:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSDictionary *options = [command.arguments objectAtIndex: 0];
    DmcPickerViewController * dmc=[[DmcPickerViewController alloc] init];
    @try{
        dmc.selectMode=[[options objectForKey:@"selectMode"]integerValue];
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    @try{
        dmc.maxSelectCount=[[options objectForKey:@"maxSelectCount"]integerValue];
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    dmc._delegate=self;
    [self.viewController presentViewController:[[UINavigationController alloc]initWithRootViewController:dmc] animated:YES completion:nil];
}

-(void) resultPicker:(NSMutableArray*) selectArray
{
    
    NSString * tmpDir = NSTemporaryDirectory();
    NSString *dmcPickerPath = [tmpDir stringByAppendingPathComponent:@"dmcPicker"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:dmcPickerPath ]){
       [fileManager createDirectoryAtPath:dmcPickerPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSMutableArray * aListArray=[[NSMutableArray alloc] init];
    if([selectArray count]<=0){
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
        return;
    }

    dispatch_async(dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int index=0;
        for(PHAsset *asset in selectArray){
            @autoreleasepool {
                if(asset.mediaType==PHAssetMediaTypeImage){
                    NSString* uniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
                    [self imageToSandbox:asset dmcPickerPath:dmcPickerPath uniqueString:uniqueString aListArray:aListArray selectArray:selectArray index:index];
                    [self imageThumbnailToSandbox:asset dmcPickerPath:dmcPickerPath uniqueString:uniqueString];
                }else{
                    [self videoToSandboxCompress:asset dmcPickerPath:dmcPickerPath aListArray:aListArray selectArray:selectArray index:index];
                }
            }
            index++;
        }
    });

}

-(void)imageToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath uniqueString:(NSString *)uniqueString aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.icloudDownloadEvent(%f,%i)", progress,index];
        [self.commandDelegate evalJs:compressCompletedjs];
    };
    [[PHImageManager defaultManager] requestImageDataForAsset:asset  options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        NSString *filename=[asset valueForKey:@"filename"];
        NSString *fullpath=[NSString stringWithFormat:@"%@/%@%@%@", dmcPickerPath, uniqueString, @"_hoopop_original_", filename];
        NSNumber *size=[NSNumber numberWithLong:imageData.length];

        NSError *error = nil;
        if (![imageData writeToFile:fullpath options:NSAtomicWrite error:&error]) {
            NSLog(@"%@", [error localizedDescription]);
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
        } else {
            
            NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",@"image",@"mediaType",size,@"size",[NSNumber numberWithInt:index],@"index", nil];
            [aListArray addObject:dict];
            if([aListArray count]==[selectArray count]){
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
            }
        }
        
    }];
}

-(void)imageThumbnailToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath uniqueString:(NSString *)uniqueString {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeExact;
    
    [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:CGSizeMake(450,450) contentMode:PHImageContentModeAspectFit options:options resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        NSString *filename = [asset valueForKey:@"filename"];
        NSString *fullpath = [NSString stringWithFormat:@"%@/%@%@", dmcPickerPath, uniqueString, @"_hoopop_thumbnail.jpeg"];
        NSError *error = nil;
        
        UIImage *rotatedImage = [self rotateWithOrientation:result];
        NSData *imageData = UIImageJPEGRepresentation(rotatedImage, 1.0);
        [imageData writeToFile:fullpath options:NSAtomicWrite error:&error];
        
        if (error != nil) {
            NSLog(@"%@", [error localizedDescription]);
        }
    }];
}

- (UIImage *)rotateWithOrientation:(UIImage*)image {
    
    if (image.imageOrientation == UIImageOrientationUp) return image;
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (image.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, image.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, image.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (image.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, image.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, image.size.width, image.size.height,
                                             CGImageGetBitsPerComponent(image.CGImage), 0,
                                             CGImageGetColorSpace(image.CGImage),
                                             CGImageGetBitmapInfo(image.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (image.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.height,image.size.width), image.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,image.size.width,image.size.height), image.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    
    return img;
}

- (void)getExifForKey:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSString *path= [command.arguments objectAtIndex: 0];
    NSString *key  = [command.arguments objectAtIndex: 1];

    NSData *imageData = [NSData dataWithContentsOfFile:path];
    //UIImage * image= [[UIImage alloc] initWithContentsOfFile:[options objectForKey:@"path"] ];
    CGImageSourceRef imageRef=CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
    
    CFDictionaryRef imageInfo = CGImageSourceCopyPropertiesAtIndex(imageRef, 0,NULL);
    
    NSDictionary  *nsdic = (__bridge_transfer  NSDictionary*)imageInfo;
    NSString* orientation=[nsdic objectForKey:key];
   
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:orientation] callbackId:callbackId];


}


-(void)videoToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.icloudDownloadEvent(%f,%i)", progress,index];
        [self.commandDelegate evalJs:compressCompletedjs];
    };
    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *avsset, AVAudioMix *audioMix, NSDictionary *info) {
        if ([avsset isKindOfClass:[AVURLAsset class]]) {
            NSString *filename = [asset valueForKey:@"filename"];
            AVURLAsset* urlAsset = (AVURLAsset*)avsset;
            
            NSString *fullpath=[NSString stringWithFormat:@"%@/%@", dmcPickerPath,filename];
            NSLog(@"%@", urlAsset.URL);
            NSData *data = [NSData dataWithContentsOfURL:urlAsset.URL options:NSDataReadingUncached error:nil];

            NSNumber* size=[NSNumber numberWithLong: data.length];
            NSError *error = nil;
            if (![data writeToFile:fullpath options:NSAtomicWrite error:&error]) {
                NSLog(@"%@", [error localizedDescription]);
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
            } else {
                
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",size,@"size",@"video",@"mediaType" ,[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
           
        }
    }];

}

-(void)videoToSandboxCompress:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    NSString *compressStartjs = [NSString stringWithFormat:@"MediaPicker.compressEvent('%@',%i)", @"start",index];
    [self.commandDelegate evalJs:compressStartjs];
    [[PHImageManager defaultManager] requestExportSessionForVideo:asset options:nil exportPreset:AVAssetExportPresetMediumQuality resultHandler:^(AVAssetExportSession *exportSession, NSDictionary *info) {
        

        NSString *fullpath=[NSString stringWithFormat:@"%@/%@.%@", dmcPickerPath,[[NSProcessInfo processInfo] globallyUniqueString], @"mp4"];
        NSURL *outputURL = [NSURL fileURLWithPath:fullpath];
        
        NSLog(@"this is the final path %@",outputURL);
        
        exportSession.outputFileType=AVFileTypeMPEG4;
        
        exportSession.outputURL=outputURL;

        [exportSession exportAsynchronouslyWithCompletionHandler:^{

            if (exportSession.status == AVAssetExportSessionStatusFailed) {
                NSString * errorString = [NSString stringWithFormat:@"videoToSandboxCompress failed %@",exportSession.error];
               [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorString] callbackId:callbackId];
                NSLog(@"failed");
                
            } else if(exportSession.status == AVAssetExportSessionStatusCompleted){
                
                NSLog(@"completed!");
                NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.compressEvent('%@',%i)", @"completed",index];
                [self.commandDelegate evalJs:compressCompletedjs];
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",@"video",@"mediaType" ,[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
            
        }];
        
    }];
}



-(NSString*)thumbnailVideo:(NSString*)path quality:(NSInteger)quality {
    UIImage *shotImage;
    //视频路径URL
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:fileURL options:nil];
    
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    
    gen.appliesPreferredTrackTransform = YES;
    
    CMTime time = CMTimeMakeWithSeconds(0.0, 600);
    
    NSError *error = nil;
    
    CMTime actualTime;
    
    CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
    
    shotImage = [[UIImage alloc] initWithCGImage:image];
    
    CGImageRelease(image);
    CGFloat q=quality/100.0f;
    NSString *thumbnail=[UIImageJPEGRepresentation(shotImage,q) base64EncodedStringWithOptions:0];
    return thumbnail;
}

- (void)takePhoto:(CDVInvokedUrlCommand*)command
{


}

-(UIImage*)getThumbnailImage:(NSString*)path type:(NSString*)mtype{
    UIImage *result;
    if([@"image" isEqualToString: mtype]){
        result= [[UIImage alloc] initWithContentsOfFile:path];
    }else{
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        
        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:fileURL options:nil];
        
        AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        
        gen.appliesPreferredTrackTransform = YES;
        
        CMTime time = CMTimeMakeWithSeconds(0.0, 600);
        
        NSError *error = nil;
        
        CMTime actualTime;
        
        CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
        
        result = [[UIImage alloc] initWithCGImage:image];
    }
    return result;
}

-(NSString*)thumbnailImage:(UIImage*)result quality:(NSInteger)quality{
    NSInteger qu = quality>0?quality:3;
    CGFloat q=qu/100.0f;
    NSString *thumbnail=[UIImageJPEGRepresentation(result,q) base64EncodedStringWithOptions:0];
    return thumbnail;
}

- (void)extractThumbnail:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSMutableDictionary *options = [command.arguments objectAtIndex: 0];
    UIImage * image=[self getThumbnailImage:[options objectForKey:@"path"] type:[options objectForKey:@"mediaType"]];
    NSString *thumbnail=[self thumbnailImage:image quality:[[options objectForKey:@"thumbnailQuality"] integerValue]];

    [options setObject:thumbnail forKey:@"thumbnailBase64"];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
}

- (void)compressImage:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSMutableDictionary *options = [command.arguments objectAtIndex: 0];

    NSInteger quality=[[options objectForKey:@"quality"] integerValue];
    if(quality<100&&[@"image" isEqualToString: [options objectForKey:@"mediaType"]]){
        UIImage *result = [[UIImage alloc] initWithContentsOfFile: [options objectForKey:@"path"]];
        NSInteger qu = quality>0?quality:3;
        CGFloat q=qu/100.0f;
        NSData *data =UIImageJPEGRepresentation(result,q);
        NSString *dmcPickerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dmcPicker"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if(![fileManager fileExistsAtPath:dmcPickerPath ]){
           [fileManager createDirectoryAtPath:dmcPickerPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *filename=[NSString stringWithFormat:@"%@%@%@",@"dmcMediaPickerCompress", [self currentTimeStr],@".jpg"];
        NSString *fullpath=[NSString stringWithFormat:@"%@/%@", dmcPickerPath,filename];
        NSNumber* size=[NSNumber numberWithLong: data.length];
        NSError *error = nil;
        if (![data writeToFile:fullpath options:NSAtomicWrite error:&error]) {
            NSLog(@"%@", [error localizedDescription]);
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
        } else {
            [options setObject:fullpath forKey:@"path"];
            [options setObject:[[NSURL fileURLWithPath:fullpath] absoluteString] forKey:@"uri"];
            [options setObject:size forKey:@"size"];
            [options setObject:filename forKey:@"name"];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
        }        
        
    }else{
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
    }
}

//获取当前时间戳
- (NSString *)currentTimeStr{
    NSDate* date = [NSDate dateWithTimeIntervalSinceNow:0];//获取当前时间0秒后的时间
    NSTimeInterval time=[date timeIntervalSince1970]*1000;// *1000 是精确到毫秒，不乘就是精确到秒
    NSString *timeString = [NSString stringWithFormat:@"%.0f", time];
    return timeString;
}


-(void)fileToBlob:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSData *result =[NSData dataWithContentsOfFile:[command.arguments objectAtIndex: 0]];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:result]callbackId:command.callbackId];
}

- (void)getFileInfo:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSString *type= [command.arguments objectAtIndex: 1];
    NSURL *url;
    NSString *path;
    if([type isEqualToString:@"uri"]){
        NSString *str=[command.arguments objectAtIndex: 0];
        url = [NSURL URLWithString:str];
        path= url.path;
    }else{
        path= [command.arguments objectAtIndex: 0];
        url =  [NSURL fileURLWithPath:path];
    }
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithCapacity:5];
    [options setObject:path forKey:@"path"];
    [options setObject:url.absoluteString forKey:@"uri"];

    NSNumber * size = [NSNumber numberWithUnsignedLongLong:[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize]];
    [options setObject:size forKey:@"size"];
    NSString *fileName = [[NSFileManager defaultManager] displayNameAtPath:path];
    [options setObject:fileName forKey:@"name"];
    if([[self getMIMETypeURLRequestAtPath:path] containsString:@"video"]){
        [options setObject:@"video" forKey:@"mediaType"];
    }else{
        [options setObject:@"image" forKey:@"mediaType"];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
}


-(NSString *)getMIMETypeURLRequestAtPath:(NSString*)path
{
    //1.确定请求路径
    NSURL *url = [NSURL fileURLWithPath:path];
    
    //2.创建可变的请求对象
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    //3.发送请求
    NSHTTPURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
    
    NSString *mimeType = response.MIMEType;
    return mimeType;
}

@end
