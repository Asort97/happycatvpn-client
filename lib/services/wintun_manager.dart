import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Управление wintun.dll для sing-box
class WintunManager {
  static const String _dllName = 'wintun.dll';
  static const String _assetPath = 'assets/bin/$_dllName';
  
  String? _dllPath;
  
  /// Получить путь к wintun.dll (извлекает из assets если нужно)
  Future<String?> ensureWintunAvailable() async {
    if (_dllPath != null && File(_dllPath!).existsSync()) {
      return _dllPath;
    }

    // Проверяем в текущей директории
    final localDll = File(_dllName);
    if (localDll.existsSync()) {
      _dllPath = localDll.absolute.path;
      return _dllPath;
    }

    // Извлекаем из assets
    try {
      final appDir = await getApplicationSupportDirectory();
      final binDir = Directory('${appDir.path}/bin');
      if (!binDir.existsSync()) {
        binDir.createSync(recursive: true);
      }

      final targetFile = File('${binDir.path}/$_dllName');
      
      // Копируем если не существует или размер отличается
      bool needsCopy = !targetFile.existsSync();
      
      if (needsCopy) {
        final data = await rootBundle.load(_assetPath);
        final bytes = data.buffer.asUint8List();
        await targetFile.writeAsBytes(bytes);
      }

      _dllPath = targetFile.absolute.path;
      return _dllPath;
    } catch (e) {
      print('[WintunManager] Не удалось извлечь wintun.dll: $e');
      return null;
    }
  }

  /// Проверка доступности wintun
  Future<bool> isWintunAvailable() async {
    final path = await ensureWintunAvailable();
    return path != null && File(path).existsSync();
  }

  /// Очистка временных файлов
  Future<void> cleanup() async {
    // Не удаляем wintun.dll для повторного использования
  }
}
