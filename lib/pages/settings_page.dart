import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// 设置页 — OCR 服务器 + MQTT 配置
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ocrUrlController = TextEditingController();
  final _brokerController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _ocrUrlController.text = await SettingsService.getOcrServerUrl();
    _brokerController.text = await SettingsService.getMqttBroker();
    _portController.text = (await SettingsService.getMqttPort()).toString();
    _usernameController.text = await SettingsService.getMqttUsername();
    _passwordController.text = await SettingsService.getMqttPassword();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await SettingsService.setOcrServerUrl(_ocrUrlController.text);
    await SettingsService.setMqttBroker(_brokerController.text);
    final port = int.tryParse(_portController.text.trim()) ?? 8883;
    await SettingsService.setMqttPort(port);
    await SettingsService.setMqttUsername(_usernameController.text);
    await SettingsService.setMqttPassword(_passwordController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  @override
  void dispose() {
    _ocrUrlController.dispose();
    _brokerController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ── OCR 配置 ──
        _sectionTitle('OCR 识别配置'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextFormField(
              controller: _ocrUrlController,
              decoration: const InputDecoration(
                labelText: 'OCR 服务器地址',
                hintText: 'https://beelzebub.top',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.document_scanner),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // ── MQTT 配置 ──
        _sectionTitle('MQTT 同步配置'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextFormField(
                controller: _brokerController,
                decoration: const InputDecoration(
                  labelText: 'Broker 地址',
                  hintText: 'kf33d077.ala.cn-hangzhou.emqxsl.cn',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '8883',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存设置'),
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey)),
      );
}
