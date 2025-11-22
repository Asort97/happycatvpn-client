import 'dart:convert';
import 'vless_parser.dart';

import '../models/split_tunnel_config.dart';

/// Генерация конфигурационного JSON для sing-box с TUN (wintun)
/// Полноценный VPN туннель для всего устройства без SOCKS прокси
String generateSingBoxConfig(
  VlessLink link,
  SplitTunnelConfig splitConfig, {
  String inboundTag = 'tun-in',
  String interfaceName = 'wintun0',
}) {
  final p = link.params;
  final transportType = p['type']; // например ws, tcp, grpc, h2
  final security = p['security'];
  final isReality = security == 'reality';
  final useTls = (security == 'tls' || isReality);
  final serverName = p['sni'] ?? p['host'] ?? link.host;
  final alpn = p['alpn'] != null ? p['alpn']!.split(',') : [];
  final flow = p['flow'];
  final fingerprint = p['fp'] ?? 'chrome';
  final path = p['path'];
  final realityPublicKey = p['pbk'];
  final realityShortId = p['sid'];
  final packetEncoding = p['packetEncoding'] ?? p['packet'];
  // sing-box не принимает поле spider_x (spx) в текущей версии — игнорируем

  final outbound = <String, dynamic>{
    'type': 'vless',
    'tag': link.tag ?? 'vless-out',
    'server': link.host,
    'server_port': link.port,
    'uuid': link.uuid,
    'domain_strategy': 'ipv4_only',
  };

  if (flow != null && flow.isNotEmpty) {
    outbound['flow'] = flow;
    if ((packetEncoding == null || packetEncoding.isEmpty) && flow.contains('vision')) {
      outbound['packet_encoding'] = 'xudp';
    }
  }

  if (packetEncoding != null && packetEncoding.isNotEmpty) {
    outbound['packet_encoding'] = packetEncoding;
  }

  if (useTls) {
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': serverName,
      if (alpn.isNotEmpty) 'alpn': alpn,
      'utls': {
        'enabled': true,
        'fingerprint': fingerprint,
      }
    };
    if (isReality) {
      final shortIdList = (realityShortId ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      tls['reality'] = {
        'enabled': true,
        if (realityPublicKey != null && realityPublicKey.isNotEmpty)
          'public_key': realityPublicKey,
        if (shortIdList.isNotEmpty)
          'short_id': shortIdList.length == 1 ? shortIdList.first : shortIdList,
      };
    }
    outbound['tls'] = tls;
  }

  // transportType=tcp в sing-box не задаётся как отдельный transport.
  if (transportType != null && transportType.isNotEmpty && transportType != 'tcp') {
    final transport = <String, dynamic>{'type': transportType};
    if (transportType == 'ws') {
      if (path != null && path.isNotEmpty) transport['path'] = path;
      final hostHeader = p['host'] ?? link.host;
      transport['headers'] = {'Host': hostHeader};
    }
    outbound['transport'] = transport;
  }

  final config = {
    'log': {
      'level': 'info',
      'timestamp': true,
    },
    'dns': {
      'servers': [
        {
          'tag': 'dns-remote',
          'address': '1.1.1.1',
        },
        {
          'tag': 'dns-local',
          'address': 'local',
          'detour': 'direct',
        },
      ],
      'final': 'dns-remote',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': inboundTag,
        'interface_name': interfaceName,
        'stack': 'system',
        'mtu': 1400,
        'address': ['172.19.0.1/30'],
        'auto_route': true,
        'strict_route': false,
        'sniff': true,
        'sniff_override_destination': false,
      }
    ],
    'outbounds': [
      outbound,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': {
      'auto_detect_interface': true,
      'final': _getDefaultOutbound(splitConfig, link.tag ?? 'vless-out'),
      'rules': [
        ..._buildRouteRules(splitConfig, link.tag ?? 'vless-out'),
      ],
    }
  };
  return const JsonEncoder.withIndent('  ').convert(config);
}

String _getDefaultOutbound(SplitTunnelConfig config, String vpnTag) {
  if (config.mode == 'whitelist') return 'direct'; // По умолчанию direct, VPN только для списка
  return vpnTag; // all или blacklist — по умолчанию через VPN
}

List<Map<String, dynamic>> _buildRouteRules(SplitTunnelConfig config, String vpnTag) {
  final rules = <Map<String, dynamic>>[];
  
  if (config.domains.isEmpty) return rules;

  final domains = config.domains.where((d) => !d.contains('/')).toList();
  final ipCidrs = config.domains.where((d) => d.contains('/')).toList();

  if (config.mode == 'whitelist') {
    // Только указанные домены/IP через VPN, остальное direct
    if (domains.isNotEmpty || ipCidrs.isNotEmpty) {
      rules.add({
        if (domains.isNotEmpty) 'domain': domains,
        if (ipCidrs.isNotEmpty) 'ip_cidr': ipCidrs,
        'outbound': vpnTag,
      });
    }
  } else if (config.mode == 'blacklist') {
    // Указанные домены/IP напрямую, остальное через VPN
    if (domains.isNotEmpty || ipCidrs.isNotEmpty) {
      rules.add({
        if (domains.isNotEmpty) 'domain': domains,
        if (ipCidrs.isNotEmpty) 'ip_cidr': ipCidrs,
        'outbound': 'direct',
      });
    }
  }
  
  return rules;
}
