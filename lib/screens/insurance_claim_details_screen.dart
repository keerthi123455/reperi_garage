import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class InsuranceClaimDetailsScreen extends StatefulWidget {
  final int claimId;
  final String adminUsername;

  const InsuranceClaimDetailsScreen({
    super.key,
    required this.claimId,
    required this.adminUsername,
  });

  @override
  State<InsuranceClaimDetailsScreen> createState() =>
      _InsuranceClaimDetailsScreenState();
}

class _InsuranceClaimDetailsScreenState
    extends State<InsuranceClaimDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final _updateController = TextEditingController();
  Map? claim;
  List updates = [];
  bool loading = true;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _fetchClaimDetails();
  }

  Future<void> _fetchClaimDetails() async {
    try {
      final claimResponse = await _supabase
          .from('insurance_claims')
          .select('*')
          .eq('id', widget.claimId)
          .single();

      final updatesResponse = await _supabase
          .from('insurance_claims_updates')
          .select('*')
          .eq('claim_id', widget.claimId)
          .order('created_at', ascending: false);

      setState(() {
        claim = claimResponse;
        updates = updatesResponse;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _downloadDocument(String url) async {
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _addUpdate() async {
    if (_updateController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description')),
      );
      return;
    }

    try {
      await _supabase.from('insurance_claims_updates').insert({
        'claim_id': widget.claimId,
        'admin_id': widget.adminUsername,
        'description': _updateController.text,
        'photo_url': null,
        'created_at': DateTime.now().toIso8601String(),
      });

      _updateController.clear();
      _fetchClaimDetails();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update added!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _updateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Claim Details'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4A017)),
        ),
      );
    }

    if (claim == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Claim Details'),
        ),
        body: const Center(child: Text('Claim not found')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Claim Details'),
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: const Color(0xFFD4A017),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFD4A017),
              tabs: const [
                Tab(text: 'Documents'),
                Tab(text: 'Updates'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Documents Tab
                  _buildDocumentsTab(),
                  // Updates Tab
                  _buildUpdatesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUpdateDialog(),
        backgroundColor: const Color(0xFFD4A017),
        label: const Text(
          'Add Update',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Damage Description Dropdown at Top
          GestureDetector(
            onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFD4A017).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Damage Description',
                        style: TextStyle(
                          color: Color(0xFFD4A017),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Icon(
                        _descriptionExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: const Color(0xFFD4A017),
                      ),
                    ],
                  ),
                  if (_descriptionExpanded) ...[
                    const SizedBox(height: 12),
                    Text(
                      claim!['damage_description'] ?? 'No description provided',
                      style: TextStyle(
                        color: Colors.grey.withOpacity(0.9),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Submitted Documents',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _buildDocumentItem('RC Copy', claim!['rc_copy_url']),
          _buildDocumentItem('Driving License', claim!['driving_license_url']),
          _buildDocumentItem('Owner Aadhaar', claim!['owner_aadhaar_url']),
          _buildDocumentItem('Owner PAN', claim!['owner_pan_url']),
          _buildDocumentItem('Insurance Copy', claim!['insurance_copy_url']),
          _buildDocumentItem('Damage Photo', claim!['damage_photo_url']),
          const SizedBox(height: 40), // Extra padding at bottom
        ],
      ),
    );
  }

  Widget _buildDocumentItem(String title, String? url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFD4A017).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  url != null ? '✅ Uploaded' : '❌ Not uploaded',
                  style: TextStyle(
                    color: url != null ? Colors.green : Colors.red,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (url != null)
            ElevatedButton.icon(
              onPressed: () => _downloadDocument(url),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                foregroundColor: Colors.black,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUpdatesTab() {
    if (updates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.update, size: 48, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'No updates yet',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: updates.length,
      itemBuilder: (context, index) {
        final update = updates[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFD4A017).withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update #${updates.length - index}',
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (update['photo_url'] != null)
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(update['photo_url']),
                      fit: BoxFit.cover,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              Text(
                update['description'],
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.9),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                DateTime.parse(update['created_at'])
                    .toString()
                    .split('.')[0],
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddUpdateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Add Update',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _updateController,
          maxLines: 4,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Describe the inspection update...',
            hintStyle: TextStyle(color: Colors.grey.withOpacity(0.6)),
            filled: true,
            fillColor: const Color(0xFF0C0C0C),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _addUpdate();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
            ),
            child: const Text(
              'Add',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}