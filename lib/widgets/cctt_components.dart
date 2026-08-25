import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/order.dart';
import '../models/stock_movement.dart';
import '../theme/app_theme.dart';

/// 主操作按钮。全 App 只有「唯一的下一步」才用它，
/// 橙红渐变 + 微光晕是整个设计里唯一花哨的地方，用得越少越有效。
class CCTTPrimaryButton extends StatelessWidget {
  const CCTTPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;

    return Container(
      width: expand ? double.infinity : null,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
        gradient: enabled
            ? const LinearGradient(
                colors: [CCTTTheme.accentOrange, CCTTTheme.accentOrangeLight],
              )
            : null,
        color: enabled ? null : CCTTTheme.neutral300,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: CCTTTheme.accentOrange.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 20,
                          color: enabled
                              ? Colors.white
                              : CCTTTheme.neutral500,
                        ),
                        const SizedBox(width: CCTTTheme.space2),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: enabled ? Colors.white : CCTTTheme.neutral500,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 同步状态点。只在「同步中」时呼吸，其余状态保持静止 ——
/// 常亮动画会让列表一直在动，反而让人焦虑。
class SyncStatusDot extends StatefulWidget {
  const SyncStatusDot({super.key, required this.status, this.size = 8});

  final SyncStatus status;
  final double size;

