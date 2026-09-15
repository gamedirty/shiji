import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../theme.dart';

/// 备份/恢复的共享 UI 流程：食材库的备份入口与加载失败页的灾难恢复入口共用。

/// 从剪贴板读取备份并恢复（先确认覆盖）。成功时 Store 会清除加载错误并置为已加载。
Future<void> restoreFromClipboard(BuildContext context, AppStore store) async {
  final ok = await confirmReplace(context);
  if (!ok || !context.mounted) return;
  final data = await Clipboard.getData('text/plain');
  final text = data?.text ?? '';
  if (!context.mounted) return;
  if (text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('剪贴板里没有内容'),
        duration: Duration(milliseconds: 1200),
      ),
    );
    return;
  }
  final success = await store.importJson(text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? '已从备份恢复' : (store.lastWriteError ?? '恢复失败')),
      duration: const Duration(milliseconds: 1500),
    ),
  );
}

/// 备份 / 恢复对话框：导出全部数据为 JSON 文本到剪贴板，或从剪贴板恢复
Future<void> showBackupSheet(BuildContext context, AppStore store) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('备份 / 恢复'),
      content: const Text(
        '导出会把全部数据（目标、食材、组合餐、饮食记录）复制为 JSON 文本；'
        '恢复会用剪贴板里的备份覆盖当前所有数据。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消', style: TextStyle(color: AppColors.subtext)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'import'),
          child: const Text('从剪贴板恢复'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'export'),
          child: const Text(
            '导出到剪贴板',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'export') {
    await Clipboard.setData(ClipboardData(text: store.exportJson()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板，粘贴到备忘录等处保存即可'),
        duration: Duration(milliseconds: 1500),
      ),
    );
    return;
  }
  await restoreFromClipboard(context, store);
}

Future<bool> confirmReplace(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('覆盖当前数据'),
      content: const Text('当前的目标、食材、组合餐和饮食记录都会被备份内容替换，且无法撤销。确定继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消', style: TextStyle(color: AppColors.subtext)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            '覆盖',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}
