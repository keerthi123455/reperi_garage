import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../services/community_service.dart';
import 'community_ui.dart';

/// Full-screen viewer for a Recent work post: swipe between its photos and
/// videos, pinch or double-tap to zoom, drag down to close. Photos fly in
/// from their tile in the feed (Hero).
class CommunityMediaViewer extends StatefulWidget {
  const CommunityMediaViewer({super.key, required this.post, required this.initialIndex});

  final CommunityPost post;
  final int initialIndex;

  static String heroTag(String postId, int index) => 'community-$postId-$index';

  static Future<void> open(BuildContext context, {required CommunityPost post, required int index}) {
    HapticFeedback.selectionClick();
    return Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => CommunityMediaViewer(post: post, initialIndex: index),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
        child: child,
      ),
    ));
  }

  @override
  State<CommunityMediaViewer> createState() => _CommunityMediaViewerState();
}

class _CommunityMediaViewerState extends State<CommunityMediaViewer> with SingleTickerProviderStateMixin {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  bool _chrome = true;

  /// How far the current item has been dragged down (to close).
  double _drag = 0;
  late final AnimationController _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
    ..addListener(() => setState(() => _drag = _snapFrom * (1 - Curves.easeOutCubic.transform(_snap.value))));
  double _snapFrom = 0;

  List<CommunityMedia> get _media => widget.post.media;

  @override
  void dispose() {
    _snap.dispose();
    _page.dispose();
    super.dispose();
  }

  void _onDrag(double dy) {
    if (_snap.isAnimating) _snap.stop();
    setState(() => _drag += dy);
  }

