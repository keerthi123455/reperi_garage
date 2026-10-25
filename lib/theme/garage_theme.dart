import 'package:flutter/material.dart';

/// Light look for everything on the garage side (dashboard, booking,
/// claim, fleet, ReperiResolve, inspection and add-on screens). Always light,
/// whatever the customer theme is set to.
class G {
  G._();

  static const Color bg = Color(0xFFF6F5F1);
  static const Color card = Colors.white;
  static const Color sunken = Color(0xFFF1EFE9);
  static const Color line = Color(0xFFE3E0D8);
  static const Color txt = Color(0xFF15171A);
  static const Color mut = Color(0xFF63656B);
  static const Color faint = Color(0xFF94969B);

  /// Brand: navy for text / icons / outlines, yellow for the main button.
  static const Color navy = Color(0xFF022B57);
  static const Color yellow = Color(0xFFFDF003);

  static const Color green = Color(0xFF17803D);
  static const Color greenBg = Color(0xFFE3F6E8);
  static const Color red = Color(0xFFD93A3F);
  static const Color redBg = Color(0xFFFDE8E8);
  static const Color blue = Color(0xFF1A4FB5);
  static const Color blueBg = Color(0xFFE6EEFF);
  static const Color amber = Color(0xFF8A5A00);
  static const Color amberBg = Color(0xFFFFF4C2);
  static const Color orange = Color(0xFFB4520C);
  static const Color orangeBg = Color(0xFFFFE9DA);

  static BoxDecoration cardBox({Color? border, double radius = 20, double width = 1}) => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? line, width: width),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      );

  static InputDecoration input(String hint, {Widget? prefixIcon}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: faint, fontWeight: FontWeight.w600),
        prefixIcon: prefixIcon,
        filled: true,
        fillColor: sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: navy, width: 1.6)),
      );

  /// "KA01AB1234" / "ka 01 ab 1234" → "KA 01 AB 1234". Anything that
  /// doesn't look like a normal Indian number is just upper-cased.
  static String plateText(String? raw) {
    final s = (raw ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.isEmpty) return '';
    final m = RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{0,3})(\d{1,4})$').firstMatch(s);
    if (m == null) return (raw ?? '').toUpperCase().trim();
    return [m.group(1), m.group(2), m.group(3), m.group(4)].where((p) => p != null && p.isNotEmpty).join(' ');
  }

  /// Letters and digits only, lower case — so "ka01" finds "KA 01 AB 1234".
  static String squash(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Colour pair for a status in any of the garage lists.
  static (Color fg, Color bg) statusColors(String status) {
    final s = status.toLowerCase();
    if (s.contains('cancel') || s.contains('reject')) return (red, redBg);
    if (s.contains('ready') || s.contains('complete') || s.contains('deliver') || s.contains('done') ||
        s.contains('approved') || s.contains('accepted')) {
      return (green, greenBg);
    }
    if (s.contains('picked') || s.contains('on the way') || s.contains('quoted') || s.contains('price sent')) {
      return (orange, orangeBg);
    }
    if (s.contains('garage') || s.contains('progress') || s.contains('inspection') || s.contains('service')) {
      return (blue, blueBg);
    }
    return (amber, amberBg);
  }

  /// "PENDING" / "in_garage" → "Pending" / "In garage".
  static String sentence(String s) {
    final t = s.replaceAll('_', ' ').trim().toLowerCase();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  /// "Just now", "Today 10:30", "Yesterday", "12 Oct".
  static String when(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 2 && !diff.isNegative) return 'Just now';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$hh:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    if (day == today) return 'Today $time';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${d.day} ${m[d.month - 1]}${d.year != now.year ? ' ${d.year}' : ''}';
  }
}

/// Indian-style number plate. Never wraps: on a narrow phone or with big
/// text it shrinks to fit the space it's given.
class GaragePlate extends StatelessWidget {
  const GaragePlate(this.number, {super.key, this.fontSize = 22});

  final String? number;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = G.plateText(number);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF111111), width: 2.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: fontSize * 0.72,
                color: const Color(0xFF1A4FB5),
                alignment: Alignment.center,
                child: const RotatedBox(
                  quarterTurns: 3,
                  child: Text('IND',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: fontSize * 0.45, vertical: fontSize * 0.28),
                child: Text(
                  text.isEmpty ? 'NO NUMBER' : text,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: text.isEmpty ? G.faint : const Color(0xFF111111),
                    fontSize: text.isEmpty ? fontSize * 0.7 : fontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded status label ("In garage", "Ready for pickup"…).
class GarageStatusPill extends StatelessWidget {
  const GarageStatusPill(this.status, {super.key, this.label});

  final String status;

  /// Text to show instead of the status itself.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = G.statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Text(
        label ?? G.sentence(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Small coloured tag ("New message", "REPERIRESOLVE"…).
class GarageTag extends StatelessWidget {
  const GarageTag(this.text, {super.key, this.color = G.red, this.textColor = Colors.white, this.icon});

  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light app bar used by every garage screen.
PreferredSizeWidget garageAppBar(String title, {List<Widget>? actions}) => AppBar(
      backgroundColor: G.bg,
      surfaceTintColor: G.bg,
      foregroundColor: G.txt,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: G.txt),
      centerTitle: false,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: G.txt, fontSize: 18, fontWeight: FontWeight.w800),
      ),
      actions: actions,
    );

/// Text with every match of [query] highlighted in yellow.
Widget garageHighlight(String text, String query, TextStyle style, {int maxLines = 1}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || !text.toLowerCase().contains(q)) {
    return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
  }
  final spans = <TextSpan>[];
  final lower = text.toLowerCase();
  var i = 0;
  while (true) {
    final j = lower.indexOf(q, i);
    if (j < 0) {
      spans.add(TextSpan(text: text.substring(i)));
      break;
    }
    if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
    spans.add(TextSpan(text: text.substring(j, j + q.length), style: const TextStyle(backgroundColor: G.yellow)));
    i = j + q.length;
  }
  return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
}
