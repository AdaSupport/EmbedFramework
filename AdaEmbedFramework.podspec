Pod::Spec.new do |spec|

  spec.name         = "AdaEmbedFramework"
  spec.version      = "1.3.6"
  spec.summary      = "Embed the Ada Support SDK in your app."
  spec.description  = "Use the Ada Support SDK to inject the Ada support experience into your app. Visit https://ada.support to learn more."
  spec.homepage     = "https://github.com/AdaSupport/ios-sdk"
  spec.license         = { :type => "COMMERCIAL", :text => "" }
  spec.author       = { "Ada Support" => "nic@ada.support" }
  spec.platform     = :ios, "10.0"
  spec.source       = { :git => "https://github.com/AdaSupport/ios-sdk.git", :branch => 'master', :tag => spec.version.to_s }
  spec.source_files = "EmbedFramework/**/*.swift"
  spec.resource_bundles = { "AdaEmbedFramework" => ['EmbedFramework/**/*.xcassets', 'EmbedFramework/AdaWebHostViewController.storyboard'] }
  spec.swift_version = '5.0'
end
