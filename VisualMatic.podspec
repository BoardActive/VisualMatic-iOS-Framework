#
# Be sure to run `pod lib lint VisualMatic.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'VisualMatic'
  s.version          = '1.0'
  s.summary          = 'A short description of VisualMatic.'
  s.description      = 'Description of visual matic framework'
  s.homepage         = 'https://boardactive.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'innovify' => 'krishna.solanki@innovify.in' }
  s.source           = { :git => 'https://github.com/BoardActive/VisualMatic-iOS-Framework.git', :tag => s.version.to_s }

  s.ios.deployment_target = '11.0'
  s.swift_version         = '5.0'
  s.source_files = 'VisualMatic/Source/**/*.{swift,h,m,storyboard}'
  s.static_framework = true
  s.resources = 'VisualMatic/**/*.{png,jpeg,jpg,storyboard,xib,xcassets}

#   s.resource_bundles = {
#     'VisualMatic' => ['VisualMatic/**/*.{storyboard,lproj}']
#   }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
  s.dependency 'BAKit-iOS', '~> 2.0.11'
  s.dependency 'Firebase/Messaging'
  s.dependency 'GoogleMLKit/BarcodeScanning', '~> 2.1.0'
  s.dependency 'GoogleMLKit/FaceDetection', '~> 2.1.0'
  s.dependency 'GoogleMLKit/ImageLabeling', '~> 2.1.0'
  s.dependency 'GoogleMLKit/ImageLabelingCustom', '~> 2.1.0'
  s.dependency 'GoogleMLKit/ObjectDetection', '~> 2.1.0'
  s.dependency 'GoogleMLKit/ObjectDetectionCustom', '~> 2.1.0'
  s.dependency 'GoogleMLKit/TextRecognition', '~> 2.1.0'
end
