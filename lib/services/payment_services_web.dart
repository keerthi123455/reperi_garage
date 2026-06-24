import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'payment_service.dart';
import 'dart:js_interop_unsafe';

@JS('eval')
external void _jsEval(String code);

@JS('openRazorpayCheckout')
external void _openRazorpayCheckout(
  JSObject options,
  JSFunction onSuccess,
  JSFunction onFailure,
);

class PaymentServiceWeb implements PaymentService {
  PaymentServiceWeb() {
    _injectHelper();
  }

  void _injectHelper() {
    _jsEval('''
      window.openRazorpayCheckout = function(options, onSuccess, onFailure) {
        var rzp = new Razorpay({
          key: options.key,
          amount: options.amount,
          currency: options.currency,
          order_id: options.order_id,
          name: "Reperi",
          description: options.description,
          prefill: {
            name: options.name,
            email: options.email,
            contact: options.contact
          },
          theme: {
            color: "#D4A017"
          },
          handler: function (response) {
            onSuccess(JSON.stringify({
              razorpay_payment_id: response.razorpay_payment_id,
              razorpay_order_id: response.razorpay_order_id,
              razorpay_signature: response.razorpay_signature
            }));
          },
          modal: {
            ondismiss: function () {
              onFailure("Payment cancelled by user");
            }
          }
        });
        rzp.on('payment.failed', function (response) {
          onFailure(response.error.description || "Payment failed");
        });
        rzp.open();
      };
    ''');
  }

  @override
  Future<PaymentResult> openCheckout({
    required String orderId,
    required String keyId,
    required int amountInPaise,
    required String name,
    required String email,
    required String contact,
  }) async {
    final completer = Completer<PaymentResult>();

    final onSuccess = (JSString resultJson) {
      final Map<String, dynamic> data = jsonDecode(resultJson.toDart);
      completer.complete(PaymentResult(
        success: true,
        paymentId: data['razorpay_payment_id'] as String?,
        orderId: data['razorpay_order_id'] as String?,
        signature: data['razorpay_signature'] as String?,
      ));
    }.toJS;

    final onFailure = (JSString errorMsg) {
      completer.complete(PaymentResult(
        success: false,
        errorMessage: errorMsg.toDart,
      ));
    }.toJS;

    final options = JSObject()
      ..setProperty('key'.toJS, keyId.toJS)
      ..setProperty('amount'.toJS, amountInPaise.toJS)
      ..setProperty('currency'.toJS, 'INR'.toJS)
      ..setProperty('order_id'.toJS, orderId.toJS)
      ..setProperty('description'.toJS, 'Reperi Service Booking'.toJS)
      ..setProperty('name'.toJS, name.toJS)
      ..setProperty('email'.toJS, email.toJS)
      ..setProperty('contact'.toJS, contact.toJS);

    _openRazorpayCheckout(options, onSuccess, onFailure);

    return completer.future;
  }
}