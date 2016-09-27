/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTHTTPRequestHandler.h"
#import "QRCTBundleURLProtocol.h"

@interface RCTHTTPRequestHandler () <NSURLSessionDataDelegate>

@end

@implementation RCTHTTPRequestHandler
{
  NSMapTable *_delegates;
  NSURLSession *_session;
}

RCT_EXPORT_MODULE()

- (void)invalidate
{
  [_session invalidateAndCancel];
  _session = nil;
}

- (BOOL)isValid
{
  // if session == nil and delegates != nil, we've been invalidated
  return _session || !_delegates;
}

#pragma mark - NSURLRequestHandler

- (BOOL)canHandleRequest:(NSURLRequest *)request
{
  static NSSet<NSString *> *schemes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // technically, RCTHTTPRequestHandler can handle file:// as well,
    // but it's less efficient than using RCTFileRequestHandler
    schemes = [[NSSet alloc] initWithObjects:@"http", @"https", nil];
  });
  return [schemes containsObject:request.URL.scheme.lowercaseString];
}

- (NSURLSessionDataTask *)sendRequest:(NSURLRequest *)request
                         withDelegate:(id<RCTURLRequestDelegate>)delegate
{
  // Lazy setup
  if (!_session && [self isValid]) {

    NSOperationQueue *callbackQueue = [NSOperationQueue new];
    callbackQueue.maxConcurrentOperationCount = 1;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    // ----------- QUNAR PATCH --------------
    // RCT使用NSURLSession进行HTTP请求，必须向session注册HY的拦截器才能使离线包生效
    NSMutableArray *configurationProtocols = configuration.protocolClasses ? [configuration.protocolClasses mutableCopy] : [NSMutableArray array];
    Class HYURLProtocolClass = NSClassFromString(@"HYURLProtocol");
    if (HYURLProtocolClass) {
      // 必须把自定义的protocol放在前面，才能优先使用，否则会走自带的HTTP protocol
      // 【醒目】 必须与Hytive framework链接到一起，才能引用到HYURLProtocol的实现。
      //        （目前我们的客户端应该不存在不链接Hy的情况）
      [configurationProtocols insertObject:HYURLProtocolClass atIndex:0];
    }
    [configurationProtocols insertObject:[QRCTBundleURLProtocol class] atIndex:0];
    configuration.protocolClasses = configurationProtocols;
    // ----------- QUNAR PATCH END ----------
    
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:self
                                        delegateQueue:callbackQueue];

    _delegates = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                           valueOptions:NSPointerFunctionsStrongMemory
                                               capacity:0];
  }

  NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
  [_delegates setObject:delegate forKey:task];
  [task resume];
  return task;
}

- (void)cancelRequest:(NSURLSessionDataTask *)task
{
  [task cancel];
  [_delegates removeObjectForKey:task];
}

#pragma mark - NSURLSession delegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
  [[_delegates objectForKey:task] URLRequest:task didSendDataWithProgress:totalBytesSent];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
  [[_delegates objectForKey:task] URLRequest:task didReceiveResponse:response];
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
    didReceiveData:(NSData *)data
{
  [[_delegates objectForKey:task] URLRequest:task didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  [[_delegates objectForKey:task] URLRequest:task didCompleteWithError:error];
  [_delegates removeObjectForKey:task];
}

@end