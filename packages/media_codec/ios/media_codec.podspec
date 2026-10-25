Pod::Spec.new do |s|
  s.name = 'media_codec'
  s.version = '0.1.0'
  s.summary = 'Packet-driven remote video decoding and PCM output.'
  s.description = 'Trimmed FFmpeg decoding with native Flutter textures; no media player, demuxer or network stack.'
  s.homepage = 'https://github.com/scrcpy-connect/scrcpy-connect'
  s.license = { :type => 'Unspecified', :text => 'Project license not specified. Bundled FFmpeg and dav1d retain their upstream licenses; see the application media_codec notices.' }
  s.author = { 'scrcpy-connect' => 'maintainers@scrcpy-connect.local' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/MediaCodecPlugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'VideoToolbox', 'CoreMedia', 'CoreVideo', 'CoreImage', 'Metal', 'CoreGraphics', 'AudioToolbox', 'AVFoundation', 'CoreFoundation', 'Security'
  s.libraries = 'media_codec_native', 'c++', 'z', 'bz2', 'iconv'
  root = ENV['MEDIA_CODEC_FFMPEG_ROOT']
  root = '$(PODS_CONFIGURATION_BUILD_DIR)/media_codec_ffmpeg/$(PLATFORM_NAME)/$(CURRENT_ARCH)' if root.nil? || root.empty?
  s.script_phase = {
    :name => 'Build Rust packet decoder and pinned FFmpeg',
    :execution_position => :before_compile,
    :shell_path => '/bin/sh',
    :script => '/bin/sh "$PODS_TARGET_SRCROOT/../darwin/build_native.sh" ios'
  }
  # FRB 由 Dart 动态查找，显式保留同一 framework 内 Rust 静态库的入口。
  frb_symbols = File.readlines(File.expand_path('../native/frb_symbols.list', __dir__), chomp: true)
  frb_link_flags = frb_symbols.map { |symbol| "-Wl,-u,_#{symbol}" }.join(' ')
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => "$(inherited) #{frb_link_flags}",
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
    'HEADER_SEARCH_PATHS' => "$(inherited) \"#{root}/include\" \"$(PODS_TARGET_SRCROOT)/../native\"",
    'LIBRARY_SEARCH_PATHS' => "$(inherited) \"#{root}/lib\"",
  }
  s.user_target_xcconfig = { 'LIBRARY_SEARCH_PATHS' => "$(inherited) \"#{root}/lib\"" }
end
