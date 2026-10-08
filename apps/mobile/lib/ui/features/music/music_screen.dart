import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/atl_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../../domain/models/track.dart';
import 'music_view_model.dart';

/// The full music player: search, now-playing with transport + seek, the queue,
/// likes, and playlists. Streams audio from the gateway's `/music/stream` proxy
/// via the on-device player. Follows the Today/Email screen conventions (Atl
/// theme, watch the ChangeNotifier VM, pull-to-refresh).
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _searchCtrl = TextEditingController();
  late final MusicViewModel _vm;

  /// While the user is dragging the seek bar, hold the in-progress position (in
  /// seconds) so the thumb tracks the finger; committed to the player on release.
  double? _dragSeconds;

  @override
  void initState() {
    super.initState();
    _vm = context.read<MusicViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _vm.setScreenActive(true);
      _vm.loadIfNeeded();
    });
  }

  @override
  void dispose() {
    // Keep polling only while the screen is up; the mini-player takes over.
    // Use the cached VM ref — reading context in dispose is unsafe.
    _vm.setScreenActive(false);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final vm = context.watch<MusicViewModel>();

    return Container(
      decoration: BoxDecoration(gradient: atl.appBg),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Music', style: atlSerif(size: 26, color: atl.text)),
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: vm.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                _searchField(atl, vm),
                const SizedBox(height: 16),
                if (vm.notConnected) _notConnectedCard(atl),
                if (vm.error != null) _errorCard(atl, vm.error!),
                if (vm.hasTrack) ...[
                  _nowPlaying(atl, vm),
                  const SizedBox(height: 18),
                ],
                if (vm.searching)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (vm.results.isNotEmpty) ...[
                  _sectionLabel(atl, 'Results'),
                  const SizedBox(height: 8),
                  ...vm.results.map((t) => _trackRow(atl, t, onTap: () => vm.playTrack(t),
                      trailing: IconButton(
                        icon: Icon(Icons.playlist_add, size: 20, color: atl.text3),
                        onPressed: () => vm.enqueue(t),
                      ))),
                  const SizedBox(height: 18),
                ],
                if (vm.queue.length > 1) ...[
                  _sectionLabel(atl, 'Up next'),
                  const SizedBox(height: 8),
                  ..._upNext(atl, vm),
                  const SizedBox(height: 18),
                ],
                _playlistsSection(atl, vm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(AtlColors atl, MusicViewModel vm) => Container(
        decoration: BoxDecoration(
          color: atl.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: atl.hairline),
        ),
        child: TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: vm.search,
          style: atlSans(size: 15, color: atl.text),
          decoration: InputDecoration(
            hintText: 'Search songs, artists…',
            hintStyle: atlSans(size: 15, color: atl.text3),
            prefixIcon: Icon(Icons.search, color: atl.text3, size: 20),
            suffixIcon: IconButton(
              icon: Icon(Icons.arrow_forward, color: atl.accent, size: 20),
              onPressed: () => vm.search(_searchCtrl.text),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );

  Widget _nowPlaying(AtlColors atl, MusicViewModel vm) {
    final t = vm.current!;
    final dur = vm.duration.inSeconds.toDouble();
    final maxV = dur <= 0 ? 1.0 : dur;
    final live = vm.position.inSeconds.toDouble().clamp(0.0, maxV);
    // Track the finger while scrubbing; otherwise follow playback.
    final sliderValue = (_dragSeconds ?? live).clamp(0.0, maxV);
    final shownPos = _dragSeconds != null
        ? Duration(seconds: _dragSeconds!.round())
        : vm.position;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: atl.hairline),
          boxShadow: atl.cardShadow,
        ),
        child: Stack(
          children: [
            // Blurred album-art backdrop for a hero feel; falls back to the
            // signature gradient when there's no artwork.
            Positioned.fill(
              child: t.thumbnail.isEmpty
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0x2E8FE9FF),
                            atl.surface,
                            const Color(0x26F4A9D6),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    )
                  : ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: Image.network(t.thumbnail, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    ),
            ),
            // Scrim keeps controls legible over any artwork.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: atl.surface.withValues(alpha: 0.72)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AtlSpace.xl),
              child: Column(
                children: [
                  // Hero artwork.
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: AtlRadius.mdAll,
                      boxShadow: atl.elevatedShadow,
                    ),
                    child: MusicArt(url: t.thumbnail, size: 200, radius: AtlRadius.md),
                  ),
                  const SizedBox(height: AtlSpace.lg),
                  Text(t.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AtlType.heading(color: atl.text)),
                  const SizedBox(height: AtlSpace.xs),
                  Text(t.artist,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AtlType.body(color: atl.text2)),
                  const SizedBox(height: AtlSpace.md),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: atl.accent,
                      inactiveTrackColor: atl.divider,
                      thumbColor: atl.accent,
                    ),
                    child: Slider(
                      value: sliderValue,
                      max: maxV,
                      onChanged: (v) => setState(() => _dragSeconds = v),
                      onChangeEnd: (v) {
                        vm.seekTo(v);
                        setState(() => _dragSeconds = null);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(shownPos), style: AtlType.mono(size: 11, color: atl.text3)),
                        Text(_fmt(vm.duration), style: AtlType.mono(size: 11, color: atl.text3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AtlSpace.sm),
                  // Transport: play/pause is the clear primary; skip is secondary;
                  // like/dislike are subordinate (smaller, muted).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 22,
                        icon: Icon(Icons.thumb_down_alt_outlined, color: atl.text3),
                        onPressed: vm.dislike,
                      ),
                      const SizedBox(width: AtlSpace.sm),
                      IconButton(
                        iconSize: 34,
                        icon: Icon(Icons.skip_previous, color: atl.text),
                        onPressed: vm.previous,
                      ),
                      const SizedBox(width: AtlSpace.md),
                      _playPauseButton(atl, vm),
                      const SizedBox(width: AtlSpace.md),
                      IconButton(
                        iconSize: 34,
                        icon: Icon(Icons.skip_next, color: atl.text),
                        onPressed: vm.next,
                      ),
                      const SizedBox(width: AtlSpace.sm),
                      IconButton(
                        iconSize: 22,
                        icon: Icon(Icons.thumb_up_alt_outlined, color: atl.accent),
                        onPressed: vm.like,
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: Icon(Icons.playlist_add, size: 18, color: atl.text2),
                      label: Text('Add to playlist', style: AtlType.label(color: atl.text2)),
                      onPressed: () => _addToPlaylistSheet(context, vm),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playPauseButton(AtlColors atl, MusicViewModel vm) => GestureDetector(
        onTap: vm.buffering ? null : vm.togglePlay,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(shape: BoxShape.circle, color: atl.accent),
          child: vm.buffering
              ? Padding(
                  padding: const EdgeInsets.all(17),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: atl.accentInk),
                )
              : Icon(vm.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 30, color: atl.accentInk),
        ),
      );

  Widget _sectionLabel(AtlColors atl, String label) => Text(
        label.toUpperCase(),
        style: atlSans(size: 12, color: atl.text2, weight: FontWeight.w600, letterSpacing: 1),
      );

  Widget _trackRow(AtlColors atl, Track t,
          {required VoidCallback onTap, Widget? trailing}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              MusicArt(url: t.thumbnail, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: atlSans(size: 15, color: atl.text, weight: FontWeight.w500)),
                    Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: atlSans(size: 13, color: atl.text2)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );

  List<Widget> _upNext(AtlColors atl, MusicViewModel vm) {
    final rows = <Widget>[];
    for (var i = vm.snapshot.index + 1; i < vm.queue.length && rows.length < 20; i++) {
      final idx = i;
      rows.add(_trackRow(atl, vm.queue[i], onTap: () => vm.playIndex(idx)));
    }
    return rows;
  }

  Widget _playlistsSection(AtlColors atl, MusicViewModel vm) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionLabel(atl, 'Playlists'),
              IconButton(
                icon: Icon(Icons.add, size: 20, color: atl.accent),
                onPressed: () => _createPlaylistDialog(context, vm),
              ),
            ],
          ),
          if (vm.playlists.isEmpty)
            Text('No playlists yet.', style: atlSans(size: 13, color: atl.text3))
          else
            ...vm.playlists.map((p) => InkWell(
                  onTap: () => vm.playPlaylist(p['id'] as String),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.queue_music, color: atl.accent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(p['name']?.toString() ?? 'Playlist',
                              style: atlSans(size: 15, color: atl.text, weight: FontWeight.w500)),
                        ),
                        Text('${(p['tracks'] as List?)?.length ?? 0}',
                            style: atlMono(size: 12, color: atl.text3)),
                        const SizedBox(width: 8),
                        Icon(Icons.play_arrow, color: atl.text3, size: 20),
                      ],
                    ),
                  ),
                )),
        ],
      );

  Widget _notConnectedCard(AtlColors atl) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: atl.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: atl.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.music_off, color: atl.text3),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Music streaming is unavailable on the gateway (yt-dlp not installed).',
                  style: atlSans(size: 13, color: atl.text2)),
            ),
          ],
        ),
      );

  Widget _errorCard(AtlColors atl, String msg) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x1AFF6B75),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(msg, style: atlSans(size: 13, color: AtlColors.danger)),
      );

  Future<void> _createPlaylistDialog(BuildContext context, MusicViewModel vm) async {
    final ctrl = TextEditingController();
    final atl = context.atl;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New playlist', style: atlSans(size: 17, color: atl.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await vm.createPlaylist(name);
  }

  Future<void> _addToPlaylistSheet(BuildContext context, MusicViewModel vm) async {
    final atl = context.atl;
    if (vm.playlists.isEmpty) {
      await _createPlaylistDialog(context, vm);
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: atl.elevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Add to playlist', style: atlSans(size: 16, color: atl.text, weight: FontWeight.w600)),
            ),
            ...vm.playlists.map((p) => ListTile(
                  leading: Icon(Icons.queue_music, color: atl.accent),
                  title: Text(p['name']?.toString() ?? 'Playlist',
                      style: atlSans(size: 15, color: atl.text)),
                  onTap: () {
                    vm.addCurrentToPlaylist(p['id'] as String);
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

/// Album/thumbnail art with a graceful fallback to a music glyph. Shared by the
/// now-playing hero, track rows, and the mini-player (pass [radius] `0` for a
/// flush square, as the mini-player does).
class MusicArt extends StatelessWidget {
  const MusicArt({
    super.key,
    required this.url,
    required this.size,
    this.radius = 10,
  });
  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final fallback = Container(
      width: size,
      height: size,
      color: atl.surface2,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: size * 0.5, color: atl.text3),
    );
    final child = url.isEmpty
        ? fallback
        : Image.network(url,
            width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback);
    return radius > 0
        ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
        : child;
  }
}
