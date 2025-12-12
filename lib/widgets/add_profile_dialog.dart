import 'package:flutter/material.dart';
import '../services/subscription_manager.dart';

class AddProfileDialog extends StatefulWidget {
  const AddProfileDialog({Key? key}) : super(key: key);

  @override
  State<AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<AddProfileDialog> {
  late TextEditingController _inputController;
  late TextEditingController _nameController;
  String _detectedType = 'Определяю...';
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _nameController = TextEditingController();
    _inputController.addListener(_detectType);
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _detectType() {
    setState(() => _isValidating = true);

    final input = _inputController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _detectedType = 'Введите URL или VLESS ключ';
        _isValidating = false;
      });
      return;
    }

    // Проверяем если это VLESS ключ
    if (input.startsWith('vless://')) {
      setState(() {
        _detectedType = '✓ VLESS Ключ';
        _isValidating = false;
      });
      return;
    }

    // Проверяем если это подписка (URL)
    final manager = SubscriptionService();
    if (manager.isValidSubscriptionUrl(input)) {
      setState(() {
        _detectedType = '✓ Подписка URL';
        _isValidating = false;
      });
    } else {
      setState(() {
        _detectedType = '✗ Неверный формат';
        _isValidating = false;
      });
    }
  }

  bool get _isVless => _inputController.text.trim().startsWith('vless://');
  bool get _isValidInput => _inputController.text.isNotEmpty &&
      (_isVless ||
          SubscriptionService().isValidSubscriptionUrl(_inputController.text.trim()));
  bool get _isComplete =>
      _isValidInput && _nameController.text.isNotEmpty && !_isValidating;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить профиль/подписку'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя (опционально)',
                hintText: 'Например: Мой сервер',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'URL подписки или VLESS ключ',
                hintText: 'vless://... или https://...',
                border: const OutlineInputBorder(),
                helperText: _detectedType,
                helperStyle: TextStyle(
                  color: _isValidating
                      ? Colors.blue
                      : (_isValidInput ? Colors.green : Colors.red),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isVless
                  ? 'Тип: Прямой VLESS ключ'
                  : 'Тип: Подписка (будут загружены все профили)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isComplete
              ? () {
                  final input = _inputController.text.trim();
                  final name = _nameController.text.trim();

                  Navigator.pop(
                    context,
                    {
                      'input': input,
                      'name': name,
                      'isVless': _isVless,
                    },
                  );
                }
              : null,
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
