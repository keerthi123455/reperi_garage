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
  final _companyController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _companyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
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
                _label('Company Name'),
                const SizedBox(height: 8),

                _field(
                  controller: _companyController,
                  hint: 'Company Name',
                  icon: Icons.business_rounded,
                ),

                const SizedBox(height: 20),

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
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF2A2A2A),
                    ),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Enter password',
                      hintStyle: TextStyle(
                        color: Color(0xFF444444),
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
                              final fleetUser = await Supabase.instance.client
                                  .from('fleet_users')
                                  .select()
                                  .ilike(
                                    'company_name',
                                    _companyController.text.trim(),
                                  )
                                  .ilike(
                                    'username',
                                    _usernameController.text.trim(),
                                  )
                                  .eq(
                                    'password',
                                    _passwordController.text.trim(),
                                  )
                                  .maybeSingle();

                              if (!mounted) return;

                              if (fleetUser != null) {

      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setBool(
        'fleet_logged_in',
        true,
      );

      await prefs.setString(
        'fleet_company',
        fleetUser['company_name'],
      );

      await prefs.setString(
        'fleet_username',
        fleetUser['username'],
      );

      await prefs.setString(
        'fleet_user_id',
        fleetUser['id'].toString(),
      );

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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid Company, Username or Password',
          ),
          backgroundColor: Colors.red,
        ),
      );

    }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _loading = false;
                                });
                              }
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF444444)),
          prefixIcon: Icon(icon, color: const Color(0xFFD4A017), size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}