  @override
  State<SyncStatusDot> createState() => _SyncStatusDotState();
}

class _SyncStatusDotState extends State<SyncStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(SyncStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.status == SyncStatus.syncing) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = CCTTTheme.syncColor(widget.status);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = widget.status == SyncStatus.syncing
            ? 0.3 + (_controller.value * 0.7)
            : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
            boxShadow: widget.status == SyncStatus.syncing
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: opacity * 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

/// 小号状态标签
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CCTTTheme.radiusSmall),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: filled ? Colors.white : color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单据卡片 —— 整个设计的签名组件。
///
/// 形态取自仓库里贴在货堆上的货物标签：顶部一条 4dp 的类型色带做「色标」，
/// 下面是品名，右下角是最重要的那个数字（金额）。
/// 信息按「扫一眼要看到什么」排序：品名 → 金额 → 客户 → 仓库/时间。
/// 原来的版本把 6 个事实塞进一个 ListTile，每条都在抢注意力；
/// 这里让金额独占一个视觉层级，其余降为辅助信息。
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.detail,
    required this.warehouseName,
    this.onTap,
  });

  final OrderDetail detail;
  final String warehouseName;
  final VoidCallback? onTap;

  static final _amountFormat = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    final o = detail.order;
    final isVoid = o.isDeleted;
    final typeColor =
        isVoid ? CCTTTheme.neutral500 : CCTTTheme.typeColor(o.type);

    final goodsTitle = detail.items.isNotEmpty
        ? detail.items.map((i) => i.itemName).toSet().join('、')
        : o.partnerName;

    final dt = DateTime.fromMillisecondsSinceEpoch(o.timestamp);
    String pf(int n) => n.toString().padLeft(2, '0');
    final ts = '${dt.year}-${pf(dt.month)}-${pf(dt.day)} '
        '${pf(dt.hour)}:${pf(dt.minute)}';

    return Container(
      margin: const EdgeInsets.only(bottom: CCTTTheme.space3),
      decoration: BoxDecoration(
        color: isVoid ? CCTTTheme.neutral50 : Colors.white,
        borderRadius: BorderRadius.circular(CCTTTheme.radiusLarge),
        border: Border.all(color: CCTTTheme.neutral300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 类型色带：不看文字也能扫出这是入库还是出库
              Container(height: 4, color: typeColor),
              Padding(
                padding: const EdgeInsets.all(CCTTTheme.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                          label: CCTTTheme.typeLabel(o.type),
                          color: typeColor,
                          icon: CCTTTheme.typeIcon(o.type),
                        ),
                        if (isVoid) ...[
                          const SizedBox(width: CCTTTheme.space2),
                          const StatusChip(
                            label: '已作废',
                            color: CCTTTheme.statusFailed,
                          ),
                        ],
                        if (o.isSettled && !isVoid) ...[
                          const SizedBox(width: CCTTTheme.space2),
                          const StatusChip(
                            label: '已结清',
                            color: CCTTTheme.statusSynced,
                            icon: Icons.lock_outline,
                          ),
                        ],
                        const Spacer(),
                        SyncStatusDot(status: o.syncStatus),
                        const SizedBox(width: 6),
                        Text(
                          CCTTTheme.syncLabel(o.syncStatus),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isVoid
                                ? CCTTTheme.neutral500
                                : CCTTTheme.syncColor(o.syncStatus),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CCTTTheme.space3),

                    // 品名：卡片主标题
                    Text(
                      goodsTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -0.2,
                        color: isVoid
                            ? CCTTTheme.neutral500
                            : CCTTTheme.neutral900,
                        decoration: isVoid ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: CCTTTheme.space1),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              o.partnerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: CCTTTheme.neutral700,
                              ),
                            ),
                          ),
                        ),
                        // 金额：全 App 唯一用强调色的数据
                        Text(
                          '¥${_amountFormat.format(detail.totalAmount)}',
                          style: CCTTTheme.numeric(
                            size: 22,
                            color: isVoid
                                ? CCTTTheme.neutral500
                                : CCTTTheme.accentOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CCTTTheme.space3),
                    const Divider(height: 1, color: CCTTTheme.neutral300),
                    const SizedBox(height: CCTTTheme.space2),
                    Row(
                      children: [
                        const Icon(
                          Icons.warehouse_outlined,
                          size: 13,
                          color: CCTTTheme.neutral500,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            warehouseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: CCTTTheme.neutral700,
                            ),
                          ),
                        ),
                        const SizedBox(width: CCTTTheme.space2),
                        Text(
                          ts,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: CCTTTheme.monoFont,
                            color: CCTTTheme.neutral500,
                          ),
                        ),
                        const Spacer(),
                        if (detail.items.length > 1)
                          Text(
                            '${detail.items.length} 项',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: CCTTTheme.neutral700,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// OCR 入口卡片。
///
/// 拍照识别是这个 App 最省力的录入方式，但原来它是页面中部一张普通的 Card，
/// 排在手动填写的表单之后 —— 结构上等于在说「手动填写才是正途」。
/// 这里把它提到页面第一屏、给足深色底和尺寸，让默认路径变成拍照。
class OCRHeroCard extends StatelessWidget {
  const OCRHeroCard({
    super.key,
    this.onTakePhoto,
    this.onPickGallery,
    this.isProcessing = false,
    this.recognizedCount,
  });

  final VoidCallback? onTakePhoto;
  final VoidCallback? onPickGallery;
  final bool isProcessing;
  final int? recognizedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CCTTTheme.space6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CCTTTheme.radiusXLarge),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CCTTTheme.primaryDark, CCTTTheme.primaryMid],
        ),
      ),
      child: Column(
        children: [
          if (isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: CCTTTheme.space2),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: CCTTTheme.accentOrange,
                ),
              ),
            )
          else
            const Icon(
              Icons.document_scanner_outlined,
              size: 56,
              color: CCTTTheme.accentOrange,
            ),
          const SizedBox(height: CCTTTheme.space3),
          Text(
            isProcessing ? '正在识别单据…' : '拍单据，自动填表',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: CCTTTheme.space1),
          Text(
            isProcessing ? '识别完成后可以逐项核对修改' : '手写单、出库单都能认，识别完可以改',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (recognizedCount != null) ...[
            const SizedBox(height: CCTTTheme.space3),
            StatusChip(
              label: '已识别 $recognizedCount 项',
              color: CCTTTheme.statusSynced,
              icon: Icons.check,
              filled: true,
            ),
          ],
          const SizedBox(height: CCTTTheme.space4),
          Row(
            children: [
              Expanded(
                child: _GhostButton(
                  icon: Icons.photo_camera_outlined,
                  label: '拍照',
                  onPressed: isProcessing ? null : onTakePhoto,
                ),
              ),
              const SizedBox(width: CCTTTheme.space3),
              Expanded(
                child: _GhostButton(
                  icon: Icons.photo_library_outlined,
                  label: '从相册选',
                  onPressed: isProcessing ? null : onPickGallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 深色底上的次级按钮
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = Colors.white.withValues(alpha: enabled ? 1 : 0.4);

    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CCTTTheme.radiusMedium),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: CCTTTheme.space2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态。文案从用户这一侧写：说「还没有单据」而不是「暂无数据」。
class CCTTEmptyState extends StatelessWidget {
  const CCTTEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CCTTTheme.space8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: CCTTTheme.neutral100,
              ),
              child: Icon(icon, size: 40, color: CCTTTheme.neutral500),
            ),
            const SizedBox(height: CCTTTheme.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: CCTTTheme.neutral900,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: CCTTTheme.space2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: CCTTTheme.neutral700,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: CCTTTheme.space6),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 区块小标题：全大写字距拉开的短标签，配一条细线，
/// 让长表单在滚动时有清晰的分段感。
class CCTTSectionLabel extends StatelessWidget {
  const CCTTSectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: CCTTTheme.space6,
        bottom: CCTTTheme.space3,
      ),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: CCTTTheme.accentOrange),
          const SizedBox(width: CCTTTheme.space2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: CCTTTheme.neutral700,
            ),
          ),
          const SizedBox(width: CCTTTheme.space3),
          const Expanded(child: Divider(height: 1)),
          if (trailing != null) ...[
            const SizedBox(width: CCTTTheme.space3),
            trailing!,
          ],
        ],
      ),
    );
  }
}
