import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_subscription.dart';

class SubscriptionRepository {
  static const String _storageKey = 'vpn_subscriptions_list';
  static const String _selectedSubscriptionKey = 'selected_subscription_id';

  late SharedPreferences _prefs;
  bool _initialized = false;

  /// Инициализировать репозиторий
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// Получить все подписки
  Future<List<VpnSubscription>> getAllSubscriptions() async {
    await initialize();
    final stored = _prefs.getStringList(_storageKey) ?? [];
    return stored
        .map((json) {
          try {
            return VpnSubscription.fromJson(jsonDecode(json));
          } catch (_) {
            return null;
          }
        })
        .whereType<VpnSubscription>()
        .toList();
  }

  /// Получить подписку по ID
  Future<VpnSubscription?> getSubscription(String id) async {
    final all = await getAllSubscriptions();
    try {
      return all.firstWhere((sub) => sub.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Добавить подписку
  Future<bool> addSubscription(VpnSubscription subscription) async {
    await initialize();
    try {
      final all = await getAllSubscriptions();
      // Проверяем что такая подписка ещё не добавлена
      if (all.any((sub) => sub.url == subscription.url)) {
        return false;
      }
      all.add(subscription);
      await _saveAll(all);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Обновить подписку
  Future<bool> updateSubscription(VpnSubscription subscription) async {
    await initialize();
    try {
      final all = await getAllSubscriptions();
      final index = all.indexWhere((sub) => sub.id == subscription.id);
      if (index == -1) return false;
      all[index] = subscription;
      await _saveAll(all);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Удалить подписку
  Future<bool> deleteSubscription(String id) async {
    await initialize();
    try {
      final all = await getAllSubscriptions();
      all.removeWhere((sub) => sub.id == id);
      await _saveAll(all);

      // Если это была выбранная подписка, очищаем выбор
      final selected = await getSelectedSubscriptionId();
      if (selected == id) {
        await clearSelectedSubscription();
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Получить выбранную подписку (ID)
  Future<String?> getSelectedSubscriptionId() async {
    await initialize();
    return _prefs.getString(_selectedSubscriptionKey);
  }

  /// Установить выбранную подписку
  Future<bool> setSelectedSubscription(String subscriptionId) async {
    await initialize();
    try {
      await _prefs.setString(_selectedSubscriptionKey, subscriptionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Очистить выбранную подписку
  Future<bool> clearSelectedSubscription() async {
    await initialize();
    try {
      await _prefs.remove(_selectedSubscriptionKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Получить выбранную подписку со всеми данными
  Future<VpnSubscription?> getSelectedSubscription() async {
    final id = await getSelectedSubscriptionId();
    if (id == null) return null;
    return getSubscription(id);
  }

  /// Вспомогательный метод для сохранения всех подписок
  Future<void> _saveAll(List<VpnSubscription> subscriptions) async {
    final jsonList = subscriptions.map((sub) => jsonEncode(sub.toJson())).toList();
    await _prefs.setStringList(_storageKey, jsonList);
  }
}