  void _onDragEnd(double velocity) {
    if (_drag.abs() > 130 || velocity.abs() > 900) {
      HapticFeedback.lightImpact();
      Navigator.of(context).maybePop();
      return;
    }
    _snapFrom = _drag;
    _snap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final fade = (1 - _drag.abs() / 420).clamp(0.0, 1.0);
    final showChrome = _chrome && _drag.abs() < 8;
    final caption = widget.post.body.trim();

    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Colors.black.withValues(alpha: fade),
        child: Stack(
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: const CommunityScrollBehavior(),
                child: PageView.builder(
                  controller: _page,
                  physics: _zoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                  itemCount: _media.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, i) {
                    final m = _media[i];
                    final tag = CommunityMediaViewer.heroTag(widget.post.id, i);
                    final item = m.isVideo
                        ? _ViewerVideo(
                            media: m,
                            heroTag: tag,
                            active: i == _index,
                            onDrag: _onDrag,
                            onDragEnd: _onDragEnd,
                          )
                        : _ZoomableImage(
                            url: m.url,
                            heroTag: tag,
                            onZoomChanged: (z) {
                              if (z != _zoomed) setState(() => _zoomed = z);
                            },
                            onDrag: _onDrag,
                            onDragEnd: _onDragEnd,
                            onTap: () => setState(() => _chrome = !_chrome),
                          );
                    return Transform.translate(
                      offset: Offset(0, i == _index ? _drag : 0),
                      child: Transform.scale(scale: i == _index ? 1 - (_drag.abs() / 2400).clamp(0.0, 0.15) : 1, child: item),
                    );
                  },
                ),
              ),
            ),
            // Close · 3 / 7 · Share
            Positioned(
              top: pad.top + 8,
              left: 16,
              right: 16,
              child: IgnorePointer(
                ignoring: !showChrome,
                child: AnimatedOpacity(
                  opacity: showChrome ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    children: [
                      GlassCircleButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Close',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Text(
                          _media.length > 1 ? '${_index + 1} / ${_media.length}' : '',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: communityText(size: 15, weight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      Builder(
                        builder: (btnContext) => GlassCircleButton(
                          icon: Icons.share_rounded,
                          iconSize: 19,
                          tooltip: 'Share',
                          onTap: () => CommunityService.share(
                            btnContext,
                            text: widget.post.body,
                            link: CommunityService.postLink(widget.post.id),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Dots + the brief
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showChrome && !_zoomed ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(20, 40, 20, pad.bottom + 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_media.length > 1)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < _media.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  width: i == _index ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: i == _index ? 1 : 0.4),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ],
                          ),
                        if (caption.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: communityText(
                                size: 14, weight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.92), height: 1.4),
                          ),
                        ],
                      ],
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

/// A photo you can pinch / double-tap to zoom (up to 5×). While not zoomed,
/// a one-finger vertical drag is passed up to close the viewer.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.url,
    required this.heroTag,
    required this.onZoomChanged,
    required this.onDrag,
    required this.onDragEnd,
    required this.onTap,
  });

  final String url;
  final String heroTag;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onTap;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
    ..addListener(() {
      final t = _tween;
      if (t != null) _tc.value = t.transform(Curves.easeOutCubic.transform(_anim.value));
    });
  Matrix4Tween? _tween;
  Offset? _tapAt;
  bool _zoomed = false;
  bool _dragging = false;

  double get _scale => _tc.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _setZoomed(bool z) {
    if (z == _zoomed) return;
    setState(() => _zoomed = z);
    widget.onZoomChanged(z);
  }

  void _doubleTap() {
    final box = context.findRenderObject() as RenderBox?;
    final at = _tapAt ?? (box != null ? box.size.center(Offset.zero) : Offset.zero);
    final Matrix4 end;
    if (_scale > 1.01) {
      end = Matrix4.identity();
    } else {
      const s = 2.6;
      end = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setEntry(0, 3, -at.dx * (s - 1))
        ..setEntry(1, 3, -at.dy * (s - 1));
    }
    HapticFeedback.selectionClick();
    _tween = Matrix4Tween(begin: _tc.value.clone(), end: end);
    _anim.forward(from: 0);
    _setZoomed(end.getMaxScaleOnAxis() > 1.01);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1,
        maxScale: 5,
        panEnabled: _zoomed,
        clipBehavior: Clip.none,
        onInteractionStart: (d) {
          if (_anim.isAnimating) _anim.stop();
          _dragging = !_zoomed && d.pointerCount == 1;
        },
        onInteractionUpdate: (d) {
          if (!_dragging) return;
          if (d.pointerCount > 1) {
            // Second finger came down: it's a pinch, not a drag to close.
            _dragging = false;
            widget.onDragEnd(0);
            return;
          }
          widget.onDrag(d.focalPointDelta.dy);
        },
        onInteractionEnd: (d) {
          if (_dragging) widget.onDragEnd(d.velocity.pixelsPerSecond.dy);
          _dragging = false;
          _setZoomed(_scale > 1.01);
        },
        child: SizedBox.expand(
          child: Hero(
            tag: widget.heroTag,
            child: CachedNetworkImage(
              imageUrl: widget.url,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, __) => const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                ),
              ),
              errorWidget: (_, __, ___) => Center(
                child: Text("Couldn't load this photo",
                    style: communityText(size: 14, weight: FontWeight.w600, color: Colors.white70)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A video inside the viewer: plays while it's the current item, tap to
/// pause, drag the bar to seek, drag down to close.
class _ViewerVideo extends StatefulWidget {
  const _ViewerVideo({
    required this.media,
    required this.heroTag,
    required this.active,
    required this.onDrag,
    required this.onDragEnd,
  });

  final CommunityMedia media;
  final String heroTag;
  final bool active;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  State<_ViewerVideo> createState() => _ViewerVideoState();
}

class _ViewerVideoState extends State<_ViewerVideo> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _paused = false;
  // Sound ON by default on both the app and the website. The viewer can
  // still tap the speaker to mute at any time.
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _ViewerVideo old) {
    super.didUpdateWidget(old);
    if (widget.active && _c == null && !_failed) _start();
    _apply();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _start() {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.media.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _c = c;
    c.initialize().then((_) async {
      if (!mounted || _c != c) return;
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);
      if (!mounted || _c != c) return;
      setState(() {});
      _apply();
    }).catchError((Object e) {
      debugPrint('Viewer video did not load: $e');
      if (!mounted || _c != c) return;
      setState(() {
        _failed = true;
        _c = null;
      });
      c.dispose();
    });
  }

  void _apply() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (widget.active && !_paused) {
      if (!c.value.isPlaying) c.play();
    } else if (c.value.isPlaying) {
      c.pause();
    }
  }

  void _tap() {
    if (_c == null || !_c!.value.isInitialized) return;
    HapticFeedback.lightImpact();
    setState(() => _paused = !_paused);
    _apply();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _c?.setVolume(_muted ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final pad = MediaQuery.paddingOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
      onVerticalDragEnd: (d) => widget.onDragEnd(d.velocity.pixelsPerSecond.dy),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: widget.heroTag,
            child: widget.media.posterUrl == null
                ? const SizedBox.expand()
                : CachedNetworkImage(imageUrl: widget.media.posterUrl!, fit: BoxFit.contain),
          ),
          if (c != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (context, v, _) {
                final ready = v.isInitialized && v.aspectRatio > 0;
                return AnimatedOpacity(
                  opacity: ready ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  child: ready
                      ? Center(child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c)))
                      : const SizedBox.expand(),
                );
              },
            ),
          if (c != null)
            IgnorePointer(
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (context, v, _) => Center(
                  child: !v.isInitialized || v.isBuffering
                      ? const SizedBox(
                          width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : AnimatedOpacity(
                          opacity: _paused ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.4)),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                          ),
                        ),
                ),
              ),
            ),
          if (_failed)
            Center(
              child: Text("Couldn't play this video",
                  style: communityText(size: 14, weight: FontWeight.w600, color: Colors.white70)),
            ),
          if (c != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: pad.bottom + 92,
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        colors: VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white.withValues(alpha: 0.32),
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassCircleButton(
                    icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    tooltip: _muted ? 'Turn sound on' : 'Mute',
                    size: 36,
                    iconSize: 18,
                    onTap: _toggleMute,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
