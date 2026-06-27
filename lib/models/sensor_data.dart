// lib/models/sensor_data.dart
import 'package:flutter/material.dart';

// ================================
// KELAS UTAMA: SensorData
// ================================
class SensorData {
  final double temperature; // dalam °C (suhu udara)
  final double soilMoisture; // dalam %
  final double soilTemperature; // dalam °C (suhu tanah)
  final double conductivity; // dalam µS/cm
  final double pH; // dalam pH
  final double nitrogen; // dalam mg/kg
  final double phosphorus; // dalam mg/kg
  final double potassium; // dalam mg/kg
  final DateTime timestamp;

  SensorData({
    required this.temperature,
    required this.soilMoisture,
    required this.soilTemperature,
    required this.conductivity,
    required this.pH,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.timestamp,
  });

  // Factory constructor untuk data dari Firebase (format Arduino) - DIPERBAIKI
  factory SensorData.fromFirebase(Map<String, dynamic> data) {
    try {
      // Debug logging untuk melihat data mentah
      print('\n=== PARSING DATA DARI ARDUINO ===');
      print('Data mentah: $data');

      // Parsing dengan handling khusus untuk tipe data Arduino
      double tempAir = _parseDoubleFromArduino(data['temp_air'], defaultValue: 25.0);
      double tempTanah = data['temp_tanah'] != null 
          ? _parseDoubleFromArduino(data['temp_tanah'], defaultValue: tempAir)
          : tempAir; // Fallback ke suhu udara jika tidak ada
      
      double moisture = _parseDoubleFromArduino(data['moisture'], defaultValue: 50.0);
      double ec = _parseDoubleFromArduino(data['ec'], defaultValue: 1.0);
      double ph = _parseDoubleFromArduino(data['ph'], defaultValue: 7.0);

      // Parsing NPK - handle berbagai format dari Arduino
      double n = _parseNPKFromArduino(data['nitrogen']);
      double p = _parseNPKFromArduino(data['phosphorus']);
      double k = _parseNPKFromArduino(data['potassium']);

      // Log hasil parsing
      print('\n=== HASIL PARSING ===');
      print('Suhu Udara: $tempAir°C');
      print('Suhu Tanah: $tempTanah°C');
      print('Kelembapan: $moisture%');
      print('EC: $ec dS/m (${ec * 1000} µS/cm)');
      print('pH: $ph');
      print('Nitrogen: $n mg/kg');
      print('Fosfor: $p mg/kg');
      print('Kalium: $k mg/kg');
      print('=====================\n');

      // Parse timestamp
      DateTime timestamp;
      if (data['timestamp'] != null) {
        try {
          String timeStr = data['timestamp'].toString();
          // Handle format "YYYY-MM-DD HH:MM:SS"
          if (timeStr.contains(' ')) {
            timeStr = timeStr.replaceAll(' ', 'T');
          }
          // Tambahkan detik jika tidak ada
          if (!timeStr.contains(':')) {
            timeStr += ':00';
          }
          timestamp = DateTime.parse(timeStr);
        } catch (e) {
          print('Error parsing timestamp "${data['timestamp']}": $e');
          timestamp = DateTime.now();
        }
      } else {
        timestamp = DateTime.now();
      }

      return SensorData(
        temperature: tempAir,
        soilMoisture: moisture.clamp(0, 100),
        soilTemperature: tempTanah,
        conductivity: ec * 1000, // Convert dS/m ke µS/cm
        pH: ph.clamp(0, 14),
        nitrogen: n.abs(),
        phosphorus: p.abs(),
        potassium: k.abs(),
        timestamp: timestamp,
      );
    } catch (e) {
      print('\n❌ ERROR PARSING DATA DARI FIREBASE ❌');
      print('Error: $e');
      print('Stack trace: ${e.toString()}');
      print('Data yang gagal diparsing: $data');
      
      // Return data default agar aplikasi tidak crash
      return SensorData(
        temperature: 25.0,
        soilMoisture: 50.0,
        soilTemperature: 25.0,
        conductivity: 1000.0,
        pH: 7.0,
        nitrogen: 30.0,
        phosphorus: 25.0,
        potassium: 150.0,
        timestamp: DateTime.now(),
      );
    }
  }

  // Helper method untuk parsing double dari Arduino dengan berbagai format
  static double _parseDoubleFromArduino(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;

    try {
      if (value is int) {
        return value.toDouble();
      } else if (value is double) {
        return value;
      } else if (value is String) {
        String cleaned = value.trim();
        
        // Handle format desimal dengan koma
        cleaned = cleaned.replaceAll(',', '.');
        
        // Hapus karakter non-numerik kecuali titik dan minus
        cleaned = cleaned.replaceAll(RegExp(r'[^\d.-]'), '');
        
        if (cleaned.isEmpty) return defaultValue;
        
        // Handle kasus seperti "25.00" atau "25"
        double? result = double.tryParse(cleaned);
        if (result != null) return result;
        
        // Coba ekstrak angka menggunakan regex
        RegExp regex = RegExp(r'[-]?\d*\.?\d+');
        Match? match = regex.firstMatch(value.toString());
        if (match != null) {
          return double.tryParse(match.group(0)!) ?? defaultValue;
        }
      }
      return defaultValue;
    } catch (e) {
      print('Error parsing double "$value": $e');
      return defaultValue;
    }
  }

  // Helper khusus untuk parsing nilai NPK dari Arduino
  static double _parseNPKFromArduino(dynamic value) {
    if (value == null) return 0.0;

    try {
      // Debug NPK parsing
      print('Parsing NPK value: $value (type: ${value.runtimeType})');

      if (value is int) {
        return value.toDouble();
      } else if (value is double) {
        return value;
      } else if (value is String) {
        String cleaned = value.trim();
        
        // Debug intermediate steps
        print('  After trim: "$cleaned"');
        
        // Coba parse langsung
        double? result = double.tryParse(cleaned);
        if (result != null) {
          print('  Direct parse success: $result');
          return result;
        }
        
        // Clean lebih lanjut untuk Arduino format
        cleaned = cleaned.replaceAll(' ', '').replaceAll(',', '.');
        
        // Hapus unit jika ada
        cleaned = cleaned.replaceAll(RegExp(r'[a-zA-Z]'), '');
        
        print('  After cleaning: "$cleaned"');
        
        result = double.tryParse(cleaned);
        if (result != null) {
          print('  Parse after cleaning success: $result');
          return result;
        }
        
        // Coba ekstrak angka menggunakan regex
        RegExp regex = RegExp(r'(\d+(\.\d+)?)');
        Match? match = regex.firstMatch(value.toString());
        if (match != null) {
          result = double.tryParse(match.group(0)!);
          print('  Regex match: "${match.group(0)}" -> $result');
          if (result != null) return result;
        }
        
        // Last resort: cari semua angka
        Iterable<Match> matches = RegExp(r'\d+').allMatches(value.toString());
        if (matches.isNotEmpty) {
          String numberStr = matches.first.group(0)!;
          result = double.tryParse(numberStr);
          print('  First number found: "$numberStr" -> $result');
          if (result != null) return result;
        }
      }
      
      print('  NPK parsing failed, returning 0');
      return 0.0;
    } catch (e) {
      print('Error parsing NPK value "$value": $e');
      return 0.0;
    }
  }

