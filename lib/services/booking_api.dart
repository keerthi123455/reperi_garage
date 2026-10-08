import 'package:supabase_flutter/supabase_flutter.dart';

/// Client for the `booking-api` Edge Function — the server prices every
/// booking from the `services` table, creates the Razorpay order for that
/// exact amount, and after payment creates the booking and assigns the
/// garage / delivery partner / washer. The app never sends a price.
class BookingApi {
  BookingApi._();

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('booking-api', body: body)
          .timeout(const Duration(seconds: 30));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const BookingApiException('unexpected', 'Unexpected response from the server.');
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        throw BookingApiException(
          (details['error'] ?? 'error').toString(),
          (details['message'] ?? 'Something went wrong. Please try again.').toString(),
          status: e.status,
          intentId: details['intent_id']?.toString(),
          paymentId: details['payment_id']?.toString(),
        );
      }
      throw BookingApiException('error', 'Something went wrong. Please try again.', status: e.status);
    }
  }

  /// Price breakdown for [items] (service keys) — what the payment screen shows.
  static Future<BookingQuote> quote({
    required List<String> items,
    bool pickupDrop = false,
    String? fleetRequestId,
  }) async {
    final data = await _call({
      'action': 'quote',
      if (fleetRequestId != null) 'fleet_request_id': fleetRequestId else 'items': items,
      'pickup_drop': pickupDrop,
    });
    return BookingQuote.fromJson(data);
  }

  /// Starts a checkout. Online: returns the Razorpay order to open.
  /// Cash: the booking is created immediately ([CreateResult.booked]).
  static Future<CreateResult> create({
    required List<String> items,
    required bool cash,
    bool pickupDrop = false,
    String vehicleId = '',
    Map<String, dynamic> options = const {},
    String? fleetRequestId,
  }) async {
    final data = await _call({
      'action': 'create',
      if (fleetRequestId != null) 'fleet_request_id': fleetRequestId else 'items': items,
      'pickup_drop': pickupDrop,
      'payment_method': cash ? 'cod' : 'online',
      if (vehicleId.isNotEmpty) 'vehicle_id': vehicleId,
      'options': options,
    });
    return CreateResult.fromJson(data);
  }

  /// After Razorpay checkout succeeds: verifies the payment and creates the
  /// booking. Safe to call again with the same values if it fails — the
  /// customer is never charged twice.
  static Future<BookingResult> confirm({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final data = await _call({
      'action': 'confirm',
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
    return BookingResult.fromJson(data);
  }

  /// Where a checkout stands (and retries a failed save server-side).
  static Future<BookingResult> status(String intentId) async {
    final data = await _call({'action': 'status', 'intent_id': intentId});
    return BookingResult.fromJson(data);
  }
}

class BookingApiException implements Exception {
  const BookingApiException(this.code, this.message, {this.status, this.intentId, this.paymentId});

  final String code;
  final String message;
  final int? status;
  final String? intentId;
  final String? paymentId;

  /// The customer has paid but the booking isn't saved yet — retrying is safe.
  bool get paidButNotSaved => code == 'booking_save_failed' && paymentId != null;

  @override
  String toString() => message;
}

class QuoteLine {
  const QuoteLine(this.name, this.amount, this.display);
  final String name;
  final int amount;
  final String display;
}

class BookingQuote {
  const BookingQuote({
    required this.lines,
    required this.subtotal,
    required this.pickupMode,
    required this.pickupFee,
    required this.pickupDrop,
    required this.pickupFeeCharged,
    required this.total,
    required this.totalDisplay,
    required this.allowCod,
    required this.bookingName,
  });

  final List<QuoteLine> lines;
  final int subtotal;
  final String pickupMode; // optional | none | included | locked
  final int pickupFee;
  final bool pickupDrop;
  final int pickupFeeCharged;
  final int total;
  final String totalDisplay;
  final bool allowCod;
  final String bookingName;

  bool get showsPickupCard => pickupMode == 'optional' || pickupMode == 'locked';
  bool get pickupLocked => pickupMode == 'locked';

  static int _int(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

  factory BookingQuote.fromJson(Map<String, dynamic> j) => BookingQuote(
        lines: (j['lines'] as List? ?? const [])
            .whereType<Map>()
            .map((l) => QuoteLine(
                  (l['name'] ?? '').toString(),
                  _int(l['amount']),
                  (l['display'] ?? '').toString(),
                ))
            .toList(),
        subtotal: _int(j['subtotal']),
        pickupMode: (j['pickup_mode'] ?? 'none').toString(),
        pickupFee: _int(j['pickup_fee']),
        pickupDrop: j['pickup_drop'] == true,
        pickupFeeCharged: _int(j['pickup_fee_charged']),
        total: _int(j['total']),
        totalDisplay: (j['total_display'] ?? '').toString(),
        allowCod: j['allow_cod'] == true,
        bookingName: (j['booking_name'] ?? '').toString(),
      );
}

class CreateResult {
  const CreateResult({
    required this.intentId,
    this.orderId,
    this.keyId,
    this.amountPaise,
    this.booked = false,
    this.bookingTable,
  });

  final String intentId;
  final String? orderId;
  final String? keyId;
  final int? amountPaise;
  final bool booked;
  final String? bookingTable;

  factory CreateResult.fromJson(Map<String, dynamic> j) => CreateResult(
        intentId: (j['intent_id'] ?? '').toString(),
        orderId: j['order_id']?.toString(),
        keyId: j['key_id']?.toString(),
        amountPaise: j['amount_paise'] is num ? (j['amount_paise'] as num).round() : null,
        booked: j['status'] == 'booked',
        bookingTable: j['booking_table']?.toString(),
      );
}

class BookingResult {
  const BookingResult({required this.booked, this.bookingTable, this.bookingId, this.intentId});

  final bool booked; // false = still being finished (webhook / retry)
  final String? bookingTable;
  final String? bookingId;
  final String? intentId;

  factory BookingResult.fromJson(Map<String, dynamic> j) => BookingResult(
        booked: j['status'] == 'booked',
        bookingTable: j['booking_table']?.toString(),
        bookingId: j['booking_id']?.toString(),
        intentId: j['intent_id']?.toString(),
      );
}
