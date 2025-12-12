import 'dart:convert';
import 'lib/vless/vless_parser.dart';
import 'lib/vless/config_generator.dart';
import 'lib/models/split_tunnel_config.dart';

void main() {
  // Тестовый URI из подписки
  const testUri = 'vless://5f5eb7bd-6509-4ec8-908a-f0096fd4653c@sub.staticdeliverycdn.com:10001?encryption=none&flow=xtls-rprx-vision&fp=chrome&pbk=lRgGleThmoAL5mOh1WoeNObl9gEJzxxRoX_-l7WvBGU&security=reality&sid=42a92d1e&sni=web.max.ru&spx=%2FYHiQ65khcT5rysZ&type=tcp#web.max.ru-Asort97@mail.ru-746D,11H';
  
  print('Парсинг VLESS URI...');
  final parsed = parseVlessUri(testUri);
  
  if (parsed == null) {
    print('❌ Ошибка парсинга URI');
    return;
  }
  
  print('✅ URI распарсен успешно:');
  print('  UUID: ${parsed.uuid}');
  print('  Host: ${parsed.host}');
  print('  Port: ${parsed.port}');
  print('  Security: ${parsed.security}');
  print('  Flow: ${parsed.flow}');
  print('  SNI: ${parsed.sni}');
  print('  Public Key: ${parsed.params['pbk']}');
  print('  Short ID: ${parsed.params['sid']}');
  print('  Spider X: ${parsed.params['spx']}');
  print('');
  
  print('Генерация конфига...');
  final config = SplitTunnelConfig();
  final jsonConfig = generateSingBoxConfig(parsed, config);
  
  print('');
  print('=' * 80);
  print('Сгенерированный конфиг:');
  print('=' * 80);
  
  // Красивый вывод JSON
  final decoded = jsonDecode(jsonConfig);
  final prettyJson = const JsonEncoder.withIndent('  ').convert(decoded);
  print(prettyJson);
  
  // Проверяем наличие spider_x в Reality секции
  print('');
  print('=' * 80);
  print('Проверка Reality параметров:');
  print('=' * 80);
  
  final outbounds = decoded['outbounds'] as List;
  final vlessOutbound = outbounds.firstWhere((o) => o['type'] == 'vless');
  final tls = vlessOutbound['tls'];
  
  if (tls != null) {
    final reality = tls['reality'];
    if (reality != null) {
      print('✅ Reality секция найдена:');
      print('  Enabled: ${reality['enabled']}');
      print('  Public Key: ${reality['public_key']}');
      print('  Short ID: ${reality['short_id']}');
      print('  Spider X: ${reality['spider_x']}');
      
      if (reality['spider_x'] != null) {
        print('');
        print('✅ Параметр spider_x успешно добавлен в конфиг!');
      } else {
        print('');
        print('❌ ОШИБКА: Параметр spider_x отсутствует в конфиге!');
      }
    } else {
      print('❌ Reality секция не найдена');
    }
  } else {
    print('❌ TLS секция не найдена');
  }
}