  // Factory constructor untuk JSON
  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      temperature: (json['temperature'] as num).toDouble(),
      soilMoisture: (json['soilMoisture'] as num).toDouble(),
      soilTemperature: (json['soilTemperature'] as num).toDouble(),
      conductivity: (json['conductivity'] as num).toDouble(),
      pH: (json['pH'] as num).toDouble(),
      nitrogen: (json['nitrogen'] as num).toDouble(),
      phosphorus: (json['phosphorus'] as num).toDouble(),
      potassium: (json['potassium'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  // Method untuk mengonversi ke Map
  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'soilMoisture': soilMoisture,
      'soilTemperature': soilTemperature,
      'conductivity': conductivity,
      'pH': pH,
      'nitrogen': nitrogen,
      'phosphorus': phosphorus,
      'potassium': potassium,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Method untuk mengonversi ke Map Firebase (format Arduino)
  Map<String, dynamic> toFirebaseMap() {
    return {
      'temp_air': temperature,
      'temp_tanah': soilTemperature,
      'moisture': soilMoisture,
      'ec': conductivity / 1000, // Convert µS/cm ke dS/m
      'ph': pH,
      'nitrogen': nitrogen,
      'phosphorus': phosphorus,
      'potassium': potassium,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Copy with method untuk update data
  SensorData copyWith({
    double? temperature,
    double? soilMoisture,
    double? soilTemperature,
    double? conductivity,
    double? pH,
    double? nitrogen,
    double? phosphorus,
    double? potassium,
    DateTime? timestamp,
  }) {
    return SensorData(
      temperature: temperature ?? this.temperature,
      soilMoisture: soilMoisture ?? this.soilMoisture,
      soilTemperature: soilTemperature ?? this.soilTemperature,
      conductivity: conductivity ?? this.conductivity,
      pH: pH ?? this.pH,
      nitrogen: nitrogen ?? this.nitrogen,
      phosphorus: phosphorus ?? this.phosphorus,
      potassium: potassium ?? this.potassium,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  // Helper untuk mendapatkan status nilai
  String getValueStatus(double value, String type) {
    switch (type) {
      case 'moisture':
        if (value < 20) return 'Sangat Kering';
        if (value < 40) return 'Kering';
        if (value < 60) return 'Optimal';
        if (value < 80) return 'Basah';
        return 'Sangat Basah';
      case 'ph':
        if (value < 5.0) return 'Sangat Asam';
        if (value < 6.0) return 'Asam';
        if (value < 7.5) return 'Optimal';
        if (value < 8.5) return 'Basa';
        return 'Sangat Basa';
      case 'temperature':
        if (value < 15) return 'Sangat Dingin';
        if (value < 25) return 'Dingin';
        if (value < 32) return 'Optimal';
        if (value < 38) return 'Panas';
        return 'Sangat Panas';
      case 'nitrogen':
        if (value < 10) return 'Sangat Rendah';
        if (value < 20) return 'Rendah';
        if (value < 40) return 'Optimal';
        if (value < 60) return 'Tinggi';
        return 'Sangat Tinggi';
      case 'phosphorus':
        if (value < 10) return 'Sangat Rendah';
        if (value < 15) return 'Rendah';
        if (value < 45) return 'Optimal';
        if (value < 60) return 'Tinggi';
        return 'Sangat Tinggi';
      case 'potassium':
        if (value < 50) return 'Sangat Rendah';
        if (value < 100) return 'Rendah';
        if (value < 200) return 'Optimal';
        if (value < 300) return 'Tinggi';
        return 'Sangat Tinggi';
      case 'conductivity':
        if (value < 200) return 'Sangat Rendah';
        if (value < 400) return 'Rendah';
        if (value < 800) return 'Optimal';
        if (value < 1200) return 'Tinggi';
        return 'Sangat Tinggi';
      default:
        return 'Normal';
    }
  }

  // Helper untuk mendapatkan warna status
  Color getValueColor(double value, String type) {
    switch (type) {
      case 'moisture':
        if (value < 20) return Colors.red;
        if (value < 40) return Colors.orange;
        if (value < 60) return Colors.green;
        if (value < 80) return Colors.blue;
        return Colors.purple;
      case 'ph':
        if (value < 5.0 || value > 8.5) return Colors.red;
        if (value < 6.0 || value > 7.5) return Colors.orange;
        return Colors.green;
      case 'temperature':
        if (value < 15 || value > 38) return Colors.red;
        if (value < 25 || value > 32) return Colors.orange;
        return Colors.green;
      case 'nitrogen':
      case 'phosphorus':
      case 'potassium':
        if (value < 20) return Colors.red;
        if (value < 40) return Colors.green;
        if (value < 60) return Colors.orange;
        return Colors.red;
      case 'conductivity':
        if (value < 200 || value > 1200) return Colors.red;
        if (value < 400 || value > 800) return Colors.orange;
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  String toString() {
    return '''
SensorData {
  Suhu Udara: ${temperature.toStringAsFixed(1)}°C,
  Suhu Tanah: ${soilTemperature.toStringAsFixed(1)}°C,
  Kelembapan: ${soilMoisture.toStringAsFixed(1)}%,
  Konduktivitas: ${conductivity.toStringAsFixed(0)} µS/cm,
  pH: ${pH.toStringAsFixed(1)},
  Nitrogen: ${nitrogen.toStringAsFixed(0)} mg/kg,
  Fosfor: ${phosphorus.toStringAsFixed(0)} mg/kg,
  Kalium: ${potassium.toStringAsFixed(0)} mg/kg,
  Waktu: ${timestamp.toLocal().toString()}
}
''';
  }

  // Format untuk display di UI
  String toDisplayString() {
    return '''
📊 DATA SENSOR TERKINI
🌡️  Suhu: ${temperature.toStringAsFixed(1)}°C
🌡️  Suhu Tanah: ${soilTemperature.toStringAsFixed(1)}°C
💧 Kelembapan: ${soilMoisture.toStringAsFixed(1)}%
🧪 pH: ${pH.toStringAsFixed(1)}
⚡ EC: ${conductivity.toStringAsFixed(0)} µS/cm
🌱 N: ${nitrogen.toStringAsFixed(0)} mg/kg
🌱 P: ${phosphorus.toStringAsFixed(0)} mg/kg  
🌱 K: ${potassium.toStringAsFixed(0)} mg/kg
🕒 ${_formatTime(timestamp)}
''';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

// ================================
// KELAS: FuzzyAnalysis
// ================================
class FuzzyAnalysis {
  final String soilCondition;
  final String recommendation;
  final double score;
  final String status;

  FuzzyAnalysis({
    required this.soilCondition,
    required this.recommendation,
    required this.score,
    required this.status,
  });

  factory FuzzyAnalysis.fromMap(Map<String, dynamic> map) {
    return FuzzyAnalysis(
      soilCondition: map['soilCondition'] ?? '',
      recommendation: map['recommendation'] ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'soilCondition': soilCondition,
      'recommendation': recommendation,
      'score': score,
      'status': status,
    };
  }

  @override
  String toString() {
    return '''
FuzzyAnalysis {
  Status: $status,
  Skor: ${score.toStringAsFixed(1)},
  Kondisi: $soilCondition,
  Rekomendasi: $recommendation
}
''';
  }
}

// ================================
// KELAS: SystemStatus
// ================================
class SystemStatus {
  final bool isOnline;
  final bool waterPumpOn;
  final bool fertilizerPumpOn;
  final String irrigationMode; // 'auto' or 'manual'

  SystemStatus({
    required this.isOnline,
    required this.waterPumpOn,
    required this.fertilizerPumpOn,
    required this.irrigationMode,
  });

  // Factory constructor dengan default value AUTO
  factory SystemStatus.auto() {
    return SystemStatus(
      isOnline: true,
      waterPumpOn: false,
      fertilizerPumpOn: false,
      irrigationMode: 'auto',
    );
  }

  // Factory constructor untuk data dari Firebase - DIPERBAIKI
  factory SystemStatus.fromFirebase(Map<String, dynamic>? data) {
    if (data == null) {
      return SystemStatus.auto();
    }

    return SystemStatus(
      isOnline: true,
      waterPumpOn: _parseBool(data['pompa_air_status']),  
      fertilizerPumpOn: _parseBool(data['pompa_pupuk_status']),
      irrigationMode: data['mode']?.toString() ?? 'auto',
    );
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }

  // Copy with method
  SystemStatus copyWith({
    bool? isOnline,
    bool? waterPumpOn,
    bool? fertilizerPumpOn,
    String? irrigationMode,
  }) {
    return SystemStatus(
      isOnline: isOnline ?? this.isOnline,
      waterPumpOn: waterPumpOn ?? this.waterPumpOn,
      fertilizerPumpOn: fertilizerPumpOn ?? this.fertilizerPumpOn,
      irrigationMode: irrigationMode ?? this.irrigationMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isOnline': isOnline,
      'waterPumpOn': waterPumpOn,
      'fertilizerPumpOn': fertilizerPumpOn,
      'irrigationMode': irrigationMode,
    };
  }

  String get irrigationModeText {
    return irrigationMode == 'auto' ? 'Mode Otomatis' : 'Mode Manual';
  }

  String get waterPumpStatus {
    return waterPumpOn ? 'ON' : 'OFF';
  }

  String get fertilizerPumpStatus {
    return fertilizerPumpOn ? 'ON' : 'OFF';
  }

  Color get waterPumpColor {
    return waterPumpOn ? Colors.green : Colors.grey;
  }

  Color get fertilizerPumpColor {
    return fertilizerPumpOn ? Colors.green : Colors.grey;
  }

  @override
  String toString() {
    return '''
SystemStatus {
  Online: $isOnline,
  Pompa Air: $waterPumpOn ($waterPumpStatus),
  Pompa Pupuk: $fertilizerPumpOn ($fertilizerPumpStatus),
  Mode: $irrigationMode ($irrigationModeText)
}
''';
  }
}

// ================================
// ENUM: NotificationType
// ================================
enum NotificationType {
  warning, // Peringatan
  info, // Informasi
  success, // Berhasil
  danger, // Bahaya
}

// ================================
// KELAS: SoilNotification
// ================================
class SoilNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final NotificationType type;
  bool isRead;

  SoilNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.type,
    this.isRead = false,
  });

  factory SoilNotification.create({
    required String title,
    required String message,
    required NotificationType type,
  }) {
    return SoilNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      timestamp: DateTime.now(),
      type: type,
      isRead: false,
    );
  }

  // Copy with method untuk membuat salinan dengan perubahan
  SoilNotification copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? timestamp,
    NotificationType? type,
    bool? isRead,
  }) {
    return SoilNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'type': type.index,
      'isRead': isRead,
    };
  }

  factory SoilNotification.fromMap(Map<String, dynamic> map) {
    return SoilNotification(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
      type: NotificationType.values[map['type'] ?? 0],
      isRead: map['isRead'] ?? false,
    );
  }

  @override
  String toString() {
    return '''
SoilNotification {
  ID: $id,
  Judul: $title,
  Tipe: $type,
  Waktu: $timestamp,
  Dibaca: $isRead
}
''';
  }
}

// ================================
// KELAS: TankStatus - VERSI YANG DIPERBAIKI
// ================================
class TankStatus {
  final double waterTankDistance; // Jarak dari sensor ke permukaan air (cm)
  final double
      fertilizerTankDistance; // Jarak dari sensor ke permukaan pupuk (cm)
  final DateTime timestamp;

  // Tinggi tangki konstan (20cm dari sensor ke dasar)
  static const double tankHeight = 20.0;

  TankStatus({
    required this.waterTankDistance,
    required this.fertilizerTankDistance,
    required this.timestamp,
  });

  // Factory constructor untuk data dari Firebase - VERSI DIPERBAIKI
  factory TankStatus.fromFirebase(Map<String, dynamic>? data) {
    if (data == null) {
      return TankStatus(
        waterTankDistance: tankHeight, // 20cm = kosong
        fertilizerTankDistance: tankHeight, // 20cm = kosong
        timestamp: DateTime.now(),
      );
    }

    // Debug log
    print('\n=== PARSING DATA TANGKI (LOGIKA DIPERBAIKI) ===');
    print('Data mentah: $data');

    double waterDistance = tankHeight; // Default: tangki kosong
    double fertilizerDistance = tankHeight; // Default: tangki kosong

    // 1. Utamakan parsing dari 'distance_air' dan 'distance_pupuk' (jarak langsung dari sensor)
    if (data['distance_air'] != null) {
      waterDistance = _parseDistance(data['distance_air']);
      print('Jarak air dari sensor: $waterDistance cm');
    }

    if (data['distance_pupuk'] != null) {
      fertilizerDistance = _parseDistance(data['distance_pupuk']);
      print('Jarak pupuk dari sensor: $fertilizerDistance cm');
    }

    // 2. Jika tidak ada distance, coba dari level_cm (level dalam cm dari dasar)
    if (waterDistance == tankHeight && data['level_air_cm'] != null) {
      double levelCm = _parseTankLevel(data['level_air_cm']);
      // PERBAIKAN: Jika level_cm adalah ketinggian dari dasar, maka jarak = tinggi tangki - level
      waterDistance = tankHeight - levelCm; // Konversi level ke jarak
      print('Level air: $levelCm cm -> Jarak: $waterDistance cm');
    }

    if (fertilizerDistance == tankHeight && data['level_pupuk_cm'] != null) {
      double levelCm = _parseTankLevel(data['level_pupuk_cm']);
      fertilizerDistance = tankHeight - levelCm;
      print('Level pupuk: $levelCm cm -> Jarak: $fertilizerDistance cm');
    }

    print('Hasil akhir:');
    print(
        '  - Air: Jarak sensor ke permukaan = $waterDistance cm (${tankHeight - waterDistance} cm dari dasar)');
    print(
        '  - Pupuk: Jarak sensor ke permukaan = $fertilizerDistance cm (${tankHeight - fertilizerDistance} cm dari dasar)');
    print('================================\n');

    return TankStatus(
      waterTankDistance: waterDistance,
      fertilizerTankDistance: fertilizerDistance,
      timestamp: DateTime.now(),
    );
  }

  static double _parseDistance(dynamic value) {
    if (value == null) return tankHeight;

    try {
      double distance = _parseDouble(value) ?? tankHeight;
      if (distance < 0) distance = 0;
      if (distance > tankHeight) distance = tankHeight;
      return distance;
    } catch (e) {
      print('Error parsing distance $value: $e');
      return tankHeight;
    }
  }

  static double _parseTankLevel(dynamic value) {
    if (value == null) return 0.0;

    try {
      if (value is int) return value.toDouble();
      if (value is double) return value;
      if (value is String) {
        String cleaned = value
            .toString()
            .replaceAll(' ', '')
            .replaceAll(',', '.')
            .replaceAll(RegExp(r'[^\d.-]'), '');
        return double.tryParse(cleaned) ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      print('Error parsing tank level $value: $e');
      return 0.0;
    }
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;

    if (value is int) {
      return value.toDouble();
    } else if (value is double) {
      return value;
    } else if (value is String) {
      String cleaned = value
          .toString()
          .replaceAll(' ', '')
          .replaceAll(',', '.')
          .replaceAll(RegExp(r'[^\d.-]'), '');
      return double.tryParse(cleaned);
    }
    return null;
  }

  TankStatus copyWith({
    double? waterTankDistance,
    double? fertilizerTankDistance,
    DateTime? timestamp,
  }) {
    return TankStatus(
      waterTankDistance: waterTankDistance ?? this.waterTankDistance,
      fertilizerTankDistance:
          fertilizerTankDistance ?? this.fertilizerTankDistance,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'waterTankDistance': waterTankDistance,
      'fertilizerTankDistance': fertilizerTankDistance,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // GETTERS YANG DIPERBAIKI
  // Tinggi air dari dasar (cm) = tinggi tangki - jarak sensor ke permukaan
  double get waterLevelCm => tankHeight - waterTankDistance;
  double get fertilizerLevelCm => tankHeight - fertilizerTankDistance;

  // Persentase
  double get waterTankPercent =>
      (waterLevelCm / tankHeight * 100).clamp(0, 100);
  double get fertilizerTankPercent =>
      (fertilizerLevelCm / tankHeight * 100).clamp(0, 100);

  // PERBAIKAN DI SINI: Threshold yang benar
  bool get isWaterTankLow => waterLevelCm < 6.0; // < 6cm = rendah
  bool get isFertilizerTankLow => fertilizerLevelCm < 6.0;
  bool get isWaterTankCritical => waterLevelCm < 2.0; // < 2cm = kritis
  bool get isFertilizerTankCritical => fertilizerLevelCm < 2.0;

  // Status warna
  Color get waterTankColor {
    if (isWaterTankCritical) return Colors.red;
    if (isWaterTankLow) return Colors.orange;
    return Colors.green;
  }

  Color get fertilizerTankColor {
    if (isFertilizerTankCritical) return Colors.red;
    if (isFertilizerTankLow) return Colors.orange;
    return Colors.green;
  }

  // Status text yang diperbaiki
  String get waterTankStatus {
    if (waterLevelCm <= 0) return 'ERROR';
    if (isWaterTankCritical) return 'KRITIS (<2cm)';
    if (isWaterTankLow) return 'RENDAH (2-6cm)';
    if (waterLevelCm >= 18) return 'PENUH (>18cm)';
    if (waterLevelCm >= 10) return 'CUKUP';
    return 'AMAN (6-18cm)';
  }

  String get fertilizerTankStatus {
    if (fertilizerLevelCm <= 0) return 'ERROR';
    if (isFertilizerTankCritical) return 'KRITIS (<2cm)';
    if (isFertilizerTankLow) return 'RENDAH (2-6cm)';
    if (fertilizerLevelCm >= 18) return 'PENUH (>18cm)';
    if (fertilizerLevelCm >= 10) return 'CUKUP';
    return 'AMAN (6-18cm)';
  }

  // Informasi lengkap
  String get waterTankInfo =>
      '${waterLevelCm.toStringAsFixed(1)} cm dari dasar (jarak sensor: ${waterTankDistance.toStringAsFixed(1)} cm)';
  String get fertilizerTankInfo =>
      '${fertilizerLevelCm.toStringAsFixed(1)} cm dari dasar (jarak sensor: ${fertilizerTankDistance.toStringAsFixed(1)} cm)';

  @override
  String toString() {
    return '''
TankStatus {
  Tangki Air: ${waterLevelCm.toStringAsFixed(1)} cm - $waterTankStatus (${waterTankPercent.toStringAsFixed(0)}%)
  Tangki Pupuk: ${fertilizerLevelCm.toStringAsFixed(1)} cm - $fertilizerTankStatus (${fertilizerTankPercent.toStringAsFixed(0)}%)
  Waktu: ${timestamp.toLocal().toString()}
}
''';
  }

  String toDisplayString() {
    return '''
💧 TANGKI AIR: ${waterLevelCm.toStringAsFixed(1)} cm - $waterTankStatus
🌿 TANGKI PUPUK: ${fertilizerLevelCm.toStringAsFixed(1)} cm - $fertilizerTankStatus
🕒 ${_formatTime(timestamp)}
''';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

// ================================
// KELAS: FuzzySugenoAnalysis
// ================================
class FuzzySugenoAnalysis {
  final Map<String, double> membershipValues;
  final Map<String, double> ruleOutputs;
  final double crispOutput;
  final String decision;
  final String kondisiTanah;
  final String rekomendasi;
  final Color decisionColor;

  FuzzySugenoAnalysis({
    required this.membershipValues,
    required this.ruleOutputs,
    required this.crispOutput,
    required this.decision,
    required this.kondisiTanah,
    required this.rekomendasi,
    required this.decisionColor,
  });

  factory FuzzySugenoAnalysis.empty() {
    return FuzzySugenoAnalysis(
      membershipValues: {},
      ruleOutputs: {},
      crispOutput: 0.0,
      decision: 'Memuat analisis...',
      kondisiTanah: 'Memuat data kondisi tanah...',
      rekomendasi: 'Menunggu data sensor...',
      decisionColor: Colors.grey,
    );
  }

  factory FuzzySugenoAnalysis.fromMap(Map<String, dynamic> map) {
    return FuzzySugenoAnalysis(
      membershipValues: Map<String, double>.from(map['membershipValues'] ?? {}),
      ruleOutputs: Map<String, double>.from(map['ruleOutputs'] ?? {}),
      crispOutput: (map['crispOutput'] as num?)?.toDouble() ?? 0.0,
      decision: map['decision'] ?? '',
      kondisiTanah: map['kondisiTanah'] ?? '',
      rekomendasi: map['rekomendasi'] ?? '',
      decisionColor: Color(map['decisionColor'] ?? Colors.grey.value),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'membershipValues': membershipValues,
      'ruleOutputs': ruleOutputs,
      'crispOutput': crispOutput,
      'decision': decision,
      'kondisiTanah': kondisiTanah,
      'rekomendasi': rekomendasi,
      'decisionColor': decisionColor.value,
    };
  }

  // Copy with method
  FuzzySugenoAnalysis copyWith({
    Map<String, double>? membershipValues,
    Map<String, double>? ruleOutputs,
    double? crispOutput,
    String? decision,
    String? kondisiTanah,
    String? rekomendasi,
    Color? decisionColor,
  }) {
    return FuzzySugenoAnalysis(
      membershipValues: membershipValues ?? this.membershipValues,
      ruleOutputs: ruleOutputs ?? this.ruleOutputs,
      crispOutput: crispOutput ?? this.crispOutput,
      decision: decision ?? this.decision,
      kondisiTanah: kondisiTanah ?? this.kondisiTanah,
      rekomendasi: rekomendasi ?? this.rekomendasi,
      decisionColor: decisionColor ?? this.decisionColor,
    );
  }

  // Helper untuk mendapatkan tingkat prioritas
  String get priorityLevel {
    if (crispOutput >= 0.7) return 'SANGAT TINGGI';
    if (crispOutput >= 0.5) return 'TINGGI';
    if (crispOutput >= 0.3) return 'SEDANG';
    return 'RENDAH';
  }

  // Helper untuk mendapatkan warna prioritas
  Color get priorityColor {
    if (crispOutput >= 0.7) return Colors.red;
    if (crispOutput >= 0.5) return Colors.orange;
    if (crispOutput >= 0.3) return Colors.blue;
    return Colors.green;
  }

  // Helper untuk mendapatkan ikon prioritas
  IconData get priorityIcon {
    if (crispOutput >= 0.7) return Icons.warning;
    if (crispOutput >= 0.5) return Icons.info;
    return Icons.check_circle;
  }

  @override
  String toString() {
    return '''
FuzzySugenoAnalysis {
  Output: ${crispOutput.toStringAsFixed(2)},
  Keputusan: $decision,
  Kondisi Tanah: $kondisiTanah,
  Rekomendasi: $rekomendasi,
  Prioritas: $priorityLevel
}
''';
  }
}

// ================================
// KELAS: ManualControl
// ================================
class ManualControl {
  final bool waterPump;
  final bool fertilizerPump;
  final DateTime timestamp;
  final String byUser;

  ManualControl({
    required this.waterPump,
    required this.fertilizerPump,
    required this.timestamp,
    required this.byUser,
  });

  factory ManualControl.fromMap(Map<String, dynamic> map) {
    return ManualControl(
      waterPump: map['waterPump'] ?? false,
      fertilizerPump: map['fertilizerPump'] ?? false,
      timestamp: DateTime.parse(map['timestamp']),
      byUser: map['byUser'] ?? 'system',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'waterPump': waterPump,
      'fertilizerPump': fertilizerPump,
      'timestamp': timestamp.toIso8601String(),
      'byUser': byUser,
    };
  }

  ManualControl copyWith({
    bool? waterPump,
    bool? fertilizerPump,
    DateTime? timestamp,
    String? byUser,
  }) {
    return ManualControl(
      waterPump: waterPump ?? this.waterPump,
      fertilizerPump: fertilizerPump ?? this.fertilizerPump,
      timestamp: timestamp ?? this.timestamp,
      byUser: byUser ?? this.byUser,
    );
  }
}

// ================================
// KELAS: DailyStats
// ================================
class DailyStats {
  final DateTime date;
  final double avgTemperature;
  final double avgMoisture;
  final double avgPH;
  final double avgNitrogen;
  final double avgPhosphorus;
  final double avgPotassium;
  final int irrigationCount;
  final int fertilizationCount;

  DailyStats({
    required this.date,
    required this.avgTemperature,
    required this.avgMoisture,
    required this.avgPH,
    required this.avgNitrogen,
    required this.avgPhosphorus,
    required this.avgPotassium,
    required this.irrigationCount,
    required this.fertilizationCount,
  });

  factory DailyStats.fromSensorDataList(
      List<SensorData> dataList, DateTime date) {
    if (dataList.isEmpty) {
      return DailyStats(
        date: date,
        avgTemperature: 0,
        avgMoisture: 0,
        avgPH: 0,
        avgNitrogen: 0,
        avgPhosphorus: 0,
        avgPotassium: 0,
        irrigationCount: 0,
        fertilizationCount: 0,
      );
    }

    double totalTemp = 0;
    double totalMoisture = 0;
    double totalPH = 0;
    double totalNitrogen = 0;
    double totalPhosphorus = 0;
    double totalPotassium = 0;

    for (var data in dataList) {
      totalTemp += data.temperature;
      totalMoisture += data.soilMoisture;
      totalPH += data.pH;
      totalNitrogen += data.nitrogen;
      totalPhosphorus += data.phosphorus;
      totalPotassium += data.potassium;
    }

    int count = dataList.length;

    return DailyStats(
      date: date,
      avgTemperature: totalTemp / count,
      avgMoisture: totalMoisture / count,
      avgPH: totalPH / count,
      avgNitrogen: totalNitrogen / count,
      avgPhosphorus: totalPhosphorus / count,
      avgPotassium: totalPotassium / count,
      irrigationCount: 0, // Diisi dari data lain
      fertilizationCount: 0, // Diisi dari data lain
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'avgTemperature': avgTemperature,
      'avgMoisture': avgMoisture,
      'avgPH': avgPH,
      'avgNitrogen': avgNitrogen,
      'avgPhosphorus': avgPhosphorus,
      'avgPotassium': avgPotassium,
      'irrigationCount': irrigationCount,
      'fertilizationCount': fertilizationCount,
    };
  }

  DailyStats copyWith({
    DateTime? date,
    double? avgTemperature,
    double? avgMoisture,
    double? avgPH,
    double? avgNitrogen,
    double? avgPhosphorus,
    double? avgPotassium,
    int? irrigationCount,
    int? fertilizationCount,
  }) {
    return DailyStats(
      date: date ?? this.date,
      avgTemperature: avgTemperature ?? this.avgTemperature,
      avgMoisture: avgMoisture ?? this.avgMoisture,
      avgPH: avgPH ?? this.avgPH,
      avgNitrogen: avgNitrogen ?? this.avgNitrogen,
      avgPhosphorus: avgPhosphorus ?? this.avgPhosphorus,
      avgPotassium: avgPotassium ?? this.avgPotassium,
      irrigationCount: irrigationCount ?? this.irrigationCount,
      fertilizationCount: fertilizationCount ?? this.fertilizationCount,
    );
  }
}

// ================================
// KELAS: ValidatedSensorData
// ================================
class ValidatedSensorData {
  final SensorData data;
  final bool isValid;
  final String? validationMessage;
  final DateTime validationTime;

  ValidatedSensorData({
    required this.data,
    required this.isValid,
    this.validationMessage,
    required this.validationTime,
  });

  factory ValidatedSensorData.fromSensorData(SensorData sensorData) {
    bool valid = true;
    List<String> messages = [];

    // Validasi NPK khusus
    if (sensorData.nitrogen < 0 || sensorData.nitrogen > 1000) {
      valid = false;
      messages.add('Nitrogen di luar range (0-1000 mg/kg)');
    }

    if (sensorData.phosphorus < 0 || sensorData.phosphorus > 1000) {
      valid = false;
      messages.add('Fosfor di luar range (0-1000 mg/kg)');
    }

    if (sensorData.potassium < 0 || sensorData.potassium > 1000) {
      valid = false;
      messages.add('Kalium di luar range (0-1000 mg/kg)');
    }

    // Validasi lainnya
    if (sensorData.soilMoisture < 0 || sensorData.soilMoisture > 100) {
      valid = false;
      messages.add('Kelembapan di luar range (0-100%)');
    }

    if (sensorData.pH < 0 || sensorData.pH > 14) {
      valid = false;
      messages.add('pH di luar range (0-14)');
    }

    if (sensorData.temperature < -50 || sensorData.temperature > 100) {
      valid = false;
      messages.add('Suhu di luar range (-50-100°C)');
    }

    return ValidatedSensorData(
      data: sensorData,
      isValid: valid,
      validationMessage: messages.isNotEmpty ? messages.join(', ') : null,
      validationTime: DateTime.now(),
    );
  }

  @override
  String toString() {
    return '''
ValidatedSensorData {
  Valid: $isValid,
  Pesan: $validationMessage,
  Data: $data
}
''';
  }
}

// ================================
// KELAS: DashboardSummary
// ================================
class DashboardSummary {
  final SensorData latestData;
  final FuzzyAnalysis fuzzyAnalysis;
  final FuzzySugenoAnalysis sugenoAnalysis;
  final SystemStatus systemStatus;
  final TankStatus tankStatus;
  final int unreadNotifications;
  final DateTime lastUpdate;

  DashboardSummary({
    required this.latestData,
    required this.fuzzyAnalysis,
    required this.sugenoAnalysis,
    required this.systemStatus,
    required this.tankStatus,
    required this.unreadNotifications,
    required this.lastUpdate,
  });

  DashboardSummary copyWith({
    SensorData? latestData,
    FuzzyAnalysis? fuzzyAnalysis,
    FuzzySugenoAnalysis? sugenoAnalysis,
    SystemStatus? systemStatus,
    TankStatus? tankStatus,
    int? unreadNotifications,
    DateTime? lastUpdate,
  }) {
    return DashboardSummary(
      latestData: latestData ?? this.latestData,
      fuzzyAnalysis: fuzzyAnalysis ?? this.fuzzyAnalysis,
      sugenoAnalysis: sugenoAnalysis ?? this.sugenoAnalysis,
      systemStatus: systemStatus ?? this.systemStatus,
      tankStatus: tankStatus ?? this.tankStatus,
      unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  @override
  String toString() {
    return '''
DashboardSummary {
  Update Terakhir: ${lastUpdate.toLocal().toString()},
  Notifikasi Belum Dibaca: $unreadNotifications,
  Status Sistem: $systemStatus,
  Status Tangki: $tankStatus
}
''';
  }
}

// ================================
// KELAS: AlertThresholds
// ================================
class AlertThresholds {
  final double moistureLow;
  final double moistureHigh;
  final double pHLow;
  final double pHHigh;
  final double tempLow;
  final double tempHigh;
  final double waterTankLow;
  final double fertilizerTankLow;

  AlertThresholds({
    this.moistureLow = 20.0,
    this.moistureHigh = 80.0,
    this.pHLow = 5.5,
    this.pHHigh = 7.5,
    this.tempLow = 15.0,
    this.tempHigh = 35.0,
    this.waterTankLow = 10.0, // dalam cm
    this.fertilizerTankLow = 10.0, // dalam cm
  });

  factory AlertThresholds.defaults() {
    return AlertThresholds();
  }

  factory AlertThresholds.fromMap(Map<String, dynamic> map) {
    return AlertThresholds(
      moistureLow: (map['moistureLow'] as num?)?.toDouble() ?? 20.0,
      moistureHigh: (map['moistureHigh'] as num?)?.toDouble() ?? 80.0,
      pHLow: (map['pHLow'] as num?)?.toDouble() ?? 5.5,
      pHHigh: (map['pHHigh'] as num?)?.toDouble() ?? 7.5,
      tempLow: (map['tempLow'] as num?)?.toDouble() ?? 15.0,
      tempHigh: (map['tempHigh'] as num?)?.toDouble() ?? 35.0,
      waterTankLow: (map['waterTankLow'] as num?)?.toDouble() ?? 10.0,
      fertilizerTankLow: (map['fertilizerTankLow'] as num?)?.toDouble() ?? 10.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'moistureLow': moistureLow,
      'moistureHigh': moistureHigh,
      'pHLow': pHLow,
      'pHHigh': pHHigh,
      'tempLow': tempLow,
      'tempHigh': tempHigh,
      'waterTankLow': waterTankLow,
      'fertilizerTankLow': fertilizerTankLow,
    };
  }

  AlertThresholds copyWith({
    double? moistureLow,
    double? moistureHigh,
    double? pHLow,
    double? pHHigh,
    double? tempLow,
    double? tempHigh,
    double? waterTankLow,
    double? fertilizerTankLow,
  }) {
    return AlertThresholds(
      moistureLow: moistureLow ?? this.moistureLow,
      moistureHigh: moistureHigh ?? this.moistureHigh,
      pHLow: pHLow ?? this.pHLow,
      pHHigh: pHHigh ?? this.pHHigh,
      tempLow: tempLow ?? this.tempLow,
      tempHigh: tempHigh ?? this.tempHigh,
      waterTankLow: waterTankLow ?? this.waterTankLow,
      fertilizerTankLow: fertilizerTankLow ?? this.fertilizerTankLow,
    );
  }
}

// ================================
// KELAS: UnitConverter
// ================================
class UnitConverter {
  static double celsiusToFahrenheit(double celsius) {
    return (celsius * 9 / 5) + 32;
  }

  static double fahrenheitToCelsius(double fahrenheit) {
    return (fahrenheit - 32) * 5 / 9;
  }

  static double dsmToUsCm(double dsm) {
    return dsm * 1000;
  }

  static double usCmToDsm(double usCm) {
    return usCm / 1000;
  }

  static double mgKgToPpm(double mgKg) {
    return mgKg; // 1 mg/kg = 1 ppm untuk tanah
  }

  static double ppmToMgKg(double ppm) {
    return ppm;
  }

  // Konversi cm ke persen
  static double cmToPercent(double cm, double totalHeight) {
    return (cm / totalHeight) * 100;
  }

  // Konversi persen ke cm
  static double percentToCm(double percent, double totalHeight) {
    return (percent / 100) * totalHeight;
  }

  // Konversi dS/m ke µS/cm
  static double dsmToUscm(double dsm) {
    return dsm * 1000;
  }

  // Konversi µS/cm ke dS/m
  static double uscmToDsm(double uscm) {
    return uscm / 1000;
  }
}

// ================================
// KELAS: SoilCondition
// ================================
class SoilCondition {
  final SensorData sensorData;
  final TankStatus tankStatus;
  final SystemStatus systemStatus;
  final DateTime analysisTime;

  SoilCondition({
    required this.sensorData,
    required this.tankStatus,
    required this.systemStatus,
    required this.analysisTime,
  });

  // Analisis kondisi tanah secara menyeluruh
  String get overallCondition {
    // Prioritaskan kondisi kritis
    if (sensorData.soilMoisture < 20) return 'KRITIS - Tanah Sangat Kering';
    if (sensorData.soilMoisture > 80) return 'KRITIS - Tanah Terlalu Basah';
    if (tankStatus.isWaterTankCritical) return 'KRITIS - Tangki Air Kosong';
    if (tankStatus.isFertilizerTankCritical)
      return 'KRITIS - Tangki Pupuk Kosong';
    if (sensorData.pH < 5.0 || sensorData.pH > 8.0)
      return 'PERINGATAN - pH Ekstrem';

    // Kondisi optimal
    if (sensorData.soilMoisture >= 40 &&
        sensorData.soilMoisture <= 60 &&
        sensorData.pH >= 6.0 &&
        sensorData.pH <= 7.5 &&
        sensorData.nitrogen >= 20 &&
        sensorData.phosphorus >= 15 &&
        sensorData.potassium >= 100) {
      return 'OPTIMAL - Kondisi Tanah Sangat Baik';
    }

    // Kondisi peringatan
    if (sensorData.soilMoisture < 40 || sensorData.soilMoisture > 60) {
      return 'PERINGATAN - Kelembapan Tidak Optimal';
    }

    if (sensorData.pH < 6.0 || sensorData.pH > 7.5) {
      return 'PERINGATAN - pH Tidak Optimal';
    }

    if (sensorData.nitrogen < 20 ||
        sensorData.phosphorus < 15 ||
        sensorData.potassium < 100) {
      return 'PERINGATAN - Nutrisi Rendah';
    }

    return 'NORMAL - Kondisi Tanah Baik';
  }

  // Rekomendasi tindakan
  String get recommendation {
    List<String> recommendations = [];

    // Rekomendasi berdasarkan kelembapan
    if (sensorData.soilMoisture < 20) {
      recommendations.add('SIARKAN AIR SEGERA - Tanah sangat kering');
    } else if (sensorData.soilMoisture < 40) {
      recommendations.add('SIARKAN AIR - Kelembapan rendah');
    } else if (sensorData.soilMoisture > 80) {
      recommendations.add('HENTIKAN PENYIRAMAN - Tanah terlalu basah');
    }

    // Rekomendasi berdasarkan NPK
    if (sensorData.nitrogen < 20) {
      recommendations.add('BERIKAN PUPUK NITROGEN - Kadar rendah');
    }
    if (sensorData.phosphorus < 15) {
      recommendations.add('BERIKAN PUPUK FOSFOR - Kadar rendah');
    }
    if (sensorData.potassium < 100) {
      recommendations.add('BERIKAN PUPUK KALIUM - Kadar rendah');
    }

    // Rekomendasi berdasarkan pH
    if (sensorData.pH < 5.0) {
      recommendations.add('TAMBAHKAN KAPUR - pH terlalu asam');
    } else if (sensorData.pH < 6.0) {
      recommendations.add('PERTIMBANGKAN PENGAPURAN - pH agak asam');
    } else if (sensorData.pH > 8.0) {
      recommendations.add('TAMBAHKAN BELERANG - pH terlalu basa');
    } else if (sensorData.pH > 7.5) {
      recommendations.add('MONITOR pH - pH agak basa');
    }

    // Rekomendasi berdasarkan tangki
    if (tankStatus.isWaterTankCritical) {
      recommendations.add('ISI TANGKI AIR SEGERA - Level kritis');
    } else if (tankStatus.isWaterTankLow) {
      recommendations.add('PERSIAPKAN PENGISIAN TANGKI AIR - Level rendah');
    }

    if (tankStatus.isFertilizerTankCritical) {
      recommendations.add('ISI TANGKI PUPUK SEGERA - Level kritis');
    } else if (tankStatus.isFertilizerTankLow) {
      recommendations.add('PERSIAPKAN PENGISIAN TANGKI PUPUK - Level rendah');
    }

    // Jika tidak ada rekomendasi
    if (recommendations.isEmpty) {
      return 'Tidak ada tindakan khusus diperlukan. Kondisi optimal.';
    }

    return recommendations.join('\n');
  }

  // Status warna
  Color get statusColor {
    final condition = overallCondition;
    if (condition.contains('KRITIS')) return Colors.red;
    if (condition.contains('PERINGATAN')) return Colors.orange;
    if (condition.contains('OPTIMAL')) return Colors.green;
    return Colors.blue;
  }

  @override
  String toString() {
    return '''
SoilCondition {
  Kondisi: $overallCondition,
  Rekomendasi: $recommendation,
  Waktu Analisis: $analysisTime
}
''';
  }
}

// ================================
// KELAS: IrrigationSystem
// ================================
class IrrigationSystem {
  final bool isAutoMode;
  final bool waterPumpActive;
  final bool fertilizerPumpActive;
  final DateTime lastActivation;
  final String activationReason;

  IrrigationSystem({
    required this.isAutoMode,
    required this.waterPumpActive,
    required this.fertilizerPumpActive,
    required this.lastActivation,
    required this.activationReason,
  });

  factory IrrigationSystem.fromFirebase(Map<String, dynamic>? data) {
    if (data == null) {
      return IrrigationSystem(
        isAutoMode: true,
        waterPumpActive: false,
        fertilizerPumpActive: false,
        lastActivation: DateTime.now(),
        activationReason: 'System initialized',
      );
    }

    return IrrigationSystem(
      isAutoMode: data['mode']?.toString() == 'auto',
      waterPumpActive: data['pompa_air_status'] == true,
      fertilizerPumpActive: data['pompa_pupuk_status'] == true,
      lastActivation: DateTime.now(),
      activationReason:
          data['activation_reason']?.toString() ?? 'Automatic control',
    );
  }

  String get statusDescription {
    if (waterPumpActive && fertilizerPumpActive) {
      return 'Menyiram Air dan Pupuk';
    } else if (waterPumpActive) {
      return 'Menyiram Air';
    } else if (fertilizerPumpActive) {
      return 'Menyiram Pupuk';
    } else {
      return 'Tidak Menyiram';
    }
  }

  Color get statusColor {
    if (waterPumpActive || fertilizerPumpActive) {
      return Colors.green;
    }
    return Colors.grey;
  }

  @override
  String toString() {
    return '''
IrrigationSystem {
  Mode: ${isAutoMode ? 'Auto' : 'Manual'},
  Status: $statusDescription,
  Aktivasi Terakhir: $lastActivation,
  Alasan: $activationReason
}
''';
  }
}

// ================================
// KELAS: DataFormatter
// ================================
class DataFormatter {
  static String formatDouble(double value, int decimals) {
    return value.toStringAsFixed(decimals);
  }

  static String formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  static String formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hari lalu';
    } else {
      return formatDateTime(dateTime);
    }
  }

  static String formatTankLevel(double levelCm) {
    return '${levelCm.toStringAsFixed(1)} cm';
  }

  static String formatNPKValue(double value) {
    return '${value.toStringAsFixed(0)} mg/kg';
  }

  static String formatMoisture(double moisture) {
    return '${moisture.toStringAsFixed(1)}%';
  }

  static String formatTemperature(double temperature) {
    return '${temperature.toStringAsFixed(1)}°C';
  }

  static String formatPH(double ph) {
    return ph.toStringAsFixed(1);
  }

  static String formatConductivity(double conductivity) {
    return '${conductivity.toStringAsFixed(0)} µS/cm';
  }

  static String formatFuzzyOutput(int fuzzyOutput) {
    switch (fuzzyOutput) {
      case 0: return 'None';
      case 1: return 'Pupuk';
      case 2: return 'Air+Pupuk';
      case 3: return 'Air';
      default: return 'Unknown';
    }
  }
}

// ================================
// EXTENSIONS
// ================================

// Extension untuk NotificationType
extension NotificationTypeExtension on NotificationType {
  Color get color {
    switch (this) {
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.info:
        return Colors.blue;
      case NotificationType.success:
        return Colors.green;
      case NotificationType.danger:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.info:
        return Icons.info;
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.danger:
        return Icons.error;
    }
  }

  String get displayName {
    switch (this) {
      case NotificationType.warning:
        return 'Peringatan';
      case NotificationType.info:
        return 'Informasi';
      case NotificationType.success:
        return 'Berhasil';
      case NotificationType.danger:
        return 'Bahaya';
    }
  }
}

// Extension untuk SensorData
extension SensorDataExtensions on SensorData {
  // Status kelembapan
  String get moistureStatus {
    if (soilMoisture < 20) return 'Sangat Kering';
    if (soilMoisture < 40) return 'Kering';
    if (soilMoisture < 60) return 'Optimal';
    if (soilMoisture < 80) return 'Basah';
    return 'Sangat Basah';
  }

  Color get moistureColor {
    if (soilMoisture < 20) return Colors.red;
    if (soilMoisture < 40) return Colors.orange;
    if (soilMoisture < 60) return Colors.green;
    if (soilMoisture < 80) return Colors.blue;
    return Colors.purple;
  }

  // Status pH
  String get pHStatus {
    if (pH < 5.0) return 'Sangat Asam';
    if (pH < 6.0) return 'Asam';
    if (pH < 7.5) return 'Optimal';
    if (pH < 8.5) return 'Basa';
    return 'Sangat Basa';
  }

  Color get pHColor {
    if (pH < 5.0) return Colors.red;
    if (pH < 6.0) return Colors.orange;
    if (pH < 7.5) return Colors.green;
    if (pH < 8.5) return Colors.orange;
    return Colors.red;
  }

  // Status suhu
  String get temperatureStatus {
    if (temperature < 15) return 'Sangat Dingin';
    if (temperature < 25) return 'Dingin';
    if (temperature < 32) return 'Optimal';
    if (temperature < 38) return 'Panas';
    return 'Sangat Panas';
  }

  Color get temperatureColor {
    if (temperature < 15) return Colors.blue;
    if (temperature < 25) return Colors.lightBlue;
    if (temperature < 32) return Colors.green;
    if (temperature < 38) return Colors.orange;
    return Colors.red;
  }

  // Status suhu tanah
  String get soilTemperatureStatus {
    if (soilTemperature < 15) return 'Sangat Dingin';
    if (soilTemperature < 25) return 'Dingin';
    if (soilTemperature < 32) return 'Optimal';
    if (soilTemperature < 38) return 'Panas';
    return 'Sangat Panas';
  }

  Color get soilTemperatureColor {
    if (soilTemperature < 15) return Colors.blue;
    if (soilTemperature < 25) return Colors.lightBlue;
    if (soilTemperature < 32) return Colors.green;
    if (soilTemperature < 38) return Colors.orange;
    return Colors.red;
  }

  // Status konduktivitas
  String get conductivityStatus {
    if (conductivity < 200) return 'Sangat Rendah';
    if (conductivity < 400) return 'Rendah';
    if (conductivity < 800) return 'Optimal';
    if (conductivity < 1200) return 'Tinggi';
    return 'Sangat Tinggi';
  }

  Color get conductivityColor {
    if (conductivity < 200 || conductivity > 1200) return Colors.red;
    if (conductivity < 400 || conductivity > 800) return Colors.orange;
    return Colors.green;
  }

  // Status nutrisi NPK berdasarkan tabel standar
  String get npkStatus {
    int optimalCount = 0;
    int needCount = 0;
    int highCount = 0;

    // Nitrogen: <10 = rendah, 20-40 = medium, >40 = tinggi
    if (nitrogen >= 20 && nitrogen <= 40) {
      optimalCount++;
    } else if (nitrogen < 10) {
      needCount++;
    } else if (nitrogen > 40) {
      highCount++;
    }

    // Phosphorus: ≤25 = perlu P, 26-45 = cukup, >45 = tinggi
    if (phosphorus >= 26 && phosphorus <= 45) {
      optimalCount++;
    } else if (phosphorus <= 25) {
      needCount++;
    } else if (phosphorus > 45) {
      highCount++;
    }

    // Potassium: ≤35 = perlu K, 36-60 = cukup, >60 = tinggi
    if (potassium >= 36 && potassium <= 60) {
      optimalCount++;
    } else if (potassium <= 35) {
      needCount++;
    } else if (potassium > 60) {
      highCount++;
    }

    // Prioritaskan kondisi kritis
    if (needCount > 0) {
      return '$needCount nutrisi perlu';
    }
    if (highCount > 0) {
      return '$highCount nutrisi tinggi';
    }
    if (optimalCount == 3) {
      return 'Optimal';
    }
    if (optimalCount >= 2) {
      return 'Cukup';
    }
    return 'Perlu penyesuaian';
  }

  Color get npkColor {
    int needCount = 0;
    int highCount = 0;

    // Nitrogen
    if (nitrogen < 10) needCount++;
    if (nitrogen > 40) highCount++;

    // Phosphorus
    if (phosphorus <= 25) needCount++;
    if (phosphorus > 45) highCount++;

    // Potassium
    if (potassium <= 35) needCount++;
    if (potassium > 60) highCount++;

    if (needCount > 0) return Colors.red;
    if (highCount > 0) return Colors.orange;

    // Check jika semua optimal
    if ((nitrogen >= 20 && nitrogen <= 40) &&
        (phosphorus >= 26 && phosphorus <= 45) &&
        (potassium >= 36 && potassium <= 60)) {
      return Colors.green;
    }

    return Colors.blue;
  }

// Status masing-masing nutrisi berdasarkan tabel standar
  String get nitrogenStatus {
    if (nitrogen < 10) return 'Rendah';
    if (nitrogen < 20) return 'Medium';
    if (nitrogen <= 40) return 'Cukup';
    return 'Tinggi';
  }

  String get phosphorusStatus {
    if (phosphorus <= 25) return 'Perlu P';
    if (phosphorus <= 45) return 'Cukup';
    return 'Tinggi';
  }

  String get potassiumStatus {
    if (potassium <= 35) return 'Perlu K';
    if (potassium <= 60) return 'Cukup';
    return 'Tinggi';
  }

// Warna masing-masing nutrisi berdasarkan tabel standar
  Color get nitrogenColor {
    if (nitrogen < 10) return Colors.red;
    if (nitrogen < 20) return Colors.orange;
    if (nitrogen <= 40) return Colors.green;
    return Colors.orange; // Tinggi = orange (peringatan)
  }

  Color get phosphorusColor {
    if (phosphorus <= 25) return Colors.red;
    if (phosphorus <= 45) return Colors.green;
    return Colors.orange; // Tinggi = orange (peringatan)
  }

  Color get potassiumColor {
    if (potassium <= 35) return Colors.red;
    if (potassium <= 60) return Colors.green;
    return Colors.orange; // Tinggi = orange (peringatan)
  }
}

// Extension untuk mendapatkan icon berdasarkan status
extension StatusIconExtension on SensorData {
  IconData get moistureIcon {
    if (soilMoisture < 20) return Icons.water_drop_outlined;
    if (soilMoisture < 40) return Icons.water_drop;
    if (soilMoisture < 60) return Icons.water_drop;
    return Icons.water;
  }

  IconData get pHIcon {
    if (pH < 5.0 || pH > 8.5) return Icons.warning;
    if (pH < 6.0 || pH > 7.5) return Icons.info;
    return Icons.check_circle;
  }

  IconData get temperatureIcon {
    if (temperature < 15 || temperature > 38) return Icons.warning;
    if (temperature < 25 || temperature > 32) return Icons.info;
    return Icons.thermostat_auto;
  }

  IconData get soilTemperatureIcon {
    if (soilTemperature < 15 || soilTemperature > 38) return Icons.warning;
    if (soilTemperature < 25 || soilTemperature > 32) return Icons.info;
    return Icons.thermostat_auto;
  }

  IconData get conductivityIcon {
    if (conductivity < 200 || conductivity > 1200) return Icons.warning;
    if (conductivity < 400 || conductivity > 800) return Icons.info;
    return Icons.electrical_services;
  }

  IconData get npkIcon {
    int needCount = 0;
    int highCount = 0;

    // Nitrogen
    if (nitrogen < 10) needCount++;
    if (nitrogen > 40) highCount++;

    // Phosphorus
    if (phosphorus <= 25) needCount++;
    if (phosphorus > 45) highCount++;

    // Potassium
    if (potassium <= 35) needCount++;
    if (potassium > 60) highCount++;

    if (needCount > 0) return Icons.warning;
    if (highCount > 0) return Icons.info;

    // Check jika semua optimal
    if ((nitrogen >= 20 && nitrogen <= 40) &&
        (phosphorus >= 26 && phosphorus <= 45) &&
        (potassium >= 36 && potassium <= 60)) {
      return Icons.check_circle;
    }

    return Icons.help;
  }
}