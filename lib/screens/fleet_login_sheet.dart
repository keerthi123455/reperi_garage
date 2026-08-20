import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fleet_order_sheet.dart';
import 'fleet_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
                    onPressed: () {
                      final emailController = TextEditingController();
                      final usernameController = TextEditingController();
                      final passwordController = TextEditingController();

                      showDialog(
                        context: context,
                        builder: (context) {
                          bool isLoading = false;

                          return StatefulBuilder(
                            builder: (context, setDialogState) {
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
                                    children: [
                                      // Email field
                                      const Text(
                                        'Email registered with Reperi',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: emailController,
                                        keyboardType: TextInputType.emailAddress,
                                        style: const TextStyle(color: Colors.white),
                                        enabled: !isLoading,
                                        decoration: InputDecoration(
                                          hintText: 'your@email.com',
                                          hintStyle: const TextStyle(color: Colors.white54),
                                          filled: true,
                                          fillColor: const Color(0xFF3A3A3A),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF333333)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Username field
                                      const Text(
                                        'Username registered with Reperi',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: usernameController,
                                        style: const TextStyle(color: Colors.white),
                                        enabled: !isLoading,
                                        decoration: InputDecoration(
                                          hintText: 'your_username',
                                          hintStyle: const TextStyle(color: Colors.white54),
                                          filled: true,
                                          fillColor: const Color(0xFF3A3A3A),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF333333)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // New password field
                                      const Text(
                                        'New Password',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: passwordController,
                                        obscureText: true,
                                        style: const TextStyle(color: Colors.white),
                                        enabled: !isLoading,
                                        decoration: InputDecoration(
                                          hintText: 'Enter new password',
                                          hintStyle: const TextStyle(color: Colors.white54),
                                          filled: true,
                                          fillColor: const Color(0xFF3A3A3A),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF333333)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: isLoading ? null : () => Navigator.pop(context),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(color: Color(0xFFD4A017)),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD4A017),
                                    ),
                                    onPressed: isLoading
                                        ? null
                                        : () async {
                                            setDialogState(() => isLoading = true);

                                            try {
                                              final email = emailController.text.trim();
                                              final username = usernameController.text.trim();
                                              final newPassword = passwordController.text.trim();

                                              // Validate email
                                              if (email.isEmpty) {
                                                if (!context.mounted) return;
                                                Navigator.pop(context);
                                                _showErrorDialog(
                                                  'Empty Email',
                                                  'Please enter your registered email address.',
                                                );
                                                return;
                                              }

                                              // Validate username
                                              if (username.isEmpty) {
                                                if (!context.mounted) return;
                                                Navigator.pop(context);
                                                _showErrorDialog(
                                                  'Empty Username',
                                                  'Please enter your registered username.',
                                                );
                                                return;
                                              }

                                              // Validate password
                                              if (newPassword.isEmpty) {
                                                if (!context.mounted) return;
                                                Navigator.pop(context);
                                                _showErrorDialog(
                                                  'Empty Password',
                                                  'Please enter a new password.',
                                                );
                                                return;
                                              }

                                              if (newPassword.length < 6) {
                                                if (!context.mounted) return;
                                                Navigator.pop(context);
                                                _showErrorDialog(
                                                  'Weak Password',
                                                  'Password must be at least 6 characters long.',
                                                );
                                                return;
                                              }

                                              // Find fleet user with matching email AND username
                                              final response = await Supabase.instance.client
                                                  .from('fleet_users')
                                                  .select()
                                                  .eq('email', email)
                                                  .eq('username', username)
                                                  .maybeSingle();

                                              if (!context.mounted) return;

                                              if (response == null) {
                                                // Email and username don't match
                                                Navigator.pop(context);
                                                _showErrorDialog(
                                                  'No Match Found',
                                                  'Email and username do not match our records. Please verify and try again.',
                                                );
                                                return;
                                              }

                                              // Update password
                                              await Supabase.instance.client
                                                  .from('fleet_users')
                                                  .update({'password': newPassword})
                                                  .eq('id', response['id']);

                                              if (!context.mounted) return;

                                              Navigator.pop(context);

                                              _showSuccessDialog(
                                                'Password Reset',
                                                'Password reset successfully! Please login with your new password.',
                                                () {},
                                              );
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              Navigator.pop(context);
                                              _showErrorDialog(
                                                'Reset Failed',
                                                'Error resetting password: $e',
                                              );
                                            }
                                          },
                                    child: isLoading
                                        ? const SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(Colors.black),
                                            ),
                                          )
                                        : const Text(
                                            'Reset Password',
                                            style: TextStyle(color: Colors.black),
                                          ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
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

                              final fleetUser = await Supabase.instance.client
                                  .from('fleet_users')
                                  .select()
                                  .ilike(
                                    'username',
                                    username,
                                  )
                                  .eq(
                                    'password',
                                    password,
                                  )
                                  .maybeSingle();

                              if (!mounted) return;

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
                              _showErrorDialog(
                                'Error',
                                'An error occurred: ${e.toString()}',
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