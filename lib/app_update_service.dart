import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final String releaseUrl;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.releaseUrl,
  });
}

class AppUpdateService {
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/Oliur292007/SOLO-SYSTEM/releases/latest';

  Future<AppUpdateInfo?> checkForUpdate() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ShadowLearner-Android');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await response.transform(utf8.decoder).join();
      final release = jsonDecode(body);
      if (release is! Map<String, dynamic>) return null;

      final tag = release['tag_name']?.toString() ?? '';
      final match = RegExp(r'^v?(\d+\.\d+\.\d+)[+-](\d+)$')
          .firstMatch(tag);
      if (match == null) return null;

      final latestVersion = match.group(1)!;
      final latestBuild = int.tryParse(match.group(2)!) ?? 0;
      final current = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(current.buildNumber) ?? 0;
      if (latestBuild <= currentBuild) return null;

      final assets = release['assets'];
      if (assets is! List) return null;
      String? apkUrl;
      for (final asset in assets) {
        if (asset is Map &&
            asset['name']?.toString() == 'app-release.apk') {
          apkUrl = asset['browser_download_url']?.toString();
          break;
        }
      }
      if (apkUrl == null || apkUrl.isEmpty) return null;

      return AppUpdateInfo(
        version: latestVersion,
        buildNumber: latestBuild,
        releaseNotes: release['body']?.toString() ?? 'A new version is available.',
        downloadUrl: apkUrl,
        releaseUrl: release['html_url']?.toString() ?? apkUrl,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
