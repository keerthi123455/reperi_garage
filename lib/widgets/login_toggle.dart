import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class LoginToggle extends StatefulWidget {
  final Function(bool) onChanged;

  const LoginToggle({
    super.key,
    required this.onChanged,
  });

  @override
  State<LoginToggle> createState() => _LoginToggleState();
}

class _LoginToggleState extends State<LoginToggle> {
  bool isClient = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isClient = true;
                });

                widget.onChanged(true);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isClient
                      ? AppColors.yellow
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(30),
                ),
                child: Center(
                  child: Text(
                    'Client',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isClient
                          ? Colors.black
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isClient = false;
                });

                widget.onChanged(false);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: !isClient
                      ? AppColors.yellow
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(30),
                ),
                child: Center(
                  child: Text(
                    'Admin',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: !isClient
                          ? Colors.black
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}