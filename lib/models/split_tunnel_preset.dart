class SplitTunnelPreset {
  SplitTunnelPreset({
    required this.name,
    required this.mode,
    required this.domains,
    required this.applications,
  });

  final String name;
  final String mode;
  final List<String> domains;
  final List<String> applications;

  Map<String, dynamic> toJson() => {
        'name': name,
        'mode': mode,
        'domains': domains,
        'applications': applications,
      };

  factory SplitTunnelPreset.fromJson(Map<String, dynamic> json) {
    List<String> mapList(String key) {
      final value = json[key];
      if (value is List) {
        return value.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    final rawMode = json['mode']?.toString();
    final normalizedMode = rawMode == 'whitelist'
        ? 'whitelist'
        : rawMode == 'blacklist'
            ? 'blacklist'
            : 'all';

    return SplitTunnelPreset(
      name: json['name']?.toString() ?? 'Preset',
      mode: normalizedMode,
      domains: mapList('domains'),
      applications: mapList('applications'),
    );
  }
}
