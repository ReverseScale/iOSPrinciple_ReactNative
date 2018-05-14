# iOSPrinciple_ReactNative
Principle ReactNative

### 基本原理

首先，我们来看一下在iOS中Native如何调用JS。从iOS7开始，系统进一步开放了WebCore SDK，提供JavaScript引擎库，使得我们能够直接与引擎交互拥有更多的控制权。其中，有两个最基础的概念：

```objc
JSContext // JS代码的环境，一个JSContext是一个全局环境的实例
JSValue // 包装了每一个可能的JS值：字符串、数字、数组、对象、方法等
```

通过这两个类，我们能够非常方便的实现Javascript与Native代码之间的交互，首先我们通过一个简单示例来观察Native如何调用Javascript代码：

🌰：Native -> JavaScript

```objc
// 头文件
#import <JavaScriptCore/JSContext.h>
#import <JavaScriptCore/JSValue.h>
- (void)createJSContext {
    JSContext *context = [[JSContext alloc] init];
    [context evaluateScript:@"var num = 5 + 5"];
    [context evaluateScript:@"var names = ['Grace', 'Ada', 'Margaret']"];
    [context evaluateScript:@"var triple = function(value) { return value * 3 }"];
    JSValue *tripleNum = [context evaluateScript:@"triple(num)"];
    JSValue *tripleFunction = context[@"triple"];
    JSValue *result = [tripleFunction callWithArguments:@[@5]];
    // 打印结果
    NSLog(@"JSContext function \ntripleNum:%@ \nresult:%@", tripleNum, result);
}
```

那么，JSContext如何访问我们本地客户端OC代码呢？答案是通过Blocks和JSExports协议两种方式。
我们来看一个通过Blocks来实现JS访问本地代码的示例：

🌰：JavaScript -> Native

```objc
context[@"testSay"] = ^(NSString *input) {
    NSMutableString *mutableString = [input mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformToLatin, NO);
    CFStringTransform((__bridge CFMutableStringRef)mutableString, NULL, kCFStringTransformStripCombiningMarks, NO);
    return mutableString;
};
NSLog(@"%@", [context evaluateScript:@"testSay('hello world')"]);
```

关于JSCore库的更多学习介绍，请看JavaScriptCore。

> Java​Script​Core 相关介绍 http://nshipster.cn/javascriptcore/


### React Native 初始化过程解析

在了解React-Native中JS->Native的具体调用之前，我们先做一些准备工作，看看框架中Native app的启动过程。打开FB提供的AwesomeProject定位到appDelegate的didFinishLaunchingWithOptions方法中：

```objc
// 指定JS页面文件位置
jsCodeLocation = [NSURL URLWithString:@"http://localhost:8081/index.ios.bundle?platform=ios&dev=false"];
// 创建React Native视图对象
RCTRootView *rootView = [[RCTRootView alloc] initWithBundleURL:jsCodeLocation
moduleName:@"ReactExperiment"
initialProperties:nil
launchOptions:launchOptions];
self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
// 创建VC，并且把React Native Root View赋值给VC
UIViewController *rootViewController = [UIViewController new];
rootViewController.view = rootView;
self.window.rootViewController = rootViewController;
[self.window makeKeyAndVisible];
```

可以看到使用集成非常简单，那么RCTRootView到底做了哪些事情最后渲染将视图呈现在用户面前呢？
我们继续跟着代码往下分析就会看到我们今天的主角RCTBridge。

🥟：RCTBridge

```objc
- (instancetype)initWithBundleURL:(NSURL *)bundleURL
moduleName:(NSString *)moduleName
initialProperties:(NSDictionary *)initialProperties
launchOptions:(NSDictionary *)launchOptions {
    RCTBridge *bridge = [[RCTBridge alloc] initWithBundleURL:bundleURL
    moduleProvider:nil
    launchOptions:launchOptions];
    return [self initWithBridge:bridge moduleName:moduleName initialProperties:initialProperties];
}
```

RCTBridge是Naitive端的bridge，起着桥接两端的作用 。事实上具体的实现放置在RCTBatchedBridge中，在它的start方法中执行了一系列重要的初始化工作。这部分也是ReactNative SDK的精髓所在，基于GCD实现一套异步初始化组件框架。大致的工作流程如下图所示：

