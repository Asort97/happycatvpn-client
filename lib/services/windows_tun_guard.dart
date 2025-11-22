import 'dart:io';
import 'dart:math';

class TunPreparationResult {
  const TunPreparationResult({
    required this.success,
    required this.requiresElevation,
    required this.inboundTag,
    required this.interfaceName,
    required this.logs,
    this.error,
  });

  final bool success;
  final bool requiresElevation;
  final String inboundTag;
  final String interfaceName;
  final List<String> logs;
  final String? error;
}

class WindowsTunGuard {
  WindowsTunGuard({
    this.removalTimeout = const Duration(seconds: 8),
    this.pollInterval = const Duration(milliseconds: 400),
  });

  static const String defaultInboundTag = 'tun-in';
  static const String defaultInterfaceName = 'wintun0';

  final Duration removalTimeout;
  final Duration pollInterval;
  final Random _random = Random();

  Future<TunPreparationResult> prepare() async {
    if (!Platform.isWindows) {
      return TunPreparationResult(
        success: true,
        requiresElevation: false,
        inboundTag: defaultInboundTag,
        interfaceName: defaultInterfaceName,
        logs: const ['Non-Windows OS detected, TUN guard skipped'],
      );
    }

    final logs = <String>[];
    if (!await _isElevated()) {
      logs.add('Administrator privileges are required to manage TUN adapters.');
      return TunPreparationResult(
        success: false,
        requiresElevation: true,
        inboundTag: defaultInboundTag,
        interfaceName: defaultInterfaceName,
        logs: logs,
        error: 'Run the application as Administrator',
      );
    }

    await _runNetsh(['interface', 'show', 'interface'], logs);

    final conflicts = await _findConflictingAdapters(logs);
    if (conflicts.isEmpty) {
      logs.add('No conflicting TUN adapters detected.');
      return TunPreparationResult(
        success: true,
        requiresElevation: false,
        inboundTag: defaultInboundTag,
        interfaceName: defaultInterfaceName,
        logs: logs,
      );
    }

    logs.add('Conflicting adapters detected: ${conflicts.join(', ')}');
    var cleanupSucceeded = true;
    for (final adapter in conflicts) {
      final disable = await _runNetsh(
        ['interface', 'set', 'interface', 'name="$adapter"', 'admin=disabled'],
        logs,
      );
      if (disable?.exitCode != 0) cleanupSucceeded = false;

      final delete = await _runNetsh(
        ['interface', 'ipv4', 'delete', 'interface', adapter],
        logs,
      );
      if (delete?.exitCode != 0) cleanupSucceeded = false;

      final remove = await _runPowerShell(
        "Get-NetAdapter -Name '${_escapePs(adapter)}' -ErrorAction SilentlyContinue | Remove-NetAdapter -Confirm:\$false -Force",
        logs,
      );
      if (remove?.exitCode != 0) cleanupSucceeded = false;

      if (!await _waitForAdapterRemoval(adapter, logs)) {
        cleanupSucceeded = false;
      }
    }

    if (cleanupSucceeded) {
      logs.add('All conflicting adapters were removed.');
      return TunPreparationResult(
        success: true,
        requiresElevation: false,
        inboundTag: defaultInboundTag,
        interfaceName: defaultInterfaceName,
        logs: logs,
      );
    }

    final fallbackName = _buildFallbackName();
    logs.add('Unable to cleanup adapters completely. Switching to $fallbackName');
    return TunPreparationResult(
      success: true,
      requiresElevation: false,
      inboundTag: fallbackName,
      interfaceName: fallbackName,
      logs: logs,
    );
  }

  Future<List<String>> _findConflictingAdapters(List<String> logs) async {
    const command =
        "Get-NetAdapter | Where-Object { \$_.Name -like 'tun-in*' -or \$_.Name -like 'wintun*' } | Select-Object -ExpandProperty Name";
    final result = await _runPowerShell(command, logs);
    if (result == null || result.stdout == null) return [];
    final stdout = result.stdout.toString();
    final names = stdout
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return names;
  }

  Future<bool> _waitForAdapterRemoval(String name, List<String> logs) async {
    final deadline = DateTime.now().add(removalTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _adapterExists(name)) {
        logs.add('Adapter $name removed.');
        return true;
      }
      await Future.delayed(pollInterval);
    }
    logs.add('Adapter $name is still present after ${removalTimeout.inSeconds}s.');
    return false;
  }

  Future<bool> _adapterExists(String name) async {
    final command =
        "if (Get-NetAdapter -Name '${_escapePs(name)}' -ErrorAction SilentlyContinue) { Write-Output 'True' } else { Write-Output 'False' }";
    final result = await _runPowerShell(command, null);
    if (result == null || result.stdout == null) return false;
    return result.stdout.toString().toLowerCase().contains('true');
  }

  Future<bool> _isElevated() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)'
      ]);
      if (result.stdout == null) return false;
      return result.stdout.toString().toLowerCase().contains('true');
    } catch (_) {
      return false;
    }
  }

  Future<ProcessResult?> _runNetsh(List<String> args, List<String>? logs) async {
    try {
      final result = await Process.run('netsh', args);
      logs?.add('netsh ${args.join(' ')} => ${result.exitCode}');
      final stderr = _cleanOutput(result.stderr);
      if (result.exitCode != 0 && stderr.isNotEmpty) {
        logs?.add('  stderr: $stderr');
      }
      return result;
    } catch (e) {
      logs?.add('netsh ${args.join(' ')} failed: $e');
      return null;
    }
  }

  Future<ProcessResult?> _runPowerShell(String command, List<String>? logs) async {
    try {
      final result = await Process.run('powershell', ['-NoProfile', '-Command', command]);
      logs?.add('powershell: ${command.split('\n').first} => ${result.exitCode}');
      final stderr = _cleanOutput(result.stderr);
      if (result.exitCode != 0 && stderr.isNotEmpty) {
        logs?.add('  stderr: $stderr');
      }
      return result;
    } catch (e) {
      logs?.add('PowerShell failed: $e');
      return null;
    }
  }

  String _buildFallbackName() {
    final suffix = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'tun-in-$suffix';
  }

  String _cleanOutput(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.length > 400) {
      return text.substring(0, 400);
    }
    return text;
  }

  String _escapePs(String input) => input.replaceAll("'", "''");
}
