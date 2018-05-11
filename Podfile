# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'iOSPrinciple_ReactNative' do
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  # use_frameworks!

  pod 'SVProgressHUD', '~> 2.2.2'


  # React 组件
  # 根据实际路径修改下面的`:path`
  pod 'React', :path => './react/node_modules/react-native', :subspecs => [
  'Core',
  'RCTText',
  'RCTNetwork',
  'RCTWebSocket', # 这个模块是用于调试功能的
  # 在这里继续添加你所需要的模块
  ]
  # 如果你的RN版本 >= 0.42.0，请加入下面这行
  pod "Yoga", :path => "./react/node_modules/react-native/ReactCommon/yoga"

  # Pods for iOSPrinciple_ReactNative

  target 'iOSPrinciple_ReactNativeTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'iOSPrinciple_ReactNativeUITests' do
    inherit! :search_paths
    # Pods for testing
  end

end
