import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data.dart';

class FirebaseService extends ChangeNotifier {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _currentDataSubscription;
  StreamSubscription<DatabaseEvent>? _historyDataSubscription;
  StreamSubscription<DatabaseEvent>? _controlsSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;

  // Stream Controllers
  final StreamController<SensorData?> _sensorDataController =
      StreamController<SensorData?>.broadcast();
  final StreamController<TankStatus> _tankStatusController =
      StreamController<TankStatus>.broadcast();
  final StreamController<SystemStatus> _systemStatusController =
      StreamController<SystemStatus>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<List<SensorData>> _historyController =
      StreamController<List<SensorData>>.broadcast();

  // Data state
  SensorData? _currentSensorData;
  List<SensorData> _historicalData = [];
  SystemStatus _systemStatus = SystemStatus.auto();
  TankStatus _tankStatus = TankStatus(
    waterTankDistance: 20.0,
    fertilizerTankDistance: 20.0,
    timestamp: DateTime.now(),
  );
  bool _isConnected = false;
  String _lastError = '';
  DateTime _lastUpdate = DateTime.now();
  String _deviceStatus = 'Disconnected';

  // Optimasi: Throttle yang lebih responsif
  DateTime _lastNotifyTime = DateTime.now();
  final Duration _minNotifyInterval = Duration(milliseconds: 300);
  Timer? _throttleTimer;

  // Cache untuk mencegah rebuild yang tidak perlu
  SensorData? _lastEmittedSensorData;
  TankStatus? _lastEmittedTankStatus;
  SystemStatus? _lastEmittedSystemStatus;

  // Debug mode
  bool _debugMode = true;

  // Getters
  Stream<SensorData?> get sensorDataStream => _sensorDataController.stream;
  Stream<TankStatus> get tankStatusStream => _tankStatusController.stream;
  Stream<SystemStatus> get systemStatusStream => _systemStatusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<List<SensorData>> get historyStream => _historyController.stream;

  SensorData? get currentSensorData => _currentSensorData;
  List<SensorData> get historicalData => _historicalData;
  SystemStatus get systemStatus => _systemStatus;
  TankStatus get tankStatus => _tankStatus;
  bool get isConnected => _isConnected;
  String get lastError => _lastError;
  DateTime get lastUpdate => _lastUpdate;
  String get deviceStatus => _deviceStatus;

  FirebaseService() {
    _configureFirebaseForPerformance();
    startListening();
  }

