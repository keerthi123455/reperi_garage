import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Booking time slots — one set of rules for every service.
///
///   • Pickup & drop / doorstep visits: 9 AM – 7 PM, every day, 2-hour windows
///   • Customer drops the car at the garage: 12 PM – 5 PM, 1-hour windows
///   • Same day is fine, but only from 3 hours after "now"
///   • Today + the next 6 days
///
/// All times are India time (IST), whatever the phone's own time zone is.
/// The server (booking-api) checks the same rules.
enum SlotMode { pickup, garageDrop, doorstep }

extension SlotModeX on SlotMode {
  String get apiName => switch (this) {
        SlotMode.pickup => 'pickup',
        SlotMode.garageDrop => 'garage_drop',
        SlotMode.doorstep => 'doorstep',
      };

  /// (start hour, end hour) windows in IST.
  List<(int, int)> get windows => switch (this) {
        SlotMode.garageDrop => const [(12, 13), (13, 14), (14, 15), (15, 16), (16, 17)],
        _ => const [(9, 11), (11, 13), (13, 15), (15, 17), (17, 19)],
      };
}

const _ist = Duration(hours: 5, minutes: 30);
const int kSlotLeadHours = 3;
const int kSlotDays = 7;

/// "Now" as an IST wall-clock time (stored in a UTC DateTime so no device
/// time-zone rules apply to it).
DateTime _istNow() => DateTime.now().toUtc().add(_ist);

class BookingSlot {
  BookingSlot({required this.day, required this.startHour, required this.endHour, required this.mode});

  /// IST calendar day (time part ignored).
  final DateTime day;
  final int startHour;
  final int endHour;
  final SlotMode mode;

  /// Real instants (UTC) for the server.
  DateTime get start => DateTime.utc(day.year, day.month, day.day, startHour).subtract(_ist);
  DateTime get end => DateTime.utc(day.year, day.month, day.day, endHour).subtract(_ist);

  /// Still bookable: at least [kSlotLeadHours] from now.
  bool get isStillValid => !start.isBefore(DateTime.now().toUtc().add(const Duration(hours: kSlotLeadHours)));

  String get dateKey =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static String hourLabel(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:00 ${h < 12 ? 'AM' : 'PM'}';
  }

  /// e.g. "11:00 AM – 01:00 PM"
  String get timeLabel => '${hourLabel(startHour)} – ${hourLabel(endHour)}';

  /// e.g. "Wed 22 Oct, 11:00 AM – 01:00 PM"
  String get fullLabel => '${dayLabel(day)}, $timeLabel';

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String dayLabel(DateTime d) => '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';

  Map<String, dynamic> toJson() => {
        'date': dateKey,
        'label': timeLabel,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'mode': mode.apiName,
      };
}

/// The days that still have at least one open slot for [mode].
List<DateTime> slotDays(SlotMode mode) {
  final now = _istNow();
  final today = DateTime.utc(now.year, now.month, now.day);
  return [
    for (var i = 0; i < kSlotDays; i++)
      if (slotsFor(DateTime.utc(today.year, today.month, today.day + i), mode).any((s) => s.isStillValid))
        DateTime.utc(today.year, today.month, today.day + i),
  ];
}

List<BookingSlot> slotsFor(DateTime day, SlotMode mode) => [
      for (final (a, b) in mode.windows) BookingSlot(day: day, startHour: a, endHour: b, mode: mode),
    ];

/// Colours, so the picker matches whichever screen it sits on.
class SlotPickerStyle {
  const SlotPickerStyle({
    this.accent = const Color(0xFF1D5FD6),
    this.onAccent = Colors.white,
    this.surface = Colors.white,
    this.border = const Color(0xFFE0E7F1),
    this.text = const Color(0xFF0E2A4A),
    this.muted = const Color(0xFF62728A),
    this.tint = const Color(0xFFEAF1FC),
  });

  final Color accent;
  final Color onAccent;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color tint;
}

/// Day chips + time slots. Calls [onChanged] with the chosen slot.
class SlotPicker extends StatefulWidget {
  const SlotPicker({
    super.key,
    required this.mode,
    required this.value,
    required this.onChanged,
    this.style = const SlotPickerStyle(),
    this.enabled = true,
  });

