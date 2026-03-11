Pod::Spec.new do |s|
  s.name             = 'asset_shield'
  s.version          = '0.0.1'
  s.summary          = 'Asset Shield native crypto'
  s.description      = 'Prebuilt native crypto for Asset Shield.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Asset Shield' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :osx, '10.13'

  s.vendored_libraries = 'Frameworks/libasset_shield_crypto.dylib'
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.requires_arc = false
end