![](http://og1yl0w9z.bkt.clouddn.com/18-5-11/60547481.jpg)

#### 1.Load JS Source Code（并行）

加载页面源码阶段。该阶段主要负责从指定的位置（网络或者本地）加载React Native页面代码。与initModules各模块初始化过程并行执行，通过GCD分组队列保证两个阶段完成后才会加载解析页面源码。

#### 2.Init Module（同步）

初始化加载React Native模块。该阶段会将所有注册的Native模块类整理保存到一个以Module Id为下标的数组对象中（同时还会保存一个以Module Name为Key的Dictionary，用于做索引方便后续的模块查找）。

整个模块的基础初始化和注册过程在系统Load Class阶段就会完成。React Native对模块注册的实现还是比较巧妙、方便，只需要对目标类添加相应的宏即可。

* 1.注册模块。实现RCTBridgeModule协议，并且在响应的Implemention文件中添加RCT_EXPORT_MODULE宏，该宏会为所在类自动添加一个+load方法，调用RCTBridge的RCTRegisterModule实现在Load Class阶段就完成模块注册工作。
* 2.注册函数。待注册函数所在的类必须是已注册模块，在需要注册的函数前添加RCT_EXPORT_MODULE宏即可。

当然这里需要注意的问题是模块初始化是一个同步任务，它必须被同步加载，所以当模块较多时势必会带来高延迟的问题，也是在新的版本中SDK将Module Method改为Lazy Load的原因之一。

#### 3.Setup JS Executor（并行）

初始化JS引擎。React Native在0.18中已经很好的抽象了原来了JSExecutor，目前实现了RCTWebSocketExecutor和RCTJSCExecutor两个脚本引擎的封装，前者用于通过WebSocket链接到Chrome调试，后者则是内置默认引擎直接通过IOS SDK JSContext来实现相关的逻辑。

另外，在本阶段还会通过block hook的方式注册部分核心API

* 1.nativeRequireModuleConfig：用于在JS端获取对应的Native Module，在0.14后的版本React Native已经对初始化模块做了部分优化，把关于Native Module Method部分的加载工作放置在requireModuleConfig时才做
* 2.nativeLoggingHook：调用Native写入日志
* 3.nativeFlushQueueImmediate：手动触发执行当前Native Call队列中所有的Native处理请求
* 4.nativePerformanceNow：用于性能统计，获取当前Native的绝对时间（毫秒）

对于模块类中想要声明的方法，需要添加RCT_EXPORT_METHOD宏。它会给方法名添加” rct_export “前缀。

🌰：React 调用 Native 的 SVProgressHUD 提示窗

在 Native 中声明方法
```objc
RCT_EXPORT_METHOD(calliOSActionWithOneParams:(NSString *)name) {
    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeBlack];
    [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:@"参数：%@",name]];
}
```

在 React 中调用 calliOSActionWithOneParams 方法
```js
<TouchableOpacity style={styles.calltonative}
    onPress={()=>{
        RNCalliOSAction.calliOSActionWithOneParams('hello');
    }}>
    <Text>点击调用 Native 方法, 并传递一个参数</Text>
</TouchableOpacity>
```

#### 4.Module Config（并行）

这步将第2步中的Native模块类转换成Json，保存为remoteModuleConfig。注意在这里获取到的列表并非含有完整模块信息，而仅仅是一个Module List而已。

```js
{
"remoteModuleConfig":[
[
"HTSimpleAPI", // module
],
[
"RCTViewManager",
],
[
"HTTestView",
],
[
"RCTAccessibilityManager",
],
...
],
}
```

#### JS Source Code代码分析

JS的主入口index.ios.js在我们看来只有短短数十行，然而这不是最终执行的代码。React-Native页面源码需要通过Transform Server转换处理，并把转化后的模块一起合并为一个bundle.js，这个过程称为buildBundle。转换后的index.ios.bundle才是最终可被Javascript引擎直接解释运行的代码。下面我们按照主程序的逻辑来分析源码几个核心模块实现原理。

在React Server中需要查看Bundle的模块映射关系可以直接访问：http://localhost:8081/index.ios.bundle.map，查看相关依赖和Bundle的缓存则可以访问： http://localhost:8081/debug

1.BatchedBridge

在上一部分我们知道，Native完成模块初始化后会通过Inject Json Config将配置信息同步至JS里中的全局变量__fbBatchedBridgeConfig，打开BatchedBridge.js我们可以看到如下代码。

```js
__d('BatchedBridge',function(global, require, module, exports) { 'use strict';
var MessageQueue=require('MessageQueue');
var BatchedBridge=new MessageQueue(
__fbBatchedBridgeConfig.remoteModuleConfig,
__fbBatchedBridgeConfig.localModulesConfig);
//......
Object.defineProperty(global,'__fbBatchedBridge',{value:BatchedBridge});
module.exports = BatchedBridge;
});
```

对于这段代码，我们可以得出以下几个结论：

* 1.在JS端也存在一个bridge模块BatchedBridge，也是与Native建立双向通信的关键所在
* 2.BatchedBridge是一个MessageQueue实例，它在创建时传入了__fbBatchedBridgeConfig值保存Native端支持的模块列表配置

BatchedBridge在创建时将自己写入全局变量__fbBatchedBridge上，这样Native可以通过JSContext[@”__fbBatchedBridge”]访问到JS bridge对象。

2.MessageQueue

接着我们继续看MessageQueue，它在整个通讯链路的机制上面有着重要作用，首先我们来观察一下它的构造函数。

```js
constructor(remoteModules, localModules) {
this.RemoteModules = {};
this._callableModules = {};
this._queue = [[], [], [], 0];
this._moduleTable = {};
this._methodTable = {};
this._callbacks = [];
this._callbackID = 0;
this._callID = 0;
//......
let modulesConfig = this._genModulesConfig(remoteModules);
this._genModules(modulesConfig);
//......
}
```
从构造函数，我们大致能了解MessageQueue的几个信息：

* 1.RemoteModules属性，用于保存Native端模块配置
* 2.Callbacks属性缓存js的回调方法
* 3.Queue事件队列用于处理各类事件等

在构造函数中，解析Native传入的remoteModules JSON，转换成JS对象

3.Config Modules

根据上一步MessageQueue的逻辑，继续往下跟踪_genModules函数，可以看到在MessageQueue已经对Native注入的Module Config做了一次预处理，如果debug模式可以看到大致的数据结构会转换成如下表中所示结构（其中HTSimepleAPI是一个自定义模块）。

```js
config = ["HTSimpleAPI", Array[1]], moduleID = 0
config = null, moduleID = 1
config = null, moduleID = 2
config = ["RCTAccessibilityManager", Array[3]], moduleID = 3
```

至于这样的预处理有什么作用，我们继续往下分析，后面再来总结。

4.Lazily Config Methods

对于NativeModule，它们在上一步之后只有一个包含Module Name等简单信息的Module List的对象，只有在实际调用了该模块之后才会加载该模块的具体信息（比如暴露的API等）。

```js
const NativeModules = {};
Object.keys(RemoteModules).forEach((moduleName) => {
Object.defineProperty(NativeModules, moduleName, {
enumerable: true,
get: () => {
let module = RemoteModules[moduleName];
if (module && typeof module.moduleID === 'number' && global.nativeRequireModuleConfig) {
const json = global.nativeRequireModuleConfig(moduleName);
const config = json && JSON.parse(json);
module = config && BatchedBridge.processModuleConfig(config, module.moduleID);
RemoteModules[moduleName] = module;
}
return module;
},
});
});
```

这段代码定义了一个全局模块NativeModules，遍历之前取到的remoteModules，将每一个module在NativeModules对象上扩展了一个getter方法，该方法中通过nativeRequireModuleConfig进一步加载模块的详细信息，通过processModuleConfig对模块信息进行预处理。进一步分析代码就可以发现这个方法其实是Native中定义的全局JS Block（nativeRequireModuleConfig）。

接下来我们继续看processModuleConfig中具体的代码逻辑，如下表所示：

```js
processModuleConfig(config, moduleID) {
    const module = this._genModule(config, moduleID);
    return module;
}
_genMethod(module, method, type) {
//......
    fn = function(...args) {
    return self.__nativeCall(module, method, args, onFail, onSucc);
};
//......
return fn;
}
```

processModuleConfig方法的主要工作是生成methods配置，并对每一个method封装了一个闭包fn，当调用method时，会转换成成调用self.__nativeCall(moduleID, methodID, args, onFail, onSucc)方法

预处理完成后，在JavaScript环境中的Moudle Config信息才算完整，包含Module Name、Native Method等信息，具体信息如下所示。

```js
config = ["HTSimpleAPI", Array[1]], moduleID = 0
methodName = "test", methodID = 0
config = null, moduleID = 1
config = null, moduleID = 2
config = ["RCTAccessibilityManager", Array[3]], moduleID = 3
methodName = "setAccessibilityContentSizeMultipliers", methodID = 0
methodName = "getMultiplier", methodID = 1
methodName = "getCurrentVoiceOverState", methodID = 2
```

还记得第二部分第5步中Native端生成的模块配置表吗？结合它的结构，我们可以得知：对于Module&Method，在Native和JS端都以数组的形式存放，数组下标即为它们的ModuleID和MethodID。

5.__nativeCall

分析完Bridge部分的映射关系以及模块加载，那么我们再来看看最终调用Native代码是如何实现的。当JS调用module.method时，其实调用了self.__nativeCall(module, method, args, onFail, onSucc)，对于__nativeCall方法：

```js
__nativeCall(module, method, params, onFail, onSucc) {
    if (onFail || onSucc) {
    ......
    onFail && params.push(this._callbackID);
    this._callbacks[this._callbackID++] = onFail;
    onSucc && params.push(this._callbackID);
    this._callbacks[this._callbackID++] = onSucc;
    }
this._queue[MODULE_IDS].push(module);
this._queue[METHOD_IDS].push(method);
this._queue[PARAMS].push(params);
global.nativeFlushQueueImmediate(this._queue);
......
}
```

这段代码为每个method创建了一个闭包fn，在__nativeCall方法中，并且在这里做了两件重要的工作：

* 1.把onFail和onSucc缓存到_callbacks中，同时把callbackID添加到params
* 2.把moduleID, methodID, params放入队列中，回调Native代码.

__nativeCall如何做到回调Native代码呢？看第二部分第3步，在初始化JS引擎JSExecutor Setup时，Native端注册一个全局block回调nativeFlushedQueueImmediate，nativeCall在处理完毕后，通过该回调把队列作为返回值传给Native。nativeFlushedQueueImmediate的实现如下所示。

```js
[self addSynchronousHookWithName:@"nativeFlushQueueImmediate" usingBlock:^(NSArray *calls){
RCTJSCExecutor *strongSelf = weakSelf;
    if (!strongSelf.valid || !calls) {
        return;
    }
[strongSelf->_bridge handleBuffer:calls batchEnded:NO];
}];
```

这里的handleBuffer就是Native端解析JS的模块调用最后通过NSInvocation机制调用Native代码对应的逻辑。有兴趣的朋友继续跟踪handleBuffer代码会发现，他的实现和React在JS端定义的MessageQueue有惊人的相似之处。

6.Call JS function & Callbacks

最后，我们回过头来看看Native端是如何调用JS端的相关逻辑的，这部分我们需要回到MessageQueue.js代码中来，可以看到MessageQueue暴露了3个核心方法：’invokeCallbackAndReturnFlushedQueue’、’callFunctionReturnFlushedQueue’、’flushedQueue’。

```js
// 将API暴露到全局作用域中
[
'invokeCallbackAndReturnFlushedQueue',
'callFunctionReturnFlushedQueue',
'flushedQueue',
].forEach((fn) => this[fn] = this[fn].bind(this));
…
// 声明带有返回值的函数
callFunctionReturnFlushedQueue(module, method, args) {
guard(() => {C
this.__callFunction(module, method, args);
this.__callImmediates();
});
return this.flushedQueue();
}
// 声明带有Callback的函数
invokeCallbackAndReturnFlushedQueue(cbID, args) {
guard(() => {
this.__invokeCallback(cbID, args);
this.__callImmediates();
});
return this.flushedQueue();
}
```

callFunctionReturnFlushedQueue用于实现Native调用带有返回值的JS端函数（这里的返回值也是通过Queue来模拟）；
invokeCallbackAndReturnFlushedQueue用于实现Native调用带有Call的JS端函数（可以将Native的Callback作为JS端函数的入参，JS端执行完后调用Native的Callback）。

对于callFunctionReturnFlushedQueue方法，它最终调用的是__callFunction：

```js
__callFunction(module, method, args) {
......
var moduleMethods = this._callableModules[module];
......
moduleMethods[method].apply(moduleMethods, args);
}
```

可以看到，此处会根据Native传入的module, method，调用JS端相应的模块并传入参数列表args.
同时我们又可以获得对于MessageQueue的另一条推测，_callableModules用来存放JS端暴露给Native的模块，进一步分析我们可以发现SDK中正是通过registerCallableModules方法注册JS端暴露API模块。

对于JS bridge提供的调用回调方法invokeCallbackAndReturnFlushedQueue，原理上和callFunction差不多，不再细说。

#### JS <-> Native 通信原理
1.Native->JS

综上所述，在JS端提供callFunctionReturnFlushedQueue，Native bridge调用JS端方法时，应该使用这个方法。查看Native代码实现可知，RCTBridge封装了enqueueJSCall方法调用JS，梳理Native->JS的整体交互流程如下图所示。

![](http://og1yl0w9z.bkt.clouddn.com/18-5-11/44610127.jpg)

之前已经论述过，如果在NATIVE端需要自定义模块提供给JS端使用那么该类需要实现RCTBridgeModule协议 。

此外，React-Native提供了另一种基于通知的方式，通过RCTEventDispatcher发送消息通知 。eventDispatcher作为Native Bridge的属性，封装了sendEventWithName:body:方法。使用时，Native中类同样需要实现RCTBridgeModule协议，通过self.bridge发送通知，JS端对应事件的EventEmitter添加监听处理调用。

> 查看sendEvent方法的代码可以发现，这种方式本质上还是调用enqueueJSCall方法。官方推荐我们使用通知的方式来实现 Native->JS，这样可以减少模块初始化加载解析的时间。

2.JS->Native

最后，我们来看一下JS如何调用Native。答案是JS不会主动传递数据给Native，也不能直接调用Native（一种情况除外，在入口直接通过NativeModules调用API），只有在Native调用JS时才会通过返回值触发调用。因为Native是基于事件响应机制的，比如触摸事件、启动事件、定时器事件、回调事件等。

当事件发生时，Native会调用JS相应模块处理，完毕后再通过返回值把队列传递给Native执行对应的代码。

![](http://og1yl0w9z.bkt.clouddn.com/18-5-11/39019479.jpg)

如上图所示，整个调用过程可以归纳为：

* 1.JS把需要Module, Method, args(CallbackID)保存在队列中， 作为返回值通过blocks回调Native
* 2.Native调用相应模块方法，完成
* 3.Native通过CallbackID调用JS回调

### 总结

React Native的通讯基础建立在传统的JS Bridge之上，不过对于Bridge处理的MessageQueue机制、模块定义、加载机制上的巧妙处理指的借鉴。对于上述的整个原理解析可以概括为以下四个部分：

* 1.在启动阶段，初始化JS引擎，生成Native端模块配置表存于两端，其中模块配置是同步取得，而各模块的方法配置在该方法被真正调用时懒加载。
* 2.Native和JS端分别有一个bridge，发生调用时，调用端bridge查找模块配置表将调用转换成{moduleID, methodID, args(callbackID)}，处理端通过同一份模块配置表转换为实际的方法实现。
* 3.Native->JS，原理上使用JSCore从Native执行JS代码，React-Native在此基础上给我们提供了通知发送的执行方式。
* 4.JS->Native，原理上JS并不主动调用Native，而是把方法和参数(回调)缓存到队列中，在Native事件触发并访问JS后，通过blocks回调Native。

> 以上原理解析文章来源：http://i.dotidea.cn/2016/05/react-native-communication-principle-for-ios/
