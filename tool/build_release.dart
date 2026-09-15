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

String findAdbExecutable() {
  // 1. android/local.properties 에서 sdk.dir 탐지
  try {
    final localProps = File('android/local.properties');
    if (localProps.existsSync()) {
      final lines = localProps.readAsLinesSync();
      for (var line in lines) {
        if (line.startsWith('sdk.dir=')) {
          final sdkPath = line.substring('sdk.dir='.length).trim().replaceAll('\\\\', '\\');
          final adbExe = File('$sdkPath\\platform-tools\\adb.exe');
          if (adbExe.existsSync()) return adbExe.path;
        }
      }
    }
  } catch (_) {}

  // 2. 기본 안드로이드 SDK 경로 확인
  final defaultAdb = File('C:\\Users\\IBCenter\\AppData\\Local\\Android\\sdk\\platform-tools\\adb.exe');
  if (defaultAdb.existsSync()) return defaultAdb.path;

  return 'adb';
}

Future<String?> findConnectedDeviceId(String adbCmd) async {
  try {
    var result = await Process.run(adbCmd, ['devices'], runInShell: true);
    if (result.exitCode == 0) {
      final lines = result.stdout.toString().split('\n');
      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.endsWith('device') && !trimmed.startsWith('List of')) {
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.isNotEmpty) return parts.first;
        }
      }
    }
  } catch (_) {}
  return null;
}

void main() async {
  print('========================================================');
  print('🚀 [AI Golf Coach] Release APK 빌드를 시작합니다...');
  print('========================================================\n');

  String flutterCmd = findFlutterExecutable();
  String adbCmd = findAdbExecutable();
  print('📌 Flutter 실행 경로: $flutterCmd');
  print('📌 ADB 실행 경로: $adbCmd\n');

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

      // 연결된 스마트폰 ID 감지
      final deviceId = await findConnectedDeviceId(adbCmd);

      if (deviceId != null) {
        print('\n📱 연결된 스마트폰($deviceId)으로 자동 설치 및 앱 실행 중...');
        final apkPath = '${Directory.current.path}\\build\\app\\outputs\\flutter-apk\\app-release.apk';

        var installResult = await Process.run(adbCmd, ['-s', deviceId, 'install', '-r', apkPath], runInShell: true);
        
        // 이전 디버그 서명 앱이 설치되어 있어 충돌 발생 시 자동 언인스톨 후 재설치
        if (installResult.exitCode != 0) {
          print('💡 기존 설치 앱과 서명이 달라 자동 삭제 후 클린 재설치를 시도합니다...');
          await Process.run(adbCmd, ['-s', deviceId, 'uninstall', 'com.metaoffice.aigolfcoatch'], runInShell: true);
          installResult = await Process.run(adbCmd, ['-s', deviceId, 'install', '-r', apkPath], runInShell: true);
        }

        if (installResult.exitCode == 0) {
          print('✅ 기기($deviceId)에 앱 설치 완료!');
          var startResult = await Process.run(
            adbCmd,
            ['-s', deviceId, 'shell', 'am', 'start', '-n', 'com.metaoffice.aigolfcoatch/.MainActivity'],
            runInShell: true,
          );
          if (startResult.exitCode == 0) {
            print('🚀 스마트폰에서 앱이 성공적으로 실행되었습니다!');
          } else {
            print('⚠️ 앱 실행 실패: ${startResult.stderr}');
          }
        } else {
          print('⚠️ 설치 실패: ${installResult.stdout} ${installResult.stderr}');
        }
      } else {
        print('\n💡 연결된 스마트폰을 찾을 수 없어 APK 파일 생성만 완료되었습니다.');
      }
    } else {
      print('\n❌ 빌드 중 오류가 발생했습니다. (Exit Code: $exitCode)');
    }
  } catch (e) {
    print('❌ 실행 중 오류가 발생했습니다: $e');
  }
}
