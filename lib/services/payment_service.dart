abstract class PaymentService {
  Future<PaymentResult> openCheckout({
    required String orderId,
    required String keyId,
    required int amountInPaise,
    required String name,
    required String email,
    required String contact,
  });
}

class PaymentResult {
  final bool success;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorMessage;

  PaymentResult({
    required this.success,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorMessage,
  });
}