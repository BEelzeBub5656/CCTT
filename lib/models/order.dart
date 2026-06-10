import 'package:uuid/uuid.dart';
import 'stock_movement.dart';

// ───── 主单据 ─────

class Order {
  final String id;
  final String partnerName;
  final String warehouseId;
  final MovementType type;
  final int timestamp;
  final SyncStatus syncStatus;
  final bool isDeleted;
  final bool isSettled;
  final String? remark;
  final String? voidReason;

  Order({
    String? id,
    required this.partnerName,
    required this.warehouseId,
    required this.type,
    required this.timestamp,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
    this.isSettled = false,
    this.remark,
    this.voidReason,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'partnerName': partnerName,
        'warehouseId': warehouseId,
        'type': type.name,
        'timestamp': timestamp,
        'syncStatus': syncStatus.name,
        'isDeleted': isDeleted ? 1 : 0,
        'isSettled': isSettled ? 1 : 0,
        'remark': remark,
        'voidReason': voidReason,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String? ?? '',
        partnerName: (json['partnerName'] as String?) ?? '',
        warehouseId: (json['warehouseId'] as String?) ?? '',
        type: _parseType(json['type']),
        timestamp: (json['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        syncStatus: _parseSync(json['syncStatus']),
        isDeleted: (json['isDeleted'] as int?) == 1,
        isSettled: (json['isSettled'] as int?) == 1,
        remark: json['remark'] as String?,
        voidReason: json['voidReason'] as String?,
      );

  Order copyWith({
    String? id,
    String? partnerName,
    String? warehouseId,
    MovementType? type,
    int? timestamp,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isSettled,
    String? remark,
    String? voidReason,
  }) =>
      Order(
        id: id ?? this.id,
        partnerName: partnerName ?? this.partnerName,
        warehouseId: warehouseId ?? this.warehouseId,
        type: type ?? this.type,
        timestamp: timestamp ?? this.timestamp,
        syncStatus: syncStatus ?? this.syncStatus,
        isDeleted: isDeleted ?? this.isDeleted,
        isSettled: isSettled ?? this.isSettled,
        remark: remark ?? this.remark,
        voidReason: voidReason ?? this.voidReason,
      );

  static MovementType _parseType(dynamic v) {
    try { return MovementType.values.byName(v as String); } catch (_) { return MovementType.outbound; }
  }
  static SyncStatus _parseSync(dynamic v) {
    try { return SyncStatus.values.byName(v as String); } catch (_) { return SyncStatus.pending; }
  }
}

// ───── 明细 ─────

class OrderItem {
  final String id;
  final String orderId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double grossWeight;
  final double tareWeight;
  final int? totalPieces;
  final String? deliveryPerson;
  final String? imagePath;
  final int sortOrder;

  OrderItem({
    String? id,
    required this.orderId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.grossWeight = 0.0,
    this.tareWeight = 0.0,
    this.totalPieces,
    this.deliveryPerson,
    this.imagePath,
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  double get amount => (quantity / 1000) * unitPrice;
  double get calculatedNetWeight => grossWeight - tareWeight;

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'itemName': itemName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'grossWeight': grossWeight,
        'tareWeight': tareWeight,
        'totalPieces': totalPieces,
        'deliveryPerson': deliveryPerson,
        'imagePath': imagePath,
        'sortOrder': sortOrder,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as String? ?? '',
        orderId: (json['orderId'] as String?) ?? '',
        itemName: (json['itemName'] as String?) ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
        grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0.0,
        tareWeight: (json['tareWeight'] as num?)?.toDouble() ?? 0.0,
        totalPieces: json['totalPieces'] as int?,
        deliveryPerson: json['deliveryPerson'] as String?,
        imagePath: json['imagePath'] as String?,
        sortOrder: (json['sortOrder'] as int?) ?? 0,
      );

  OrderItem copyWith({
    String? id, String? orderId, String? itemName, double? quantity,
    double? unitPrice, double? grossWeight, double? tareWeight,
    int? totalPieces, String? deliveryPerson, String? imagePath, int? sortOrder,
  }) =>
      OrderItem(
        id: id ?? this.id, orderId: orderId ?? this.orderId,
        itemName: itemName ?? this.itemName, quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice, grossWeight: grossWeight ?? this.grossWeight,
        tareWeight: tareWeight ?? this.tareWeight, totalPieces: totalPieces ?? this.totalPieces,
        deliveryPerson: deliveryPerson ?? this.deliveryPerson,
        imagePath: imagePath ?? this.imagePath, sortOrder: sortOrder ?? this.sortOrder,
      );
}

// ───── 额外费用 ─────

class OrderFee {
  final String id;
  final String orderId;
  final String feeName;
  final double amount;
  final String? remark;
  final int sortOrder;

  OrderFee({
    String? id,
    required this.orderId,
    required this.feeName,
    required this.amount,
    this.remark,
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'feeName': feeName,
        'amount': amount,
        'remark': remark,
        'sortOrder': sortOrder,
      };

  factory OrderFee.fromJson(Map<String, dynamic> json) => OrderFee(
        id: json['id'] as String? ?? '',
        orderId: (json['orderId'] as String?) ?? '',
        feeName: (json['feeName'] as String?) ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        remark: json['remark'] as String?,
        sortOrder: (json['sortOrder'] as int?) ?? 0,
      );

  OrderFee copyWith({
    String? id, String? orderId, String? feeName, double? amount,
    String? remark, int? sortOrder,
  }) =>
      OrderFee(
        id: id ?? this.id, orderId: orderId ?? this.orderId,
        feeName: feeName ?? this.feeName, amount: amount ?? this.amount,
        remark: remark ?? this.remark, sortOrder: sortOrder ?? this.sortOrder,
      );
}

// ───── 视图：Order + Items + Fees 组合 ─────

class OrderDetail {
  final Order order;
  final List<OrderItem> items;
  final List<OrderFee> fees;

  OrderDetail({required this.order, required this.items, required this.fees});

  double get totalItemAmount => items.fold(0.0, (s, i) => s + i.amount);
  double get totalFeeAmount => fees.fold(0.0, (s, f) => s + f.amount);
  double get totalAmount => totalItemAmount + totalFeeAmount;
}
