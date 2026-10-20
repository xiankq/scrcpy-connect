import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../tooling.dart';

const version = '5.0.1';
const commit = 'a60891aea193d92e7e5c3942700eca63f9d19a5f';
const sourceSha =
    'a0d699fc7388b8252416c49e6293639de39ab76a03e7302ddced56c284d45200';
const officialSha =
    '764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536';
const gradleVersion = '9.8.1';
const gradleSha =
    'dce76f55f8e251a3a1f130eb120f30b3d271de2b76c9b0729d316b5a1b6dc01f';
const desugarCommit = '73170c345e6a762fc6a1f0301bb15218850023ef';
const desugarSourceSha =
    '4cd2faa88ecb2450522fd4f0dcd11d6df878d7197b2276fb35532c50267f7a64';
const desugarSourceName = 'desugar_jdk_libs-2.1.5-source.tar.gz';
const dependencies = {
  'desugar_jdk_libs':
      'd8044befae095781b9a80bf1faa92edc30382d75d437476784c1bf991598a976',
  'desugar_jdk_libs_configuration':
      '7bc9051b3a1ec19806311dcb6aa9b9ba7ef9c22caa6f4810da55bde285fb7770',
};
const androidJarSha =
    'd9eb9da824d9e247a352f570f01e1169e725b2954bca9e283a71786c59b59f9a';
const buildAddition = '''
// Build-only core library API desugaring. Upstream Java sources are unchanged.
android {
    buildToolsVersion '37.0.0'
    compileOptions {
        coreLibraryDesugaringEnabled true
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.5'
}
''';
const licenseFiles = [
  'LICENSE-scrcpy',
  'LICENSE-desugar_jdk_libs',
  'ASSEMBLY_EXCEPTION-desugar_jdk_libs',
  'ADDITIONAL_LICENSE_INFO-desugar_jdk_libs',
  'LICENSE-desugar_jdk_libs_configuration',
];

Directory get here =>
    Directory(p.join(repositoryRoot().path, 'servers', 'vendor'));
File get artifact => File(p.join(here.path, 'scrcpy-server-v$version'));
String sourceUrl(String revision, [String project = 'Genymobile/scrcpy']) =>
    'https://codeload.github.com/$project/tar.gz/$revision';

({
  Map<String, List<String>> definitions,
  List<String> types,
  List<String> markers,
})
dexInfo(List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  require(data.length >= 112, 'Truncated DEX');
  require(
    sameJson(data.sublist(0, 8), [100, 101, 120, 10, 48, 51, 53, 0]),
    'Expected Android 5 compatible DEX 035',
  );
  require(
    sameJson(crypto.sha1.convert(data.sublist(32)).bytes, data.sublist(12, 32)),
    'Invalid DEX signature',
  );
  final view = ByteData.sublistView(data);
  int u32(int offset) => view.getUint32(offset, Endian.little);
  int u16(int offset) => view.getUint16(offset, Endian.little);
  final strings = <String>[];
  for (var i = 0; i < u32(56); i++) {
    var offset = u32(u32(60) + 4 * i);
    while (data[offset] & 128 != 0) {
      offset++;
    }
    offset++;
    var end = offset;
    while (data[end] != 0) {
      end++;
    }
    strings.add(utf8.decode(data.sublist(offset, end), allowMalformed: true));
  }
  final types = [
    for (var i = 0; i < u32(64); i++) strings[u32(u32(68) + 4 * i)],
  ];
  final definitions = <String, List<String>>{};
  for (var i = 0; i < u32(96); i++) {
    final offset = u32(100) + 32 * i;
    final interfaceOffset = u32(offset + 12);
    definitions[types[u32(offset)]] = interfaceOffset == 0
        ? []
        : [
            for (var j = 0; j < u32(interfaceOffset); j++)
              types[u16(interfaceOffset + 4 + 2 * j)],
          ];
  }
  final markers = strings
      .where((value) => RegExp(r'^~~(?:D8|L8|R8)\{').hasMatch(value))
      .toList();
  require(markers.isNotEmpty, 'Missing D8/L8/R8 build provenance');
  for (final marker in markers) {
    final metadata = jsonDecode(marker.substring(4)) as Map<String, dynamic>;
    require(metadata['min-api'] == 21, 'DEX was not built with min API 21');
    require(metadata['version'] == '9.4.24', 'Unexpected D8/L8/R8 version');
  }
  return (definitions: definitions, types: types, markers: markers);
}

