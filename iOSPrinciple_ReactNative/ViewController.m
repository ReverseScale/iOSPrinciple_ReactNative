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
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self createJSContext];
    
    [self callbackJSContext];
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

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
@end
