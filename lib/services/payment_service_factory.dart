import 'payment_service.dart';
import 'payment_service_stub.dart'
    if (dart.library.js_interop) 'payment_services_web.dart'
    if (dart.library.io) 'payment_service_mobile.dart';

PaymentService getPaymentService() {
  return createPaymentService();
}