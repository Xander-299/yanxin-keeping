part of '../toon.dart';

/// 浮动按钮（**Ant Design `FloatButton` 的 Flutter 版**）。
///
/// 为什么不用 M3 的 `FloatingActionButton`：它只能贴 Scaffold 的四个角（`FloatingActionButtonLocation`），
/// 挂不了「固定在屏幕高度 15% 处」这种自由坐标；这里做成**纯 widget**，由调用方用 `Positioned`
/// 定位（不可拖动），形状固定圆形，展开方式固定 `trigger: click`（点按切换，不跟手、不悬停）。
///
/// 结构（`Column` 线性排布）：
/// ```
/// [主钮 ⌾+]           ← 位置固定，展开时只把「+」转 45°，自身不位移
/// [标签 + 子钮 ⌾F]     ← 点主钮后向下展开
/// [标签 + 子钮 ⌾S]
/// ```

/// 浮动按钮组的子项。
class ToonFloatAction {
  const ToonFloatAction({
    required this.letter,
    required this.label,
    required this.onTap,
  });

  /// 圆形子钮里的字母：一级分类 `F`（First）、二级 `S`（Second），依次类推。
  final String letter;

  /// 子钮左侧的说明文字（同时也是无障碍 / 测试用的可见标签）。
  final String label;

  final VoidCallback onTap;
}

/// 点按展开的浮动按钮组。
class ToonFloatMenu extends StatefulWidget {
  const ToonFloatMenu({
    super.key,
    required this.actions,
    this.icon = Icons.add_rounded,
    this.tooltip = '添加分类',
    this.size = 56,
    this.expandUp = false,
  });

  /// 展开后的子项（展开方向由 [expandUp] 决定，顺序始终是「一级在前」）。
  final List<ToonFloatAction> actions;

  /// 主钮图标（任务书：加号）。
  final IconData icon;

  final String tooltip;

  /// 主钮直径（子钮固定 42）。
  final double size;

  /// 是否向上展开。按钮贴屏幕底部时必须为 `true` —— 向下展开会掉到屏幕外，
  /// 而且主钮会随菜单一起位移（实测过），向上展开时主钮钉在 `Column` 末尾、位置不变。
  final bool expandUp;

  @override
  State<ToonFloatMenu> createState() => _ToonFloatMenuState();
}

class _ToonFloatMenuState extends State<ToonFloatMenu> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  void _pick(ToonFloatAction action) {
    // 先收起再执行：避免回调里弹出的新弹层与展开菜单同屏。
    setState(() => _open = false);
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Widget main = Material(
      color: p.brand,
      elevation: 6,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _toggle,
        child: Tooltip(
          message: widget.tooltip,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedRotation(
              turns: _open ? 0.125 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(widget.icon, size: 26, color: p.onBrand),
            ),
          ),
        ),
      ),
    );

    final Widget menu = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: widget.expandUp
          ? Alignment.bottomRight
          : Alignment.topRight,
      child: _open
          ? Padding(
              padding: EdgeInsets.only(
                top: widget.expandUp ? 0 : 10,
                bottom: widget.expandUp ? 10 : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final ToonFloatAction action in widget.actions)
                    _FloatChild(action: action, onTap: () => _pick(action)),
                ],
              ),
            )
          : const SizedBox(width: 0, height: 0),
    );

    // 这一层挂在 Scaffold 外面（用整屏坐标定位），没有 Material 祖先 → 自己铺一层透明
    // Material，否则 InkWell 会抛「No Material widget found」。
    //
    // 向上展开时主钮放在 `Column` **末尾**：菜单长高只往上顶，主钮不会被推下去。
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: widget.expandUp
            ? <Widget>[menu, main]
            : <Widget>[main, menu],
      ),
    );
  }
}

/// 展开后的一个子钮：左侧说明文字 + 右侧圆钮（字母）。
class _FloatChild extends StatelessWidget {
  const _FloatChild({required this.action, required this.onTap});

  final ToonFloatAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // 整行（说明文字 + 圆钮）都可点：手指落在文字上也能进，别只让 42dp 的圆钮响应。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: p.paper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.line),
              ),
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: p.canvas,
              elevation: 2,
              shape: CircleBorder(side: BorderSide(color: p.line)),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: Text(
                    action.letter,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
