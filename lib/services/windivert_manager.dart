import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

class WinDivertPaths {
  const WinDivertPaths({
    required this.dllPath,
    required this.sysPath,
  });

  final String dllPath;
  final String sysPath;

  String get directory => File(dllPath).parent.path;

  bool get isReady => File(dllPath).existsSync() && File(sysPath).existsSync();
}

/// Handles extracting WinDivert runtime files for process-based split tunneling on Windows.
class WinDivertManager {
  static const String _dllAsset = 'assets/bin/WinDivert.dll';
  static const String _driverAsset = 'assets/bin/WinDivert64.sys';

  WinDivertPaths? _cachedPaths;

  Future<WinDivertPaths?> ensureAvailable() async {
    if (!Platform.isWindows) {
      return null;
    }

    if (_cachedPaths?.isReady == true) {
      return _cachedPaths;
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      final binDir = Directory('${supportDir.path}/bin');
      if (!binDir.existsSync()) {
        binDir.createSync(recursive: true);
      }

      final dllFile = File('${binDir.path}/WinDivert.dll');
      final driverFile = File('${binDir.path}/WinDivert64.sys');

      await _writeIfNeeded(_dllAsset, dllFile);
      await _writeIfNeeded(_driverAsset, driverFile);

      final paths = WinDivertPaths(
        dllPath: dllFile.path,
        sysPath: driverFile.path,
      );
      if (!paths.isReady) {
        return null;
      }
      _cachedPaths = paths;
      return paths;
    } catch (e, stack) {
      debugPrint('[WinDivertManager] Failed to prepare WinDivert: $e\n$stack');
      return null;
    }
  }

  Future<void> _writeIfNeeded(String asset, File target) async {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    var needsWrite = !target.existsSync();
    if (!needsWrite) {
      final currentLength = target.lengthSync();
      if (currentLength != bytes.length) {
        needsWrite = true;
      }
    }

    if (needsWrite) {
      await target.writeAsBytes(bytes, flush: true);
    }
  }
}
