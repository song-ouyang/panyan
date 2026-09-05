import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/wanpan_theme.dart';
import '../motion/wanpan_motion.dart';

class WanpanGradePicker extends StatefulWidget {
  const WanpanGradePicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  State<WanpanGradePicker> createState() => _WanpanGradePickerState();
}

class _WanpanGradePickerState extends State<WanpanGradePicker> {
  bool _open = false;

  Future<void> _chooseGrade() async {
    if (_open || widget.onChanged == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _open = true);
    final grade = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: WanpanMotion.reduceMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => _GradePickerSheet(value: widget.value),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (grade != null) widget.onChanged?.call(grade);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '难度',
      value: widget.value,
      child: InkWell(
        onTap: enabled ? _chooseGrade : null,
        borderRadius: BorderRadius.circular(WanpanRadii.medium),
        child: InputDecorator(
          isFocused: _open,
          decoration: InputDecoration(labelText: '难度', enabled: enabled),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: enabled ? WanpanColors.ink : WanpanColors.muted,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: WanpanColors.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradePickerSheet extends StatefulWidget {
  const _GradePickerSheet({required this.value});

  final String value;

  @override
  State<_GradePickerSheet> createState() => _GradePickerSheetState();
}

class _GradePickerSheetState extends State<_GradePickerSheet> {
  final _selectedKey = GlobalKey();
  final _advancedStartKey = GlobalKey();
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = (int.tryParse(widget.value.replaceFirst('V', '')) ?? 0) > 10;
    if (_expanded) _reveal(_selectedKey);
  }

  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final optionContext = key.currentContext;
      if (optionContext != null) {
        Scrollable.ensureVisible(optionContext, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, constraints.maxHeight * .85 - keyboardInset),
          ),
          child: SingleChildScrollView(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选择难度',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: '关闭难度选择',
                          icon: const Icon(Icons.close_rounded),
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 12.0;
                        final minimumWidth = math.max(
                          60.0,
                          MediaQuery.textScalerOf(context).scale(16) * 3 + 24,
                        );
                        final columns =
                            ((constraints.maxWidth + gap) /
                                    (minimumWidth + gap))
                                .floor()
                                .clamp(2, 4);
                        final width =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (
                              var index = 0;
                              index <= (_expanded ? 17 : 10);
                              index++
                            )
                              SizedBox(
                                width: width,
                                child: _gradeOption(index),
                              ),
                          ],
                        );
                      },
                    ),
                    if (!_expanded) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        key: const Key('wanpan-grade-more'),
                        onPressed: () {
                          setState(() => _expanded = true);
                          _reveal(_advancedStartKey);
                        },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 48),
                        ),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('更多'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _gradeOption(int index) {
    final grade = 'V$index';
    final selected = grade == widget.value;
    Widget option = Semantics(
      selected: selected,
      child: OutlinedButton(
        key: Key('wanpan-grade-$grade'),
        onPressed: () => Navigator.of(context).pop(grade),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          backgroundColor: selected
              ? WanpanColors.coralSoft
              : WanpanColors.surface,
          foregroundColor: selected
              ? WanpanColors.coralStrong
              : WanpanColors.ink,
          side: BorderSide(
            color: selected ? WanpanColors.coral : WanpanColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WanpanRadii.medium),
          ),
        ),
        child: Text(grade),
      ),
    );
    if (selected) option = KeyedSubtree(key: _selectedKey, child: option);
    if (index == 11) {
      option = KeyedSubtree(key: _advancedStartKey, child: option);
    }
    return option;
  }
}
