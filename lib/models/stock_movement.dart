import 'package:uuid/uuid.dart';

/// 同步状态枚举
enum SyncStatus { pending, synced }

/// 库存移动类型枚举
/// - [inbound]: 入库（增加库存）
/// - [outbound]: 出库（减少库存）
enum MovementType { inbound, outbound }

/// 库存移动记录模型（原 TransactionRecord 的升级版）
///
/// 对应 SQLite 表 `stock_movements`。
class StockMovement {
  /// 全局唯一标识符（UUID v4）
  final String id;

  /// 操作发生的时间戳（Unix 毫秒）
  final int timestamp;

  /// 交易对象名称（如供应商、客户）
  final String partnerName;

  /// 所属仓库 ID（外键，关联 warehouses 表）
  final String warehouseId;

  /// 移动类型：入库或出库
  final MovementType type;

  /// 数量
  final double quantity;

  /// 单价（人民币，单位：元）
  final double unitPrice;

  /// 同步状态
  final SyncStatus syncStatus;

  StockMovement({
    String? id,
    required this.timestamp,
    required this.partnerName,
    required this.warehouseId,
    required this.type,
    required this.quantity,
    required this.unitPrice,
    this.syncStatus = SyncStatus.pending,
  }) : id = id ?? const Uuid().v4();

  /// 计算总金额（数量 × 单价）
  double get totalAmount => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'partnerName': partnerName,
        'warehouseId': warehouseId,
        'type': type.name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'syncStatus': syncStatus.name,
      };

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        timestamp: json['timestamp'] as int,
        partnerName: json['partnerName'] as String,
        warehouseId: json['warehouseId'] as String,
        type: MovementType.values.byName(json['type'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        syncStatus: SyncStatus.values.byName(json['syncStatus'] as String),
      );

  StockMovement copyWith({
    String? id,
    int? timestamp,
    String? partnerName,
    String? warehouseId,
    MovementType? type,
    double? quantity,
    double? unitPrice,
    SyncStatus? syncStatus,
  }) =>
      StockMovement(
        id: id ?? this.id,
        timestamp: timestamp ?? this.timestamp,
        partnerName: partnerName ?? this.partnerName,
        warehouseId: warehouseId ?? this.warehouseId,
        type: type ?? this.type,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
