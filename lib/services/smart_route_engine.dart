import 'dart:async';

import 'cache_repository.dart';

enum RouteDecision { bypassVpn, useVpn }

/// Lightweight smart routing engine based on Russian TLDs and a curated list of services.
///
/// Intentionally avoids IP/ASN heuristics to prevent false positives from anycast CDNs.
class SmartRouteEngine {
  SmartRouteEngine({
    Set<String>? ruTlds,
    Set<String>? russianServices,
    Duration domainCacheTtl = const Duration(minutes: 30),
    int domainCacheSize = 512,
    DateTime Function()? clock,
    CacheRepository? cacheRepository,
  }) : ruTlds = Set<String>.from(ruTlds ?? _defaultTlds),
       russianServices = Set<String>.from(russianServices ?? _defaultServices),
       _clock = clock ?? DateTime.now,
       _cacheRepository = cacheRepository {
    _domainCache = _TtlLruCache<String, RouteDecision>(
      ttl: domainCacheTtl,
      capacity: domainCacheSize,
      clock: _clock,
    );
  }

  final Set<String> ruTlds;
  final Set<String> russianServices;
  late final _TtlLruCache<String, RouteDecision> _domainCache;
  final DateTime Function() _clock;
  final CacheRepository? _cacheRepository;

  bool _restoredFromDisk = false;
  Timer? _persistDebounce;

  /// Main decision function following strict priority:
  /// 1) RU TLD (.ru/.su/.xn--p1ai) => bypass
  /// 2) Known Russian services list => bypass
  /// 3) Otherwise => use VPN
  Future<RouteDecision> decideForDomain(String domain) async {
    await _restoreCacheIfNeeded();

    final normalized = _normalizeDomain(domain);
    if (normalized.isEmpty) return RouteDecision.useVpn;

    final cached = _domainCache.get(normalized);
    if (cached != null) return cached;

    final decision = _decide(normalized);
    _domainCache.set(normalized, decision);
    _schedulePersist();
    return decision;
  }

  Future<void> _restoreCacheIfNeeded() async {
    if (_cacheRepository == null || _restoredFromDisk) return;
    _restoredFromDisk = true;
    try {
      final stored = await _cacheRepository.loadRouteDecisions();
      final now = _clock();
      stored.forEach((domain, record) {
        if (now.isBefore(record.expiresAt)) {
          final decision = record.decision == 'bypass'
              ? RouteDecision.bypassVpn
              : RouteDecision.useVpn;
          _domainCache.set(domain, decision, customExpiry: record.expiresAt);
        }
      });
    } catch (_) {
      // Игнорируем ошибки чтения кеша.
    }
  }

  void _schedulePersist() {
    if (_cacheRepository == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 1), () async {
      final now = _clock();
      final data = <String, RouteCacheRecord>{};
      for (final entry in _domainCache.dump()) {
        final expiresAt = entry.value.expiresAt;
        if (now.isBefore(expiresAt)) {
          data[entry.key] = RouteCacheRecord(
            decision: entry.value.value == RouteDecision.bypassVpn
                ? 'bypass'
                : 'vpn',
            expiresAt: expiresAt,
          );
        }
      }
      if (data.isEmpty) return;
      try {
        await _cacheRepository.saveRouteDecisions(data);
      } catch (_) {
        // Игнорируем ошибки записи.
      }
    });
  }

  void dispose() {
    _persistDebounce?.cancel();
  }

  RouteDecision _decide(String normalizedDomain) {
    if (_hasRuTld(normalizedDomain)) {
      return RouteDecision.bypassVpn;
    }
    if (_matchesRussianService(normalizedDomain)) {
      return RouteDecision.bypassVpn;
    }
    return RouteDecision.useVpn;
  }

  bool _hasRuTld(String normalizedDomain) {
    final lastDot = normalizedDomain.lastIndexOf('.');
    if (lastDot == -1 || lastDot == normalizedDomain.length - 1) return false;
    final tld = normalizedDomain.substring(lastDot + 1);
    return ruTlds.contains(tld);
  }

  bool _matchesRussianService(String normalizedDomain) {
    if (russianServices.contains(normalizedDomain)) return true;
    for (final service in russianServices) {
      if (normalizedDomain.endsWith('.$service')) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> buildRouteRules({required String outboundTag}) {
    final suffixes = ruTlds.toList();
    final domains = russianServices.toList();
    return [
      {
        if (domains.isNotEmpty) 'domain': domains,
        if (suffixes.isNotEmpty) 'domain_suffix': suffixes,
        'outbound': outboundTag,
      },
    ];
  }

  List<String> exportLegacyRuleEntries() {
    return [...ruTlds.map((tld) => '.$tld'), ...russianServices];
  }

  static String _normalizeDomain(String domain) {
    return domain.trim().toLowerCase().replaceAll(RegExp(r'\.+$'), '');
  }
}

class _CacheEntry<V> {
  _CacheEntry(this.value, this.expiresAt);
  final V value;
  final DateTime expiresAt;
}

class _TtlLruCache<K, V> {
  _TtlLruCache({
    required this.ttl,
    required this.capacity,
    required DateTime Function() clock,
  }) : _clock = clock;

  final Duration ttl;
  final int capacity;
  final DateTime Function() _clock;
  final _store = <K, _CacheEntry<V>>{};

  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (_clock().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    _store.remove(key);
    _store[key] = entry;
    return entry.value;
  }

  void set(K key, V value, {DateTime? customExpiry}) {
    if (capacity <= 0) return;
    if (_store.length >= capacity && !_store.containsKey(key)) {
      final firstKey = _store.keys.first;
      _store.remove(firstKey);
    }
    final expiry = customExpiry ?? _clock().add(ttl);
    _store[key] = _CacheEntry(value, expiry);
  }

  Iterable<MapEntry<K, _CacheEntry<V>>> dump() => _store.entries.toList();

  void clear() => _store.clear();
}

const _defaultTlds = {'ru', 'su', 'xn--p1ai'};

const _defaultServices = {
  'yandex.ru',
  'yandex.net',
  'mail.ru',
  'vk.com',
  'ok.ru',
  'sber.ru',
  'sberbank.ru',
  'vtb.ru',
  'tinkoff.ru',
  'alfabank.ru',
  'gazprombank.ru',
  'qiwi.com',
  'ozon.ru',
  'wildberries.ru',
  'lenta.ru',
  'rambler.ru',
  'hh.ru',
  'avito.ru',
  'rutube.ru',
  'rbc.ru',
  'dns-shop.ru',
  'gosuslugi.ru',
  'nalog.ru',
  'mos.ru',
  'mvd.ru',
  'ria.ru',
};
