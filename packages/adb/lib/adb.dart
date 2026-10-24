/// 统一 ADB 协议能力及调用方持有的宿主生命周期。
library;

export 'src/adb_host.dart';
export 'src/api.dart';
export 'src/local_files.dart';
export 'src/native/initialize.dart'
    show
        createNativeAdbApi,
        initializeNativeAdb,
        prepareAdbIdentity,
        createNativeLocalFiles;
export 'src/native_client.dart'
    show NativeAdbClient, NativeAdbConnectionAttempt;
