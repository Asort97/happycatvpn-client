import 'dart:async';
import 'dart:io';

import '../models/connectivity_test.dart';
import '../services/smart_route_engine.dart';

class ConnectivityTester {
  ConnectivityTester({
    this.maxConcurrency = 20,
    this.timeout = const Duration(seconds: 2),
    DateTime Function()? clock,
    SmartRouteEngine? routeEngine,
  }) : _clock = clock ?? DateTime.now,
       _routeEngine = routeEngine ?? SmartRouteEngine();

  final int maxConcurrency;
  final Duration timeout;
  final DateTime Function() _clock;
  final SmartRouteEngine _routeEngine;
  final Map<String, _CachedResult> _cache = {};

  Map<String, ConnectivityTestResult> get cache =>
      _cache.map((key, value) => MapEntry(key, value.result));

  void clearCache() => _cache.clear();

  Future<Map<String, ConnectivityTestResult>> run(
    List<ConnectivityTestTarget> targets, {
    Duration cacheTtl = const Duration(minutes: 30),
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <String, ConnectivityTestResult>{};
    final tasks = <Future<void>>[];
    var completed = 0;

    for (final target in targets) {
      if (isCancelled?.call() == true) break;

      final cached = _cache[target.domain];
      if (cached != null && _clock().difference(cached.timestamp) <= cacheTtl) {
        results[target.domain] = cached.result;
        completed++;
        onProgress?.call(completed, targets.length);
        continue;
      }

      final future = _runSingle(target)
          .then((result) {
            results[target.domain] = result;
            _cache[target.domain] = _CachedResult(result, _clock());
          })
          .whenComplete(() {
            completed++;
            onProgress?.call(completed, targets.length);
          });

      tasks.add(future);
      if (tasks.length >= maxConcurrency) {
        await tasks.first;
        tasks.removeAt(0);
      }
    }

    await Future.wait(tasks);
    return results;
  }

  Future<ConnectivityTestResult> _runSingle(
    ConnectivityTestTarget target,
  ) async {
    final stopwatch = Stopwatch()..start();
    String status = 'routing_error';
    String? error;
    int? httpStatus;

    String route = 'vpn';
    try {
      final routeDecision = await _routeEngine.decideForDomain(target.domain);
      route = routeDecision == RouteDecision.bypassVpn ? 'bypass' : 'vpn';
    } catch (_) {}

    try {
      final addresses = await InternetAddress.lookup(target.domain).timeout(
        timeout,
        onTimeout: () => throw TimeoutException('dns_timeout'),
      );
      if (addresses.isEmpty) {
        status = 'dns_error';
        error = 'no_address';
      } else {
        final client = HttpClient();
        client.connectionTimeout = timeout;
        client.badCertificateCallback = (cert, host, port) => false;
        try {
          final request = await client
              .getUrl(Uri.https(target.domain, '/'))
              .timeout(
                timeout,
                onTimeout: () => throw TimeoutException('connect_timeout'),
              );
          final response = await request.close().timeout(
            timeout,
            onTimeout: () => throw TimeoutException('read_timeout'),
          );
          httpStatus = response.statusCode;
          status = response.statusCode >= 200 && response.statusCode < 400
              ? 'ok'
              : 'http_error';
        } on HandshakeException catch (e) {
          status = 'ssl_error';
          error = e.toString();
        } on TimeoutException catch (e) {
          status = 'timeout';
          error = e.message ?? 'timeout';
        } on SocketException catch (e) {
          final message = e.message.toLowerCase();
          if (message.contains('refused')) {
            status = 'connection_refused';
          } else if (message.contains('host lookup')) {
            status = 'dns_error';
          } else {
            status = 'network_error';
          }
          error = e.message;
        } catch (e) {
          status = 'routing_error';
          error = e.toString();
        } finally {
          client.close(force: true);
        }
      }
    } on TimeoutException catch (e) {
      status = 'timeout';
      error = e.message ?? 'timeout';
    } on SocketException catch (e) {
      status = 'dns_error';
      error = e.message;
    } catch (e) {
      status = 'routing_error';
      error = e.toString();
    }

    stopwatch.stop();
    final durationMs = stopwatch.elapsedMilliseconds;
    return ConnectivityTestResult(
      status: status,
      error: error,
      durationMs: durationMs,
      route: route,
      httpStatus: httpStatus,
      timestamp: _clock(),
    );
  }
}

class _CachedResult {
  _CachedResult(this.result, this.timestamp);
  final ConnectivityTestResult result;
  final DateTime timestamp;
}
