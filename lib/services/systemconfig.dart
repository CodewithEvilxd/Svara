import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../shared/constants.dart';

bool isAppUpdateAvailable = false;

class SystemUiConfigurator {
  static Future<void> configure() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
}

Future<void> checkForUpdate() async {
  await Future.delayed(const Duration(seconds: 1));

  if (!await InternetConnection().hasInternetAccess) {
    debugPrint('[UPDATERTOOL] Update check skipped: no internet connection.');
    return;
  }

  try {
    final updateInfo = await githubUpdate();
    isAppUpdateAvailable = updateInfo['results'] == true;
    debugPrint(
      '[UPDATERTOOL] Update available: $isAppUpdateAvailable (${updateInfo['newVer'] ?? 'n/a'})',
    );
  } catch (e) {
    debugPrint('[UPDATERTOOL] Update check failed: $e');
    isAppUpdateAvailable = false;
  }
}

bool isUpdateAvailable(
  String currentVer,
  String currentBuild,
  String newVer,
  String newBuild, {
  bool checkBuild = true,
}) {
  try {
    final currentParts = currentVer.split('.').map(int.parse).toList();
    final newParts = newVer.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }

    if (checkBuild) {
      final currBuild = int.tryParse(currentBuild) ?? 0;
      final nextBuild = int.tryParse(newBuild) ?? 0;
      return nextBuild > currBuild;
    }
  } catch (e) {
    debugPrint('[UPDATERTOOL] Version comparison failed: $e');
  }

  return false;
}

Future<Map<String, dynamic>> githubUpdate() async {
  final packageInfo = await PackageInfo.fromPlatform();

  try {
    final response = await get(
      Uri.parse('https://api.github.com/repos/codewithevilxd/svara/releases/latest'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Svara-App',
      },
    );

    if (response.statusCode != 200) {
      debugPrint('[UPDATERTOOL] GitHub API failed: ${response.statusCode}');
      return {'results': false};
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final tagName = (data['tag_name'] as String? ?? '').trim();
    final tagParts = tagName.split('+');
    final version =
        tagParts.isNotEmpty && tagParts.first.isNotEmpty
            ? tagParts.first.replaceFirst('v', '')
            : '0.0.0';
    final newBuild = tagParts.length > 1 ? tagParts[1] : '0';

    return {
      'results': isUpdateAvailable(
        packageInfo.version,
        packageInfo.buildNumber,
        version,
        newBuild,
        checkBuild: false,
      ),
      'currVer': packageInfo.version,
      'currBuild': packageInfo.buildNumber,
      'newVer': version,
      'newBuild': newBuild,
      'download_url': latestReleaseUrl,
    };
  } catch (e) {
    debugPrint('[UPDATERTOOL] GitHub check error: $e');
    return {'results': false};
  }
}
