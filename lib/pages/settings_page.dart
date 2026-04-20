import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 设置中心
///
/// 提供 MQTT 连接配置和交互偏好设置。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _brokerController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  double _longPressDuration = 3.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final broker = await SettingsService.getMqttBroker();
    final port = await SettingsService.getMqttPort();
    final username = await SettingsService.getMqttUsername();
    final password = await SettingsService.getMqttPassword();
    final duration = await SettingsService.getLongPressDuration();

    if (mounted) {
      setState(() {
        _brokerController.text = broker;
        _portController.text = port.toString();
        _usernameController.text = username;
        _passwordController.text = password;
        _longPressDuration = duration;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final port = int.tryParse(_portController.text.trim()) ?? 8883;

    await SettingsService.setMqttBroker(_brokerController.text.trim());
    await SettingsService.setMqttPort(port);
    await SettingsService.setMqttUsername(_usernameController.text.trim());
    await SettingsService.setMqttPassword(_passwordController.text.trim());
    await SettingsService.setLongPressDuration(_longPressDuration);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置中心'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ───── MQTT 配置 ─────
                _buildSectionTitle('MQTT 连接配置'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _brokerController,
                          decoration: const InputDecoration(
                            labelText: 'Broker 地址',
                            hintText: '如：kf33d077.ala.cn-hangzhou.emqxsl.cn',
                            prefixIcon: Icon(Icons.dns),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _portController,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            hintText: '如：8883',
                            prefixIcon: Icon(Icons.settings_ethernet),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: '密码',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ───── 长按确认时间 ─────
                _buildSectionTitle('长按修改确认时间'),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('按住时长'),
                            Text(
                              '${_longPressDuration.toStringAsFixed(1)} 秒',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _longPressDuration,
                          min: 1.0,
                          max: 5.0,
                          divisions: 8,
                          label: '${_longPressDuration.toStringAsFixed(1)}s',
                          onChanged: (value) {
                            setState(() => _longPressDuration = value);
                          },
                        ),
                        const Text(
                          '主页列表中长按某条记录达到该时长后，会弹出修改确认对话框。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ───── 保存按钮 ─────
                FilledButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('保存设置'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}
