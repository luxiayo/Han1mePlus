import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/han1me_repository.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../shared/video_card.dart';

final previewsProvider = FutureProvider.autoDispose.family<PreviewFeed, String>((ref, month) async {
  final settings = await ref.watch(settingsProvider.future);
  return ref.watch(han1meRepositoryProvider).previews(settings.resolvedBaseUrl, month);
});

class PreviewsPage extends ConsumerWidget {
  const PreviewsPage({super.key, required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedMonth = _PreviewMonth.parse(month);
    final result = ref.watch(previewsProvider(month));
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedMonth.isCurrentOrFuture ? l10n.upcomingPreviews : l10n.previews),
        actions: [
          IconButton(
            tooltip: l10n.getchuPreviews,
            onPressed: () => context.push('/previews/getchu/$month'),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: l10n.comments,
            onPressed: () => context.push('/comments/preview/$month', extra: l10n.previews),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _MonthNavigation(
            month: selectedMonth,
            onPrevious: () => _replaceMonth(context, selectedMonth.previous),
            onNext: selectedMonth.isCurrentOrFuture ? null : () => _replaceMonth(context, selectedMonth.next),
            onSelect: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: selectedMonth.date,
                firstDate: DateTime(1990),
                lastDate: _PreviewMonth.current.date,
                initialDatePickerMode: DatePickerMode.year,
              );
              if (selected != null && context.mounted) _replaceMonth(context, _PreviewMonth(selected.year, selected.month));
            },
          ),
          Expanded(
            child: result.when(
              loading: () => const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) => _PreviewUnavailable(
                title: l10n.previewUnavailable,
                description: l10n.previewUnavailableDescription,
                onPrevious: () => _replaceMonth(context, selectedMonth.previous),
                onRetry: () => ref.invalidate(previewsProvider(month)),
              ),
              data: (feed) => feed.items.isEmpty
                  ? _PreviewUnavailable(
                      title: l10n.noPreviews,
                      description: l10n.noPreviewsDescription,
                      onPrevious: () => _replaceMonth(context, selectedMonth.previous),
                      onRetry: () => ref.invalidate(previewsProvider(month)),
                    )
                  : CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(child: _PreviewHeader(feed: feed)),
                        SliverLayoutBuilder(
                          builder: (context, constraints) {
                            // 纵向卡片网格：与紧凑影片卡同款的列数推导
                            //（目标卡宽 130、下限用影片卡片每行数量设置、上限 8）。
                            const crossAxisSpacing = 10.0;
                            final cardsPerRow = ref.watch(settingsProvider).valueOrNull?.searchCardsPerRow ?? 2;
                            final columns = (constraints.crossAxisExtent / 130).floor().clamp(cardsPerRow, 8).toInt();
                            final textScaler = MediaQuery.textScalerOf(context);
                            final cardWidth = (constraints.crossAxisExtent - crossAxisSpacing * (columns - 1)) / columns;
                            final cardHeight = cardWidth * 4 / 3 + textScaler.scale(40) + 2 + textScaler.scale(17) + 16;
                            return SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 12, crossAxisSpacing: crossAxisSpacing, mainAxisExtent: cardHeight),
                                delegate: SliverChildBuilderDelegate((context, index) => _PreviewCard(item: feed.items[index]), childCount: feed.items.length),
                              ),
                            );
                          },
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _replaceMonth(BuildContext context, _PreviewMonth month) => context.replace('/previews/${month.value}');
}

class _PreviewMonth {
  const _PreviewMonth(this.year, this.month);

  final int year;
  final int month;

  static _PreviewMonth get current {
    final now = DateTime.now();
    return _PreviewMonth(now.year, now.month);
  }

  factory _PreviewMonth.parse(String value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return current;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    return year == null || month == null || month < 1 || month > 12 ? current : _PreviewMonth(year, month);
  }

  DateTime get date => DateTime(year, month);
  String get value => '$year${month.toString().padLeft(2, '0')}';
  String get label => '$year${month.toString().padLeft(2, '0')}';
  _PreviewMonth get previous => _fromDate(DateTime(year, month - 1));
  _PreviewMonth get next => _fromDate(DateTime(year, month + 1));
  bool get isCurrentOrFuture => date.compareTo(current.date) >= 0;

  static _PreviewMonth _fromDate(DateTime value) => _PreviewMonth(value.year, value.month);
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({required this.month, required this.onPrevious, required this.onNext, required this.onSelect});

  final _PreviewMonth month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(tooltip: l10n.previousMonth, onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: TextButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(l10n.previewMonth(month.label)),
              ),
            ),
            IconButton(tooltip: l10n.nextMonth, onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({required this.title, required this.description, required this.onPrevious, required this.onRetry});

  final String title;
  final String description;
  final VoidCallback onPrevious;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(onPressed: onPrevious, icon: const Icon(Icons.chevron_left), label: Text(l10n.previousMonth)),
                OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(l10n.reload)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.feed});

  final PreviewFeed feed;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(feed.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (feed.description.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(feed.description)),
        ],
      );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.item});

  final PreviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = videoCardCacheWidth(constraints.maxWidth, MediaQuery.devicePixelRatioOf(context));
        return Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // 预览图查看器移到长按：卡面只留封面+标题+厂牌，保证纵向紧凑。
            onTap: () => context.push('/video/${item.id}'),
            onLongPress: item.previewImages.isNotEmpty ? () => _showPreviewImages(context, item, 0) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(imageUrl: item.coverUrl, fit: BoxFit.cover, memCacheWidth: cacheWidth, fadeInDuration: Duration.zero),
                      if (item.releaseDate != null) Positioned(top: 6, right: 6, child: _PreviewBadge(text: item.releaseDate!)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题盒固定高度（2×14×1.4=39.2 ≤ 40），行高显式钉死不依赖字体度量
                      SizedBox(
                        height: textScaler.scale(40),
                        child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: textScaler.scale(17),
                        child: Text(item.brand ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}

Future<void> _showPreviewImages(BuildContext context, PreviewItem item, int initialPage) => showDialog<void>(
      context: context,
      builder: (context) => _PreviewImagesDialog(item: item, initialPage: initialPage),
    );

class _PreviewImagesDialog extends StatefulWidget {
  const _PreviewImagesDialog({required this.item, required this.initialPage});

  final PreviewItem item;
  final int initialPage;

  @override
  State<_PreviewImagesDialog> createState() => _PreviewImagesDialogState();
}

class _PreviewImagesDialogState extends State<_PreviewImagesDialog> {
  late final _controller = PageController(initialPage: widget.initialPage);
  late var _index = widget.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text(widget.item.videoTitle ?? widget.item.title)),
          body: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.item.previewImages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) => InteractiveViewer(
                  child: Center(child: CachedNetworkImage(imageUrl: widget.item.previewImages[index], fit: BoxFit.contain, fadeInDuration: Duration.zero)),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: _PreviewBadge(text: '${_index + 1} / ${widget.item.previewImages.length}'),
              ),
            ],
          ),
        ),
      );
}
