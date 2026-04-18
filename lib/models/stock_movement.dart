import 'package:uuid/uuid.dart';

/// 同步状态枚举
enum SyncStatus { pending, synced }

/// 库存移动类型枚举
/// - [inbound]: 入库（增加库存）
/// - [outbound]: 出库（减少库存）
enum MovementType { inbound, outbound }

/// 库存移动记录模型（毛纺厂专用版）
///
/// 对应 SQLite 表 `stock_movements`（v4）。
///
/// 计重逻辑：
/// - [grossWeight] = 毛重（地磅读数）
/// - [tareWeight]  = 扣皮（去皮、容器重量）
/// - [quantity]    = 净重（kg），理论上等于 grossWeight - tareWeight
/// - [unitPrice]   = 单价（元/吨）
/// - [totalAmount] = (quantity / 1000) * unitPrice
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

  /// 净重（单位：kg）
  /// 由 毛重 - 扣皮 计算得出，也可直接录入
  final double quantity;

  /// 单价（人民币，单位：元/吨）
  final double unitPrice;

  /// 同步状态
  final SyncStatus syncStatus;

  // ───── 毛纺厂核心字段（v4） ─────

  /// 颜色
  final String color;

  /// 品种
  final String variety;

  /// 毛重（地磅读数，单位：kg）
  final double grossWeight;

  /// 扣皮（去皮重量，单位：kg）
  final double tareWeight;

  // ───── 其他辅助字段 ─────

  /// 总计件数
  final int? totalPieces;

  /// 送货人
  final String? deliveryPerson;

  StockMovement({
    String? id,
    required this.timestamp,
    required this.partnerName,
    required this.warehouseId,
    required this.type,
    required this.quantity,
    required this.unitPrice,
    this.syncStatus = SyncStatus.pending,
    this.color = '',
    this.variety = '',
    this.grossWeight = 0.0,
    this.tareWeight = 0.0,
    this.totalPieces,
    this.deliveryPerson,
  }) : id = id ?? const Uuid().v4();

  /// 总金额（元）= (净重 kg / 1000) × 单价(元/吨)
  double get totalAmount => (quantity / 1000) * unitPrice;

  /// 根据毛重和扣皮计算出的净重
  /// 可用于校验 [quantity] 是否一致
  double get calculatedNetWeight => grossWeight - tareWeight;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'partnerName': partnerName,
        'warehouseId': warehouseId,
        'type': type.name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'syncStatus': syncStatus.name,
        'color': color,
        'variety': variety,
        'grossWeight': grossWeight,
        'tareWeight': tareWeight,
        'totalPieces': totalPieces,
        'deliveryPerson': deliveryPerson,
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
        color: (json['color'] as String?) ?? '',
        variety: (json['variety'] as String?) ?? '',
        grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0.0,
        tareWeight: (json['tareWeight'] as num?)?.toDouble() ?? 0.0,
        totalPieces: json['totalPieces'] as int?,
        deliveryPerson: json['deliveryPerson'] as String?,
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
    String? color,
    String? variety,
    double? grossWeight,
    double? tareWeight,
    int? totalPieces,
    String? deliveryPerson,
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
        color: color ?? this.color,
        variety: variety ?? this.variety,
        grossWeight: grossWeight ?? this.grossWeight,
        tareWeight: tareWeight ?? this.tareWeight,
        totalPieces: totalPieces ?? this.totalPieces,
        deliveryPerson: deliveryPerson ?? this.deliveryPerson,
      );
}