  void _configureFirebaseForPerformance() {
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      FirebaseDatabase.instance.setPersistenceCacheSizeBytes(5000000);
      _database.keepSynced(true);
      _logDebug('✅ Firebase performance configured');
    } catch (e) {
      _logDebug('⚠️ Could not configure Firebase persistence: $e');
    }
  }

  void startListening() {
    _logDebug('🔥 Memulai listening Firebase...');
    _listenToCurrentData();
    _listenToHistoryData();
    _listenToControls();
    _listenToConnectionStatus();
  }

  void stopListening() {
    _logDebug('🛑 Menghentikan listening Firebase...');
    _currentDataSubscription?.cancel();
    _historyDataSubscription?.cancel();
    _controlsSubscription?.cancel();
    _connectionSubscription?.cancel();
    _throttleTimer?.cancel();
  }

  // ============================================
  // THROTTLE OPTIMASI
  // ============================================
  void _safeNotifyListeners() {
    _throttleTimer?.cancel();
    _throttleTimer = Timer(_minNotifyInterval, () {
      if (_hasStateChanged()) {
        _logDebug('🔄 Notifying listeners (throttled)');
        notifyListeners();
        _updateLastEmittedState();
      }
    });
  }

  void _criticalNotifyListeners() {
    _logDebug('🚨 CRITICAL: Notifying listeners immediately');
    notifyListeners();
    _updateLastEmittedState();
  }

  bool _hasStateChanged() {
    return _currentSensorData != _lastEmittedSensorData ||
        !_tankStatusEquals(_tankStatus, _lastEmittedTankStatus) ||
        !_systemStatusEquals(_systemStatus, _lastEmittedSystemStatus);
  }

  void _updateLastEmittedState() {
    _lastEmittedSensorData = _currentSensorData;
    _lastEmittedTankStatus = _tankStatus.copyWith();
    _lastEmittedSystemStatus = _systemStatus.copyWith();
  }

  bool _tankStatusEquals(TankStatus? a, TankStatus? b) {
    if (a == null || b == null) return a == b;
    return a.waterTankDistance == b.waterTankDistance &&
        a.fertilizerTankDistance == b.fertilizerTankDistance;
  }

  bool _systemStatusEquals(SystemStatus? a, SystemStatus? b) {
    if (a == null || b == null) return a == b;
    return a.waterPumpOn == b.waterPumpOn &&
        a.fertilizerPumpOn == b.fertilizerPumpOn &&
        a.irrigationMode == b.irrigationMode;
  }

  // ============================================
  // LISTEN TO CURRENT DATA
  // ============================================
  void _listenToCurrentData() {
    _logDebug('📡 Mendengarkan data current...');

    _currentDataSubscription = _database
        .child('smartfarm/current')
        .onValue
        .listen((DatabaseEvent event) {
      try {
        final data = event.snapshot.value;

        if (data == null) {
          _logDebug('⚠️ Data current kosong');
          return;
        }

        if (data is! Map) {
          _logDebug('❌ Data current bukan Map');
          return;
        }

        final Map<String, dynamic> dataMap = Map<String, dynamic>.from(data);
        _logDebug('📊 Data current diterima (${dataMap.length} fields)');

        // Parsing data sensor
        final newSensorData = SensorData.fromFirebase(dataMap);
        final newTankStatus = TankStatus.fromFirebase(dataMap);

        // Parsing status pompa
        final waterPumpOn = _parsePumpStatus(dataMap, 'air');
        final fertilizerPumpOn = _parsePumpStatus(dataMap, 'pupuk');
        final irrigationMode = dataMap['mode']?.toString() ?? 'auto';

        final newSystemStatus = SystemStatus(
          isOnline: true,
          waterPumpOn: waterPumpOn,
          fertilizerPumpOn: fertilizerPumpOn,
          irrigationMode: irrigationMode,
        );

        _logDebug(
            '🎛️ Status Pompa - Air: $waterPumpOn, Pupuk: $fertilizerPumpOn');

        // Update state
        _currentSensorData = newSensorData;
        _tankStatus = newTankStatus;
        _systemStatus = newSystemStatus;
        _lastUpdate = DateTime.now();
        _isConnected = true;
        _lastError = '';
        _deviceStatus = 'Connected';

        // Emit ke stream controllers
        _sensorDataController.add(newSensorData);
        _tankStatusController.add(newTankStatus);
        _systemStatusController.add(newSystemStatus);
        _connectionController.add(true);

        // Tambah ke history
        _addToHistoryIfNeeded(dataMap);

        _criticalNotifyListeners();
      } catch (e) {
        _lastError = 'Error processing current data: $e';
        _logDebug('❌ Error current data: $e');
        _isConnected = false;
        _deviceStatus = 'Error';
        _connectionController.add(false);
        _criticalNotifyListeners();
      }
    }, onError: (error) {
      _lastError = 'Firebase error: $error';
      _logDebug('❌ Firebase current error: $error');
      _isConnected = false;
      _deviceStatus = 'Firebase Error';
      _connectionController.add(false);
      _criticalNotifyListeners();
    });
  }

  bool _parsePumpStatus(Map<String, dynamic> dataMap, String pumpType) {
    try {
      final statusKey = 'pompa_${pumpType}_status';
      if (dataMap.containsKey(statusKey)) {
        final statusValue = dataMap[statusKey];

        if (statusValue is bool) return statusValue;
        if (statusValue is int) return statusValue == 1;
        if (statusValue is String) {
          final lowerValue = statusValue.toLowerCase().trim();
          return lowerValue == 'on' ||
              lowerValue == 'true' ||
              lowerValue == '1';
        }
      }

      final simpleKey = 'pompa_$pumpType';
      if (dataMap.containsKey(simpleKey)) {
        return _parseBool(dataMap[simpleKey]);
      }

      if (dataMap.containsKey('fuzzy')) {
        final fuzzyValue = dataMap['fuzzy'];
        if (fuzzyValue is int) {
          if (pumpType == 'air') {
            return fuzzyValue == 2 || fuzzyValue == 3;
          } else if (pumpType == 'pupuk') {
            return fuzzyValue == 1 || fuzzyValue == 2;
          }
        }
      }

      return false;
    } catch (e) {
      _logDebug('❌ Error parsing pump status $pumpType: $e');
      return false;
    }
  }

  // ============================================
  // LISTEN TO HISTORY DATA - VERSI DIPERBAIKI
  // ============================================
  void _listenToHistoryData() {
    _logDebug('📚 Mendengarkan data history...');

    // Dapatkan tanggal hari ini
    final now = DateTime.now();
    final todayDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final historyPath = 'smartfarm/history/$todayDate';

    _logDebug('📡 Listening ke path: $historyPath');

    _historyDataSubscription =
        _database.child(historyPath).onValue.listen((DatabaseEvent event) {
      try {
        final data = event.snapshot.value;

        if (data == null) {
          _logDebug('⚠️ Data history kosong untuk hari ini');
          _historicalData.clear();
          _historyController.add(_historicalData);
          return;
        }

        if (data is! Map) {
          _logDebug('❌ Struktur data history tidak valid');
          return;
        }

        final Map<dynamic, dynamic> historyMap =
            Map<dynamic, dynamic>.from(data);
        List<SensorData> tempList = [];
        int parsedCount = 0;

        _logDebug('🔍 Processing ${historyMap.length} history items...');

        // Process each history item
        historyMap.forEach((key, value) {
          try {
            if (value is Map) {
              final valueMap = Map<String, dynamic>.from(value);

              try {
                final sensorData = SensorData.fromFirebase(valueMap);
                tempList.add(sensorData);
                parsedCount++;

                if (parsedCount <= 3) {
                  // Log first 3 items for debugging
                  _logDebug('📝 Item $parsedCount: ${sensorData.timestamp} - '
                      'Moist: ${sensorData.soilMoisture}, '
                      'Temp: ${sensorData.temperature}');
                }
              } catch (e) {
                _logDebug('⚠️ Error parsing history item $key: $e');
              }
            }
          } catch (e) {
            _logDebug('⚠️ Error processing history item $key: $e');
          }
        });

        // Sort by timestamp (newest first)
        tempList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        _historicalData = tempList;
        _historyController.add(_historicalData);

        _logDebug('✅ History updated: $parsedCount items loaded');

        // Notify UI
        _criticalNotifyListeners();
      } catch (e) {
        _logDebug('❌ History listener error: $e');
      }
    }, onError: (error) {
      _logDebug('❌ Firebase history error: $error');
    });
  }

  // ============================================
  // REFRESH HISTORICAL DATA - VERSI DIPERBAIKI
  // ============================================
  Future<void> refreshHistoricalData() async {
    try {
      _logDebug('🔄 Memuat ulang data histori...');

      // Dapatkan tanggal hari ini
      final now = DateTime.now();
      final todayDate =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final historyPath = 'smartfarm/history/$todayDate';

      _logDebug('📡 Mengambil data dari: $historyPath');

      // Baca data dari Firebase
      final snapshot = await _database.child(historyPath).once();
      final data = snapshot.snapshot.value;

      if (data == null) {
        _logDebug('⚠️ Tidak ada data histori untuk hari ini');
        _historicalData.clear();
        _historyController.add(_historicalData);
        _criticalNotifyListeners();
        return;
      }

      if (data is! Map) {
        _logDebug('❌ Struktur data tidak valid: ${data.runtimeType}');
        return;
      }

      final Map<dynamic, dynamic> historyData =
          Map<dynamic, dynamic>.from(data);
      List<SensorData> tempList = [];
      int parsedCount = 0;
      int errorCount = 0;

      _logDebug('🔍 Memproses ${historyData.length} data...');

      // Parse semua data
      historyData.forEach((key, value) {
        try {
          if (value != null && value is Map) {
            final valueMap = Map<String, dynamic>.from(value);

            try {
              final sensorData = SensorData.fromFirebase(valueMap);
              tempList.add(sensorData);
              parsedCount++;

              // Debug first 5 items
              if (parsedCount <= 5) {
                _logDebug('📊 Data $parsedCount: ${sensorData.timestamp} - '
                    'Moist: ${sensorData.soilMoisture}, '
                    'pH: ${sensorData.pH}');
              }
            } catch (parseError) {
              errorCount++;
              _logDebug('❌ Gagal parse data $key: $parseError');
            }
          }
        } catch (e) {
          errorCount++;
          _logDebug('⚠️ Error processing item $key: $e');
        }
      });

      // Urutkan dari yang terbaru ke terlama
      tempList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Update state
      _historicalData = tempList;
      _historyController.add(_historicalData);

      _logDebug(
          '✅ Data histori diperbarui: $parsedCount items berhasil, $errorCount error');

      if (_historicalData.isNotEmpty) {
        _logDebug(
            '📈 Data terbaru: ${_formatTime(_historicalData.first.timestamp)}');
        _logDebug(
            '📉 Data terlama: ${_formatTime(_historicalData.last.timestamp)}');
      }

      // Notify UI
      _criticalNotifyListeners();
    } catch (e) {
      _lastError = 'Gagal memuat data histori: $e';
      _logDebug('❌ Error refreshHistoricalData: $e');
      _criticalNotifyListeners();
      rethrow;
    }
  }

  // Helper untuk format waktu debug
  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  // ============================================
  // GET ALL HISTORICAL DATA (untuk debugging)
  // ============================================
  Future<List<SensorData>> getAllHistoricalData() async {
    try {
      // Dapatkan tanggal hari ini
      final now = DateTime.now();
      final todayDate =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final historyPath = 'smartfarm/history/$todayDate';

      final snapshot = await _database.child(historyPath).once();
      final data = snapshot.snapshot.value;

      if (data == null || data is! Map) {
        return [];
      }

      final Map<dynamic, dynamic> historyData =
          Map<dynamic, dynamic>.from(data);
      List<SensorData> result = [];

      historyData.forEach((key, value) {
        try {
          if (value != null && value is Map) {
            final valueMap = Map<String, dynamic>.from(value);
            final sensorData = SensorData.fromFirebase(valueMap);
            result.add(sensorData);
          }
        } catch (e) {
          _logDebug('⚠️ Error parsing item $key: $e');
        }
      });

      // Urutkan dari yang terbaru ke terlama
      result.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return result;
    } catch (e) {
      _logDebug('❌ Error getAllHistoricalData: $e');
      return [];
    }
  }

  // ============================================
  // CONTROLS DATA
  // ============================================
  void _listenToControls() {
    _logDebug('🎛️  Mendengarkan data kontrol...');

    _controlsSubscription = _database
        .child('smartfarm/controls')
        .onValue
        .listen((DatabaseEvent event) {
      try {
        final data = event.snapshot.value;
        if (data == null || data is! Map) {
          return;
        }

        final Map<String, dynamic> dataMap = Map<String, dynamic>.from(data);

        if (dataMap.containsKey('mode')) {
          final newMode = dataMap['mode']?.toString() ?? 'auto';
          if (_systemStatus.irrigationMode != newMode) {
            _systemStatus = _systemStatus.copyWith(
              irrigationMode: newMode,
            );
            _systemStatusController.add(_systemStatus);
            _logDebug('🔄 Mode diupdate ke: $newMode');
            _criticalNotifyListeners();
          }
        }
      } catch (e) {
        _logDebug('❌ Controls error: $e');
      }
    }, onError: (error) {
      _logDebug('❌ Firebase controls error: $error');
    });
  }

  // ============================================
  // CONNECTION STATUS
  // ============================================
  void _listenToConnectionStatus() {
    _logDebug('🌐 Mendengarkan status koneksi...');

    _connectionSubscription = _database
        .child('.info/connected')
        .onValue
        .listen((DatabaseEvent event) {
      try {
        final connected = event.snapshot.value == true;

        if (connected != _isConnected) {
          _isConnected = connected;
          _deviceStatus = connected ? 'Connected' : 'Disconnected';
          _connectionController.add(connected);

          if (connected) {
            _logDebug('✅ Terhubung ke Firebase');
            // Refresh data ketika terhubung
            _forceRefresh();
          } else {
            _lastError = 'Terputus dari Firebase';
            _logDebug('❌ Terputus dari Firebase');
          }
          _criticalNotifyListeners();
        }
      } catch (e) {
        _logDebug('❌ Connection status error: $e');
      }
    });
  }

  // ============================================
  // HELPER FUNCTIONS
  // ============================================
  void _logDebug(String message) {
    if (_debugMode) {
      print('[FirebaseService] ${DateTime.now().toIso8601String()} $message');
    }
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is double) return value == 1.0;
    if (value is String) {
      final lowerValue = value.toLowerCase().trim();
      return lowerValue == 'true' ||
          lowerValue == '1' ||
          lowerValue == 'on' ||
          lowerValue == 'aktif';
    }
    return false;
  }

  void _addToHistoryIfNeeded(Map<String, dynamic> dataMap) {
    try {
      if (_historicalData.isEmpty) {
        _addToHistory(dataMap);
        return;
      }

      final newData = SensorData.fromFirebase(dataMap);
      final lastData = _historicalData.first;

      final bool hasSignificantChange =
          (newData.soilMoisture - lastData.soilMoisture).abs() > 5 ||
              (newData.pH - lastData.pH).abs() > 0.5 ||
              DateTime.now().difference(lastData.timestamp).inMinutes >= 5;

      if (hasSignificantChange) {
        _addToHistory(dataMap);
        _logDebug('📝 Added to history: significant change detected');
      }
    } catch (e) {
      _logDebug('⚠️ Error in addToHistoryIfNeeded: $e');
    }
  }

  void _addToHistory(Map<String, dynamic> dataMap) {
    try {
      final sensorData = SensorData.fromFirebase(dataMap);
      _historicalData.insert(0, sensorData);

      // Batasi jumlah data history
      if (_historicalData.length > 100) {
        _historicalData = _historicalData.take(100).toList();
      }

      _historyController.add(_historicalData);
    } catch (e) {
      _logDebug('⚠️ Error adding to history: $e');
    }
  }

  void _forceRefresh() async {
    try {
      _logDebug('🔄 Force refresh triggered');

      final snapshot = await _database.child('smartfarm/current').once();
      final data = snapshot.snapshot.value;

      if (data != null && data is Map) {
        final dataMap = Map<String, dynamic>.from(data);

        _currentSensorData = SensorData.fromFirebase(dataMap);
        _tankStatus = TankStatus.fromFirebase(dataMap);

        final waterPumpOn = _parsePumpStatus(dataMap, 'air');
        final fertilizerPumpOn = _parsePumpStatus(dataMap, 'pupuk');
        final irrigationMode = dataMap['mode']?.toString() ?? 'auto';

        _systemStatus = SystemStatus(
          isOnline: true,
          waterPumpOn: waterPumpOn,
          fertilizerPumpOn: fertilizerPumpOn,
          irrigationMode: irrigationMode,
        );

        _lastUpdate = DateTime.now();

        _sensorDataController.add(_currentSensorData);
        _tankStatusController.add(_tankStatus);
        _systemStatusController.add(_systemStatus);

        _criticalNotifyListeners();
        _logDebug('✅ Force refresh completed');
      }
    } catch (e) {
      _logDebug('❌ Force refresh error: $e');
    }
  }

  // ============================================
  // PUBLIC METHODS
  // ============================================
  Future<void> sendControl(String controlType, dynamic value) async {
    try {
      final timestamp = DateTime.now().toIso8601String();

      await _database.child('smartfarm/controls').update({
        controlType: value,
        'timestamp': timestamp,
        'controlled_by': 'flutter_app',
      });

      _logDebug('🎮 Control sent: $controlType = $value');
    } catch (e) {
      _lastError = 'Failed to send control: $e';
      _logDebug('❌ Control send error: $e');
      _criticalNotifyListeners();
      rethrow;
    }
  }

  Future<void> togglePump(String pumpType, bool value) async {
    if (pumpType == 'water') {
      await sendControl('pompa_air', value);
    } else if (pumpType == 'fertilizer') {
      await sendControl('pompa_pupuk', value);
    }
  }

  Future<void> changeIrrigationMode(String mode) async {
    if (mode != 'auto' && mode != 'manual') {
      return;
    }

    await sendControl('mode', mode);
    _systemStatus = _systemStatus.copyWith(
      irrigationMode: mode,
    );
    _systemStatusController.add(_systemStatus);
    _logDebug('🔄 Mode changed to: $mode');
  }

  Future<bool> testConnection() async {
    try {
      final snapshot = await _database.child('.info/connected').once();
      final connected = snapshot.snapshot.value == true;

      _isConnected = connected;
      _deviceStatus = connected ? 'Connected' : 'Disconnected';
      _connectionController.add(connected);

      _criticalNotifyListeners();
      return connected;
    } catch (e) {
      _isConnected = false;
      _deviceStatus = 'Connection Error';
      _lastError = 'Connection test failed: $e';
      _connectionController.add(false);
      _criticalNotifyListeners();
      return false;
    }
  }

  Future<void> refreshData() async {
    try {
      _logDebug('🔃 Manual refresh requested');

      final snapshot = await _database.child('smartfarm/current').once();
      final data = snapshot.snapshot.value;

      if (data != null && data is Map) {
        final dataMap = Map<String, dynamic>.from(data);

        _currentSensorData = SensorData.fromFirebase(dataMap);
        _tankStatus = TankStatus.fromFirebase(dataMap);

        final waterPumpOn = _parsePumpStatus(dataMap, 'air');
        final fertilizerPumpOn = _parsePumpStatus(dataMap, 'pupuk');
        final irrigationMode = dataMap['mode']?.toString() ?? 'auto';

        _systemStatus = SystemStatus(
          isOnline: true,
          waterPumpOn: waterPumpOn,
          fertilizerPumpOn: fertilizerPumpOn,
          irrigationMode: irrigationMode,
        );

        _lastUpdate = DateTime.now();
        _isConnected = true;
        _deviceStatus = 'Connected';

        _sensorDataController.add(_currentSensorData);
        _tankStatusController.add(_tankStatus);
        _systemStatusController.add(_systemStatus);
        _connectionController.add(true);

        _criticalNotifyListeners();
        _logDebug('✅ Manual refresh completed');
      }
    } catch (e) {
      _lastError = 'Refresh failed: $e';
      _logDebug('❌ Manual refresh error: $e');
      _criticalNotifyListeners();
    }
  }

  // ============================================
  // DEBUG METHODS
  // ============================================
  Future<void> debugCurrentData() async {
    try {
      final snapshot = await _database.child('smartfarm/current').once();
      final data = snapshot.snapshot.value;

      if (data != null && data is Map) {
        final dataMap = Map<String, dynamic>.from(data);

        print('\n🔥🔥🔥 DEBUG - CURRENT DATA STRUCTURE 🔥🔥🔥');
        print('📋 Total fields: ${dataMap.length}');
        print('=' * 50);

        dataMap.forEach((key, value) {
          print('📌 $key: $value (${value.runtimeType})');
        });

        print('=' * 50);
      } else {
        print('❌ DEBUG: Data current kosong atau null');
      }
    } catch (e) {
      print('❌ DEBUG error: $e');
    }
  }

  Future<void> debugHistoricalData() async {
    try {
      final now = DateTime.now();
      final todayDate =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final historyPath = 'smartfarm/history/$todayDate';

      print('\n📚📚📚 DEBUG - HISTORICAL DATA STRUCTURE 📚📚📚');
      print('📡 Path: $historyPath');

      final snapshot = await _database.child(historyPath).once();
      final data = snapshot.snapshot.value;

      if (data == null) {
        print('❌ Tidak ada data history untuk hari ini');
        return;
      }

      if (data is! Map) {
        print('❌ Struktur data tidak valid: ${data.runtimeType}');
        return;
      }

      final Map<dynamic, dynamic> historyData =
          Map<dynamic, dynamic>.from(data);

      print('📊 Total history items: ${historyData.length}');
      print('=' * 50);

      int itemCount = 0;
      historyData.forEach((key, value) {
        itemCount++;
        if (itemCount <= 5) {
          // Show only first 5 items
          print('\n📝 Item $itemCount (key: $key):');
          if (value is Map) {
            final valueMap = Map<String, dynamic>.from(value);
            print('  ⏰ Timestamp: ${valueMap['timestamp']}');
            print('  💧 Moisture: ${valueMap['moisture']}');
            print('  🌡️ Temp Air: ${valueMap['temp_air']}');
            print('  ⚗️ pH: ${valueMap['ph']}');
          }
        }
      });

      if (historyData.length > 5) {
        print('\n📈 ... dan ${historyData.length - 5} data lainnya');
      }

      print('=' * 50);
    } catch (e) {
      print('❌ DEBUG historical error: $e');
    }
  }

  bool get isDeviceActive {
    final difference = DateTime.now().difference(_lastUpdate);
    return difference.inMinutes < 10;
  }

  String get dataFreshness {
    final difference = DateTime.now().difference(_lastUpdate);

    if (difference.inSeconds < 10) {
      return 'Baru saja';
    } else if (difference.inMinutes < 1) {
      return '${difference.inSeconds} detik lalu';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else {
      return '${difference.inDays} hari lalu';
    }
  }

  void clearError() {
    _lastError = '';
    _criticalNotifyListeners();
  }

  void toggleDebugMode() {
    _debugMode = !_debugMode;
    _logDebug('🔧 Debug mode: $_debugMode');
  }

  @override
  void dispose() {
    _logDebug('♻️ Disposing FirebaseService...');
    stopListening();

    _sensorDataController.close();
    _tankStatusController.close();
    _systemStatusController.close();
    _connectionController.close();
    _historyController.close();

    _throttleTimer?.cancel();
    super.dispose();
  }
}
