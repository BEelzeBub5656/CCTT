import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';

import '../services/update_service.dart';

/// 更新对话框
class UpdateDialog extends StatefulWidget {
  final VersionInfo versionInfo;
  final bool forceUpdate;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
    required this.forceUpdate,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !widget.forceUpdate && !_downloading,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.teal),
            const SizedBox(width: 8),
            Text('发现新版本 ${widget.versionInfo.versionName}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 版本信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('版本号', widget.versionInfo.versionName),
                    _buildInfoRow('大小', widget.versionInfo.fileSizeFormatted),
                    _buildInfoRow(
                      '发布时间',
                      _formatTimestamp(widget.versionInfo.buildTime),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 更新日志
              if (widget.versionInfo.changelog.isNotEmpty) ...[
                const Text('更新内容：',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                ...widget.versionInfo.changelog.map((log) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: Colors.teal)),
                          Expanded(
                            child: Text(log,
                                style: const TextStyle(fontSize: 13, height: 1.4)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
              ],

              // 强制更新提示
              if (widget.forceUpdate)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '此版本为强制更新，必须更新后才能继续使用',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // 下载进度
              if (_downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(_status,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        actions: [
          if (!widget.forceUpdate && !_downloading)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后更新'),
            ),
          ElevatedButton(
            onPressed: _downloading ? null : _downloadAndInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: Text(_downloading ? '下载中...' : '立即更新'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0.0;
      _status = '正在请求下载权限...';
    });

    // 请求存储权限
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        setState(() {
          _downloading = false;
          _status = '需要存储权限才能下载更新';
        });
        return;
      }
    }

    try {
      setState(() => _status = '正在下载...');

      // 下载文件
      final response = await http.Client().send(
        http.Request('GET', Uri.parse(widget.versionInfo.downloadUrl)),
      );

      if (response.statusCode != 200) {
        throw Exception('下载失败: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final bytes = <int>[];
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        receivedBytes += chunk.length;

        if (contentLength > 0) {
          setState(() {
            _progress = receivedBytes / contentLength;
            _status =
                '已下载 ${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(contentLength / (1024 * 1024)).toStringAsFixed(1)} MB';
          });
        }
      }

      // 保存文件
      setState(() => _status = '正在保存...');
      final directory = await getExternalStorageDirectory();
      final filePath =
          '${directory!.path}/cctt-${widget.versionInfo.versionName}.apk';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      setState(() => _status = '准备安装...');

      // 安装APK
      if (mounted) {
        final result = await OpenFile.open(filePath);
        if (result.type == ResultType.done) {
          // 安装成功，关闭对话框
          if (mounted) Navigator.pop(context, true);
        } else {
          setState(() {
            _downloading = false;
            _status = '打开安装包失败: ${result.message}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _status = '下载失败: $e';
        });
      }
    }
  }
}

/// 在APP启动时检查更新
Future<void> checkUpdateOnStartup(BuildContext context) async {
  try {
    final result = await UpdateService.checkUpdate();

    if (!context.mounted) return;

    if (result.hasUpdate && result.latest != null) {
      await showDialog(
        context: context,
        barrierDismissible: !result.forceUpdate,
        builder: (ctx) => UpdateDialog(
          versionInfo: result.latest!,
          forceUpdate: result.forceUpdate,
        ),
      );
    }
  } catch (e) {
    // 静默失败，不打扰用户
  }
}

/// 手动检查更新
Future<void> checkUpdateManually(BuildContext context) async {
  // 显示加载提示
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在检查更新...'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final result = await UpdateService.checkUpdate();

    if (!context.mounted) return;

    // 关闭加载提示
    Navigator.pop(context);

    if (result.hasUpdate && result.latest != null) {
      await showDialog(
        context: context,
        barrierDismissible: !result.forceUpdate,
        builder: (ctx) => UpdateDialog(
          versionInfo: result.latest!,
          forceUpdate: result.forceUpdate,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败: $e')),
      );
    }
  }
}
