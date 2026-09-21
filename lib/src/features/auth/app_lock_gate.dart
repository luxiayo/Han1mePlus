import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import 'app_lock_controller.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockIfLocked());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appLockProvider, (previous, next) {
      if (next == AppLockStatus.locked) _unlockIfLocked();
    });
    final locked = ref.watch(appLockProvider) != AppLockStatus.unlocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !locked,
          child: IgnorePointer(
            ignoring: locked,
            child: ExcludeSemantics(excluding: locked, child: widget.child),
          ),
        ),
        if (locked) const _LockLayer(),
      ],
    );
  }

  void _unlockIfLocked() {
    if (!mounted) return;
    if (ref.read(appLockProvider) == AppLockStatus.locked) {
      ref.read(appLockProvider.notifier).unlock();
    }
  }
}

class _LockLayer extends ConsumerStatefulWidget {
  const _LockLayer();

  @override
  ConsumerState<_LockLayer> createState() => _LockLayerState();
}

class _LockLayerState extends ConsumerState<_LockLayer> {
  var _busy = false;
  var _failed = false;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(appLockProvider.notifier).unlock();
    if (!mounted) return;
    setState(() => _busy = false);
    // 仍在锁上 = 认证失败或设备无生物识别；给出可见反馈而不是留在空白遮罩上。
    if (ref.read(appLockProvider) != AppLockStatus.unlocked) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _unlock,
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const CircularProgressIndicator()
              else
                Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(_failed ? l10n.appLockAuthFailed : l10n.appLocked, style: theme.textTheme.titleMedium),
              if (!_busy) ...[
                const SizedBox(height: 4),
                Text(l10n.unlocking, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