Archive _verifiedZip(List<int> bytes) {
  final decoder = ZipDecoder();
  final archive = decoder.decodeBytes(bytes, verify: true);
  final names = <String>{};
  // archive 4 deduplicates names and no longer verifies CRCs during decode.
  for (final header in decoder.directory.fileHeaders) {
    require(names.add(header.filename), 'Duplicate ZIP entries');
    final file = header.file;
    require(
      file != null && header.crc32 == file.crc32 && file.verifyCrc32(),
      'Corrupt ZIP entry: ${header.filename}',
    );
  }
  return archive;
}

Map<String, Object?> verifyArtifact(List<int> bytes) {
  final archive = _verifiedZip(bytes);
  final names = archive.files.map((file) => file.name).toList();
  final dexNames =
      names
          .where(
            (name) => RegExp(r'^classes(?:[2-9][0-9]*)?\.dex$').hasMatch(name),
          )
          .toList()
        ..sort();
  require(
    sameJson(dexNames, ['classes.dex', 'classes2.dex']),
    'Expected both program and backfill DEX',
  );
  final definitions = <String, List<String>>{};
  final references = <String>{};
  final dex = <String, Object?>{};
  for (final name in dexNames) {
    final content = archiveBytes(archive.findFile(name)!);
    final info = dexInfo(content);
    require(
      definitions.keys
          .toSet()
          .intersection(info.definitions.keys.toSet())
          .isEmpty,
      'Duplicate DEX class definitions',
    );
    definitions.addAll(info.definitions);
    references.addAll(info.types);
    dex[name] = {
      'sha256': sha256(content),
      'classes': info.definitions.length,
      'markers': info.markers,
    };
  }
  for (final name in licenseFiles) {
    final embedded = archive.findFile('META-INF/$name');
    require(
      embedded != null &&
          sameJson(
            archiveBytes(embedded),
            File(p.join(here.path, name)).readAsBytesSync(),
          ),
      'Missing/changed embedded license: $name',
    );
  }
  for (final name in [
    'Lcom/genymobile/scrcpy/Server;',
    'Lcom/genymobile/scrcpy/model/Size;',
    'Ljava/util/function/Predicate;',
    'Ljava/util/function/Supplier;',
    r'Lj$/util/function/Predicate$-CC;',
  ]) {
    require(
      definitions.containsKey(name),
      'Missing runtime class definition: $name',
    );
  }
  require(
    sameJson(
      definitions[r'Lcom/genymobile/scrcpy/model/Size$$ExternalSyntheticLambda0;'],
      ['Ljava/util/function/Predicate;'],
    ),
    'Unexpected Size lambda interface',
  );
  final missing =
      references
          .where(
            (type) =>
                type.startsWith('Ljava/util/function/') &&
                !definitions.containsKey(type),
          )
          .toList()
        ..sort();
  require(missing.isEmpty, 'Unresolved function backfill classes: $missing');
  return dex;
}

Uint8List package(File apk) {
  final source = _verifiedZip(apk.readAsBytesSync());
  final contents = <String, List<int>>{
    for (final file in source.where((file) => file.name.endsWith('.dex')))
      file.name: archiveBytes(file),
    for (final name in licenseFiles)
      'META-INF/$name': File(p.join(here.path, name)).readAsBytesSync(),
  };
  return storedZip({
    for (final name in contents.keys.toList()..sort()) name: contents[name]!,
  }, date: DateTime.utc(1980));
}

Map<String, String> trackedInputs() => {
  for (final name in [
    '../tooling.dart',
    'build.dart',
    'test/ScrcpyApi21Probe.java',
    'test/build_probe.dart',
    ...licenseFiles,
  ])
    name: digest(File(p.join(here.path, name))),
};

void check() {
  final manifest = readJson(File(p.join(here.path, 'manifest.json')));
  final source = manifest['source'] as Map<String, dynamic>;
  require(
    manifest['version'] == version && source['commit'] == commit,
    'Source version mismatch',
  );
  require(source['archiveSha256'] == sourceSha, 'Source pin mismatch');
  require(
    (manifest['officialRelease'] as Map<String, dynamic>)['sha256'] ==
        officialSha,
    'Official release provenance mismatch',
  );
  require(
    sameJson(manifest['inputs'], trackedInputs()),
    'Build/test/license inputs changed; rebuild vendor artifact',
  );
  require(
    digest(File(p.join(here.path, desugarSourceName))) == desugarSourceSha,
    'Corresponding source archive mismatch',
  );
  final bytes = artifact.readAsBytesSync();
  final output = manifest['artifact'] as Map<String, dynamic>;
  require(
    output['sha256'] == sha256(bytes),
    'Server artifact SHA-256 mismatch',
  );
  require(output['bytes'] == bytes.length, 'Server artifact size mismatch');
  require(
    sameJson(manifest['dex'], verifyArtifact(bytes)),
    'DEX provenance mismatch',
  );
  stdout.writeln(
    'OK scrcpy $version, min API 21, program + function backfill; SHA-256 ${sha256(bytes)}',
  );
}

