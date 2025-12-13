enum DpiEvasionProfile { balanced, aggressive }

class DpiEvasionConfig {
  const DpiEvasionConfig._({
    required this.enableFragmentation,
    required this.enableTtlPhantom,
    required this.profile,
  });

  final bool enableFragmentation;
  final bool enableTtlPhantom;
  final DpiEvasionProfile profile;

  static const DpiEvasionConfig balanced = DpiEvasionConfig._(
    enableFragmentation: true,
    enableTtlPhantom: false,
    profile: DpiEvasionProfile.balanced,
  );

  static const DpiEvasionConfig aggressive = DpiEvasionConfig._(
    enableFragmentation: true,
    enableTtlPhantom: true,
    profile: DpiEvasionProfile.aggressive,
  );
}
