import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/atl_theme.dart';
import 'music_screen.dart';
import 'music_view_model.dart';

/// A compact now-playing bar shown above the bottom tab bar whenever something
/// is loaded — so music stays reachable from anywhere in the app (the "push +
/// mini-player" navigation model). Tapping it opens the full [MusicScreen].
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<MusicViewModel>();
    if (!vm.hasTrack) return const SizedBox.shrink();

    final track = vm.current!;
    final dur = vm.duration.inMilliseconds;
    final progress = dur > 0 ? (vm.position.inMilliseconds / dur).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MusicScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        decoration: BoxDecoration(
          color: atl.elevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Art(url: track.thumbnail, size: 46, radius: 0),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: atlSans(size: 14, color: atl.text, weight: FontWeight.w600)),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: atlSans(size: 12, color: atl.text2)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(vm.isPlaying ? Icons.pause : Icons.play_arrow, color: atl.text),
                  onPressed: vm.togglePlay,
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, color: atl.text2),
                  onPressed: vm.next,
                ),
                const SizedBox(width: 4),
              ],
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: atl.divider,
              valueColor: AlwaysStoppedAnimation(atl.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Album/thumbnail art with a graceful fallback to a music glyph.
class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size, this.radius = 10});
  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    Widget fallback = Container(
      width: size,
      height: size,
      color: atl.surface2,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: size * 0.5, color: atl.text3),
    );
    final child = url.isEmpty
        ? fallback
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          );
    return radius > 0
        ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
        : child;
  }
}
