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
                MusicArt(url: track.thumbnail, size: 46, radius: 0),
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
