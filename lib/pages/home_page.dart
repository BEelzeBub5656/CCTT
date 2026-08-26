import 'dart:async';
import 'package:flutter/material.dart';
import '../data/database_helper.dart';
import '../models/order.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../services/sync_service.dart';
import '../widgets/update_dialog.dart';
import 'add_order_page.dart';
import 'order_detail_page.dart';
import 'settings_page.dart';
import 'summary_page.dart';

/// 主页面
///
/// 以 ListView 展示本地主单据，支持按仓库筛选，并用不同颜色图标区分同步状态。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<OrderDetail> _orders = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;
  int _unpushedCount = 0;
  int _cloudNewCount = 0;
  String _searchKeyword = '';
  Timer? _autoSyncTimer;
  bool _isAutoSyncRunning = false;
  bool _isManualSyncing = false;

  /// null 表示「所有仓库」
  String? _selectedWarehouseId;

  /// null 表示「全部单据类型」
  MovementType? _selectedType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkUpdateOnStartup(context);
    });
    _loadData().then((_) {
      _checkUnpushedRecords();
      _autoPullFromCloud();
      _startAutoSyncTimer();
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
      final allOrders = await DatabaseHelper.instance.getAllOrders();
      final orderDetails = <OrderDetail>[];
      for (final o in allOrders) {
        final items = await DatabaseHelper.instance.getOrderItems(o.id);
        final fees = await DatabaseHelper.instance.getOrderFees(o.id);
        orderDetails.add(OrderDetail(order: o, items: items, fees: fees));
      }
      if (mounted) {
        if (movements.isNotEmpty) {
          await DatabaseHelper.instance.deleteMovements(
            movements.map((m) => m.id).toList(),
          );
        }
        final unsynced = orderDetails
            .where((d) => d.order.syncStatus != SyncStatus.synced)
            .length;
        setState(() {
          _orders = orderDetails;
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

  /// 启动后检测未推送到云端的单据
  void _checkUnpushedRecords() {
    if (!mounted || _unpushedCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('有 $_unpushedCount 张单据尚未同步到云端'),
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
            backgroundColor:
                result.addedCount > 0 ? Colors.teal : Colors.grey.shade700,
            duration: Duration(seconds: result.addedCount > 0 ? 5 : 2),
          ),
        );
      });
    }
    // 超时等错误静默忽略，用户可手动下拉
  }

  List<OrderDetail> get _filteredOrders {
    var list = _orders.where((o) => !o.order.isDeleted).toList();
    if (_selectedWarehouseId != null) {
      list = list
          .where((o) => o.order.warehouseId == _selectedWarehouseId)
          .toList();
    }
    if (_selectedType != null) {
      list = list.where((o) => o.order.type == _selectedType).toList();
    }
    if (_searchKeyword.isNotEmpty) {
      final kw = _searchKeyword.toLowerCase();
      list = list.where((o) {
        final time = DateTime.fromMillisecondsSinceEpoch(o.order.timestamp);
        final monthStr = '${time.year}年${time.month}月 ${time.month}月';
        final itemNames = o.items.map((i) => i.itemName).join(' ');
        final searchText = [
          o.order.partnerName,
          itemNames,
          o.order.remark ?? '',
          _warehouseName(o.order.warehouseId),
          monthStr,
        ].join(' ').toLowerCase();
        return searchText.contains(kw);
      }).toList();
    }
    return list;
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    await _syncRecords();
  }

  /// 手动同步（上传 + 下拉合一，先上后下）
  Future<void> _syncRecords() async {
    if (!mounted || _isManualSyncing) return;
    setState(() => _isManualSyncing = true);
    var retryRequested = false;

    try {
      // 1. 推本地变更到 Master
      final pushResult = await SyncService.syncPendingRecords();

      // 2. 下拉 Master 最新快照
      final pullResult = await SyncService.pullSnapshot();
      if (mounted) {
        setState(() => _cloudNewCount = pullResult.addedCount);
      }
      await _loadData();

      // 3. 提示结果
      if (mounted) {
        final isSuccess = !pushResult.startsWith('同步失败') && pullResult.success;
        if (isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(pullResult.message),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // 失败弹窗，提供重试
          final failureMessages = <String>[
            if (pushResult.startsWith('同步失败')) pushResult,
            if (!pullResult.success) pullResult.message,
          ];
          retryRequested = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('同步失败'),
                  content: Text(failureMessages.join('\n\n')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('重试'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ) ??
              false;
        }
      }
    } finally {
      if (mounted) setState(() => _isManualSyncing = false);
    }
    if (retryRequested && mounted) await _syncRecords();
  }

  /// 跳转到新建 Order 页面
  Future<void> _navigateToAddOrder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddOrderPage()),
    );
    await _loadData();
    _autoSync();
  }

  /// 静默自动同步（不弹窗，上传→等 Master 处理→下拉）
  void _autoSync() {
    if (_isAutoSyncRunning) return;
    _isAutoSyncRunning = true;
    SyncService.syncPendingRecords()
        .then((_) async {
          // 等 Web 处理完并发快照（去抖 800ms + 网络延迟）
          await Future.delayed(const Duration(milliseconds: 2000));
          final r = await SyncService.pullSnapshot();
          if (mounted) {
            setState(() {
              _cloudNewCount = r.addedCount;
            });
            await _loadData();
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          _isAutoSyncRunning = false;
        });
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      _autoSync();
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
    _autoSyncTimer?.cancel();
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
    final filtered = _filteredOrders;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        titleSpacing: 10,
        title: PopupMenuButton<String>(
          tooltip: '选择仓库',
          padding: EdgeInsets.zero,
          offset: const Offset(0, 44),
          onSelected: (value) {
            setState(() {
              _selectedWarehouseId = value.isEmpty ? null : value;
            });
          },
          itemBuilder: (_) {
            final totalActive = _orders.where((o) => !o.order.isDeleted).length;
            return [
              PopupMenuItem<String>(
                value: '',
                child: Text(
                  '所有仓库（$totalActive）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ..._warehouses.map((warehouse) {
                final count = _orders
                    .where((o) =>
                        !o.order.isDeleted &&
                        o.order.warehouseId == warehouse.id)
                    .length;
                return PopupMenuItem<String>(
                  value: warehouse.id,
                  child: Text('${warehouse.name}（$count）'),
                );
              }),
            ];
          },
          child: Row(
            children: [
              const Icon(Icons.warehouse_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedWarehouseId == null
                      ? '所有仓库（${_orders.where((o) => !o.order.isDeleted).length}）'
                      : '${_warehouseName(_selectedWarehouseId!)}（${_orders.where((o) => !o.order.isDeleted && o.order.warehouseId == _selectedWarehouseId).length}）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business),
            tooltip: '添加仓库',
            visualDensity: VisualDensity.compact,
            onPressed: _showAddWarehouseDialog,
          ),
          IconButton(
            icon: _buildSyncIcon(),
            tooltip: _unpushedCount > 0 || _cloudNewCount > 0
                ? '同步并刷新（待上传 $_unpushedCount，云端新增 $_cloudNewCount）'
                : '同步并刷新',
            visualDensity: VisualDensity.compact,
            onPressed: _isManualSyncing ? null : _syncRecords,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '已作废单据',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DeletedOrdersPage(
                    orders: _orders.where((o) => o.order.isDeleted).toList(),
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
          // ───────────── 单据类型筛选 ─────────────
          _buildTypeFilter(),

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
                              return _buildOrderCard(filtered[index]);
                            },
                          ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildSyncIcon() {
    if (_isManualSyncing) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    final pendingCount = _unpushedCount + _cloudNewCount;
    if (pendingCount > 0) {
      return Badge(
        label: Text('$pendingCount'),
        child: const Icon(Icons.sync),
      );
    }
    return const Icon(Icons.sync);
  }

  Widget _buildTypeFilter() {
    final types = <MovementType?>[
      null,
      MovementType.inbound,
      MovementType.outbound,
      MovementType.supply,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: types.map((type) {
          final selected = _selectedType == type;
          final color = _typeFilterColor(type);
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: type == MovementType.supply ? 0 : 6,
              ),
              child: InkWell(
                onTap: () => setState(() => _selectedType = type),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.12)
                        : Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? color
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${_typeFilterLabel(type)} ${_typeFilterCount(type)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? color
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  int _typeFilterCount(MovementType? type) {
    return _orders.where((detail) {
      final order = detail.order;
      if (order.isDeleted) return false;
      if (_selectedWarehouseId != null &&
          order.warehouseId != _selectedWarehouseId) {
        return false;
      }
      return type == null || order.type == type;
    }).length;
  }

  String _typeFilterLabel(MovementType? type) {
    return switch (type) {
      null => '全部',
      MovementType.inbound => '入库',
      MovementType.outbound => '出库',
      MovementType.supply => '进货',
    };
  }

  Color _typeFilterColor(MovementType? type) {
    return switch (type) {
      null => Colors.teal,
      MovementType.inbound => Colors.green,
      MovementType.outbound => Colors.red,
      MovementType.supply => Colors.orange.shade800,
    };
  }

  Widget _buildBottomNavigationBar() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              _buildNavItem(
                icon: Icons.home_rounded,
                label: '首页',
                selected: _searchKeyword.isEmpty,
                onTap: () {},
              ),
              _buildNavItem(
                icon: Icons.analytics_outlined,
                label: '汇总',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SummaryPage()),
                  );
                },
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: '新增单据',
                  child: InkResponse(
                    onTap: _navigateToAddOrder,
                    radius: 30,
                    child: Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 32,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildNavItem(
                icon: Icons.search_rounded,
                label: '查询',
                selected: _searchKeyword.isNotEmpty,
                onTap: _showSearchDialog,
              ),
              _buildNavItem(
                icon: Icons.settings_outlined,
                label: '设置',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? colors.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
          const Text('查询单据'),
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
                hintText: '交易对象、货物、备注、X月…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_note),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: ['6月', '白色', '黑色', '绵羊毛', '山羊绒']
                  .map((tag) => ActionChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.pop(ctx, tag),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
                    _selectedWarehouseId == null ? '暂无单据' : '该仓库暂无单据',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '点击右下角按钮添加第一张单据',
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

  /// 新建 Order 卡片
  Widget _buildOrderCard(OrderDetail d) {
    final o = d.order;
    final isInbound = o.type == MovementType.inbound;
    final isDeleted = o.isDeleted;
    final displayTitle = d.items.isNotEmpty
        ? d.items.map((i) => i.itemName).toSet().join('、')
        : o.partnerName;
    final dt = DateTime.fromMillisecondsSinceEpoch(o.timestamp);
    String pf(int n) => n.toString().padLeft(2, '0');
    final ts =
        '${dt.year}-${pf(dt.month)}-${pf(dt.day)} ${pf(dt.hour)}:${pf(dt.minute)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isDeleted ? Colors.grey.shade50 : null,
      child: ListTile(
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OrderDetailPage(orderId: o.id))),
        leading: CircleAvatar(
            backgroundColor: o.syncStatus == SyncStatus.synced
                ? Colors.green.shade100
                : Colors.orange.shade100,
            child: Icon(
                o.syncStatus == SyncStatus.synced
                    ? Icons.check_circle
                    : Icons.sync,
                color: o.syncStatus == SyncStatus.synced
                    ? Colors.green.shade800
                    : Colors.orange.shade800)),
        title: Row(children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: isInbound
                      ? Colors.green.shade50
                      : o.type == MovementType.outbound
                          ? Colors.red.shade50
                          : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isInbound
                          ? Colors.green
                          : o.type == MovementType.outbound
                              ? Colors.red
                              : Colors.orange)),
              child: Text(
                  isInbound
                      ? '入库'
                      : o.type == MovementType.outbound
                          ? '出库'
                          : '进货',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isInbound
                          ? Colors.green.shade800
                          : o.type == MovementType.outbound
                              ? Colors.red.shade800
                              : Colors.orange.shade800))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(displayTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isDeleted ? TextDecoration.lineThrough : null,
                      color: isDeleted ? Colors.grey.shade500 : null))),
          if (isDeleted)
            Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 1.5),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('已作废',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.red))),
        ]),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text(
              '${_warehouseName(o.warehouseId)}  •  $ts${d.items.length > 1 ? "  •  ${d.items.length}项货物" : ""}',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      isDeleted ? Colors.grey.shade400 : Colors.grey.shade700,
                  decoration: isDeleted ? TextDecoration.lineThrough : null)),
          Text('${o.partnerName}  |  ¥${d.totalAmount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: 12,
                  color: isDeleted ? Colors.grey.shade400 : Colors.teal)),
        ]),
        trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: (o.syncStatus == SyncStatus.synced
                        ? Colors.green
                        : Colors.orange)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: o.syncStatus == SyncStatus.synced
                        ? Colors.green
                        : Colors.orange,
                    width: 1.5)),
            child: Text(o.syncStatus == SyncStatus.synced ? '已同步' : '未同步',
                style: TextStyle(
                    color: o.syncStatus == SyncStatus.synced
                        ? Colors.green
                        : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold))),
      ),
    );
  }
}

// ── 已作废单据列表页 ──
class _DeletedOrdersPage extends StatelessWidget {
  final List<OrderDetail> orders;
  final String Function(String) warehouseName;

  const _DeletedOrdersPage({
    required this.orders,
    required this.warehouseName,
  });

  String _fmt(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  String _typeLabel(MovementType type) {
    return switch (type) {
      MovementType.inbound => '入库',
      MovementType.outbound => '出库',
      MovementType.supply => '进货',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('已作废单据（${orders.length}）')),
      body: orders.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_sweep, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    '没有已作废的单据',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final d = orders[index];
                final o = d.order;
                final displayTitle = d.items.isNotEmpty
                    ? d.items.map((i) => i.itemName).toSet().join('、')
                    : o.partnerName;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: Colors.grey.shade50,
                  child: ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailPage(orderId: o.id),
                        ),
                      );
                    },
                    leading: const Icon(Icons.cancel, color: Colors.red),
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Text(
                            _typeLabel(o.type),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayTitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${warehouseName(o.warehouseId)}  •  ${_fmt(o.timestamp)}  |  ${o.partnerName}  |  ¥${d.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
