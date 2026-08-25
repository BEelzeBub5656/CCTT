import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../services/offline_sync_service.dart';

/// 离线同步页面 - 数据导出/导入
class OfflineSyncPage extends StatefulWidget {
  const OfflineSyncPage({super.key});

  @override
  State<OfflineSyncPage> createState() => _OfflineSyncPageState();
}

class _OfflineSyncPageState extends State<OfflineSyncPage> {
  List<File> _backupFiles = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
  }

  Future<void> _loadBackupFiles() async {
    setState(() => _loading = true);
    try {
      final files = await OfflineSyncService.getExportFiles();
      if (mounted) {
        setState(() {
          _backupFiles = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('加载备份文件失败: $e');
      }
    }
  }

  Future<void> _exportData() async {
    setState(() => _loading = true);
    try {
      await OfflineSyncService.exportAndShare();
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据已导出，可通过分享发送到其他设备')),
        );
        _loadBackupFiles();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('导出失败: $e');
      }
    }
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
      await _showImportDialog(filePath);
    } catch (e) {
      _showError('选择文件失败: $e');
    }
  }

  Future<void> _showImportDialog(String filePath) async {
    String? strategy = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件: ${filePath.split('/').last}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            const Text('遇到重复数据时：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildStrategyOption(ctx, 'merge', '合并', '使用最新时间戳的数据（推荐）', true),
            _buildStrategyOption(ctx, 'skip', '跳过', '保留本地数据，不导入重复项', false),
            _buildStrategyOption(ctx, 'replace', '替换', '用导入数据覆盖本地', false),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (strategy != null && mounted) {
      await _performImport(filePath, strategy);
    }
  }

  Widget _buildStrategyOption(
      BuildContext ctx, String value, String title, String desc, bool recommended) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: recommended ? Colors.teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: recommended ? Colors.teal.shade50 : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: recommended ? Colors.teal.shade800 : null)),
                if (recommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('推荐',
                        style: TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Future<void> _performImport(String filePath, String strategy) async {
    setState(() => _loading = true);
    try {
      final result = await OfflineSyncService.importFromJson(filePath, strategy: strategy);
      if (mounted) {
        setState(() => _loading = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导入完成'),
            content: Text(result.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('导入失败: $e');
      }
    }
  }

  Future<void> _importFromBackup(File file) async {
    await _showImportDialog(file.path);
  }

  void _showError(String message) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('错误'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线数据同步'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBackupFiles,
            tooltip: '刷新列表',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 说明卡片
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            const Text('离线同步说明',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '• 导出数据后，可通过微信/邮件/蓝牙发送到其他设备\n'
                          '• 在其他设备上导入该文件即可同步数据\n'
                          '• 合并策略会智能选择最新的数据\n'
                          '• 支持多次导入，不会产生重复数据',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 导出按钮
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _exportData,
                    icon: const Icon(Icons.upload, size: 24),
                    label: const Text('导出数据并分享', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 导入按钮
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _importFromFile,
                    icon: const Icon(Icons.download, size: 24),
                    label: const Text('从文件导入数据', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      side: const BorderSide(color: Colors.teal, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 本地备份列表
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('本地备份文件',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${_backupFiles.length} 个',
                        style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 12),

                if (_backupFiles.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('暂无本地备份文件',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ..._backupFiles.map((file) {
                    final stat = file.statSync();
                    final modified = DateFormat('yyyy-MM-dd HH:mm:ss').format(stat.modified);
                    final size = _formatFileSize(stat.size);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.folder, color: Colors.orange),
                        title: Text(file.path.split('/').last,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text('$modified · $size',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: IconButton(
                          icon: const Icon(Icons.upload, color: Colors.teal),
                          onPressed: () => _importFromBackup(file),
                          tooltip: '导入此备份',
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