Future<File> getGradle(ArgResults options, Directory temporary) async {
  final override = options['gradle'] as String?;
  final File executable;
  if (override != null) {
    executable = File(override).absolute;
  } else {
    final bytes = await download(
      'https://services.gradle.org/distributions/gradle-$gradleVersion-bin.zip',
      gradleSha,
    );
    await extractArchive(_verifiedZip(bytes), temporary);
    executable = File(
      p.join(
        temporary.path,
        'gradle-$gradleVersion',
        'bin',
        Platform.isWindows ? 'gradle.bat' : 'gradle',
      ),
    );
    if (!Platform.isWindows) await run('chmod', ['755', executable.path]);
  }
  final result = await run(executable.path, ['--version']);
  require(
    (result.stdout as String).contains('Gradle $gradleVersion\n'),
    'Gradle version mismatch',
  );
  return executable;
}

Future<void> build(ArgResults options) async {
  final sdk = androidSdk(options['sdk'] as String?);
  require(
    Platform.environment['JAVA_HOME'] != null &&
        File(javaTool('javac')).existsSync(),
    'Set JAVA_HOME to OpenJDK 21',
  );
  final javaVersion =
      (await run(javaTool('java'), ['-version'])).stderr as String;
  require(javaVersion.contains('version "21.'), 'OpenJDK 21 is required');
  final android = File(
    p.join(sdk.path, 'platforms', 'android-36', 'android.jar'),
  );
  require(
    android.existsSync() && digest(android) == androidJarSha,
    'Install the pinned Android API 36 platform',
  );
  require(
    File(
      p.join(
        sdk.path,
        'build-tools',
        '37.0.0',
        Platform.isWindows ? 'aapt2.exe' : 'aapt2',
      ),
    ).existsSync(),
    'Install Android build-tools 37.0.0',
  );
  await withTemporary('scrcpy-vendor-build-', (temporary) async {
    final gradle = await getGradle(options, temporary);
    final source = await download(sourceUrl(commit), sourceSha);
    await extractArchive(
      TarDecoder().decodeBytes(GZipDecoder().decodeBytes(source, verify: true)),
      temporary,
    );
    final root = Directory(p.join(temporary.path, 'scrcpy-$commit'));
    Map<String, String> javaSources() => {
      for (final file in files(
        Directory(p.join(root.path, 'server', 'src')),
        '.java',
      ))
        relative(file.path, root.path): digest(file),
    };
    final originalSources = javaSources();
    final upstreamBuild = File(p.join(root.path, 'build.gradle'));
    const upstreamAgp = 'com.android.tools.build:gradle:9.1.0';
    final upstreamBuildText = upstreamBuild.readAsStringSync();
    require(
      upstreamBuildText.contains(upstreamAgp),
      'Unexpected upstream Android Gradle plugin declaration',
    );
    await upstreamBuild.writeAsString(
      upstreamBuildText.replaceAll(
        upstreamAgp,
        'com.android.tools.build:gradle:9.4.1',
      ),
    );
    final buildFile = File(p.join(root.path, 'server', 'build.gradle'));
    await buildFile.writeAsString(
      '${buildFile.readAsStringSync()}$buildAddition',
    );
    await run(
      gradle.path,
      [
        '--no-daemon',
        '--max-workers=2',
        ':server:assembleRelease',
        if (options['offline'] as bool) '--offline',
        ...options['gradle-arg'] as List<String>,
      ],
      cwd: root,
      environment: {'ANDROID_HOME': sdk.path},
      echo: true,
    );
    require(
      sameJson(originalSources, javaSources()),
      'Upstream Java source changed',
    );
    final gradleHome = Directory(
      Platform.environment['GRADLE_USER_HOME'] ?? p.join(userHome, '.gradle'),
    );
    for (final entry in dependencies.entries) {
      final directory = Directory(
        p.join(
          gradleHome.path,
          'caches',
          'modules-2',
          'files-2.1',
          'com.android.tools',
          entry.key,
          '2.1.5',
        ),
      );
      final jars = directory.existsSync() ? files(directory, '.jar') : <File>[];
      require(
        jars.isNotEmpty && jars.every((file) => digest(file) == entry.value),
        'Desugar dependency SHA mismatch: ${entry.key}',
      );
    }
    final bytes = package(
      File(
        p.join(
          root.path,
          'server',
          'build',
          'outputs',
          'apk',
          'release',
          'server-release-unsigned.apk',
        ),
      ),
    );
    final dex = verifyArtifact(bytes);
    if (options['rebuild'] as bool) {
      require(
        sameJson(bytes, artifact.readAsBytesSync()),
        'Clean build differs: ${sha256(bytes)} != ${digest(artifact)}',
      );
      stdout.writeln('OK clean source rebuild is byte-for-byte identical');
      return;
    }
    // Preserve the source-set hash encoding used by the existing provenance.
    final names = originalSources.keys.toList()..sort();
    final sourceJson =
        '{${names.map((name) => '${jsonEncode(name)}: ${jsonEncode(originalSources[name])}').join(', ')}}';
    final manifest = <String, Object?>{
      'schema': 1,
      'version': version,
      'kind': 'source-built-core-library-desugared',
      'source': {
        'commit': commit,
        'archiveUrl': sourceUrl(commit),
        'archiveSha256': sourceSha,
        'javaSourcesSha256': sha256(utf8.encode(sourceJson)),
        'javaSourcesUnmodified': true,
      },
      'officialRelease': {
        'url':
            'https://github.com/Genymobile/scrcpy/releases/download/v$version/scrcpy-server-v$version',
        'sha256': officialSha,
        'bundled': false,
      },
      'artifact': {
        'file': p.basename(artifact.path),
        'sha256': sha256(bytes),
        'bytes': bytes.length,
      },
      'toolchain': {
        'gradle': gradleVersion,
        'gradleDistributionSha256': gradleSha,
        'agp': '9.4.1',
        'd8L8R8': '9.4.24',
        'jdkMajor': 21,
        'buildJdk': const LineSplitter().convert(javaVersion).first,
        'compileSdk': 36,
        'androidJarSha256': androidJarSha,
        'buildTools': '37.0.0',
        'minApi': 21,
        'targetApi': 36,
        'javaSourceTarget': '1.8',
      },
      'desugaring': {
        'version': '2.1.5',
        'dependencies': {
          for (final entry in dependencies.entries)
            'com.android.tools:${entry.key}': {
              'version': '2.1.5',
              'sha256': entry.value,
            },
        },
        'sourceCommit': desugarCommit,
        'sourceArchive': desugarSourceName,
        'sourceUrl': sourceUrl(desugarCommit, 'google/desugar_jdk_libs'),
        'sourceSha256': desugarSourceSha,
        'functionStrategy': r'Official maintain_type: java.util.function definitions in classes2.dex; default methods in j$.util.function',
      },
      'dex': dex,
      'inputs': trackedInputs(),
    };
    final staging = File('${artifact.path}.new');
    try {
      await staging.writeAsBytes(bytes);
      await staging.rename(artifact.path);
    } finally {
      if (staging.existsSync()) await staging.delete();
    }
    writeJson(File(p.join(here.path, 'manifest.json')), manifest);
    check();
  });
}

Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addFlag('check', negatable: false)
    ..addFlag('rebuild', negatable: false)
    ..addFlag('update', negatable: false)
    ..addOption('sdk')
    ..addOption('gradle')
    ..addFlag('offline', negatable: false)
    ..addMultiOption('gradle-arg', splitCommas: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    stdout.writeln(
      'Build pinned, unmodified scrcpy sources. Choose --check, --rebuild or --update.\n${parser.usage}',
    );
    return;
  }
  require(
    options.rest.isEmpty &&
        [
              'check',
              'rebuild',
              'update',
            ].where((name) => options[name] as bool).length ==
            1,
    'Choose exactly one of --check, --rebuild or --update',
  );
  if (options['check'] as bool) {
    check();
  } else {
    require(
      digest(File(p.join(here.path, desugarSourceName))) == desugarSourceSha,
      'Corresponding source archive missing/changed',
    );
    await build(options);
  }
});
