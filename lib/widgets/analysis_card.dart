import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

class AnalysisCard extends StatelessWidget {
  final FuzzyAnalysis analysis;

  const AnalysisCard({Key? key, required this.analysis}) : super(key: key);

  Color _getStatusColor() {
    switch (analysis.status) {
      case 'Sangat Baik':
        return Colors.green;
      case 'Baik':
        return Colors.lightGreen;
      case 'Cukup':
        return Colors.orange;
      case 'Perlu Perhatian':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: _getStatusColor().withOpacity(0.1),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: _getStatusColor(), size: 20),
                SizedBox(width: 6),
                Text(
                  'Analisis Fuzzy',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Status: ${analysis.status}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _getStatusColor(),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Kondisi: ${analysis.soilCondition}',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 4),
            Text(
              'Rekomendasi: ${analysis.recommendation}',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 6),
            LinearProgressIndicator(
              value: (analysis.score + 2) / 5,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
            ),
            SizedBox(height: 2),
            Text(
              'Skor: ${analysis.score.toStringAsFixed(1)}',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