  final SlotMode mode;
  final BookingSlot? value;
  final ValueChanged<BookingSlot> onChanged;
  final SlotPickerStyle style;
  final bool enabled;

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  late List<DateTime> _days = slotDays(widget.mode);
  int _dayIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncDayToValue();
  }

  @override
  void didUpdateWidget(SlotPicker old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _days = slotDays(widget.mode);
      _dayIndex = 0;
    }
    if (old.value != widget.value) _syncDayToValue();
  }

  void _syncDayToValue() {
    final v = widget.value;
    if (v == null) return;
    final i = _days.indexWhere((d) => d.year == v.day.year && d.month == v.day.month && d.day == v.day.day);
    if (i >= 0) _dayIndex = i;
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.style;
    if (_days.isEmpty) {
      return Text('No slots available right now — please call us.', style: TextStyle(color: st.muted));
    }
    final day = _days[_dayIndex < _days.length ? _dayIndex : 0];
    final slots = slotsFor(day, widget.mode);
    final now = _istNow();
    final todayKey = DateTime.utc(now.year, now.month, now.day);

    String dayTitle(DateTime d) {
      final diff = d.difference(todayKey).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      return BookingSlot._wd[d.weekday - 1];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = _days[i];
              final on = i == _dayIndex;
              return GestureDetector(
                onTap: !widget.enabled
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() => _dayIndex = i);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: 74,
                  decoration: BoxDecoration(
                    color: on ? st.accent : st.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: on ? st.accent : st.border, width: on ? 1.6 : 1),
                    boxShadow: on
                        ? [BoxShadow(color: st.accent.withOpacity(0.28), blurRadius: 12, offset: const Offset(0, 5))]
                        : const [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dayTitle(d),
                          style: TextStyle(
                              color: on ? st.onAccent : st.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('${d.day} ${BookingSlot._mo[d.month - 1]}',
                          style: TextStyle(
                              color: on ? st.onAccent : st.text, fontSize: 15, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 10) / 2;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: Wrap(
              key: ValueKey('${day.toIso8601String()}-${widget.mode}'),
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in slots)
                  _SlotChip(
                    width: w,
                    slot: s,
                    selected: widget.value != null &&
                        widget.value!.dateKey == s.dateKey &&
                        widget.value!.startHour == s.startHour &&
                        widget.value!.mode == s.mode,
                    available: s.isStillValid && widget.enabled,
                    style: st,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(s);
                    },
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: st.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.mode == SlotMode.garageDrop
                    ? 'Drop your car at the garage within this time. Same-day slots open 3 hours from now.'
                    : 'Same-day slots open 3 hours from now.',
                style: TextStyle(color: st.muted, fontSize: 11.5, height: 1.3),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.width,
    required this.slot,
    required this.selected,
    required this.available,
    required this.style,
    required this.onTap,
  });

  final double width;
  final BookingSlot slot;
  final bool selected;
  final bool available;
  final SlotPickerStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = style;
    return GestureDetector(
      onTap: available ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? st.tint : (available ? st.surface : st.border.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? st.accent : st.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 16,
              color: selected ? st.accent : (available ? st.muted : st.muted.withOpacity(0.4)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${_short(slot.startHour)} – ${_short(slot.endHour)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? st.accent : (available ? st.text : st.muted.withOpacity(0.5)),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  decoration: available ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'AM' : 'PM'}';
  }
}

/// The picked slot on a booking card — "🕒 Wed 22 Oct, 11:00 AM – 01:00 PM"
/// plus what happens then. Shows nothing for bookings without a slot.
class BookingSlotBadge extends StatelessWidget {
  const BookingSlotBadge({super.key, required this.record, this.accent = const Color(0xFFD4A017), this.textColor});

  /// A booking row (needs slot_date, slot_time, slot_mode).
  final Map record;
  final Color accent;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final raw = record['slot_date']?.toString();
    final d = raw == null ? null : DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    if (d == null) return const SizedBox.shrink();
    final time = record['slot_time']?.toString();
    final mode = switch (record['slot_mode']?.toString()) {
      'pickup' => 'We pick up your car',
      'garage_drop' => 'Drop your car at the garage',
      'doorstep' => 'We come to you',
      _ => 'Scheduled',
    };
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${BookingSlot.dayLabel(d)}${time != null && time.isNotEmpty ? ', $time' : ''}',
                  style: TextStyle(color: textColor ?? accent, fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(mode, style: TextStyle(color: (textColor ?? accent).withOpacity(0.75), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
