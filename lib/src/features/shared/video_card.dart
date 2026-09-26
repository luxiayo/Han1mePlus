import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';

int videoCardCacheWidth(double cardWidth, double devicePixelRatio) => (cardWidth * devicePixelRatio).round().clamp(240, 480).toInt();

/// 6 列及以上的列数判定阈值（与探索页 _maxContentWidth 对齐）。
const _wideColumnThreshold = 1680.0;
/// 6 列及以上卡片的额外高度补偿。
const _wideCardHeightBonus = 24.0;

const _metaGap = 8.0;
// 46 = 2 行 × 19.6（14px × 1.4 行高）+ 6.8px 余量：日文假名/汉字可能经
// 回退字体渲染，墨迹可超出行盒，余量防止 Material 裁切吃掉第 2 行底部。
const _titleBoxHeight = 46.0;
const _metaLineHeight = 17.0;
// 标题行高显式化：不依赖字体度量（微软雅黑等大行高字体否则会把
// 第 2 行挤出盒子裁掉下半截）。1.4 略小于盒高上限 40/2/14≈1.43，给缩放舍入留余量。
const _titleLineHeight = 1.4;

double videoCardDetailsHeightFor(TextScaler textScaler) =>
    textScaler.scale(_titleBoxHeight) + 2 + textScaler.scale(_metaLineHeight) + 2 + textScaler.scale(_metaLineHeight);

double videoCardMetaHeightFor(TextScaler textScaler) => _metaGap + videoCardDetailsHeightFor(textScaler);

double videoCardMetaHeight(BuildContext context) => videoCardMetaHeightFor(MediaQuery.textScalerOf(context));

class VideoCardMetrics {
  const VideoCardMetrics({required this.horizontal, required this.cardsPerRow, required this.cardWidth, required this.cardHeight});

  final bool horizontal;
  final int cardsPerRow;
  final double cardWidth;
  final double cardHeight;
}

