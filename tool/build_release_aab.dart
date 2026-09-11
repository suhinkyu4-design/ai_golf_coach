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
  print('🚀 [AI Golf Coach] Play 스토어용 Release AAB 빌드를 시작합니다...');
  print('========================================================\n');

  String flutterCmd = findFlutterExecutable();
  print('📌 Flutter 실행 경로: $flutterCmd\n');

  // 환경변수에서 ANDROID_PREFS_ROOT 완전 제거
  final env = Map<String, String>.from(Platform.environment);
  env.remove('ANDROID_PREFS_ROOT');

  try {
    var process = await Process.start(
      flutterCmd,
      ['build', 'appbundle', '--release'],
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
      print('✅ Release AAB 빌드가 성공적으로 완료되었습니다!');
      print('📦 생성된 AAB 파일 위치:');
      print('   ${Directory.current.path}\\build\\app\\outputs\\bundle\\release\\app-release.aab');
      print('========================================================');
    } else {
      print('\n❌ 빌드 중 오류가 발생했습니다. (Exit Code: $exitCode)');
    }
  } catch (e) {
    print('❌ 실행 중 오류가 발생했습니다: $e');
  }
}
