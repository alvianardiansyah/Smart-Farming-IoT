import 'package:flutter/material.dart';

class SensorCard extends StatelessWidget {
  final String title;
  final double value;
  final String unit;
  final IconData icon;
  final Color color;
  final bool compact;

  const SensorCard({
    Key? key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: compact ? EdgeInsets.all(8) : EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: compact ? 24 : 32, color: color),
            SizedBox(height: compact ? 4 : 6),
            Text(
              _getCompactTitle(title),
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            SizedBox(height: compact ? 2 : 4),
            Text(
              '${value.toStringAsFixed(compact ? 0 : 1)} $unit',
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCompactTitle(String title) {
    if (!compact) return title;

    final shortTitles = {
      'Kelembapan Tanah': 'Kelembapan',
      'Konduktivitas': 'Konduktivitas',
      'Nitrogen (N)': 'Nitrogen',
      'Fosfor (P)': 'Fosfor',
      'Kalium (K)': 'Kalium',
    };

    return shortTitles[title] ?? title;
  }
}
