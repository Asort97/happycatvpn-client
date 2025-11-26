/// Модель настроек split tunneling
class SplitTunnelConfig {
  /// Режимы: 'all' (весь трафик), 'whitelist' (только заданное идет в VPN), 'blacklist' (эти идут в обход)
  final String mode;

  /// Список доменных имен или IP/подсетей (можно CIDR), которые идут в selected outbound (зависит от режима)
  final List<String> domains;

  /// Список путей к exe или package name для процесс-ориентированных правил
  final List<String> applications;

  /// Умный обход российских доменов
  final bool smartRouting;

  /// Список доменов/суффиксов для smart routing (используется, если smartRouting == true)
  final List<String> smartDomains;

  SplitTunnelConfig({
    this.mode = 'all',
    this.domains = const [],
    this.applications = const [],
    this.smartRouting = false,
    this.smartDomains = const [],
  });

  SplitTunnelConfig copyWith({
    String? mode,
    List<String>? domains,
    List<String>? applications,
    bool? smartRouting,
    List<String>? smartDomains,
  }) {
    return SplitTunnelConfig(
      mode: mode ?? this.mode,
      domains: domains ?? this.domains,
      applications: applications ?? this.applications,
      smartRouting: smartRouting ?? this.smartRouting,
      smartDomains: smartDomains ?? this.smartDomains,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'domains': domains,
        'applications': applications,
        'smartRouting': smartRouting,
        'smartDomains': smartDomains,
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
      smartRouting: json['smartRouting'] == true,
      smartDomains: mapList('smartDomains'),
    );
  }
}