VideoCardMetrics videoCardMetrics({
  required double viewportWidth,
  required bool horizontal,
  required int cardsPerRow,
  required bool expanded,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  const spacing = 10.0;
  const padding = 32.0;
  final metaHeight = videoCardMetaHeightFor(textScaler);
  if (expanded) {
    // 按目标卡宽 280px 推导列数（用户设置为下限、上限 8）：
    // 旧的 ≥1200 门控 + 300px 下限在宽屏只能排 4 列，右侧大片留白。
    final effective = (viewportWidth / 280).floor().clamp(cardsPerRow, 8).toInt();
    final cardWidth = (viewportWidth - padding - spacing * (effective - 1)) / effective;
    final cardHeight = horizontal ? cardWidth * 9 / 16 + metaHeight : cardWidth / .58;
    return VideoCardMetrics(horizontal: horizontal, cardsPerRow: effective, cardWidth: cardWidth, cardHeight: cardHeight);
  }
  final desktop = viewportWidth >= 700;
  final cardWidth = horizontal ? (desktop ? 220.0 : 154.0) : (desktop ? 170.0 : 132.0);
  final cardHeight = horizontal ? cardWidth * 9 / 16 + metaHeight : cardWidth / .58;
  return VideoCardMetrics(horizontal: horizontal, cardsPerRow: 1, cardWidth: cardWidth, cardHeight: cardHeight);
}

class VideoCardTile extends StatelessWidget {
  const VideoCardTile({super.key, required this.video, this.horizontal = false, this.selected = false, this.onTap, this.onLongPress, this.coverImage});

  final VideoCard video;
  final bool horizontal;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ImageProvider? coverImage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final cacheWidth = videoCardCacheWidth(constraints.maxWidth, MediaQuery.devicePixelRatioOf(context));
        return Material(
          color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: selected ? BorderSide(color: theme.colorScheme.primary, width: 2) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap ?? (video.id.isEmpty ? null : () => context.push('/video/${video.id}')),
            onLongPress: onLongPress,
            child: horizontal
                ? _horizontalContent(theme, textScaler, cacheWidth)
                : _verticalContent(theme, textScaler, cacheWidth),
          ),
        );
      },
    );
  }

  Widget _verticalContent(ThemeData theme, TextScaler textScaler, int cacheWidth) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cover(theme, cacheWidth)),
          const SizedBox(height: _metaGap),
          _details(theme, textScaler, shrinkable: false),
        ],
      );

  Widget _horizontalContent(ThemeData theme, TextScaler textScaler, int cacheWidth) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _cover(theme, cacheWidth)),
          const SizedBox(height: _metaGap),
          Flexible(fit: FlexFit.loose, child: _details(theme, textScaler, shrinkable: true)),
        ],
      );

  Widget _cover(ThemeData theme, int cacheWidth) => RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverImage != null)
                Image(image: coverImage!, fit: BoxFit.cover)
              else
                CachedNetworkImage(
                  imageUrl: video.coverUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: cacheWidth,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              if (video.duration != null) Positioned(right: 6, bottom: 6, child: _OverlayText(text: video.duration!)),
              if (video.views != null)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _OverlayText(icon: Icons.visibility_outlined, text: video.views!),
                ),
            ],
          ),
        ),
      );

  Widget _details(ThemeData theme, TextScaler textScaler, {required bool shrinkable}) {
    Widget line(Widget child) => shrinkable ? Flexible(fit: FlexFit.loose, child: child) : child;
    final rating = video.rating;
    final uploadTime = video.uploadTime;
    final artist = video.artist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        line(
          SizedBox(
            height: textScaler.scale(_titleBoxHeight),
            child: Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: _titleLineHeight,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        if (artist != null && artist.isNotEmpty)
          line(Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline))),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(child: rating == null || rating.isEmpty ? const SizedBox.shrink() : Row(children: [Icon(Icons.thumb_up_outlined, size: 14, color: theme.colorScheme.outline), const SizedBox(width: 4), Flexible(child: Text(rating, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)))])),
            if (uploadTime != null && uploadTime.isNotEmpty) Text(uploadTime, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ],
    );
  }
}

class VideoCardGrid extends ConsumerWidget {
  const VideoCardGrid({super.key, required this.videos, this.itemBuilder, this.keyboardDismissBehavior});

  final List<VideoCard> videos;
  final Widget Function(BuildContext context, int index, VideoCard video, bool horizontal)? itemBuilder;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final horizontal = settings?.useHorizontalSearchCards ?? true;
    final cardsPerRow = settings?.searchCardsPerRow ?? 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 24.0;
        const crossAxisSpacing = 10.0;
        const mainAxisSpacing = 12.0;
        final effectiveCardsPerRow = (constraints.maxWidth / 280).floor().clamp(cardsPerRow, 8).toInt();
        final cardWidth = (constraints.maxWidth - horizontalPadding - crossAxisSpacing * (effectiveCardsPerRow - 1)) / effectiveCardsPerRow;
        // 6 列及以上（宽 >1680，与探索页上限对齐）时加高度补偿：该区间实测
        // meta 区会被压缩、标题第二行被裁；加高后与 5 列的底部富余对齐。
        final wideBonus = constraints.maxWidth > _wideColumnThreshold ? _wideCardHeightBonus : 0.0;
        final cardHeight = horizontal ? cardWidth * 9 / 16 + videoCardMetaHeight(context) + wideBonus : cardWidth / .58;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
          scrollCacheExtent: ScrollCacheExtent.pixels(720),
          keyboardDismissBehavior: keyboardDismissBehavior,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveCardsPerRow,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) => itemBuilder?.call(context, index, videos[index], horizontal) ?? VideoCardTile(video: videos[index], horizontal: horizontal),
        );
      },
    );
  }
}

class _OverlayText extends StatelessWidget {
  const _OverlayText({this.icon, required this.text});
  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 3),
            ],
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        );
}
