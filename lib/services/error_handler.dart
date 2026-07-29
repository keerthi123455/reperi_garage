/// Error Handler Utility
/// Maps technical errors to user-friendly, clear messages
/// Used throughout the app for consistent error handling

class ErrorHandler {
  /// Maps exception to a user-friendly error message
  static String getUserMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    // ── Authentication Errors ──
    if (errorString.contains('invalid login credentials')) {
      return 'Email or password is incorrect. Please try again.';
    }
    if (errorString.contains('user not found')) {
      return 'No account found with this email. Please sign up.';
    }
    if (errorString.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    if (errorString.contains('weak password')) {
      return 'Password must be at least 6 characters long.';
    }
    if (errorString.contains('email already exists')) {
      return 'This email is already registered. Please log in or use a different email.';
    }
    if (errorString.contains('email already in use')) {
      return 'This email is already registered. Please log in or use a different email.';
    }
    if (errorString.contains('password_confirmation_mismatch')) {
      return 'Passwords do not match. Please try again.';
    }
    if (errorString.contains('unauthorized')) {
      return 'Your session has expired. Please log in again.';
    }
    if (errorString.contains('jwt expired')) {
      return 'Your session has expired. Please log in again.';
    }

    // ── Vehicle/Profile Errors ──
    if (errorString.contains('vehicle')) {
      if (errorString.contains('not found')) {
        return 'Vehicle not found. Please add a vehicle first.';
      }
      return 'Failed to update vehicle information. Please try again.';
    }
    if (errorString.contains('profile')) {
      return 'Failed to update your profile. Please try again.';
    }

    // ── Database/Network Errors ──
    if (errorString.contains('failed host lookup') ||
        errorString.contains('network is unreachable')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (errorString.contains('connection refused') ||
        errorString.contains('connection reset')) {
      return 'Connection failed. Please check your internet and try again.';
    }
    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    }
    if (errorString.contains('database')) {
      return 'Database error. Please try again in a moment.';
    }

    // ── Payment Errors ──
    if (errorString.contains('payment')) {
      if (errorString.contains('declined') || errorString.contains('failed')) {
        return 'Payment failed. Please check your card details and try again.';
      }
      if (errorString.contains('invalid')) {
        return 'Invalid payment details. Please check and try again.';
      }
      return 'Payment processing failed. Please try again or contact support.';
    }
    if (errorString.contains('razorpay')) {
      return 'Payment gateway error. Please try again in a moment.';
    }

    // ── File Upload Errors ──
    if (errorString.contains('file') || errorString.contains('upload')) {
      if (errorString.contains('size')) {
        return 'File size is too large. Please choose a smaller file.';
      }
      if (errorString.contains('format')) {
        return 'Invalid file format. Please choose a supported format.';
      }
      return 'Failed to upload file. Please try again.';
    }

    // ── Booking/Service Errors ──
    if (errorString.contains('booking')) {
      if (errorString.contains('not found')) {
        return 'Booking not found. Please refresh and try again.';
      }
      if (errorString.contains('cancelled')) {
        return 'This booking has been cancelled. Please create a new one.';
      }
      return 'Failed to process your booking. Please try again.';
    }
    if (errorString.contains('service')) {
      return 'Failed to load services. Please try again.';
    }

    // ── Notification Errors ──
    if (errorString.contains('notification')) {
      return 'Failed to send notification. Please try again.';
    }

    // ── Permission Errors ──
    if (errorString.contains('permission') || errorString.contains('forbidden')) {
      return 'You do not have permission to perform this action.';
    }
    if (errorString.contains('not authorized')) {
      return 'Authorization failed. Please log in again.';
    }

    // ── Validation Errors ──
    if (errorString.contains('validation')) {
      return 'Please fill in all required fields correctly.';
    }
    if (errorString.contains('required')) {
      return 'Please fill in all required fields.';
    }

    // ── Server Errors ──
    if (errorString.contains('500') || errorString.contains('internal server')) {
      return 'Server error. Please try again in a moment.';
    }
    if (errorString.contains('503') || errorString.contains('service unavailable')) {
      return 'Service temporarily unavailable. Please try again later.';
    }
    if (errorString.contains('404') || errorString.contains('not found')) {
      return 'The requested resource was not found. Please try again.';
    }
    if (errorString.contains('400') || errorString.contains('bad request')) {
      return 'Invalid request. Please check your input and try again.';
    }

    // ── Default fallback ──
    return 'Something went wrong. Please try again or contact support if the problem persists.';
  }

  /// Get error icon based on error type
  static String getErrorIcon(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('connection')) {
      return '📡'; // No connection
    }
    if (errorString.contains('auth') || errorString.contains('password')) {
      return '🔐'; // Lock
    }
    if (errorString.contains('payment')) {
      return '💳'; // Card
    }
    if (errorString.contains('upload') || errorString.contains('file')) {
      return '📁'; // Folder
    }
    if (errorString.contains('booking') || errorString.contains('service')) {
      return '🚗'; // Car
    }
    if (errorString.contains('permission')) {
      return '⛔'; // Blocked
    }

    return '⚠️'; // Generic warning
  }

  /// Check if error is a network error
  static bool isNetworkError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('socket');
  }

  /// Check if error is an auth error
  static bool isAuthError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('auth') ||
        errorString.contains('unauthorized') ||
        errorString.contains('jwt');
  }

  /// Check if error is a validation error
  static bool isValidationError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('validation') ||
        errorString.contains('required') ||
        errorString.contains('invalid');
  }
}
