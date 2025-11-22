# Примеры конфигурации sing-box

## Пример 1: VLESS Reality TCP (базовый)

### VLESS URI
```
vless://f27fc02f-0c92-44f1-bc84-2d23d99a7a20@77.110.109.188:443?type=tcp&security=reality&sni=web.max.ru&fp=chrome&pbk=9Zh68hbhSDKNLwGXE-ezeWYB5LGnlVQ0mXxzsCfafns&sid=733be61f550319e0&flow=xtls-rprx-vision#server1
```

### Сгенерированный config.json
```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-local",
        "address": "local",
        "detour": "direct"
      },
      {
        "tag": "dns-remote",
        "address": "tls://8.8.8.8",
        "strategy": "ipv4_only"
      }
    ],
    "rules": [],
    "final": "dns-remote"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "wintun0",
      "stack": "system",
      "mtu": 1400,
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": false,
      "sniff": true,
      "sniff_override_destination": false
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "server1",
      "server": "77.110.109.188",
      "server_port": 443,
      "uuid": "f27fc02f-0c92-44f1-bc84-2d23d99a7a20",
      "flow": "xtls-rprx-vision",
      "packet_encoding": "xudp",
      "tls": {
        "enabled": true,
        "server_name": "web.max.ru",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "9Zh68hbhSDKNLwGXE-ezeWYB5LGnlVQ0mXxzsCfafns",
          "short_id": "733be61f550319e0"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "final": "server1",
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      }
    ]
  }
}
```

## Пример 2: VLESS Reality WebSocket

### VLESS URI
```
vless://uuid@example.com:443?type=ws&security=reality&path=/ws&host=example.com&sni=cloudflare.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&flow=xtls-rprx-vision#ws-server
```

### Особенности конфига
- Добавляется блок `transport` с типом `ws`
- Указывается `path` и `Host` header
- SNI может отличаться от host

## Пример 3: Split Tunneling (Whitelist)

### Настройки
- Режим: `whitelist`
- Домены: `youtube.com`, `twitter.com`, `google.com`
- IP: `8.8.8.8/32`

### Route rules
```json
"route": {
  "auto_detect_interface": true,
  "final": "direct",
  "rules": [
    {
      "domain": ["youtube.com", "twitter.com", "google.com"],
      "ip_cidr": ["8.8.8.8/32"],
      "outbound": "vless-out"
    },
    {
      "protocol": "dns",
      "outbound": "dns-out"
    }
  ]
}
```

## Пример 4: Split Tunneling (Blacklist)

### Настройки
- Режим: `blacklist`
- Домены: `local.lan`, `192.168.0.0/16`

### Route rules
```json
"route": {
  "auto_detect_interface": true,
  "final": "vless-out",
  "rules": [
    {
      "domain": ["local.lan"],
      "ip_cidr": ["192.168.0.0/16", "10.0.0.0/8"],
      "outbound": "direct"
    },
    {
      "protocol": "dns",
      "outbound": "dns-out"
    }
  ]
}
```

## Проверка работы

### 1. Проверка подключения
```powershell
# Проверка DNS
nslookup google.com

# Проверка внешнего IP
curl https://ifconfig.me

# Проверка TUN интерфейса
Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*wintun*"}
```

### 2. Проверка маршрутов
```powershell
# Показать все маршруты
route print

# Должен быть маршрут через wintun0
```

### 3. Логи sing-box
Логи выводятся в UI приложения. Ищите:
- `[INFO] inbound/tun[tun-in]: started at wintun0`
- `[INFO] outbound/vless[...]: outbound connection to ...`
- Ошибки Reality: `[ERROR] ... reality handshake failed`

## Отладка

### Проблема: TUN не создаётся
```
[ERROR] start service: initialize inbound/tun[tun-in]: create tun interface: ...
```
**Решение**: Запустите от администратора

### Проблема: Reality handshake failed
```
[ERROR] ... connection: open connection to ...: reality handshake failed
```
**Решение**: Проверьте `public_key`, `short_id`, `sni`, `flow`

### Проблема: DNS не работает
**Решение**: 
- Убедитесь что `dns.final = "dns-remote"`
- Проверьте что есть правило `protocol: dns → dns-out`
- Используйте sing-box >= 1.8.0

## Рекомендации

1. **Всегда используйте flow=xtls-rprx-vision для Reality**
2. **packet_encoding=xudp добавляется автоматически**
3. **short_id должен быть строкой при одном значении**
4. **MTU=1400 оптимален для большинства сетей**
5. **Тестируйте на простых сайтах (google.com) перед сложными**
