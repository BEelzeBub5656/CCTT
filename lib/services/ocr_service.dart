import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'settings_service.dart';

/// OCR 识别结果中的单条货物明细
class OcrItem {
  final String itemName;
  final double quantity; // 普通单据为净重；formal 原始响应中可能是单件毛重
  final double unitPrice; // 元/吨
  final double grossWeight;
  final double tareWeight;
  final int? totalPieces;
  final String? deliveryPerson;
  final String? pieceNumber;
  final String? itemRemark;

  const OcrItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.grossWeight = 0,
    this.tareWeight = 0,
    this.totalPieces,
    this.deliveryPerson,
    this.pieceNumber,
    this.itemRemark,
  });

  factory OcrItem.fromJson(Map<String, dynamic> json) => OcrItem(
        itemName: (json['itemName'] as String?) ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
        grossWeight: (json['grossWeight'] as num?)?.toDouble() ?? 0,
        tareWeight: (json['tareWeight'] as num?)?.toDouble() ?? 0,
        totalPieces: (json['totalPieces'] as num?)?.toInt(),
        deliveryPerson: json['deliveryPerson'] as String?,
        pieceNumber: json['pieceNumber'] as String?,
        itemRemark:
            (json['itemRemark'] as String?) ?? (json['remark'] as String?),
      );

  OcrItem copyWith({
    String? itemName,
    double? quantity,
    double? unitPrice,
    double? grossWeight,
    double? tareWeight,
    int? totalPieces,
    String? deliveryPerson,
    String? pieceNumber,
    String? itemRemark,
  }) =>
      OcrItem(
        itemName: itemName ?? this.itemName,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        grossWeight: grossWeight ?? this.grossWeight,
        tareWeight: tareWeight ?? this.tareWeight,
        totalPieces: totalPieces ?? this.totalPieces,
        deliveryPerson: deliveryPerson ?? this.deliveryPerson,
        pieceNumber: pieceNumber ?? this.pieceNumber,
        itemRemark: itemRemark ?? this.itemRemark,
      );
}

/// OCR 识别结果中的额外费用
class OcrFee {
  final String feeName;
  final double amount;

  const OcrFee({required this.feeName, required this.amount});

