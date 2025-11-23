/// Конфигурация Split Tunneling
class SplitTunnelConfig {
  /// Режим: 'all' (весь трафик), 'whitelist' (только указанные), 'blacklist' (кроме указанных)
  final String mode;
  
  /// Список доменов и IP для проксирования (или исключения в зависимости от режима)
  final List<String> domains;
  
  /// Список путей к exe файлам приложений для проксирования
  final List<String> applications;

  SplitTunnelConfig({
    this.mode = 'all',
    this.domains = const [],
    this.applications = const [],
  });

  SplitTunnelConfig copyWith({
    String? mode,
    List<String>? domains,
    List<String>? applications,
  }) {
    return SplitTunnelConfig(
      mode: mode ?? this.mode,
      domains: domains ?? this.domains,
      applications: applications ?? this.applications,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'domains': domains,
        'applications': applications,
      };

  factory SplitTunnelConfig.fromJson(Map<String, dynamic>? json, {required String fallbackMode}) {
    if (json == null) {
      return SplitTunnelConfig(mode: fallbackMode);
    }
    List<String> mapList(String key) {
      final value = json[key];
      if (value is List) {
        return value.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    final rawMode = json['mode']?.toString();
    return SplitTunnelConfig(
      mode: rawMode == 'whitelist'
          ? 'whitelist'
          : rawMode == 'blacklist'
              ? 'blacklist'
              : fallbackMode,
      domains: mapList('domains'),
      applications: mapList('applications'),
    );
  }
}
