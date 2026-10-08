import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
import '../theme/app_colors.dart';

/// Wraps a package screen so it only builds once the services catalog
/// (names, prices, features from Supabase) is available, and rebuilds
/// whenever fresh catalog data arrives.
///
/// The catalog is almost always already in memory (loaded at startup and
/// cached on the device), so in practice this shows the spinner only on
/// the very first launch with no network.
class CatalogGate extends StatefulWidget {
  const CatalogGate({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<CatalogGate> createState() => _CatalogGateState();
}

class _CatalogGateState extends State<CatalogGate> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    CatalogService.revision.addListener(_onCatalogChanged);
    _load();
  }

  @override
  void dispose() {
    CatalogService.revision.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    try {
      await CatalogService.ensureLoaded();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (CatalogService.isLoaded) return widget.builder(context);

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.txt),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: AppColors.mut, size: 44),
                    const SizedBox(height: 16),
                    Text(
                      'Couldn\'t load our packages',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.txt, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check your internet connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.mut, fontSize: 13.5),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _load,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccentDark,
                      ),
                      child: const Text('TRY AGAIN', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                )
              : const CircularProgressIndicator(color: AppColors.accent),
        ),
      ),
    );
  }
}

/// Shown by a package screen when every one of its packages has been
/// switched off in the `services` table.
class CatalogEmpty extends StatelessWidget {
  const CatalogEmpty({super.key, this.message = 'These packages aren\'t available right now. Please check back soon.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.txt),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mut, fontSize: 15, height: 1.4),
          ),
        ),
      ),
    );
  }
}
