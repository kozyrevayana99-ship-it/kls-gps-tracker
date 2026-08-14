#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint kls_gps_tracker.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'kls_gps_tracker'
  s.version          = '0.4.0'
  s.summary          = 'KLS professional GPS workout tracking plugin for Flutter'
  s.description      = <<-DESC
KLS professional GPS workout tracking plugin for Flutter
                       DESC
  s.homepage         = 'https://github.com/kozyrevayana99-ship-it/kls-gps-tracker'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'kls_gps_tracker/Sources/kls_gps_tracker/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'kls_gps_tracker_privacy' => [
      'kls_gps_tracker/Sources/kls_gps_tracker/PrivacyInfo.xcprivacy'
    ]
  }
end