  factory OcrFee.fromJson(Map<String, dynamic> json) => OcrFee(
        feeName: (json['feeName'] as String?) ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// OCR 识别的一张单据
class OcrOrder {
  final String partnerName;
  final String type; // inbound / outbound / supply
  final String? dateHint;
  final List<OcrItem> items;
  final List<OcrFee> fees;
  final double totalHint;
  final double totalAmount;
  final int? totalPieces;
  final double grossWeight;
  final double tareWeight;
  final double quantity;
  final double unitPrice;
  final String? remark;
  final List<String> warnings;

  const OcrOrder({
    required this.partnerName,
    required this.type,
    this.dateHint,
    this.items = const [],
    this.fees = const [],
    this.totalHint = 0,
    this.totalAmount = 0,
    this.totalPieces,
    this.grossWeight = 0,
    this.tareWeight = 0,
    this.quantity = 0,
    this.unitPrice = 0,
    this.remark,
    this.warnings = const [],
  });

  factory OcrOrder.fromJson(Map<String, dynamic> json) => OcrOrder(
        partnerName: (json['partnerName'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'inbound',
        dateHint: json['date_hint'] as String?,
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => OcrItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        fees: (json['fees'] as List<dynamic>?)
                ?.map((e) => OcrFee.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalHint: _asDouble(json['total_hint']),
        totalAmount: _asDouble(json['totalAmount']),
        totalPieces: _asInt(json['totalPieces']),
        grossWeight: _asDouble(json['grossWeight']),
        tareWeight: _asDouble(json['tareWeight']),
        quantity: _asDouble(json['quantity']),
        unitPrice: _asDouble(json['unitPrice']),
        remark: json['remark'] as String?,
        warnings: _asWarnings(json['warning'] ?? json['warnings']),
      );

  /// 将服务器 formal 模板返回的“逐件毛重”转换成 App 使用的逐件净重。
  ///
  /// 扣皮平均分配到每一件，最后一件吸收浮点余差，确保逐件合计与
  /// 单据级毛重、扣皮、净重完全一致。普通手写单保持原数据不变。
  List<OcrItem> normalizedItems({required bool isFormal}) {
    if (items.isEmpty) return const [];

    final pricedItems = items
        .map((item) => item.copyWith(
              unitPrice: unitPrice > 0 ? unitPrice : item.unitPrice,
            ))
        .toList();
    if (!isFormal ||
        pricedItems
            .any((item) => item.grossWeight > 0 || item.tareWeight > 0)) {
      return pricedItems;
    }

    final itemWeightSum =
        pricedItems.fold<double>(0, (sum, item) => sum + item.quantity);
    if (grossWeight <= 0 || !_roughlyEqual(itemWeightSum, grossWeight)) {
      return pricedItems;
    }

    final summaryTare = tareWeight > 0
        ? tareWeight
        : grossWeight > quantity
            ? grossWeight - quantity
            : 0.0;
    if (summaryTare < 0 || summaryTare >= itemWeightSum) {
      return pricedItems;
    }

    final averageTare = summaryTare / pricedItems.length;
    var allocatedTare = 0.0;
    return pricedItems.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final pieceTare = index == pricedItems.length - 1
          ? summaryTare - allocatedTare
          : averageTare;
      allocatedTare += pieceTare;
      final netWeight = item.quantity - pieceTare;
      return item.copyWith(
        quantity: netWeight > 0 ? netWeight : 0,
        grossWeight: item.quantity,
        tareWeight: pieceTare,
        totalPieces: item.totalPieces ?? 1,
      );
    }).toList();
  }

  /// 兼容 `2026-08-26`、`2026年8月26日` 和 `8.26`。
  DateTime? parsedDate({DateTime? referenceDate}) {
    final value = dateHint?.trim();
    if (value == null || value.isEmpty) return null;

    final full = RegExp(r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})').firstMatch(value);
    if (full != null) {
      return _validDate(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
    }

    final short = RegExp(r'^(\d{1,2})\D+(\d{1,2})$').firstMatch(value);
    if (short != null) {
      return _validDate(
        (referenceDate ?? DateTime.now()).year,
        int.parse(short.group(1)!),
        int.parse(short.group(2)!),
      );
    }
    return null;
  }
}

/// OCR API 完整响应
class OcrResponse {
  final bool success;
  final List<OcrOrder> orders;
  final List<Map<String, dynamic>>? rawTexts;
  final String? documentType;
  final String? error;
  final List<String> warnings;

  const OcrResponse({
    required this.success,
    this.orders = const [],
    this.rawTexts,
    this.documentType,
    this.error,
    this.warnings = const [],
  });

  factory OcrResponse.fromJson(Map<String, dynamic> json) => OcrResponse(
        success: json['success'] == true,
        orders: (json['orders'] as List<dynamic>?)
                ?.map((e) => OcrOrder.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        rawTexts: (json['raw_texts'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList(),
        documentType: json['document_type'] as String?,
        error: json['error'] as String?,
        warnings: _asWarnings(json['warning'] ?? json['warnings']),
      );

  /// 获取第一张识别到的单据（常用于单张拍照场景）
  OcrOrder? get firstOrder => orders.isNotEmpty ? orders.first : null;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<String> _asWarnings(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  if (value is List) {
    return value
        .whereType<String>()
        .map((warning) => warning.trim())
        .where((warning) => warning.isNotEmpty)
        .toList();
  }
  return const [];
}

bool _roughlyEqual(double a, double b) {
  final tolerance = b.abs() * 0.02 > 1 ? b.abs() * 0.02 : 1.0;
  return (a - b).abs() <= tolerance;
}

DateTime? _validDate(int year, int month, int day) {
  if (year < 2000 || year > 2100) return null;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

/// 云端 OCR 识别服务（PP-OCRv6）
///
/// 拍照 → POST multipart 上传 → 解析结构化数据
class OcrService {
  OcrService._();

  /// 上传图片并返回 OCR 识别结果。
  ///
  /// 读取 [SettingsService.getOcrServerUrl] 作为 API 地址，
  /// 以 multipart/form-data 方式 POST 到 `/api/ocr`。
  /// 30 秒超时，失败时抛出 [OcrException]。
  static Future<OcrResponse> recognize(File image) async {
    final baseUrl = await SettingsService.getOcrServerUrl();
    if (baseUrl.isEmpty) {
      throw OcrException('OCR 服务器地址未配置');
    }

    final url = Uri.parse('$baseUrl/api/ocr');
    final request = http.MultipartRequest('POST', url)
      ..files.add(await http.MultipartFile.fromPath('image', image.path));

    http.StreamedResponse response;
    try {
      response = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw OcrException('OCR 服务响应超时，请稍后重试'),
          );
    } on OcrException {
      rethrow;
    } on SocketException {
      throw OcrException('网络连接失败，请检查网络设置');
    } on HandshakeException {
      throw OcrException('网络连接失败，请检查网络设置');
    } on TlsException {
      throw OcrException('网络连接失败，请检查网络设置');
    }

    if (response.statusCode != 200) {
      throw OcrException('服务器错误 (${response.statusCode})，请稍后重试');
    }

    final body = await response.stream.transform(utf8.decoder).join();
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return OcrResponse.fromJson(json);
    } on FormatException {
      throw OcrException('OCR 返回数据异常');
    }
  }
}

/// OCR 异常
class OcrException implements Exception {
  final String message;
  const OcrException(this.message);

  @override
  String toString() => 'OcrException: $message';
}
