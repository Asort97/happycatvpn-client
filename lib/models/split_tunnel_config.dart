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
}
