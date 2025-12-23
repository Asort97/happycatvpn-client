import 'dart:io';

import 'package:flutter/material.dart';

import '../services/dpi_evasion_config.dart';
import '../services/dpi_evasion_manager.dart';

class DpiEvasionWidget extends StatefulWidget {
  const DpiEvasionWidget({
    super.key,
    required this.manager,
    required this.config,
    this.serverHost,
    this.serverPort,
    this.onConfigChanged,
    this.enabled = true,
  });

  final DpiEvasionManager manager;
  final DpiEvasionConfig config;
  final String? serverHost;
  final int? serverPort;
  final ValueChanged<DpiEvasionConfig>? onConfigChanged;
  final bool enabled;

  @override
  State<DpiEvasionWidget> createState() => _DpiEvasionWidgetState();
}

class _DpiEvasionWidgetState extends State<DpiEvasionWidget> {
  bool _busy = false;

  bool get _isAggressive =>
      widget.config.profile == DpiEvasionProfile.aggressive;

  bool get _isFragmentationEnabled => widget.config.enableFragmentation;

  Future<void> _onToggle(bool value) async {
    if (!widget.enabled || !Platform.isWindows) return;
    if (_busy) return;

    setState(() => _busy = true);
    final nextConfig =
        value ? DpiEvasionConfig.aggressive : DpiEvasionConfig.balanced;
    widget.onConfigChanged?.call(nextConfig);

    if (value) {
      if (widget.serverHost != null && widget.serverPort != null) {
        await widget.manager.startForHost(widget.serverHost!, widget.serverPort!);
      }
    } else {
      await widget.manager.stopNativeInjector();
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _onFragmentationToggle(bool value) async {
    if (!widget.enabled || !Platform.isWindows) return;
    final nextConfig = widget.config.copyWithFragmentation(value);
    widget.onConfigChanged?.call(nextConfig);
  }

  @override
  Widget build(BuildContext context) {
    final isSupported = Platform.isWindows;
    final disabled = !isSupported || !widget.enabled;
    final subtitle = disabled
        ? 'Доступно только на Windows'
        : 'Фрагментация + TTL phantom для первых пакетов.';

    return Column(
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.25),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Агрессивная Маскировка',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _isAggressive,
                  onChanged: disabled ? null : _onToggle,
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.25),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Фрагментация Пакетов',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        disabled
                            ? 'Доступно только на Windows'
                            : 'Разбивает TLS hello на маленькие куски для обхода DPI',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _isFragmentationEnabled,
                  onChanged: disabled ? null : _onFragmentationToggle,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
