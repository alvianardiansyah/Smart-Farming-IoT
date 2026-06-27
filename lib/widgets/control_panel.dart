import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

class ControlPanel extends StatelessWidget {
  final SystemStatus systemStatus;
  final Function(String) onModeChanged;
  final Function(String, bool) onPumpToggled;

  const ControlPanel({
    Key? key,
    required this.systemStatus,
    required this.onModeChanged,
    required this.onPumpToggled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kontrol Sistem',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),

            // Irrigation Mode dengan default AUTO
            Row(
              children: [
                Text('Mode Penyiraman:'),
                SizedBox(width: 12),
                ChoiceChip(
                  label: Text('Auto'),
                  selected: systemStatus.irrigationMode == 'auto',
                  selectedColor: Colors.green,
                  onSelected: (selected) {
                    if (selected) onModeChanged('auto');
                  },
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Manual'),
                  selected: systemStatus.irrigationMode == 'manual',
                  selectedColor: Colors.blue,
                  onSelected: (selected) {
                    if (selected) onModeChanged('manual');
                  },
                ),
              ],
            ),
            SizedBox(height: 12),

            // Info mode
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: systemStatus.irrigationMode == 'auto'
                    ? Colors.green[50]
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                systemStatus.irrigationMode == 'auto'
                    ? '🔒 Mode Auto: Pompa dikontrol otomatis oleh sistem'
                    : '🛠️ Mode Manual: Anda bisa kontrol pompa manual',
                style: TextStyle(
                  fontSize: 12,
                  color: systemStatus.irrigationMode == 'auto'
                      ? Colors.green[700]
                      : Colors.blue[700],
                ),
              ),
            ),
            SizedBox(height: 12),

            // Pump Controls - hanya aktif di manual mode
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPumpControl(
                  'Pompa Air',
                  systemStatus.waterPumpOn,
                  Icons.water_drop,
                  Colors.blue,
                  'water',
                  systemStatus.irrigationMode == 'manual',
                ),
                _buildPumpControl(
                  'Pompa Pupuk',
                  systemStatus.fertilizerPumpOn,
                  Icons.eco,
                  Colors.green,
                  'fertilizer',
                  systemStatus.irrigationMode == 'manual',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPumpControl(String title, bool isOn, IconData icon, Color color,
      String type, bool enabled) {
    return Column(
      children: [
        Icon(icon, size: 32, color: enabled ? color : Colors.grey),
        SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            color: enabled ? Colors.black : Colors.grey,
          ),
        ),
        SizedBox(height: 6),
        Switch(
          value: isOn,
          onChanged: enabled ? (value) => onPumpToggled(type, value) : null,
          activeColor: color,
        ),
        Text(
          isOn ? 'ON' : 'OFF',
          style: TextStyle(
            color: isOn ? color : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (!enabled)
          Text(
            'Auto Mode',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
      ],
    );
  }
}
