import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Community — the page behind the purple "Community" circle in the Home
/// hub. Everything is uploaded from the CRM (web/crm.html → Community tab)
/// into `community_reels` / `community_posts` and the public
/// `community-media` bucket (supabase/community.sql). The app only reads
/// what's published.

/// One photo or video inside a Recent work post.
class CommunityMedia {
  const CommunityMedia({
    required this.url,
    required this.isVideo,
    this.posterUrl,
    this.width,
    this.height,
    this.duration,
  });

  final String url;
  final bool isVideo;

  /// First frame of a video (null for photos).
  final String? posterUrl;
  final double? width;
  final double? height;

  /// Seconds (videos only).
  final double? duration;

  /// width / height, when known.
  double? get aspect {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  /// What to show as a still picture (a video's cover frame).
  String? get stillUrl => isVideo ? posterUrl : url;
}

/// A vertical video on the Content tab.
class CommunityReel {
  const CommunityReel({
    required this.id,
    required this.videoUrl,
    required this.caption,
    required this.createdAt,
    this.posterUrl,
    this.width,
    this.height,
  });

  final String id;
  final String videoUrl;
  final String? posterUrl;
  final String caption;
  final DateTime createdAt;
  final double? width;
  final double? height;
}

/// A post on the Recent work tab: a brief + 1–10 photos/videos.
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.body,
    required this.media,
    required this.createdAt,
  });

  final String id;
  final String body;
  final List<CommunityMedia> media;
  final DateTime createdAt;

  int get photoCount => media.where((m) => !m.isVideo).length;
  int get videoCount => media.where((m) => m.isVideo).length;
}

/// A shared link, e.g. https://reperi.in/community/reel/<id>.
class CommunityLink {
  const CommunityLink({this.reelId, this.postId});

  final String? reelId;
  final String? postId;

  /// 0 = Content (reels), 1 = Recent work.
  int get tab => postId != null ? 1 : 0;

  String get key => 'r:$reelId|p:$postId';
}

class CommunityService {
  CommunityService._();

  static const String bucket = 'community-media';
  static const String _site = 'https://reperi.in';

  static SupabaseClient get _db => Supabase.instance.client;

  static String _publicUrl(String path) => _db.storage.from(bucket).getPublicUrl(path);

  static double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static DateTime _date(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal() ?? DateTime.now();

  static const String _reelColumns = 'id, video_path, poster_path, caption, width, height, created_at';
  static const String _postColumns = 'id, body, media, created_at';

  static CommunityReel _reel(Map<String, dynamic> r) {
    final poster = (r['poster_path'] ?? '').toString();
    return CommunityReel(
      id: r['id'].toString(),
      videoUrl: _publicUrl(r['video_path'].toString()),
      posterUrl: poster.isEmpty ? null : _publicUrl(poster),
      caption: (r['caption'] ?? '').toString(),
      width: _num(r['width']),
      height: _num(r['height']),
      createdAt: _date(r['created_at']),
    );
  }

  static CommunityPost _post(Map<String, dynamic> r) {
    final raw = r['media'];
    final media = <CommunityMedia>[];
    if (raw is List) {
      for (final m in raw) {
        if (m is! Map) continue;
        final path = (m['path'] ?? '').toString();
        if (path.isEmpty) continue;
        final poster = (m['poster_path'] ?? '').toString();
        media.add(CommunityMedia(
          url: _publicUrl(path),
          isVideo: m['type'] == 'video',
          posterUrl: poster.isEmpty ? null : _publicUrl(poster),
          width: _num(m['width']),
          height: _num(m['height']),
          duration: _num(m['duration']),
        ));
      }
    }
    return CommunityPost(
      id: r['id'].toString(),
      body: (r['body'] ?? '').toString(),
      media: media,
      createdAt: _date(r['created_at']),
    );
  }

  /// Newest first. Returns fewer than [limit] at the end of the list.
  static Future<List<CommunityReel>> fetchReels({int offset = 0, int limit = 12}) async {
    final rows = await _db
        .from('community_reels')
        .select(_reelColumns)
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return [for (final r in rows) _reel(r)];
  }

  static Future<CommunityReel?> fetchReel(String id) async {
    final row = await _db
        .from('community_reels')
        .select(_reelColumns)
        .eq('id', id)
        .eq('is_published', true)
        .maybeSingle();
    return row == null ? null : _reel(row);
  }

  /// Newest first. Posts without any media are skipped.
  static Future<List<CommunityPost>> fetchPosts({int offset = 0, int limit = 10}) async {
    final rows = await _db
        .from('community_posts')
        .select(_postColumns)
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return [for (final r in rows) _post(r)];
  }

  static Future<CommunityPost?> fetchPost(String id) async {
    final row = await _db
        .from('community_posts')
        .select(_postColumns)
        .eq('id', id)
        .eq('is_published', true)
        .maybeSingle();
    return row == null ? null : _post(row);
  }

  // ── Sharing ──────────────────────────────────────────────────────────
  // The link opens the app when it's installed (Android App Links / iOS
  // Universal Links — see web/.well-known/), otherwise reperi.in, which
  // opens the same reel / post on the website.

  static Uri reelLink(String id) => Uri.parse('$_site/community/reel/$id');
  static Uri postLink(String id) => Uri.parse('$_site/community/post/$id');

  /// Opens the phone's share sheet. [context] should be the tapped button's
  /// (iPads anchor the sheet to it).
  static Future<void> share(BuildContext context, {required String text, required Uri link}) async {
    HapticFeedback.selectionClick();
    final box = context.findRenderObject();
    Rect? origin;
    if (box is RenderBox && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final caption = _shorten(text.trim());
    final message = caption.isEmpty ? 'See this on Reperi: $link' : '$caption\n\nSee it on Reperi: $link';
    try {
      await SharePlus.instance.share(ShareParams(
        text: message,
        subject: 'Reperi',
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      // No share sheet (e.g. some desktop browsers) — copy the link instead.
      await Clipboard.setData(ClipboardData(text: link.toString()));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Link copied — paste it anywhere to share.')),
      );
    }
  }

  static String _shorten(String s) {
    if (s.length <= 220) return s;
    final cut = s.substring(0, 220);
    final space = cut.lastIndexOf(' ');
    return '${(space > 160 ? cut.substring(0, space) : cut).trimRight()}…';
  }
}

/// "Just now", "5m", "3h", "Yesterday", "3 days ago", "2 weeks ago", "12 Oct".
String communityTimeAgo(DateTime d, {bool short = false}) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return short ? '${diff.inMinutes}m' : '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return short ? '${diff.inHours}h' : '${diff.inHours} h ago';
  if (diff.inDays == 1) return short ? '1d' : 'Yesterday';
  if (diff.inDays < 7) return short ? '${diff.inDays}d' : '${diff.inDays} days ago';
  if (diff.inDays < 28) {
    final w = diff.inDays ~/ 7;
    return short ? '${w}w' : (w == 1 ? '1 week ago' : '$w weeks ago');
  }
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final sameYear = d.year == DateTime.now().year;
  return '${d.day} ${m[d.month - 1]}${sameYear ? '' : ' ${d.year}'}';
}
