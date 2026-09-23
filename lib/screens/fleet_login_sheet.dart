import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fleet_order_sheet.dart';
import 'fleet_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        backgroundColor: const Color(0xFF262626),
        title: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
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
        backgroundColor: const Color(0xFF262626),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            onPressed: () {
              Navigator.pop(context);
              onClose();
            },
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
  void _showForgotPasswordDialog() {
    final emailController = TextEditingController();
    final usernameController = TextEditingController();
    final otpController = TextEditingController();
    final passwordController = TextEditingController();

    // A throwaway client, isolated from Supabase.instance.client. The OTP
    // dance below (signInWithOtp/verifyOTP) sets whatever client runs it
    // as "logged in" — running it on the app-wide client would silently
    // replace/destroy a real customer's session if one was active on this
    // device. This client's session lives only in memory and is disposed
    // when the dialog closes, so it can never touch the customer-facing
    // auth state.
    final otpClient = SupabaseClient(
      _supabaseUrl,
      _supabaseAnonKey,
      // PKCE (the default flow) needs a persistent storage backend to hold
      // a code verifier across steps — this client never persists
      // anything and never survives a redirect, so implicit flow (which
      // doesn't need that storage) is the right fit here.
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );

    InputDecoration fieldDecoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF3A3A3A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
        );

    Widget fieldLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        int step = 0; // 0 = enter email/username, 1 = enter code + new password

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendCode() async {
              final email = emailController.text.trim();
              final username = usernameController.text.trim();

              if (email.isEmpty || username.isEmpty) {
                _showErrorDialog('Missing Fields', 'Email and username are required.');
                return;
              }

              setDialogState(() => isLoading = true);
              try {
                final verify = await Supabase.instance.client.functions.invoke(
                  'fleet-verify-identity',
                  body: {'email': email, 'username': username},
                );
                final verifyData = verify.data as Map<String, dynamic>?;

                if (verifyData?['valid'] != true) {
                  if (!context.mounted) return;
                  setDialogState(() => isLoading = false);
                  _showErrorDialog(
                    'No Match Found',
                    'Email and username do not match our records. Please verify and try again.',
                  );
                  return;
                }

                await otpClient.auth.signInWithOtp(
                  email: email,
                  shouldCreateUser: true,
                );

                if (!context.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  step = 1;
                });
              } catch (e) {
                if (!context.mounted) return;
                setDialogState(() => isLoading = false);
                ErrorDisplay.showPremiumError(
                  context,
                  error: e,
                  customMessage: 'Could not send your verification code. Please try again.',
                );
              }
            }

            Future<void> confirmReset() async {
              final email = emailController.text.trim();
              final username = usernameController.text.trim();
              final code = otpController.text.trim();
              final newPassword = passwordController.text.trim();

              if (code.isEmpty || newPassword.isEmpty) {
                _showErrorDialog('Missing Fields', 'Enter the code and a new password.');
                return;
              }
              if (newPassword.length < 6) {
                _showErrorDialog('Weak Password', 'Password must be at least 6 characters long.');
                return;
              }

              setDialogState(() => isLoading = true);
              try {
                final verifyResponse = await otpClient.auth.verifyOTP(
                  email: email,
                  token: code,
                  type: OtpType.email,
                );

                final accessToken = verifyResponse.session?.accessToken;
                if (accessToken == null) {
                  throw Exception('No session returned for that code');
                }

                // Passed explicitly rather than relying on the app-wide
                // client's current session — that session was never
                // touched by this flow in the first place (see otpClient
                // above), so it wouldn't have this OTP session anyway.
                final reset = await Supabase.instance.client.functions.invoke(
                  'fleet-reset-password',
                  body: {'username': username, 'newPassword': newPassword},
                  headers: {'Authorization': 'Bearer $accessToken'},
                );

                final resetData = reset.data as Map<String, dynamic>?;
                if (!context.mounted) return;

                if (resetData?['success'] == true) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context);
                  _showSuccessDialog(
                    'Password Reset',
                    'Password reset successfully! Please login with your new password.',
                    () {},
                  );
                } else {
                  setDialogState(() => isLoading = false);
                  _showErrorDialog(
                    'Reset Failed',
                    'Could not reset password. Please try again or contact support.',
                  );
                }
              } catch (e) {
                if (!context.mounted) return;
                setDialogState(() => isLoading = false);
                ErrorDisplay.showPremiumError(
                  context,
                  error: e,
                  customMessage: 'That code is invalid or has expired. Please try again.',
                );
              }
            }

            return AlertDialog(
              title: const Text('Reset Password'),
              backgroundColor: const Color(0xFF262626),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: step == 0
                      ? [
                          fieldLabel('Email registered with Reperi'),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('your@email.com'),
                          ),
                          const SizedBox(height: 16),
                          fieldLabel('Username registered with Reperi'),
                          TextField(
                            controller: usernameController,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('your_username'),
                          ),
                        ]
                      : [
                          Text(
                            'We sent a 6-digit code to ${emailController.text.trim()}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          fieldLabel('Verification Code'),
                          TextField(
                            controller: otpController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('123456'),
                          ),
                          const SizedBox(height: 16),
                          fieldLabel('New Password'),
                          TextField(
                            controller: passwordController,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('Enter new password'),
                          ),
                        ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          // Dropping focus before popping avoids a rare
                          // Flutter crash ('_dependents.isEmpty' assertion)
                          // that can fire if this dialog's TextField still
                          // has focus (and the keyboard is mid-animation)
                          // when its route gets torn down.
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(context);
                        },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFD4A017)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                  ),
                  onPressed: isLoading ? null : (step == 0 ? sendCode : confirmReset),
                  child: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : Text(
                          step == 0 ? 'Send Code' : 'Reset Password',
                          style: const TextStyle(color: Colors.black),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => otpClient.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Icon + Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: Color(0xFFD4A017),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fleet Login',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Manage your vehicle fleet',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                _label('Username'),
                const SizedBox(height: 8),

                _field(
                  controller: _usernameController,
                  hint: 'Enter username',
                  icon: Icons.person_rounded,
                ),

                const SizedBox(height: 20),

                _label('Password'),
                const SizedBox(height: 8),

                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF3A3A3A),
                    ),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Enter password',
                      hintStyle: TextStyle(
                        color: Colors.white54,
                      ),
                      prefixIcon: Icon(
                        Icons.lock_rounded,
                        color: Color(0xFFD4A017),
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Forgot Password Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _loading
                        ? null
                        : () async {
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
                          },
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'LOGIN',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1.2,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Note
                const Center(
                  child: Text(
                    'Authorized Fleet Access Only',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: Icon(icon, color: const Color(0xFFD4A017), size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}