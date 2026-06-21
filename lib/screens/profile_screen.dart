import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> vehicles = [];
  bool loading = true;

  final brands = [
    'Hyundai', 'Tata', 'Maruti Suzuki', 'Mahindra', 'Honda',
    'Toyota', 'Kia', 'MG', 'Volkswagen', 'Skoda', 'Renault',
    'Nissan', 'Ford', 'BMW', 'Mercedes', 'Audi', 'Jeep',
    'Volvo', 'Lexus', 'Porsche',
  ];

  @override
  void initState() {
    super.initState();
    fetchVehicles();
  }

  Future<void> fetchVehicles() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        vehicles = List<Map<String, dynamic>>.from(response);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void openAddVehicleSheet() {
    final nameController = TextEditingController();
    final carModelController = TextEditingController();
    final carNumberController = TextEditingController();
    String selectedBrand = brands.first;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 28,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44, height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Add Vehicle',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 24),
                  _sheetField(nameController, 'Your Name', Icons.person_outline),
                  const SizedBox(height: 16),
                  // Brand Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedBrand,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: brands.map((b) => DropdownMenuItem(
                          value: b, child: Text(b),
                        )).toList(),
                        onChanged: (v) => setSheetState(() => selectedBrand = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetField(carModelController, 'Car Model', Icons.directions_car_outlined),
                  const SizedBox(height: 16),
                  _sheetField(carNumberController, 'Car Number', Icons.badge_outlined),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: saving ? null : () async {
                      if (nameController.text.trim().isEmpty ||
                          carModelController.text.trim().isEmpty ||
                          carNumberController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill all fields.')),
                        );
                        return;
                      }

                      setSheetState(() => saving = true);

                      final supabase = Supabase.instance.client;
                      final user = supabase.auth.currentUser;
                      if (user == null) return;

                      try {
                        final inserted = await supabase.from('vehicles').insert({
                          'user_id': user.id,
                          'car_brand': selectedBrand,
                          'car_model': carModelController.text.trim(),
                          'car_number': carNumberController.text.trim(),
                        }).select().single();

                        final existing = await supabase
                            .from('profiles')
                            .select()
                            .eq('id', user.id)
                            .maybeSingle();

                        if (existing == null) {
                          await supabase.from('profiles').insert({
                            'id': user.id,
                            'name': nameController.text.trim(),
                            'email': user.email,
                            'active_vehicle_id': inserted['id'],
                          });
                        } else {
                          await supabase.from('profiles').update({
                            'active_vehicle_id': inserted['id'],
                          }).eq('id', user.id);
                        }

                        if (!mounted) return;
                        Navigator.pop(ctx);
                        fetchVehicles();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vehicle added!')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setSheetState(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        color: saving ? AppColors.yellow.withOpacity(0.6) : AppColors.yellow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: saving
                            ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)
                            : const Text('SAVE VEHICLE',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _sheetField(TextEditingController ctrl, String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          icon: Icon(icon, size: 22),
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Future<void> setActiveVehicle(Map<String, dynamic> vehicle) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'active_vehicle_id': vehicle['id']})
          .eq('id', user.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.07),
                                blurRadius: 12, offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text('My Garage',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Vehicle list
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : vehicles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_car_outlined,
                                      size: 80, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text('No vehicles yet',
                                    style: TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade400,
                                    )),
                                  const SizedBox(height: 8),
                                  Text('Tap the button below to add your first car',
                                    style: TextStyle(color: Colors.grey.shade400)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 22),
                              itemCount: vehicles.length,
                              itemBuilder: (_, i) {
                                final v = vehicles[i];
                                return GestureDetector(
                                  onTap: () => setActiveVehicle(v),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(26),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 16, offset: const Offset(4, 6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // Serial badge
                                        Container(
                                          width: 44, height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.yellow,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Center(
                                            child: Text('${i + 1}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                              )),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Car icon
                                        Container(
                                          width: 56, height: 56,
                                          decoration: BoxDecoration(
                                            color: AppColors.yellow.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          child: const Icon(Icons.directions_car_rounded, size: 30),
                                        ),
                                        const SizedBox(width: 16),
                                        // Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(v['car_model'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 18, fontWeight: FontWeight.w800)),
                                              const SizedBox(height: 4),
                                              Text(v['car_brand'] ?? '',
                                                style: TextStyle(
                                                  color: Colors.grey.shade500, fontSize: 14)),
                                              const SizedBox(height: 2),
                                              Text(v['car_number'] ?? '',
                                                style: TextStyle(
                                                  color: Colors.grey.shade400, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right_rounded,
                                            color: Colors.grey),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                // ADD VEHICLE button
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                  child: GestureDetector(
                    onTap: openAddVehicleSheet,
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 20, offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_rounded, size: 28),
                          SizedBox(width: 10),
                          Text('ADD VEHICLE',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}