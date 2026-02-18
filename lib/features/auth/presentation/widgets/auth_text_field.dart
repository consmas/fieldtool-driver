import 'package:flutter/material.dart';

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.dark = true,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: dark ? Colors.white : null),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: dark ? Colors.white70 : null),
        filled: true,
        fillColor: dark ? Colors.white.withValues(alpha: 0.08) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.2) : Colors.black12,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.2) : Colors.black12,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.5) : Colors.blue,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
