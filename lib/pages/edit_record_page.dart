import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';

/// 独立编辑页面（专门用于长按修改）
///
/// - 只允许修改数值字段（重量、单价、件数、送货人）
/// - 入库/出库类型、颜色、品种、仓库、交易对象 设为只读
/// - 底部提供红色「作废此记录」按钮，执行软删除
class EditRecordPage extends StatefulWidget {
  final StockMovement record;

  const EditRecordPage({super.key, required this.record});

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _grossWeightController;
  late final TextEditingController _tareWeightController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _totalPiecesController;
  late final TextEditingController _deliveryPersonController;

  bool _isSaving = false;
  bool _isDeleting = false;

  Warehouse? _warehouse;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _grossWeightController =
        TextEditingController(text: r.grossWeight.toStringAsFixed(2));
    _tareWeightController =
        TextEditingController(text: r.tareWeight.toStringAsFixed(2));
    _unitPriceController =
        TextEditingController(text: r.unitPrice.toStringAsFixed(2));
    _totalPiecesController =
        TextEditingController(text: r.totalPieces?.toString() ?? '');
    _deliveryPersonController =
        TextEditingController(text: r.deliveryPerson ?? '');
    _loadWarehouse();
  }

  Future<void> _loadWarehouse() async {
    final wh = await DatabaseHelper.instance
        .getWarehouseById(widget.record.warehouseId);
    if (mounted) {
      setState(() => _warehouse = wh);
    }
  }

  @override
  void dispose() {
    _grossWeightController.dispose();
    _tareWeightController.dispose();
    _unitPriceController.dispose();
    _totalPiecesController.dispose();
    _deliveryPersonController.dispose();
    super.dispose();
  }

  /// 当前净重
  double get _currentNetWeight {
    final gross = double.tryParse(_grossWeightController.text.trim()) ?? 0;
    final tare = double.tryParse(_tareWeightController.text.trim()) ?? 0;
    return gross - tare;
  }

  /// 当前总金额
  double get _currentTotalAmount {
    final price = double.tryParse(_unitPriceController.text.trim()) ?? 0;
    return (_currentNetWeight / 1000) * price;
  }

  /// 保存修改
  Future<void> _saveChanges() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final grossWeight = double.parse(_grossWeightController.text.trim());
      final tareWeight =
          double.tryParse(_tareWeightController.text.trim()) ?? 0;
      final netWeight = grossWeight - tareWeight;

      if (netWeight <= 0) {
        _showSnackBar('净重必须大于 0，请检查毛重和扣皮');
        setState(() => _isSaving = false);
        return;
      }

      final priceValue = double.tryParse(_unitPriceController.text.trim());
      if (priceValue == null || priceValue < 0) {
        _showSnackBar('单价无效，请检查输入');
        setState(() => _isSaving = false);
        return;
      }

      final totalPieces = _totalPiecesController.text.trim().isEmpty
          ? null
          : int.tryParse(_totalPiecesController.text.trim());

      final updated = widget.record.copyWith(
        quantity: netWeight,
        grossWeight: grossWeight,
        tareWeight: tareWeight,
        unitPrice: priceValue,
        totalPieces: totalPieces,
        deliveryPerson: _deliveryPersonController.text.trim().isEmpty
            ? null
            : _deliveryPersonController.text.trim(),
        syncStatus: SyncStatus.pending,
      );

      await DatabaseHelper.instance.updateMovement(updated);

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('保存修改出错: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('保存失败：$e');
      }
    }
  }

  /// 软删除（作废）
  Future<void> _voidRecord() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认作废'),
        content: const Text('作废后该记录将标记为删除，并同步到 PC 端。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认作废'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      final voided = widget.record.copyWith(
        isDeleted: true,
        syncStatus: SyncStatus.pending,
      );
      await DatabaseHelper.instance.updateMovement(voided);

      if (mounted) {
        setState(() => _isDeleting = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('作废记录出错: $e');
      if (mounted) {
        setState(() => _isDeleting = false);
        _showSnackBar('作废失败：$e');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final isInbound = r.type == MovementType.inbound;

    return Scaffold(
      appBar: AppBar(
        title: const Text('修改记录'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ───── 只读信息卡片 ─────
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildReadOnlyRow('交易对象', r.partnerName),
                      const SizedBox(height: 12),
                      _buildReadOnlyRow('颜色', r.color.isEmpty ? '—' : r.color),
                      const SizedBox(height: 12),
                      _buildReadOnlyRow(
                          '品种', r.variety.isEmpty ? '—' : r.variety),
                      const SizedBox(height: 12),
                      _buildReadOnlyRow(
                          '仓库', _warehouse?.name ?? '未知仓库'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            '类型',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isInbound
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    isInbound ? Colors.green : Colors.red,
                              ),
                            ),
                            child: Text(
                              isInbound ? '入库' : '出库',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isInbound
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ───── 可编辑字段 ─────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextFormField(
                      controller: _grossWeightController,
                      decoration: const InputDecoration(
                        labelText: '毛重(kg)',
                        hintText: '地磅读数',
                        prefixIcon: Icon(Icons.fitness_center_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入毛重';
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return '请输入数字';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _tareWeightController,
                      decoration: const InputDecoration(
                        labelText: '扣皮(kg)',
                        hintText: '去皮',
                        prefixIcon: Icon(Icons.remove_circle_outline),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalPiecesController,
                      decoration: const InputDecoration(
                        labelText: '总件数',
                        hintText: '如：5',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unitPriceController,
                      decoration: const InputDecoration(
                        labelText: '单价 (元/吨)',
                        hintText: '如：4500',
                        prefixIcon: Icon(Icons.attach_money),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入单价';
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return '请输入数字';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _deliveryPersonController,
                decoration: const InputDecoration(
                  labelText: '送货人',
                  hintText: '如：张三',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),

              // ───── 净重展示 ─────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.scale,
                            color: Colors.blue.shade800, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '净重（毛重 - 扣皮）',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_currentNetWeight.toStringAsFixed(2)} kg',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ───── 总金额展示 ─────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '总金额',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.teal,
                      ),
                    ),
                    Text(
                      '¥${_currentTotalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ───── 保存按钮 ─────
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? '保存中…' : '保存修改'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // ───── 作废按钮 ─────
              OutlinedButton.icon(
                onPressed: _isDeleting ? null : _voidRecord,
                icon: _isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.delete_forever, color: Colors.red),
                label: Text(
                  _isDeleting ? '作废中…' : '作废此记录',
                  style: const TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
