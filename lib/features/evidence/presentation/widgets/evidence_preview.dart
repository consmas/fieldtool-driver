import 'package:flutter/material.dart';

class EvidencePreview extends StatelessWidget {
  const EvidencePreview({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(label),
      ),
    );
  }
}
