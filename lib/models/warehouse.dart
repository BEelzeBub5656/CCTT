import 'package:uuid/uuid.dart';

/// 仓库模型
///
/// 对应 SQLite 表 `warehouses`。
class Warehouse {
  /// 全局唯一标识符（UUID v4）
  final String id;

  /// 仓库名称
  final String name;

  Warehouse({
    String? id,
    required this.name,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  Warehouse copyWith({
    String? id,
    String? name,
  }) =>
      Warehouse(
        id: id ?? this.id,
        name: name ?? this.name,
      );
}
