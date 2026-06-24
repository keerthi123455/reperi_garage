import 'package:flutter/foundation.dart';
import 'payment_service.dart';
import 'payment_services_web.dart';

PaymentService getPaymentService() {
  if (kIsWeb) {
    return PaymentServiceWeb();
  } else {
    throw UnimplementedError(
      'Mobile payment service not yet implemented. Coming when we build the Android/iOS app.',
    );
  }
}