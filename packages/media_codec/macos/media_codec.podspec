Pod::Spec.new do |s|
  s.name = 'media_codec'
  s.version = '0.1.0'
  s.summary = 'Packet-driven remote video decoding and PCM output.'
  s.description = 'Trimmed FFmpeg decoding with native Flutter textures; no media player, demuxer or network stack.'
  s.homepage = 'https://github.com/scrcpy-connect/scrcpy-connect'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = { 'scrcpy-connect' => 'maintainers@scrcpy-connect.local' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/MediaCodecPlugin.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.frameworks = 'VideoToolbox', 'CoreMedia', 'CoreVideo', 'AudioToolbox', 'AVFoundation'
  root = ENV['MEDIA_CODEC_FFMPEG_ROOT']
  if root.nil? || root.empty?
    root = '$(DERIVED_FILE_DIR)/media_codec_ffmpeg/$(PLATFORM_NAME)/$(CURRENT_ARCH)'
    s.script_phase = {
      :name => 'Build pinned decode-only FFmpeg',
      :execution_position => :before_compile,
      :shell_path => '/bin/sh',
      :script => <<-SCRIPT
set -eu
mc_package_root="$(cd "$PODS_TARGET_SRCROOT/.." && pwd)"
for mc_apple_arch in $ARCHS; do
  case "$mc_apple_arch" in
    arm64) mc_ffmpeg_arch=arm64 ;;
    x86_64) mc_ffmpeg_arch=x64 ;;
    *) echo "Unsupported media_codec Apple architecture: $mc_apple_arch" >&2; exit 1 ;;
  esac
  python3 "$mc_package_root/tool/build_ffmpeg.py" --platform macos --arch "$mc_ffmpeg_arch" \
    --sdk "$PLATFORM_NAME" --prefix "$DERIVED_FILE_DIR/media_codec_ffmpeg/$PLATFORM_NAME/$mc_apple_arch"
done
      SCRIPT
    }
  end
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
    'HEADER_SEARCH_PATHS' => "$(inherited) \"#{root}/include\" \"$(PODS_TARGET_SRCROOT)/../native\"",
    'LIBRARY_SEARCH_PATHS' => "$(inherited) \"#{root}/lib\"",
    'OTHER_LDFLAGS' => '$(inherited) -lavcodec -lavutil -lswscale -lc++ -lz -lbz2 -liconv',
  }
end
