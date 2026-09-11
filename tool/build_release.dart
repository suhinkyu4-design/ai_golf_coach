import 'dart:io';

String findFlutterExecutable() {
  // 1. android/local.properties 에서 flutter.sdk 경로 감지
  try {
    final localProps = File('android/local.properties');
    if (localProps.existsSync()) {
      final lines = localProps.readAsLinesSync();
      for (var line in lines) {
        if (line.startsWith('flutter.sdk=')) {
          final sdkPath = line.substring('flutter.sdk='.length).trim().replaceAll('\\\\', '\\');
          final bat = File('$sdkPath\\bin\\flutter.bat');
          if (bat.existsSync()) return bat.path;
          final exe = File('$sdkPath\\bin\\flutter');
          if (exe.existsSync()) return exe.path;
        }
      }
    }
  } catch (_) {}

  // 2. FLUTTER_ROOT 환경변수 확인
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final bat = File('$flutterRoot\\bin\\flutter.bat');
    if (bat.existsSync()) return bat.path;
  }

  // 3. FVM 기본 경로 확인
  final fvmDefault = File('C:\\Users\\IBCenter\\fvm\\versions\\3.16.9\\bin\\flutter.bat');
  if (fvmDefault.existsSync()) return fvmDefault.path;

  // 4. 기본 시스템 PATH
  return Platform.isWindows ? 'flutter.bat' : 'flutter';
}

void main() async {
  print('========================================================');
  print('🚀 [AI Golf Coach] Release APK 빌드를 시작합니다...');
  print('========================================================\n');

  String flutterCmd = findFlutterExecutable();
  print('📌 Flutter 실행 경로: $flutterCmd\n');

  // Gradle 환경변수 중복 설정 해제
  final env = Map<String, String>.from(Platform.environment);
  env.remove('ANDROID_PREFS_ROOT');

  try {
    var process = await Process.start(
      flutterCmd,
      ['build', 'apk', '--release'],
      runInShell: true,
      workingDirectory: Directory.current.path,
      environment: env,
      includeParentEnvironment: false,
    );

    // 실시간 출력 전달
    process.stdout.listen((data) => stdout.add(data));
    process.stderr.listen((data) => stderr.add(data));

    int exitCode = await process.exitCode;

    if (exitCode == 0) {
      print('\n========================================================');
      print('✅ Release APK 빌드가 성공적으로 완료되었습니다!');
      print('📦 생성된 APK 파일 위치:');
      print('   ${Directory.current.path}\\build\\app\\outputs\\flutter-apk\\app-release.apk');
      print('========================================================');

      // 연결된 스마트폰이 있으면 자동 설치 및 실행
      print('\n📱 연결된 스마트폰으로 자동 설치 및 앱 실행 중...');
      final apkPath = '${Directory.current.path}\\build\\app\\outputs\\flutter-apk\\app-release.apk';
      
      var installResult = await Process.run('adb', ['install', '-r', apkPath], runInShell: true);
      if (installResult.exitCode == 0) {
        print('✅ 기기에 앱 설치 완료!');
        var startResult = await Process.run(
          'adb',
          ['shell', 'am', 'start', '-n', 'com.metaoffice.aigolfcoatch/.MainActivity'],
          runInShell: true,
        );
        if (startResult.exitCode == 0) {
          print('🚀 스마트폰에서 앱이 성공적으로 실행되었습니다!');
        }
      } else {
        print('💡 스마트폰이 연결되어 있지 않아 파일 생성만 완료되었습니다.');
      }
    } else {
      print('\n❌ 빌드 중 오류가 발생했습니다. (Exit Code: $exitCode)');
    }
  } catch (e) {
    print('❌ 실행 중 오류가 발생했습니다: $e');
  }
}
