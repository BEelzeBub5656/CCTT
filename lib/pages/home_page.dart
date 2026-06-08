import 'dart:async';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../services/sync_service.dart';
import 'add_record_page.dart';
import 'edit_record_page.dart';
import 'record_detail_page.dart';
/// 主页面
///
/// 以 ListView 展示本地库存移动记录，支持按仓库筛选，并用不同颜色图标区分同步状态。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<StockMovement> _movements = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;
  int _unpushedCount = 0;
  int _cloudNewCount = 0;
  bool _cloudChecked = false;
  String _searchKeyword = '';
  /// null 表示「所有仓库」
  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      _checkUnpushedRecords();
      _autoPullFromCloud();
    }).catchError((e) {
      debugPrint('HomePage init 加载失败: $e');
    });
  }

  /// 加载所有数据
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final movements = await DatabaseHelper.instance.getAllMovements();
      final warehouses = await DatabaseHelper.instance.getAllWarehouses();
      if (mounted) {
        final unsynced = movements.where((m) => m.syncStatus != SyncStatus.synced).length;
        setState(() {
          _movements = movements;
          _warehouses = warehouses;
          _unpushedCount = unsynced;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('_loadData 失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 启动后检测未推送到云端的记录
  void _checkUnpushedRecords() {
    if (!mounted || _unpushedCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('有 $_unpushedCount 条记录尚未同步到云端'),
          action: SnackBarAction(
            label: '立即同步',
            onPressed: _syncRecords,
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    });
  }

  /// 启动后静默拉取云端快照，Master 快照强制覆盖本地
  Future<void> _autoPullFromCloud() async {
    if (!mounted) return;
    final result = await SyncService.pullSnapshot();
    if (!mounted) return;

    setState(() {
      _cloudNewCount = result.addedCount;
      _cloudChecked = true;
    });

    if (result.success) {
      // 总是刷新列表（数据可能被 Master 快照覆盖更新）
      await _loadData();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.addedCount > 0 ? Colors.teal : Colors.grey.shade700,
            duration: Duration(seconds: result.addedCount > 0 ? 5 : 2),
          ),
        );
      });
    }
    // 超时等错误静默忽略，用户可手动下拉
  }

  /// 根据当前选择筛选记录
  List<StockMovement> get _filteredMovements {
    var list = _movements.where((m) => !m.isDeleted).toList();
    if (_selectedWarehouseId != null) {
      list = list.where((m) => m.warehouseId == _selectedWarehouseId).toList();
    }
    if (_searchKeyword.isNotEmpty) {
      final kw = _searchKeyword.toLowerCase();
      list = list.where((m) {
        final time = DateTime.fromMillisecondsSinceEpoch(m.timestamp);
        final monthStr = '${time.year}年${time.month}月 ${time.month}月';
        final searchText = [
          m.partnerName, m.color, m.variety, m.deliveryPerson ?? '',
          _warehouseName(m.warehouseId),
          monthStr,
        ].join(' ').toLowerCase();
        return searchText.contains(kw);
      }).toList();
    }
    return list;
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    await _loadData();
  }

  /// 从云端拉取 retain 全量快照（带全屏 Loading，手动触发）
  Future<void> _pullSnapshot() async {
    if (!mounted) return;

    // 显示全屏 Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    PullResult result;
    try {
      result = await SyncService.pullSnapshot();
    } finally {
      // 无论成功还是失败，必须关闭 Loading，防止界面锁死
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    // 更新云端状态
    if (mounted) {
      setState(() {
        _cloudNewCount = result.addedCount;
        _cloudChecked = true;
      });
    }

    // 刷新页面
    await _loadData();

    if (!mounted) return;

    // 出错场景弹窗提示
    if (!result.success) {
      final isDnsError = result.message.contains('SocketException') ||
                         result.message.contains('host lookup') ||
                         result.message.contains('No address');
      final brokerName = 'kf33d077.ala.cn-hangzhou.emqxsl.cn';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('连接云端失败'),
          content: Text(
            isDnsError
                ? '无法解析 MQTT 服务器地址。\n\n'
                  'Broker: $brokerName\n\n'
                  '可能原因：\n'
                  '1. 手机网络未连接\n'
                  '2. EMQX 服务已停止\n'
                  '3. DNS 解析失败，稍后重试'
                : result.message,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // 重试
                if (mounted) _pullSnapshot();
              },
              child: const Text('重试'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// 手动同步（上传 + 下拉合一，先上后下）
  Future<void> _syncRecords() async {
    if (!mounted) return;

    // 1. 找出所有 != synced 的记录，标记为 syncing
    final allRecords = await DatabaseHelper.instance.getAllMovements();
    final unsynced = allRecords
        .where((r) => r.syncStatus != SyncStatus.synced)
        .toList();
    if (unsynced.isNotEmpty) {
      final ids = unsynced.map((r) => r.id).toList();
      await DatabaseHelper.instance.updateSyncStatus(ids, SyncStatus.syncing);
    }

    // 2. 刷新界面 → 蓝色"正在同步"
    await _loadData();

    // 3. 推本地变更到 Master
    final pushResult = await SyncService.syncPendingRecords();

    // 4. 下拉 Master 最新快照
    final pullResult = await SyncService.pullSnapshot();
    setState(() {
      _cloudNewCount = pullResult.addedCount;
      _cloudChecked = true;
    });
    await _loadData();

    // 5. 提示结果
    if (mounted) {
      final isSuccess = pushResult.contains('成功');
      if (isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pullResult.message),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // 失败弹窗，提供重试
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('同步失败'),
            content: Text(pushResult),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _syncRecords(); // 重试
                },
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 跳转到新建页面
  Future<void> _navigateToAdd() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddRecordPage()),
    );
    if (result == true && mounted) {
      setState(() => _selectedWarehouseId = null);
      await _loadData();
      _autoSync(); // 新建后自动上传
    }
  }

  /// 静默自动同步（不弹窗，上传→等 Master 处理→下拉）
  void _autoSync() {
    SyncService.syncPendingRecords().then((_) async {
      // 等 Web 处理完并发快照（去抖 800ms + 网络延迟）
      await Future.delayed(const Duration(milliseconds: 1500));
      final r = await SyncService.pullSnapshot();
      if (mounted) {
        setState(() { _cloudNewCount = r.addedCount; _cloudChecked = true; });
        _loadData();
      }
    });
  }

  /// 添加仓库弹窗
  Future<void> _showAddWarehouseDialog() async {
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('添加仓库'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '仓库名称',
              hintText: '如：主仓库、北区仓',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(dialogContext).pop(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final scaffold = ScaffoldMessenger.of(context);
                await DatabaseHelper.instance.insertWarehouse(
                  Warehouse(name: name),
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                await _loadData();
                if (mounted) {
                  scaffold.showSnackBar(
                    SnackBar(content: Text('仓库 "$name" 已添加')),
                  );
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );

    // 延迟到 dialog 完全关闭后再 dispose controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 创建默认仓库（空状态快捷入口）
  Future<void> _createDefaultWarehouse() async {
    final scaffold = ScaffoldMessenger.of(context);
    await DatabaseHelper.instance.insertWarehouse(
      Warehouse(name: '默认仓库'),
    );
    if (mounted) {
      await _loadData();
      scaffold.showSnackBar(
        const SnackBar(content: Text('已创建默认仓库')),
      );
    }
  }

  /// 根据仓库 ID 获取名称
  String _warehouseName(String warehouseId) {
    final w = _warehouses.firstWhere(
      (w) => w.id == warehouseId,
      orElse: () => Warehouse(name: '未知仓库'),
    );
    return w.name;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMovements;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CCTT 库存管理'),
        actions: [
          IconButton(
            icon: _unpushedCount > 0
                ? Badge(
                    label: Text('$_unpushedCount'),
                    child: const Icon(Icons.cloud_upload),
                  )
                : const Icon(Icons.cloud_upload),
            tooltip: _unpushedCount > 0 ? '推送到云端（$_unpushedCount 条待推送）' : '推送到云端',
            onPressed: _syncRecords,
          ),
          IconButton(
            icon: _cloudNewCount > 0
                ? Badge(
                    label: Text('$_cloudNewCount'),
                    backgroundColor: Colors.teal,
                    child: const Icon(Icons.cloud_download),
                  )
                : _cloudChecked
                    ? const Icon(Icons.cloud_download, color: Colors.green)
                    : const Icon(Icons.cloud_download),
            tooltip: _cloudNewCount > 0
                ? '从云端拉取（$_cloudNewCount 条新数据）'
                : _cloudChecked
                    ? '云端已同步，暂无新数据'
                    : '从云端拉取快照',
            onPressed: _pullSnapshot,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新列表',
            onPressed: _onRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '已作废记录',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DeletedRecordsPage(
                    records: _movements.where((m) => m.isDeleted).toList(),
                    warehouseName: _warehouseName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ───────────── 仓库筛选栏 ─────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: PopupMenuButton<String?>(
                    padding: EdgeInsets.zero,
                    offset: const Offset(0, 40),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _selectedWarehouseId == null
                            ? '所有仓库'
                            : _warehouseName(_selectedWarehouseId!),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onSelected: (value) {
                      if (mounted) setState(() => _selectedWarehouseId = value);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem<String?>(
                        value: null,
                        child: Text('所有仓库', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ..._warehouses.map((w) => PopupMenuItem<String?>(
                        value: w.id,
                        child: Text(w.name),
                      )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_business),
                  tooltip: '添加仓库',
                  onPressed: _showAddWarehouseDialog,
                ),
              ],
            ),
          ),

          // ───────────── 列表区域 ─────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              return _buildMovementCard(filtered[index]);
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton.extended(
              heroTag: 'search',
              onPressed: _showSearchDialog,
              icon: const Icon(Icons.search),
              label: Text(_searchKeyword.isNotEmpty ? '搜索中' : '查询'),
              backgroundColor: _searchKeyword.isNotEmpty ? Colors.teal : null,
            ),
            FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: _navigateToAdd,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// 关键词搜索弹窗
  Future<void> _showSearchDialog() async {
    final controller = TextEditingController(text: _searchKeyword);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.search, size: 20),
          const SizedBox(width: 8),
          const Text('查询记录'),
          const Spacer(),
          if (_searchKeyword.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__CLEAR__'),
              child: const Text('清除', style: TextStyle(fontSize: 12)),
            ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '交易对象、颜色、品种、送货人、X月…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_note),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: ['6月', '白色', '黑色', '绵羊毛', '山羊绒'].map((tag) => ActionChip(
                label: Text(tag, style: const TextStyle(fontSize: 12)),
                onPressed: () => Navigator.pop(ctx, tag),
              )).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );

    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
      return;
    }
    if (result == '__CLEAR__') {
      setState(() => _searchKeyword = '');
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
      return;
    }
    setState(() => _searchKeyword = result);
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  /// 空状态提示
  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    _selectedWarehouseId == null
                        ? '暂无库存移动记录'
                        : '该仓库暂无记录',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '点击右下角按钮添加第一条记录',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_warehouses.isEmpty)
                    ElevatedButton.icon(
                      onPressed: _createDefaultWarehouse,
                      icon: const Icon(Icons.add_business),
                      label: const Text('创建默认仓库'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 根据状态生成带颜色的文字标签
  /// 单条记录卡片（左滑展示操作按钮）
  Widget _buildMovementCard(StockMovement record) {
    return _SwipeableRecordCard(
      record: record,
      warehouseName: _warehouseName(record.warehouseId),
      onEdit: () async {
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => EditRecordPage(record: record)),
        );
        if (result == true && mounted) {
          setState(() => _selectedWarehouseId = null);
          await _loadData();
          _autoSync(); // 编辑后自动上传
        }
      },
      onDelete: () => _confirmDeleteRecord(record),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecordDetailPage(
              record: record,
              warehouseName: _warehouseName(record.warehouseId),
            ),
          ),
        );
      },
    );
  }

  /// 左滑作废二次确认（含作废原因选择）
  Future<void> _confirmDeleteRecord(StockMovement record) async {
    String? reason;
    final presetReasons = ['数据录入错误', '交易取消', '重复记录', '货物退回', '其他'];
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('确认作废'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要作废记录 "${record.partnerName}" 吗？'),
              const SizedBox(height: 12),
              const Text('作废原因：', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: presetReasons.map((r) => ChoiceChip(
                  label: Text(r),
                  selected: reason == r,
                  onSelected: (sel) {
                    setDialogState(() {
                      reason = sel ? r : null;
                      if (sel) reasonController.text = r == '其他' ? '' : r;
                    });
                  },
                )).toList(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  hintText: '输入作废原因（可选）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
                onChanged: (v) { reason = v.isEmpty ? null : v; },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('确认作废'),
            ),
          ],
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => reasonController.dispose());

    if (confirmed == true && mounted) {
      final updated = record.copyWith(timestamp: DateTime.now().millisecondsSinceEpoch, isDeleted: true, syncStatus: SyncStatus.pending, voidReason: reason);
      await DatabaseHelper.instance.updateMovement(updated);
      await _loadData();
      _autoSync(); // 作废后自动上传
      if (mounted) {
        final msg = reason != null && reason!.isNotEmpty
            ? '"${record.partnerName}" 已作废（原因：$reason）'
            : '"${record.partnerName}" 已作废';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }
}

// ── 记录卡片组件 ──
class _SwipeableRecordCard extends StatelessWidget {
  final StockMovement record;
  final String warehouseName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _SwipeableRecordCard({
    required this.record,
    required this.warehouseName,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  String _pad(int n) => n.toString().padLeft(2, '0');
  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = record;
    final isDeleted = r.isDeleted;

    final displayTitle = r.color.isNotEmpty || r.variety.isNotEmpty
        ? '${r.color}${r.color.isNotEmpty && r.variety.isNotEmpty ? ' / ' : ''}${r.variety}'
        : r.partnerName;

    final status = r.syncStatus;
    final badgeInfo = switch (status) {
      SyncStatus.synced  => ('已同步', Colors.green),
      SyncStatus.syncing => ('正在同步', Colors.blue),
      SyncStatus.failed  => ('同步失败', Colors.red),
      SyncStatus.pending => ('未同步', Colors.orange),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isDeleted ? Colors.grey.shade50 : null,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: status == SyncStatus.synced
              ? Colors.green.shade100 : Colors.orange.shade100,
          child: Icon(
            status == SyncStatus.synced ? Icons.check_circle : Icons.sync,
            color: status == SyncStatus.synced ? Colors.green.shade800 : Colors.orange.shade800,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: r.type == MovementType.inbound ? Colors.green.shade50 : r.type == MovementType.outbound ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: r.type == MovementType.inbound ? Colors.green : r.type == MovementType.outbound ? Colors.red : Colors.orange),
              ),
              child: Text(
                r.type == MovementType.inbound ? '入库' : r.type == MovementType.outbound ? '出库' : '进货',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: r.type == MovementType.inbound ? Colors.green.shade800 : r.type == MovementType.outbound ? Colors.red.shade800 : Colors.orange.shade800),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(displayTitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: isDeleted ? TextDecoration.lineThrough : null,
                  color: isDeleted ? Colors.grey.shade500 : null,
                ),
              ),
            ),
            if (isDeleted)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('已作废', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
              ),
            if (!isDeleted)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Icon(Icons.edit_note, color: Colors.teal.shade400, size: 20),
                tooltip: '操作',
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(
                    leading: Icon(Icons.edit, color: Colors.blue),
                    title: Text('修改记录'),
                    dense: true, contentPadding: EdgeInsets.zero,
                  )),
                  PopupMenuItem(value: 'delete', child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('作废记录', style: TextStyle(color: Colors.red)),
                    dense: true, contentPadding: EdgeInsets.zero,
                  )),
                ],
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$warehouseName  •  ${_fmt(r.timestamp)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDeleted ? Colors.grey.shade400 : Colors.grey.shade700,
                      decoration: isDeleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (r.imagePath != null && r.imagePath!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.camera_alt, size: 14, color: Colors.teal.shade300),
                  ),
              ],
            ),
            Row(
              children: [
                Text(
                  '净重 ${r.quantity.toStringAsFixed(2)} kg  |  单价 ¥${r.unitPrice.toStringAsFixed(2)}/吨',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDeleted ? Colors.grey.shade400 : Colors.grey.shade700,
                    decoration: isDeleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeInfo.$2.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeInfo.$2, width: 1.5),
                  ),
                  child: Text(badgeInfo.$1, style: TextStyle(
                    color: badgeInfo.$2, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 已作废记录列表页 ──
class _DeletedRecordsPage extends StatelessWidget {
  final List<StockMovement> records;
  final String Function(String) warehouseName;
  const _DeletedRecordsPage({required this.records, required this.warehouseName});

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('已作废记录（${records.length}）')),
      body: records.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.delete_sweep, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('没有已作废的记录', style: TextStyle(color: Colors.grey, fontSize: 16)),
              ]),
            )
          : ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final r = records[index];
                final status = r.syncStatus;
                final badgeInfo = switch (status) {
                  SyncStatus.synced  => ('已同步', Colors.green),
                  SyncStatus.syncing => ('正在同步', Colors.blue),
                  SyncStatus.failed  => ('同步失败', Colors.red),
                  SyncStatus.pending => ('未同步', Colors.orange),
                };
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: Colors.grey.shade50,
                  child: ListTile(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RecordDetailPage(record: r, warehouseName: warehouseName(r.warehouseId)),
                      ));
                    },
                    leading: const Icon(Icons.cancel, color: Colors.red),
                    title: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: r.type == MovementType.inbound ? Colors.green.shade50 : r.type == MovementType.outbound ? Colors.red.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: r.type == MovementType.inbound ? Colors.green : r.type == MovementType.outbound ? Colors.red : Colors.orange),
                        ),
                        child: Text(r.type == MovementType.inbound ? '入库' : r.type == MovementType.outbound ? '出库' : '进货',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                              color: r.type == MovementType.inbound ? Colors.green.shade800 : r.type == MovementType.outbound ? Colors.red.shade800 : Colors.orange.shade800)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.partnerName, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey))),
                    ]),
                    subtitle: Text(
                      '${warehouseName(r.warehouseId)}  •  ${_fmt(r.timestamp)}  |  ${r.quantity.toStringAsFixed(2)}kg  |  ¥${r.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeInfo.$2.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeInfo.$2, width: 1.5)),
                      child: Text(badgeInfo.$1, style: TextStyle(color: badgeInfo.$2, fontSize: 12, fontWeight: FontWeight.bold))),
                  ));
              }),
    );
  }
}
