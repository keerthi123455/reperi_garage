import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fleet_order_sheet.dart';
import 'fleet_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/fleet_theme.dart';
import '../widgets/error_display.dart';

// Same project URL/anon key as Supabase.initialize() in main.dart — used
// to spin up a throwaway SupabaseClient for the fleet OTP reset flow
// below (see the comment on _showForgotPasswordDialog for why it can't
// reuse the app-wide Supabase.instance.client).
const String _supabaseUrl = 'https://rmvxqjyoqfinbrpubsvp.supabase.co';
const String _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtdnhxanlvcWZpbmJycHVic3ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQyNDcsImV4cCI6MjA5MjgxMDI0N30.NAxb2XnicLSaBoA4kpTFmmutT68Z2ksu-T-P_NUxy5E';

class FleetLoginSheet extends StatefulWidget {
  const FleetLoginSheet({super.key});

  @override
  State<FleetLoginSheet> createState() => _FleetLoginSheetState();
}

class _FleetLoginSheetState extends State<FleetLoginSheet> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper method to show error dialog
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: F.card,
        surfaceTintColor: F.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_rounded, color: F.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: F.txt,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: F.mut,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: F.yellow,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: F.navy, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to show success dialog
  void _showSuccessDialog(String title, String message, VoidCallback onClose) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: F.card,
        surfaceTintColor: F.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: F.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: F.txt,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: F.mut,
            fontSize: 16,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: F.greenSolid,
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              onClose();
            },
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Fleet "forgot password" — same two-step, email-verified reset as the
  // garage/admin login (login_screen.dart). Step 0 confirms the
  // email+username pair is a real fleet account (fleet-verify-identity,
  // which never exposes the password column) and sends a one-time code to
  // that email via Supabase Auth's email-OTP delivery. Step 1 verifies
  // that code — proving the requester owns the inbox — and only then
  // calls fleet-reset-password, which hashes the new password
  // server-side.
  //
  // FIX: the popup is now its own StatefulWidget
  // ([_FleetForgotPasswordDialog]) — same fix as login_screen.dart's
  // garage/client reset popups. The old inline showDialog+StatefulBuilder
  // version unfocused the keyboard right before Navigator.pop and never
  // disposed its controllers, which is what causes the
  // "'_dependents.isEmpty': is not true" red screen. The success dialog
  // is now shown from here, with this sheet's own live context.
  Future<void> _showForgotPasswordDialog() async {
    final didReset = await showDialog<bool>(
      context: context,
      builder: (_) => _FleetForgotPasswordDialog(onError: _showErrorDialog),
    );

    if (didReset == true && mounted) {
      _showSuccessDialog(
        'Password Reset',
        'Password reset successfully! Please login with your new password.',
        () {},
      );
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
    });

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      // Validate fields not empty
      if (username.isEmpty || password.isEmpty) {
        setState(() {
          _loading = false;
        });
        _showErrorDialog(
          'Missing Fields',
          'Please enter both username and password.',
        );
        return;
      }

      // Verified server-side against a bcrypt hash so
      // the password never travels as a plain-text
      // table filter.
      final result = await Supabase.instance.client
          .functions
          .invoke(
        'fleet-login',
        body: {
          'username': username,
          'password': password,
        },
      );

      if (!mounted) return;

      final data = result.data as Map<String, dynamic>?;
      final fleetUser = data?['success'] == true
          ? data!['fleetUser'] as Map<String, dynamic>
          : null;

      if (fleetUser != null) {
        // Success - Login successful
        final prefs = await SharedPreferences.getInstance();

        await prefs.setBool('fleet_logged_in', true);
        await prefs.setString('fleet_company', fleetUser['company_name'] ?? 'N/A');
        await prefs.setString('fleet_username', fleetUser['username']);
        await prefs.setString('fleet_user_id', fleetUser['id'].toString());

        if (!mounted) return;

        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FleetDashboardScreen(
              fleetUser: fleetUser,
            ),
          ),
        );
      } else {
        // Error - Invalid credentials
        setState(() {
          _loading = false;
        });
        _showErrorDialog(
          'Login Failed',
          'Invalid username or password. Please try again.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage:
            'Could not log in. Please check your username and password and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: F.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(color: F.line, borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(color: F.yellow, shape: BoxShape.circle),
                            child: const Icon(Icons.local_shipping_rounded, color: F.navy, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fleet login',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: F.txt, fontSize: 28, fontWeight: FontWeight.w900)),
                                Text('Request pickups and track every vehicle',
                                    style: TextStyle(color: F.mut, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      _label('USERNAME'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _usernameController,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        cursorColor: F.accent,
                        style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w700),
                        decoration: F.input('Enter username',
                            prefixIcon: Icon(Icons.person_rounded, color: F.accent, size: 24)),
                      ),
                      const SizedBox(height: 18),
                      _label('PASSWORD'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_loading) _login();
                        },
                        cursorColor: F.accent,
                        style: TextStyle(color: F.txt, fontSize: 18, fontWeight: FontWeight.w700),
                        decoration: F.input(
                          'Enter password',
                          prefixIcon: Icon(Icons.lock_rounded, color: F.accent, size: 24),
                          suffixIcon: IconButton(
                            tooltip: _showPassword ? 'Hide password' : 'Show password',
                            icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: F.mut),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 60,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: F.yellow,
                            foregroundColor: F.navy,
                            disabledBackgroundColor: F.yellow.withOpacity(0.6),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: F.navy, strokeWidth: 2.6),
                                )
                              : const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('LOG IN',
                                      maxLines: 1,
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 0.6)),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: Text('Forgot password?',
                              style: TextStyle(color: F.accent, fontSize: 16.5, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_user_rounded, color: F.mut, size: 17),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Only for registered fleet partners',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: F.mut, fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        color: F.mut,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Fleet forgot-password popup — same logic and look as before, moved into
/// its own StatefulWidget so its controllers, throwaway client and
/// keyboard-dismiss are cleaned up in dispose(), which runs strictly after
/// the route has been fully removed (nothing left to race).
class _FleetForgotPasswordDialog extends StatefulWidget {
  const _FleetForgotPasswordDialog({required this.onError});

  /// The sheet's own _showErrorDialog — kept so validation/"no match"
  /// errors look exactly the same as before.
  final void Function(String title, String message) onError;

  @override
  State<_FleetForgotPasswordDialog> createState() =>
      _FleetForgotPasswordDialogState();
}

class _FleetForgotPasswordDialogState
    extends State<_FleetForgotPasswordDialog> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();

  // A throwaway client, isolated from Supabase.instance.client. The OTP
  // dance below (signInWithOtp/verifyOTP) sets whatever client runs it
  // as "logged in" — running it on the app-wide client would silently
  // replace/destroy a real customer's session if one was active on this
  // device. This client's session lives only in memory and is disposed
  // with this dialog, so it can never touch the customer-facing auth
  // state.
  late final _otpClient = SupabaseClient(
    _supabaseUrl,
    _supabaseAnonKey,
    // PKCE (the default flow) needs a persistent storage backend to hold
    // a code verifier across steps — this client never persists
    // anything and never survives a redirect, so implicit flow (which
    // doesn't need that storage) is the right fit here.
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  bool _isLoading = false;
  int _step = 0; // 0 = enter email/username, 1 = enter code + new password

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _emailController.dispose();
    _usernameController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _otpClient.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: F.faint),
        filled: true,
        fillColor: F.sunken,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: F.line),
        ),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: F.mut,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || username.isEmpty) {
      widget.onError('Missing Fields', 'Email and username are required.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final verify = await Supabase.instance.client.functions.invoke(
        'fleet-verify-identity',
        body: {'email': email, 'username': username},
      );
      final verifyData = verify.data as Map<String, dynamic>?;

      if (verifyData?['valid'] != true) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        widget.onError(
          'No Match Found',
          'Email and username do not match our records. Please verify and try again.',
        );
        return;
      }

      await _otpClient.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not send your verification code. Please try again.',
      );
    }
  }

  Future<void> _confirmReset() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final code = _otpController.text.trim();
    final newPassword = _passwordController.text.trim();

    if (code.isEmpty || newPassword.isEmpty) {
      widget.onError('Missing Fields', 'Enter the code and a new password.');
      return;
    }
    if (newPassword.length < 6) {
      widget.onError('Weak Password', 'Password must be at least 6 characters long.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final verifyResponse = await _otpClient.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

      final accessToken = verifyResponse.session?.accessToken;
      if (accessToken == null) {
        throw Exception('No session returned for that code');
      }

      // Passed explicitly rather than relying on the app-wide client's
      // current session — that session was never touched by this flow in
      // the first place (see _otpClient above).
      final reset = await Supabase.instance.client.functions.invoke(
        'fleet-reset-password',
        body: {'username': username, 'newPassword': newPassword},
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final resetData = reset.data as Map<String, dynamic>?;
      if (!mounted) return;

      if (resetData?['success'] == true) {
        // Success dialog is shown by FleetLoginSheet._showForgotPasswordDialog.
        Navigator.pop(context, true);
      } else {
        setState(() => _isLoading = false);
        widget.onError(
          'Reset Failed',
          'Could not reset password. Please try again or contact support.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'That code is invalid or has expired. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Password'),
      backgroundColor: F.card,
      surfaceTintColor: F.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        color: F.txt,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _step == 0
              ? [
                  _fieldLabel('Email registered with Reperi'),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: F.txt, fontSize: 17, fontWeight: FontWeight.w600),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('your@email.com'),
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('Username registered with Reperi'),
                  TextField(
                    controller: _usernameController,
                    style: TextStyle(color: F.txt, fontSize: 17, fontWeight: FontWeight.w600),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('your_username'),
                  ),
                ]
              : [
                  Text(
                    'We sent a 6-digit code to ${_emailController.text.trim()}',
                    style: TextStyle(color: F.mut, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('Verification Code'),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: F.txt, fontSize: 17, fontWeight: FontWeight.w600),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('123456'),
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('New Password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(color: F.txt, fontSize: 17, fontWeight: FontWeight.w600),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('Enter new password'),
                  ),
                ],
        ),
      ),
      actions: [
        TextButton(
          // Keyboard dismiss now happens in dispose(), not here — doing it
          // right before pop is what raced the route teardown.
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: F.accent, fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.yellow,
            elevation: 0,
          ),
          onPressed: _isLoading ? null : (_step == 0 ? _sendCode : _confirmReset),
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(F.navy),
                  ),
                )
              : Text(
                  _step == 0 ? 'Send Code' : 'Reset Password',
                  style: const TextStyle(color: F.navy, fontWeight: FontWeight.w900, fontSize: 16),
                ),
        ),
      ],
    );
  }
}
