part of '../import_page.dart';

// ────────────────────────────── 步骤条 ──────────────────────────────

/// 三步进度条：已完成打勾、当前步填品牌色 + 硬阴影，步与步之间是虚线。
class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});

  final int step;

  static const List<String> _labels = <String>['选择文件', '预览确认', '导入报告'];

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _labels.length; i++) ...<Widget>[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ToonDashedLine(color: p.dash, dash: 5, gap: 4),
                ),
              ),
            _StepNode(
              n: i + 1,
              label: _labels[i],
              state: step == i + 1
                  ? _StepState.on
                  : (step > i + 1 ? _StepState.done : _StepState.off),
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { on, done, off }

class _StepNode extends StatelessWidget {
  const _StepNode({required this.n, required this.label, required this.state});

  final int n;
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final bool done = state == _StepState.done;
    final bool on = state == _StepState.on;
    return Row(
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done
                ? p.greenTint
                : (on ? p.brand : p.paper),
            shape: BoxShape.circle,
            border: p.inkBorder(
              w: 2,
              on: done ? p.greenTint : (on ? p.brand : p.paper),
            ),
            boxShadow: on ? p.hard(d: 2) : null,
          ),
          child: done
              ? Icon(Icons.check, size: 14, color: p.green)
              : Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: on ? p.onBrand : p.ink2,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w900 : FontWeight.w700,
            color: on ? p.ink : p.ink3,
          ),
        ),
      ],
    );
  }
}
