import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'payment_service.dart';

PaymentService createPaymentService() => PaymentServiceMobile();

class PaymentServiceMobile implements PaymentService {
  Razorpay? _razorpay;
  Completer<PaymentResult>? _completer;

  @override
  Future<PaymentResult> openCheckout({
    required String orderId,
    required String keyId,
    required int amountInPaise,
    required String name,
    required String email,
    required String contact,
  }) async {
    _completer = Completer<PaymentResult>();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    final options = {
      'key': keyId,
      'amount': amountInPaise,
      'currency': 'INR',
      'order_id': orderId,
      'name': 'Reperi',
      'description': 'Reperi Service Booking',
      'prefill': {
        'contact': contact,
        'email': email,
      },
      'theme': {
        'color': '#D4A017',
      },
    };
    try {
      _razorpay!.open(options);
    } catch (e) {
      _completer!.complete(PaymentResult(
        success: false,
        errorMessage: 'Failed to open checkout: $e',
      ));
    }
    final result = await _completer!.future;
    _dispose();
    return result;
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(PaymentResult(
        success: true,
        paymentId: response.paymentId,
        orderId: response.orderId,
        signature: response.signature,
      ));
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(PaymentResult(
        success: false,
        errorMessage: response.message ?? 'Payment failed',
      ));
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(PaymentResult(
        success: false,
        errorMessage: 'External wallet selected: ${response.walletName}',
      ));
    }
  }

  void _dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}