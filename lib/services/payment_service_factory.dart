import 'payment_service.dart';
import 'payment_services_web.dart'
    if (dart.library.io) 'payment_service_mobile.dart';

PaymentService getPaymentService() {
  return createPaymentService();
}