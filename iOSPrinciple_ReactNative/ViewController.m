//
//  ViewController.m
//  iOSPrinciple_ReactNative
//
//  Created by WhatsXie on 2018/5/11.
//  Copyright © 2018年 WhatsXie. All rights reserved.
//

#import "ViewController.h"
#import <JavaScriptCore/JSContext.h>
#import <JavaScriptCore/JSValue.h>

#import <React/RCTRootView.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self createJSContext];
    
    [self callbackJSContext];
    
    
    [self setupReactNative];
}

/// 🌰：Native -> JavaScript
- (void)createJSContext {
    JSContext *context = [[JSContext alloc] init];
    [context evaluateScript:@"var num = 5 + 5"];
    [context evaluateScript:@"var names = ['Grace', 'Ada', 'Margaret']"];
    [context evaluateScript:@"var triple = function(value) { return value * 3 }"];
    JSValue *tripleNum = [context evaluateScript:@"triple(num)"];
    JSValue *tripleFunction = context[@"triple"];
    JSValue *result = [tripleFunction callWithArguments:@[@5]];
    
    NSLog(@"JSContext function \ntripleNum:%@ \nresult:%@", tripleNum, result);
}

/// 🌰：JavaScript -> Native
- (void)callbackJSContext {
    JSContext *context = [[JSContext alloc] init];
    context[@"testSay"] = ^(NSString *input) {
        NSMutableString *mutableString = [input mutableCopy];
        CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformToLatin, NO);
        CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformStripCombiningMarks, NO);
        return mutableString;
    };
    NSLog(@"%@", [context evaluateScript:@"testSay('hello world')"]);
}

- (void)setupReactNative {
    NSURL *jsCodeLocation;
    
    //    jsCodeLocation = [NSURL URLWithString:@"http://localhost:8081/index.ios.bundle?platform=ios&dev=true"];
    jsCodeLocation = [NSURL URLWithString:@"http://10.0.0.65:8081/index.ios.bundle?platform=ios&dev=true"];
    
    RCTRootView *reactRootView = [[RCTRootView alloc] initWithBundleURL:jsCodeLocation
                                                             moduleName:@"iOSPrinciple_ReactNative"
                                                      initialProperties:nil
                                                          launchOptions:nil];
    reactRootView.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    [self.view addSubview:reactRootView];
}

- (void)dealloc {
    NSLog(@"%@",@"ModuleARNPageViewController dealloc");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end
