import 'package:flutter/material.dart';
import '../models/vpn_profile.dart';
import '../models/vpn_subscription.dart';
import '../services/subscription_repository.dart';
import '../services/subscription_manager.dart';

class ProfileListView extends StatefulWidget {
  final List<VpnProfile> profiles;
  final VpnProfile? selectedProfile;
  final Function(VpnProfile) onProfileSelected;
  final Function(VpnProfile) onDeleteProfile;

  const ProfileListView({
    Key? key,
    required this.profiles,
    required this.selectedProfile,
    required this.onProfileSelected,
    required this.onDeleteProfile,
  }) : super(key: key);

  @override
  State<ProfileListView> createState() => _ProfileListViewState();
}

class _ProfileListViewState extends State<ProfileListView> {
  late SubscriptionRepository _repository;
  List<VpnSubscription> _subscriptions = [];
  Map<String, bool> _expandedSubscriptions = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _repository = SubscriptionRepository();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    setState(() => _isLoading = true);
    try {
      final subs = await _repository.getAllSubscriptions();
      setState(() {
        _subscriptions = subs;
        // Все подписки по умолчанию раскрыты
        for (var sub in subs) {
          _expandedSubscriptions[sub.id] = true;
        }
      });
    } catch (e) {
      debugPrint('Ошибка загрузки подписок: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshSubscription(VpnSubscription subscription) async {
    final manager = SubscriptionService();
    try {
      final profiles = await manager.fetchSubscription(subscription.url);
      if (profiles.isEmpty) {
        throw 'В подписке не найдено профилей';
      }

      final updated = subscription.copyWith(
        profiles: profiles,
        lastUpdated: DateTime.now(),
      );

      await _repository.updateSubscription(updated);
      await _loadSubscriptions();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подписка обновлена')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      children: [
        // Раздел КЛЮЧИ (обычные VLESS-ключи, добавленные вручную)
        if (widget.profiles.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'КЛЮЧИ',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._buildRegularKeys(),
        ],
        // Заголовок КОНФИГУРАЦИИ (подписки)
        if (_subscriptions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'КОНФИГУРАЦИИ',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._buildSubscriptions(),
        ],
      ],
    );
  }

  List<Widget> _buildRegularKeys() {
    return List.generate(widget.profiles.length, (index) {
      final profile = widget.profiles[index];
      final isSelected = widget.selectedProfile?.uri == profile.uri;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? Colors.blue.withOpacity(0.15) : null,
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: isSelected ? 1 : 0,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            leading: Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? Colors.blue : Colors.grey,
              size: 20,
            ),
            title: Text(
              profile.uri,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.blue : Colors.white,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            trailing: IconButton(
              tooltip: 'Удалить ключ',
              icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Удалить ключ?'),
                    content: Text('Ключ "${profile.name}" будет удалён.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  widget.onDeleteProfile(profile);
                }
              },
            ),
            onTap: () => widget.onProfileSelected(profile),
          ),
        ),
      );
    });
  }

  List<Widget> _buildSubscriptions() {
    if (_subscriptions.isEmpty) return [];

    return _subscriptions.map((subscription) {
      final isExpanded = _expandedSubscriptions[subscription.id] ?? true;
      return _buildSubscriptionCard(subscription, isExpanded);
    }).toList();
  }

  Widget _buildSubscriptionCard(VpnSubscription subscription, bool isExpanded) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        child: Column(
          children: [
            // Заголовок подписки
            ListTile(
              leading: Icon(
                Icons.cloud_download,
                color: Colors.blue[400],
              ),
              title: Text(subscription.name),
              subtitle: Text(
                'Профилей: ${subscription.profileCount}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    subscription.formattedLastUpdate,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: () {
                      setState(() {
                        _expandedSubscriptions[subscription.id] = !isExpanded;
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              onTap: () {
                setState(() {
                  _expandedSubscriptions[subscription.id] = !isExpanded;
                });
              },
            ),
            // Профили подписки (если раскрыто)
            if (isExpanded) ...[
              Divider(height: 1, indent: 16, endIndent: 16),
              ..._buildSubscriptionProfiles(subscription),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _refreshSubscription(subscription),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Обновить'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _deleteSubscription(subscription),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Удалить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSubscriptionProfiles(VpnSubscription subscription) {
    return List.generate(
      subscription.profiles.length,
      (index) {
        final vlessUri = subscription.profiles[index];
        final isSelected = widget.selectedProfile?.uri == vlessUri;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isSelected ? Colors.blue.withOpacity(0.15) : null,
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.transparent,
                width: isSelected ? 1 : 0,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.blue : Colors.grey,
                size: 20,
              ),
              title: Text(
                vlessUri,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.blue : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () {
                // Создаём VpnProfile на лету и выбираем его
                final profileName = '${subscription.name} - ${index + 1}';
                final profile = VpnProfile(
                  name: profileName,
                  uri: vlessUri,
                );
                widget.onProfileSelected(profile);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteSubscription(VpnSubscription subscription) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подписку?'),
        content: Text('Подписка "${subscription.name}" будет удалена'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _repository.deleteSubscription(subscription.id);
        await _loadSubscriptions();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $e')),
        );
      }
    }
  }
}

