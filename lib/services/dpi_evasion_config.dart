enum DpiEvasionProfile { balanced, aggressive }

class DpiEvasionConfig {
  const DpiEvasionConfig._({
    required this.enableFragmentation,
    required this.enableTtlPhantom,
    required this.enableTlsFragment,
    required this.tlsFragmentFallbackDelay,
    required this.profile,
  });

  final bool enableFragmentation;
  final bool enableTtlPhantom;
  final bool enableTlsFragment;
  final Duration? tlsFragmentFallbackDelay;
  final DpiEvasionProfile profile;

  static const DpiEvasionConfig balanced = DpiEvasionConfig._(
    enableFragmentation: true,
    enableTtlPhantom: false,
    enableTlsFragment: false,
    tlsFragmentFallbackDelay: null,
    profile: DpiEvasionProfile.balanced,
  );

  static const DpiEvasionConfig aggressive = DpiEvasionConfig._(
    enableFragmentation: true,
    enableTtlPhantom: true,
    enableTlsFragment: true,
    tlsFragmentFallbackDelay: Duration(milliseconds: 500),
    profile: DpiEvasionProfile.aggressive,
  );

  /// Копирует конфиг с изменением фрагментации
  DpiEvasionConfig copyWithFragmentation(bool enabled) {
    return DpiEvasionConfig._(
      enableFragmentation: enabled,
      enableTtlPhantom: enableTtlPhantom,
      enableTlsFragment: enableTlsFragment,
      tlsFragmentFallbackDelay: tlsFragmentFallbackDelay,
      profile: profile,
    );
  }
}
