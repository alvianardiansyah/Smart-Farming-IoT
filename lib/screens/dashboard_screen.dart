import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../services/firebase_service.dart';
import '../widgets/notification_badge.dart';
import 'history_screen.dart';
import 'notifications_screen.dart';

// ============================================
// VIEW MODEL UNTUK SELECTIVE REBUILDING
// ============================================
class DashboardViewModel {
  final SensorData? sensorData;
  final TankStatus tankStatus;
  final SystemStatus systemStatus;
  final bool isConnected;
  final String dataFreshness;
  final int unreadNotifications;
  final DateTime lastUpdate;

  DashboardViewModel({
    required this.sensorData,
    required this.tankStatus,
    required this.systemStatus,
    required this.isConnected,
    required this.dataFreshness,
    required this.unreadNotifications,
    required this.lastUpdate,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DashboardViewModel &&
            sensorData?.timestamp == other.sensorData?.timestamp &&
            tankStatus.timestamp == other.tankStatus.timestamp &&
            systemStatus.waterPumpOn == other.systemStatus.waterPumpOn &&
            systemStatus.fertilizerPumpOn ==
                other.systemStatus.fertilizerPumpOn &&
            isConnected == other.isConnected &&
            dataFreshness == other.dataFreshness &&
            unreadNotifications == other.unreadNotifications &&
            lastUpdate == other.lastUpdate;
  }

  @override
  int get hashCode {
    return Object.hash(
      sensorData?.timestamp,
      tankStatus.timestamp,
      systemStatus.waterPumpOn,
      systemStatus.fertilizerPumpOn,
      isConnected,
      dataFreshness,
      unreadNotifications,
      lastUpdate,
    );
  }
}

// ============================================
// MAIN DASHBOARD SCREEN - VERSI DIPERBAIKI DENGAN THRESHOLD NPK STANDAR
// ============================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Stream subscriptions
  late StreamSubscription<SensorData?> _sensorSubscription;
  late StreamSubscription<TankStatus> _tankSubscription;
  late StreamSubscription<SystemStatus> _systemSubscription;
  late StreamSubscription<bool> _connectionSubscription;

  // Data state
  SensorData? _currentData;
  TankStatus _tankStatus = TankStatus(
    waterTankDistance: 20.0,
    fertilizerTankDistance: 20.0,
    timestamp: DateTime.now(),
  );
  SystemStatus _systemStatus = SystemStatus.auto();
  bool _isConnected = false;

  // Analytics state
  FuzzyAnalysis _analysis = FuzzyAnalysis(
    soilCondition: "Memuat data...",
    recommendation: "Menunggu data dari sensor...",
    score: 0,
    status: "Memuat",
  );
  List<SoilNotification> _notifications = [];
  int _unreadNotifications = 0;
  DateTime _lastDataUpdate = DateTime.now();

  // UI state
  bool _showPumpStatus = false;
  bool _showTankStatus = false;

  // Timers dengan interval yang lebih pendek
  Timer? _analyticsTimer;
  Timer? _dataFreshnessTimer;
  Timer? _staleDataTimer;

  // Key untuk refresh indicator
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _initializeStreams();
    _startOptimizedTimers();

    // Initial data fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialDataFetch();
    });
  }

  // ============================================
  // INITIALIZATION - DIPERBAIKI
  // ============================================
  void _initializeStreams() {
    final firebaseService = context.read<FirebaseService>();

    // Subscribe ke stream dengan callback yang lebih efisien
    _sensorSubscription = firebaseService.sensorDataStream.listen((data) {
      if (mounted && data != null) {
        setState(() {
          _currentData = data;
          _lastDataUpdate = DateTime.now();
        });

        // Update analytics dengan debounce yang lebih pendek
        _triggerAnalyticsUpdate();
      }
    });

    _tankSubscription = firebaseService.tankStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _tankStatus = status;
        });
        _checkCriticalConditions();
      }
    });

    _systemSubscription = firebaseService.systemStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _systemStatus = status;
        });
      }
    });

    _connectionSubscription =
        firebaseService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
        if (connected) {
          _handleReconnection();
        }
      }
    });
  }

  void _startOptimizedTimers() {
    // PERBAIKAN: Analytics timer lebih sering (dari 60 detik ke 15 detik)
    _analyticsTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && _currentData != null) {
        _updateAnalytics();
      }
    });

    // Data freshness timer setiap 5 detik
    _dataFreshnessTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        // Hanya trigger rebuild jika data sudah stale
        final difference = DateTime.now().difference(_lastDataUpdate);
        if (difference.inSeconds > 30 && _isConnected) {
          _checkStaleData();
        }
      }
    });

    // Stale data checker setiap 30 detik
    _staleDataTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _checkStaleData();
      }
    });
  }

  void _initialDataFetch() async {
    // Coba fetch data awal
    final firebaseService = context.read<FirebaseService>();
    await firebaseService.refreshData();

    // Initial analytics update setelah 1 detik
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _currentData != null) {
        _updateAnalytics();
      }
    });
  }

  // ============================================
  // ANALYTICS FUNCTIONS - DIPERBAIKI DENGAN THRESHOLD NPK STANDAR
  // ============================================
  void _triggerAnalyticsUpdate() {
    // Cancel timer sebelumnya
    _analyticsTimer?.cancel();

    // Update analytics segera
    _updateAnalytics();

    // Restart timer dengan interval 15 detik
    _analyticsTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && _currentData != null) {
        _updateAnalytics();
      }
    });
  }

  void _updateAnalytics() {
    if (_currentData == null) return;

    // Generate analysis dengan threshold NPK standar
    final analysis = _generateFuzzyAnalysisStandard(_currentData!, _tankStatus);
    final notifications =
        _generateNotificationsStandard(_currentData!, _tankStatus, analysis);

    if (mounted) {
      setState(() {
        _analysis = analysis;
        _notifications = notifications;
        _unreadNotifications = notifications
            .where((n) =>
                n.type == NotificationType.danger ||
                n.type == NotificationType.warning)
            .length;
      });
    }
  }

  void _checkCriticalConditions() {
    if (_tankStatus.isWaterTankCritical ||
        _tankStatus.isFertilizerTankCritical) {
      // Add immediate notification for critical tank
      setState(() {
        _notifications.insert(
            0,
            SoilNotification.create(
              title: _tankStatus.isWaterTankCritical
                  ? "🚨 KRITIS: Tangki Air Habis!"
                  : "🚨 KRITIS: Tangki Pupuk Habis!",
              message: _tankStatus.isWaterTankCritical
                  ? "Level air ${_tankStatus.waterLevelCm.toStringAsFixed(1)} cm. ISI SEGERA!"
                  : "Level pupuk ${_tankStatus.fertilizerLevelCm.toStringAsFixed(1)} cm. ISI SEGERA!",
              type: NotificationType.danger,
            ));
        _unreadNotifications++;
      });
    }
  }

  void _checkStaleData() {
    final difference = DateTime.now().difference(_lastDataUpdate);

    if (difference.inSeconds > 60 && _isConnected) {
      // Cek apakah notifikasi stale data sudah ada
      final hasStaleNotification =
          _notifications.any((n) => n.title.contains("Data Tidak Terupdate"));

      if (!hasStaleNotification) {
        setState(() {
          _notifications.insert(
              0,
              SoilNotification.create(
                title: "⚠️ Data Tidak Terupdate",
                message:
                    "Data sensor tidak diperbarui selama ${difference.inSeconds} detik. "
                    "Periksa koneksi perangkat.",
                type: NotificationType.warning,
              ));
          _unreadNotifications++;
        });
      }
    }
  }

  void _handleReconnection() {
    // Refresh data ketika terkoneksi kembali
    final firebaseService = context.read<FirebaseService>();
    firebaseService.refreshData();

    // Add reconnection notification
    setState(() {
      _notifications.insert(
          0,
          SoilNotification.create(
            title: "✅ Terhubung Kembali",
            message: "Berhasil terhubung ke server Firebase.",
            type: NotificationType.success,
          ));
    });
  }

  // ============================================
  // ANALYSIS GENERATION DENGAN THRESHOLD NPK STANDAR
  // ============================================
  FuzzyAnalysis _generateFuzzyAnalysisStandard(
      SensorData data, TankStatus tankStatus) {
    double score = 3.0;
    String condition = "";
    String recommendation = "";
    String status = "";

    // Analisis kelembapan tanah
    if (data.soilMoisture < 20) {
      score = 1.0;
      condition = "Tanah sangat kering";
      recommendation = "SIARKAN TANAMAN SEGERA";
      status = "KRITIS";
    } else if (data.soilMoisture < 40) {
      score = 2.0;
      condition = "Tanah kering";
      recommendation = "SIARKAN AIR";
      status = "PERLU PERHATIAN";
    } else if (data.soilMoisture < 60) {
      score = 4.0;
      condition = "Kelembapan tanah optimal";
      recommendation = "TIDAK PERLU PENYIRAMAN";
      status = "BAIK";
    } else if (data.soilMoisture < 80) {
      score = 3.0;
      condition = "Tanah agak basah";
      recommendation = "TIDAK PERLU PENYIRAMAN";
      status = "CUKUP";
    } else {
      score = 2.0;
      condition = "Tanah sangat basah";
      recommendation = "HENTIKAN PENYIRAMAN";
      status = "PERLU PERHATIAN";
    }

    // Analisis NPK berdasarkan threshold standar baru
    String npkCondition = _analyzeNPKStandard(data);
    if (npkCondition.contains("KRITIS")) {
      score = 1.5;
      condition += " & $npkCondition";
      recommendation += " | " + _getNPKRecommendationStandard(data);
      if (status != "KRITIS") status = "PERLU PERHATIAN";
    } else if (npkCondition.contains("Perlu")) {
      score -= 0.5;
      condition += " & $npkCondition";
      recommendation += " | " + _getNPKRecommendationStandard(data);
    } else if (npkCondition.contains("tinggi")) {
      score -= 0.3;
      condition += " & $npkCondition";
      recommendation += " | Kurangi pemupukan";
    }

    // Adjust berdasarkan status tangki
    if (tankStatus.isWaterTankCritical) {
      score = 1.0;
      condition += " (Tangki Air KRITIS)";
      recommendation = "ISI TANGKI AIR SEGERA";
      status = "KRITIS";
    } else if (tankStatus.isWaterTankLow) {
      score -= 0.5;
      if (!recommendation.contains("ISI")) {
        recommendation += " | Persiapkan pengisian tangki air";
      }
    }

    if (tankStatus.isFertilizerTankCritical) {
      score = 1.0;
      condition += " (Tangki Pupuk KRITIS)";
      recommendation = recommendation.contains("ISI")
          ? recommendation.replaceAll("AIR", "AIR DAN PUPUK")
          : "ISI TANGKI PUPUK SEGERA";
      status = "KRITIS";
    } else if (tankStatus.isFertilizerTankLow) {
      score -= 0.5;
      if (!recommendation.contains("ISI")) {
        recommendation += " | Persiapkan pengisian tangki pupuk";
      }
    }

    // Clamp score
    score = score.clamp(1.0, 5.0);

    return FuzzyAnalysis(
      soilCondition: condition,
      recommendation: recommendation,
      score: score,
      status: status,
    );
  }

  // Helper untuk analisis NPK standar baru
  String _analyzeNPKStandard(SensorData data) {
    int needCount = 0;
    int highCount = 0;

    // Cek Nitrogen berdasarkan tabel: <10 = rendah, 20-40 = medium, >40 = tinggi
    if (data.nitrogen < 10)
      needCount++;
    else if (data.nitrogen > 40) highCount++;

    // Cek Phosphorus berdasarkan tabel: ≤25 = perlu P, 26-45 = cukup, >45 = tinggi
    if (data.phosphorus <= 25)
      needCount++;
    else if (data.phosphorus > 45) highCount++;

    // Cek Potassium berdasarkan tabel: ≤35 = perlu K, 36-60 = cukup, >60 = tinggi
    if (data.potassium <= 35)
      needCount++;
    else if (data.potassium > 60) highCount++;

    if (needCount >= 2) return "KRITIS: $needCount nutrisi rendah";
    if (highCount >= 2) return "PERINGATAN: $highCount nutrisi tinggi";
    if (needCount == 1 && highCount == 1) return "NPK tidak seimbang";
    if (needCount == 1) return "Satu nutrisi perlu ditambah";
    if (highCount == 1) return "Satu nutrisi berlebih";

    // Cek jika semua optimal
    if ((data.nitrogen >= 20 && data.nitrogen <= 40) &&
        (data.phosphorus >= 26 && data.phosphorus <= 45) &&
        (data.potassium >= 36 && data.potassium <= 60)) {
      return "NPK optimal";
    }

    return "NPK dalam batas normal";
  }

  // Helper untuk rekomendasi NPK standar baru
  String _getNPKRecommendationStandard(SensorData data) {
    List<String> recommendations = [];

    // Nitrogen: <10 = rendah, 20-40 = medium, >40 = tinggi
    if (data.nitrogen < 10) {
      recommendations.add("tambahkan pupuk N");
    } else if (data.nitrogen > 40) {
      recommendations.add("kurangi pupuk N");
    }

    // Phosphorus: ≤25 = perlu P, 26-45 = cukup, >45 = tinggi
    if (data.phosphorus <= 25) {
      recommendations.add("tambahkan pupuk P");
    } else if (data.phosphorus > 45) {
      recommendations.add("kurangi pupuk P");
    }

    // Potassium: ≤35 = perlu K, 36-60 = cukup, >60 = tinggi
    if (data.potassium <= 35) {
      recommendations.add("tambahkan pupuk K");
    } else if (data.potassium > 60) {
      recommendations.add("kurangi pupuk K");
    }

    if (recommendations.isEmpty) return "Pemupukan optimal";

    return "Sesuaikan " + recommendations.join(", ");
  }

  List<SoilNotification> _generateNotificationsStandard(
      SensorData data, TankStatus tankStatus, FuzzyAnalysis analysis) {
    final List<SoilNotification> notifications = [];

    // Priority: Critical conditions
    if (data.soilMoisture < 20) {
      notifications.add(SoilNotification.create(
        title: "🔴 KRITIS: Tanah Sangat Kering",
        message: "Kelembapan tanah ${data.soilMoisture.toStringAsFixed(1)}%. "
            "SIARKAN SEGERA!",
        type: NotificationType.danger,
      ));
    } else if (data.soilMoisture < 40) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Tanah Kering",
        message: "Kelembapan tanah ${data.soilMoisture.toStringAsFixed(1)}%. "
            "Perlu penyiraman.",
        type: NotificationType.warning,
      ));
    }

    if (data.soilMoisture > 80) {
      notifications.add(SoilNotification.create(
        title: "🔴 KRITIS: Tanah Terlalu Basah",
        message: "Kelembapan tanah ${data.soilMoisture.toStringAsFixed(1)}%. "
            "Risiko kelebihan air.",
        type: NotificationType.danger,
      ));
    }

    // Priority: NPK critical berdasarkan threshold standar
    // Nitrogen <10 = rendah, >40 = tinggi
    if (data.nitrogen < 10) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Nitrogen Rendah",
        message: "Nitrogen ${data.nitrogen.toStringAsFixed(0)} mg/kg. "
            "<10 mg/kg = rendah. Perlu tambah pupuk N.",
        type: NotificationType.warning,
      ));
    } else if (data.nitrogen > 40) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Nitrogen Tinggi",
        message: "Nitrogen ${data.nitrogen.toStringAsFixed(0)} mg/kg. "
            ">40 mg/kg = tinggi. Kurangi pupuk N.",
        type: NotificationType.warning,
      ));
    }

    // Phosphorus ≤25 = perlu P, >45 = tinggi
    if (data.phosphorus <= 25) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Fosfor Rendah",
        message: "Fosfor ${data.phosphorus.toStringAsFixed(0)} mg/kg. "
            "≤25 mg/kg = perlu P. Tambah pupuk P.",
        type: NotificationType.warning,
      ));
    } else if (data.phosphorus > 45) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Fosfor Tinggi",
        message: "Fosfor ${data.phosphorus.toStringAsFixed(0)} mg/kg. "
            ">45 mg/kg = tinggi. Kurangi pupuk P.",
        type: NotificationType.warning,
      ));
    }

    // Potassium ≤35 = perlu K, >60 = tinggi
    if (data.potassium <= 35) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Kalium Rendah",
        message: "Kalium ${data.potassium.toStringAsFixed(0)} mg/kg. "
            "≤35 mg/kg = perlu K. Tambah pupuk K.",
        type: NotificationType.warning,
      ));
    } else if (data.potassium > 60) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Kalium Tinggi",
        message: "Kalium ${data.potassium.toStringAsFixed(0)} mg/kg. "
            ">60 mg/kg = tinggi. Kurangi pupuk K.",
        type: NotificationType.warning,
      ));
    }

    // Priority: Critical tanks
    if (tankStatus.isWaterTankCritical) {
      notifications.add(SoilNotification.create(
        title: "🔴 KRITIS: Tangki Air Hampir Habis",
        message:
            "Level tangki air ${tankStatus.waterLevelCm.toStringAsFixed(1)} cm "
            "(${tankStatus.waterTankPercent.toStringAsFixed(0)}%). ISI SEGERA!",
        type: NotificationType.danger,
      ));
    } else if (tankStatus.isWaterTankLow) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Tangki Air Rendah",
        message:
            "Level tangki air ${tankStatus.waterLevelCm.toStringAsFixed(1)} cm "
            "(${tankStatus.waterTankPercent.toStringAsFixed(0)}%). "
            "Persiapkan pengisian.",
        type: NotificationType.warning,
      ));
    }

    if (tankStatus.isFertilizerTankCritical) {
      notifications.add(SoilNotification.create(
        title: "🔴 KRITIS: Tangki Pupuk Hampir Habis",
        message:
            "Level tangki pupuk ${tankStatus.fertilizerLevelCm.toStringAsFixed(1)} cm "
            "(${tankStatus.fertilizerTankPercent.toStringAsFixed(0)}%). ISI SEGERA!",
        type: NotificationType.danger,
      ));
    } else if (tankStatus.isFertilizerTankLow) {
      notifications.add(SoilNotification.create(
        title: "🟡 PERINGATAN: Tangki Pupuk Rendah",
        message:
            "Level tangki pupuk ${tankStatus.fertilizerLevelCm.toStringAsFixed(1)} cm "
            "(${tankStatus.fertilizerTankPercent.toStringAsFixed(0)}%). "
            "Persiapkan pengisian.",
        type: NotificationType.warning,
      ));
    }

    // Good condition notification
    if (analysis.status == "BAIK" && notifications.isEmpty) {
      notifications.add(SoilNotification.create(
        title: "🟢 SUKSES: Kondisi Optimal",
        message: "Semua parameter dalam kondisi optimal. "
            "${analysis.recommendation}",
        type: NotificationType.success,
      ));
    }

    // Limit notifications for performance
    return notifications.length > 5
        ? notifications.sublist(0, 5)
        : notifications;
  }

  // ============================================
  // UI HELPER FUNCTIONS
  // ============================================
  void _togglePumpStatus() {
    setState(() {
      _showPumpStatus = !_showPumpStatus;
    });
  }

  void _toggleTankStatus() {
    setState(() {
      _showTankStatus = !_showTankStatus;
    });
  }

  void _markNotificationsAsRead() {
    setState(() {
      _unreadNotifications = 0;
      for (var notification in _notifications) {
        notification.isRead = true;
      }
    });
  }

  String _getDataFreshnessText() {
    final difference = DateTime.now().difference(_lastDataUpdate);

    if (difference.inSeconds < 10) {
      return "Baru saja";
    } else if (difference.inSeconds < 60) {
      return "${difference.inSeconds} detik lalu";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes} menit lalu";
    } else if (difference.inHours < 24) {
      return "${difference.inHours} jam lalu";
    } else {
      return "${difference.inDays} hari lalu";
    }
  }

  Color _getAnalysisColor() {
    switch (_analysis.status) {
      case 'BAIK':
        return Colors.green;
      case 'CUKUP':
        return Colors.blue;
      case 'PERLU PERHATIAN':
        return Colors.orange;
      case 'KRITIS':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _handleRefresh() async {
    final firebaseService = context.read<FirebaseService>();
    await firebaseService.refreshData();

    // Tampilkan snackbar konfirmasi
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Memperbarui data...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Update analytics setelah refresh
    if (_currentData != null) {
      _updateAnalytics();
    }
  }

  // ============================================
  // DISPOSE
  // ============================================
  @override
  void dispose() {
    _sensorSubscription.cancel();
    _tankSubscription.cancel();
    _systemSubscription.cancel();
    _connectionSubscription.cancel();

    _analyticsTimer?.cancel();
    _dataFreshnessTimer?.cancel();
    _staleDataTimer?.cancel();

    super.dispose();
  }

  // ============================================
  // BUILD METHOD - DIPERBAIKI DENGAN THRESHOLD NPK STANDAR
  // ============================================
  @override
  Widget build(BuildContext context) {
    return Consumer<FirebaseService>(
      builder: (context, firebaseService, child) {
        return _buildDashboard(firebaseService);
      },
    );
  }

  Widget _buildDashboard(FirebaseService firebaseService) {
    final viewModel = DashboardViewModel(
      sensorData: firebaseService.currentSensorData,
      tankStatus: firebaseService.tankStatus,
      systemStatus: firebaseService.systemStatus,
      isConnected: firebaseService.isConnected,
      dataFreshness: firebaseService.dataFreshness,
      unreadNotifications: _unreadNotifications,
      lastUpdate: firebaseService.lastUpdate,
    );

    return Scaffold(
      appBar: _buildAppBar(viewModel),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _handleRefresh,
        child: _buildContent(viewModel),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(DashboardViewModel viewModel) {
    return AppBar(
      title: Row(
        children: [
          // Real-time connection indicator
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: viewModel.isConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: viewModel.isConnected ? Colors.green : Colors.red,
                width: 1.5,
              ),
            ),
            child: Icon(
              viewModel.isConnected ? Icons.wifi : Icons.wifi_off,
              color: viewModel.isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Farming IoT',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Update: ${_getDataFreshnessText()}',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: Colors.green[700],
      actions: [
        // Notifications Icon
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications, size: 24),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NotificationsScreen(
                      notifications: _notifications,
                      onMarkAsRead: _markNotificationsAsRead,
                    ),
                  ),
                );
              },
            ),
            if (_unreadNotifications > 0)
              NotificationBadge(count: _unreadNotifications),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.history, size: 24),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HistoryScreen(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 24),
          onPressed: _handleRefresh,
          tooltip: 'Refresh data',
        ),
      ],
    );
  }

  Widget _buildContent(DashboardViewModel viewModel) {
    if (!viewModel.isConnected) {
      return _buildOfflineView(viewModel);
    }

    if (viewModel.sensorData == null) {
      return _buildLoadingView();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          // Status Cards
          _buildStatusCards(viewModel),

          // Sensor Data Grid DENGAN THRESHOLD NPK STANDAR
          _buildSensorGridStandard(viewModel.sensorData!),

          // Analysis Card
          _buildAnalysisCard(),

          // Additional Info Cards
          _buildAdditionalCards(viewModel),

          // Spacer
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildOfflineView(DashboardViewModel viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              'Tidak terhubung ke server',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Data terakhir: ${_getDataFreshnessText()}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _handleRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              ),
              child: const Text('Coba Sambung Kembali'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('Memuat data dari sensor...'),
          const SizedBox(height: 10),
          Text(
            'Update terakhir: ${_getDataFreshnessText()}',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards(DashboardViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Pump Status Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatusItem(
                    'Pompa Air',
                    viewModel.systemStatus.waterPumpOn ? 'ON' : 'OFF',
                    Icons.water_drop,
                    viewModel.systemStatus.waterPumpOn
                        ? Colors.blue
                        : Colors.grey,
                  ),
                  _buildStatusItem(
                    'Pompa Pupuk',
                    viewModel.systemStatus.fertilizerPumpOn ? 'ON' : 'OFF',
                    Icons.eco,
                    viewModel.systemStatus.fertilizerPumpOn
                        ? Colors.green
                        : Colors.grey,
                  ),
                  _buildStatusItem(
                    'Mode',
                    viewModel.systemStatus.irrigationMode == 'auto'
                        ? 'Auto'
                        : 'Manual',
                    viewModel.systemStatus.irrigationMode == 'auto'
                        ? Icons.auto_awesome
                        : Icons.construction,
                    viewModel.systemStatus.irrigationMode == 'auto'
                        ? Colors.green
                        : Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tank Status Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTankStatusItem(
                    'Tangki Air',
                    '${viewModel.tankStatus.waterLevelCm.toStringAsFixed(0)} cm',
                    '${viewModel.tankStatus.waterTankPercent.toStringAsFixed(0)}%',
                    viewModel.tankStatus.waterTankColor,
                    viewModel.tankStatus.isWaterTankCritical,
                  ),
                  _buildTankStatusItem(
                    'Tangki Pupuk',
                    '${viewModel.tankStatus.fertilizerLevelCm.toStringAsFixed(0)} cm',
                    '${viewModel.tankStatus.fertilizerTankPercent.toStringAsFixed(0)}%',
                    viewModel.tankStatus.fertilizerTankColor,
                    viewModel.tankStatus.isFertilizerTankCritical,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusItem(
      String title, String status, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          status,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTankStatusItem(String title, String level, String percent,
      Color color, bool isCritical) {
    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                title.contains('Air') ? Icons.water_drop : Icons.eco,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            level,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            percent,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          if (isCritical)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                'KRITIS',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================
  // SENSOR GRID BUILDER DENGAN THRESHOLD NPK STANDAR
  // ============================================
  Widget _buildSensorGridStandard(SensorData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Row 1: Temperature and Moisture
          Row(
            children: [
              _buildSensorCard(
                'Suhu Udara',
                data.temperature,
                '°C',
                Icons.thermostat,
                Colors.orange,
                _getTemperatureStatus(data.temperature),
              ),
              const SizedBox(width: 8),
              _buildSensorCard(
                'Suhu Tanah',
                data.soilTemperature,
                '°C',
                Icons.thermostat,
                Colors.red,
                _getTemperatureStatus(data.soilTemperature),
              ),
              const SizedBox(width: 8),
              _buildSensorCard(
                'Kelembapan',
                data.soilMoisture,
                '%',
                Icons.water_drop,
                Colors.blue,
                _getMoistureStatus(data.soilMoisture),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: pH, EC, Nitrogen (STANDAR BARU)
          Row(
            children: [
              _buildSensorCard(
                'pH',
                data.pH,
                '',
                Icons.science,
                Colors.purple,
                _getPHStatus(data.pH),
              ),
              const SizedBox(width: 8),
              _buildSensorCard(
                'EC',
                data.conductivity,
                'µS/cm',
                Icons.electrical_services,
                Colors.teal,
                _getECStatus(data.conductivity),
              ),
              const SizedBox(width: 8),
              _buildSensorCard(
                'Nitrogen',
                data.nitrogen,
                'mg/kg',
                Icons.eco,
                _getNitrogenColorStandard(data.nitrogen), // STANDAR BARU
                _getNitrogenStatusStandard(data.nitrogen), // STANDAR BARU
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3: Phosphorus, Potassium, NPK Status (STANDAR BARU)
          Row(
            children: [
              _buildSensorCard(
                'Fosfor',
                data.phosphorus,
                'mg/kg',
                Icons.eco,
                _getPhosphorusColorStandard(data.phosphorus), // STANDAR BARU
                _getPhosphorusStatusStandard(data.phosphorus), // STANDAR BARU
              ),
              const SizedBox(width: 8),
              _buildSensorCard(
                'Kalium',
                data.potassium,
                'mg/kg',
                Icons.eco,
                _getPotassiumColorStandard(data.potassium), // STANDAR BARU
                _getPotassiumStatusStandard(data.potassium), // STANDAR BARU
              ),
              const SizedBox(width: 8),
              _buildSensorCard(
                'NPK',
                0,
                '',
                _getNPKIconStandard(data), // STANDAR BARU
                _getNPKColorStandard(data), // STANDAR BARU
                _getNPKOverallStatusStandard(data), // STANDAR BARU
                showValue: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================
  // HELPER FUNCTIONS UNTUK STATUS SENSOR (UMUM)
  // ============================================
  String _getTemperatureStatus(double temp) {
    if (temp < 15) return 'Dingin';
    if (temp < 25) return 'Normal';
    if (temp < 32) return 'Optimal';
    if (temp < 38) return 'Panas';
    return 'S. Panas';
  }

  String _getMoistureStatus(double moisture) {
    if (moisture < 20) return 'Kering';
    if (moisture < 40) return 'Agak Kering';
    if (moisture < 60) return 'Optimal';
    if (moisture < 80) return 'Basah';
    return 'S. Basah';
  }

  String _getPHStatus(double ph) {
    if (ph < 5.0) return 'Asam';
    if (ph < 6.0) return 'Agak Asam';
    if (ph < 7.5) return 'Optimal';
    if (ph < 8.5) return 'Agak Basa';
    return 'Basa';
  }

  String _getECStatus(double ec) {
    if (ec < 200) return 'Rendah';
    if (ec < 400) return 'Agak Rendah';
    if (ec < 800) return 'Optimal';
    if (ec < 1200) return 'Tinggi';
    return 'S. Tinggi';
  }

  // ============================================
  // HELPER FUNCTIONS UNTUK THRESHOLD NPK STANDAR BARU
  // ============================================
  // Nitrogen berdasarkan tabel: <10 = rendah, 20-40 = medium, >40 = tinggi
  String _getNitrogenStatusStandard(double nitrogen) {
    if (nitrogen < 10) return 'Rendah';
    if (nitrogen < 20) return 'Medium';
    if (nitrogen <= 40) return 'Cukup';
    return 'Tinggi';
  }

  Color _getNitrogenColorStandard(double nitrogen) {
    if (nitrogen < 10) return Colors.red;
    if (nitrogen < 20) return Colors.orange;
    if (nitrogen <= 40) return Colors.green;
    return Colors.orange; // Tinggi = orange (peringatan)
  }

  // Phosphorus berdasarkan tabel: ≤25 = perlu P, 26-45 = cukup, >45 = tinggi
  String _getPhosphorusStatusStandard(double phosphorus) {
    if (phosphorus <= 25) return 'Perlu P';
    if (phosphorus <= 45) return 'Cukup';
    return 'Tinggi';
  }

  Color _getPhosphorusColorStandard(double phosphorus) {
    if (phosphorus <= 25) return Colors.red;
    if (phosphorus <= 45) return Colors.green;
    return Colors.orange; // Tinggi = orange (peringatan)
  }

  // Potassium berdasarkan tabel: ≤35 = perlu K, 36-60 = cukup, >60 = tinggi
  String _getPotassiumStatusStandard(double potassium) {
    if (potassium <= 35) return 'Perlu K';
    if (potassium <= 60) return 'Cukup';
    return 'Tinggi';
  }

  Color _getPotassiumColorStandard(double potassium) {
    if (potassium <= 35) return Colors.red;
    if (potassium <= 60) return Colors.green;
    return Colors.orange; // Tinggi = orange (peringatan)
  }

  // ============================================
  // HELPER FUNCTIONS UNTUK STATUS NPK OVERALL STANDAR
  // ============================================
  String _getNPKOverallStatusStandard(SensorData data) {
    int optimalCount = 0;
    int needCount = 0;
    int highCount = 0;

    // Nitrogen: optimal jika 20-40
    if (data.nitrogen >= 20 && data.nitrogen <= 40) {
      optimalCount++;
    } else if (data.nitrogen < 10) {
      needCount++;
    } else if (data.nitrogen > 40) {
      highCount++;
    }

    // Phosphorus: optimal jika 26-45
    if (data.phosphorus >= 26 && data.phosphorus <= 45) {
      optimalCount++;
    } else if (data.phosphorus <= 25) {
      needCount++;
    } else if (data.phosphorus > 45) {
      highCount++;
    }

    // Potassium: optimal jika 36-60
    if (data.potassium >= 36 && data.potassium <= 60) {
      optimalCount++;
    } else if (data.potassium <= 35) {
      needCount++;
    } else if (data.potassium > 60) {
      highCount++;
    }

    // Prioritaskan kondisi kritis/perlu perhatian
    if (needCount > 0) {
      return '$needCount nutrisi rendah';
    }

    if (highCount > 0) {
      return '$highCount nutrisi tinggi';
    }

    // Jika tidak ada yang kritis, tampilkan status optimal
    if (optimalCount == 3) return 'Optimal';
    if (optimalCount >= 2) return 'Cukup';
    return 'Perlu penyesuaian';
  }

  Color _getNPKColorStandard(SensorData data) {
    int needCount = 0;
    int highCount = 0;

    // Nitrogen
    if (data.nitrogen < 10) needCount++;
    if (data.nitrogen > 40) highCount++;

    // Phosphorus
    if (data.phosphorus <= 25) needCount++;
    if (data.phosphorus > 45) highCount++;

    // Potassium
    if (data.potassium <= 35) needCount++;
    if (data.potassium > 60) highCount++;

    if (needCount > 0) return Colors.red;
    if (highCount > 0) return Colors.orange;

    // Check jika semua optimal
    if ((data.nitrogen >= 20 && data.nitrogen <= 40) &&
        (data.phosphorus >= 26 && data.phosphorus <= 45) &&
        (data.potassium >= 36 && data.potassium <= 60)) {
      return Colors.green;
    }

    return Colors.blue; // Netral jika tidak ada kondisi ekstrem
  }

  IconData _getNPKIconStandard(SensorData data) {
    int needCount = 0;
    int highCount = 0;

    if (data.nitrogen < 10) needCount++;
    if (data.nitrogen > 40) highCount++;
    if (data.phosphorus <= 25) needCount++;
    if (data.phosphorus > 45) highCount++;
    if (data.potassium <= 35) needCount++;
    if (data.potassium > 60) highCount++;

    if (needCount > 0) return Icons.warning;
    if (highCount > 0) return Icons.info;

    if ((data.nitrogen >= 20 && data.nitrogen <= 40) &&
        (data.phosphorus >= 26 && data.phosphorus <= 45) &&
        (data.potassium >= 36 && data.potassium <= 60)) {
      return Icons.check_circle;
    }

    return Icons.help;
  }

  // ============================================
  // SENSOR CARD BUILDER
  // ============================================
  Widget _buildSensorCard(
    String title,
    double value,
    String unit,
    IconData icon,
    Color color,
    String status, {
    bool showValue = true,
  }) {
    // Format nilai berdasarkan tipe data
    String formattedValue = _formatSensorValue(title, value);

    // Tentukan ukuran font berdasarkan panjang teks
    double valueFontSize = _getValueFontSize(formattedValue, unit);
    double statusFontSize = _getStatusFontSize(status);

    return Expanded(
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 4),
        child: Container(
          height: 105, // Reduced height to prevent overflow
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title dengan max 1 baris dan ellipsis
              Container(
                height: 30,
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 12),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Value (jika ditampilkan)
              if (showValue)
                Container(
                  height: 32,
                  alignment: Alignment.center,
                  child: Text(
                    '$formattedValue$unit',
                    style: TextStyle(
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Container(
                  height: 32,
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                ),

              // Status Badge dengan fixed height
              Container(
                constraints: const BoxConstraints(maxHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: statusFontSize,
                      color: color,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper untuk format nilai sensor
  String _formatSensorValue(String title, double value) {
    if (title == 'EC' || title == 'Konduktivitas') {
      return value.toStringAsFixed(0);
    } else if (title == 'pH' || title == 'pH Tanah') {
      return value.toStringAsFixed(1);
    } else if (title.contains('Nitrogen') ||
        title.contains('Fosfor') ||
        title.contains('Kalium') ||
        title.contains('NPK')) {
      return value.toStringAsFixed(0);
    } else {
      return value.toStringAsFixed(1);
    }
  }

  // Helper untuk menentukan ukuran font berdasarkan panjang nilai
  double _getValueFontSize(String value, String unit) {
    int totalLength = value.length + unit.length;

    if (totalLength > 8) return 14;
    if (totalLength > 6) return 16;
    return 18;
  }

  // Helper untuk menentukan ukuran font berdasarkan panjang status
  double _getStatusFontSize(String status) {
    if (status.length > 8) return 7;
    if (status.length > 6) return 8;
    return 9;
  }

  // ============================================
  // ANALYSIS CARD BUILDER
  // ============================================
  Widget _buildAnalysisCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Card(
        elevation: 3,
        color: _getAnalysisColor().withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.analytics, color: _getAnalysisColor(), size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Analisis Kondisi Tanah',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Status Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getAnalysisColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getAnalysisColor(), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getAnalysisIcon(),
                      color: _getAnalysisColor(),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _analysis.status,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getAnalysisColor(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Condition Text
              Text(
                _analysis.soilCondition,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              // Recommendation
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rekomendasi:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _analysis.recommendation,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Score Progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Skor Kondisi:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        '${_analysis.score.toStringAsFixed(1)}/5.0',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getAnalysisColor(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (_analysis.score) / 5,
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_getAnalysisColor()),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Update: ${_getDataFreshnessText()}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        'Prioritas: ${_getPriorityText(_analysis.score)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: _getPriorityColor(_analysis.score),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAnalysisIcon() {
    switch (_analysis.status) {
      case 'BAIK':
        return Icons.check_circle;
      case 'CUKUP':
        return Icons.info;
      case 'PERLU PERHATIAN':
        return Icons.warning;
      case 'KRITIS':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  String _getPriorityText(double score) {
    if (score >= 4.0) return 'Rendah';
    if (score >= 3.0) return 'Sedang';
    if (score >= 2.0) return 'Tinggi';
    return 'Sangat Tinggi';
  }

  Color _getPriorityColor(double score) {
    if (score >= 4.0) return Colors.green;
    if (score >= 3.0) return Colors.blue;
    if (score >= 2.0) return Colors.orange;
    return Colors.red;
  }

  // ============================================
  // ADDITIONAL CARDS BUILDER
  // ============================================
  Widget _buildAdditionalCards(DashboardViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Pump Status Detail Card
          _buildExpandableCard(
            title: 'Detail Status Pompa',
            subtitle: 'Informasi lengkap sistem penyiraman',
            icon: Icons.build_circle,
            color: Colors.blue,
            isExpanded: _showPumpStatus,
            onToggle: _togglePumpStatus,
            content: _buildPumpStatusDetail(viewModel.systemStatus),
          ),
          const SizedBox(height: 12),

          // Tank Status Detail Card
          _buildExpandableCard(
            title: 'Detail Level Tangki',
            subtitle: 'Monitor ketersediaan air dan pupuk',
            icon: Icons.inventory_2,
            color: Colors.teal,
            isExpanded: _showTankStatus,
            onToggle: _toggleTankStatus,
            content: _buildTankStatusDetail(viewModel.tankStatus),
          ),
          const SizedBox(height: 12),

          // System Info Card (always visible)
          _buildSystemInfoCard(viewModel),
        ],
      ),
    );
  }

  Widget _buildExpandableCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget content,
  }) {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey,
            ),
            onTap: onToggle,
          ),
          if (isExpanded) content,
        ],
      ),
    );
  }

  Widget _buildPumpStatusDetail(SystemStatus systemStatus) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Water Pump Detail
          _buildPumpDetailRow(
            title: 'Pompa Air',
            isActive: systemStatus.waterPumpOn,
            description: systemStatus.waterPumpOn
                ? 'Sedang menyiram air ke tanaman'
                : 'Siap diaktifkan untuk penyiraman',
            icon: Icons.water_drop,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),

          // Fertilizer Pump Detail
          _buildPumpDetailRow(
            title: 'Pompa Pupuk',
            isActive: systemStatus.fertilizerPumpOn,
            description: systemStatus.fertilizerPumpOn
                ? 'Sedang menyiram pupuk ke tanaman'
                : 'Siap diaktifkan untuk pemupukan',
            icon: Icons.eco,
            color: Colors.green,
          ),
          const SizedBox(height: 12),

          // Mode Detail
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(
                  systemStatus.irrigationMode == 'auto'
                      ? Icons.auto_awesome
                      : Icons.construction,
                  color: systemStatus.irrigationMode == 'auto'
                      ? Colors.green
                      : Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Operasi',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        systemStatus.irrigationModeText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: systemStatus.irrigationMode == 'auto'
                              ? Colors.green
                              : Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        systemStatus.irrigationMode == 'auto'
                            ? 'Sistem akan otomatis mengontrol penyiraman berdasarkan kondisi tanah'
                            : 'Kontrol manual oleh pengguna',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPumpDetailRow({
    required String title,
    required bool isActive,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? color : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive
                  ? color.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? color : Colors.grey, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isActive ? color : Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? color : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isActive ? 'AKTIF' : 'NONAKTIF',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTankStatusDetail(TankStatus tankStatus) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // Water Tank Detail
          _buildTankDetailRow(
            title: 'Tangki Air',
            levelCm: tankStatus.waterLevelCm,
            percent: tankStatus.waterTankPercent,
            isCritical: tankStatus.isWaterTankCritical,
            isLow: tankStatus.isWaterTankLow,
            color: Colors.blue,
            icon: Icons.water_drop,
          ),
          const SizedBox(height: 12),

          // Fertilizer Tank Detail
          _buildTankDetailRow(
            title: 'Tangki Pupuk',
            levelCm: tankStatus.fertilizerLevelCm,
            percent: tankStatus.fertilizerTankPercent,
            isCritical: tankStatus.isFertilizerTankCritical,
            isLow: tankStatus.isFertilizerTankLow,
            color: Colors.green,
            icon: Icons.eco,
          ),
          const SizedBox(height: 12),

          // Tank Information
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text(
                      'Informasi Tangki',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoRow('Tinggi total tangki', '20.0 cm'),
                _buildInfoRow('Jarak sensor ke dasar', '20.0 cm'),
                _buildInfoRow('0 cm dari dasar', 'Tangki penuh'),
                _buildInfoRow('20 cm dari dasar', 'Tangki kosong'),
                _buildInfoRow('< 6 cm dari dasar', 'Status rendah'),
                _buildInfoRow('< 2 cm dari dasar', 'Status kritis'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTankDetailRow({
    required String title,
    required double levelCm,
    required double percent,
    required bool isCritical,
    required bool isLow,
    required Color color,
    required IconData icon,
  }) {
    final statusColor =
        isCritical ? Colors.red : (isLow ? Colors.orange : color);
    final statusText = isCritical ? 'KRITIS' : (isLow ? 'RENDAH' : 'AMAN');
    final statusDescription = isCritical
        ? 'Segera isi ulang tangki!'
        : (isLow ? 'Persiapkan pengisian' : 'Kondisi baik');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    Text(
                      statusDescription,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Level saat ini',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '${levelCm.toStringAsFixed(1)} cm (${percent.toStringAsFixed(0)}%)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey[200],
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: statusColor,
                      gradient: LinearGradient(
                        colors: [
                          statusColor,
                          statusColor.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '0%',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    '100%',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemInfoCard(DashboardViewModel viewModel) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.device_hub, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  'Informasi Sistem',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSystemInfoRow(
                'Status Koneksi',
                viewModel.isConnected ? 'Terhubung' : 'Terputus',
                viewModel.isConnected ? Colors.green : Colors.red),
            _buildSystemInfoRow(
                'Status Perangkat',
                viewModel.isConnected ? 'Aktif' : 'Offline',
                viewModel.isConnected ? Colors.green : Colors.grey),
            _buildSystemInfoRow(
                'Data Terakhir', _getDataFreshnessText(), Colors.blue),
            _buildSystemInfoRow(
                'Mode Operasi',
                viewModel.systemStatus.irrigationModeText,
                viewModel.systemStatus.irrigationMode == 'auto'
                    ? Colors.green
                    : Colors.blue),
            _buildSystemInfoRow(
                'Notifikasi',
                '$_unreadNotifications belum dibaca',
                _unreadNotifications > 0 ? Colors.orange : Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // TAMBAHAN: FUNGSI UNTUK HANDLE REAL-TIME UPDATES
  // ============================================
  void _handleRealTimeUpdate(SensorData newData, TankStatus newTankStatus,
      SystemStatus newSystemStatus) {
    // Cek apakah ada perubahan signifikan yang perlu diupdate UI
    bool needsUpdate = false;

    if (_currentData == null) {
      needsUpdate = true;
    } else {
      // Cek perubahan sensor data
      final moistureDiff =
          (newData.soilMoisture - _currentData!.soilMoisture).abs();
      final tempDiff = (newData.temperature - _currentData!.temperature).abs();
      final pHDiff = (newData.pH - _currentData!.pH).abs();

      if (moistureDiff > 0.5 || tempDiff > 0.5 || pHDiff > 0.1) {
        needsUpdate = true;
      }

      // Cek perubahan tank status
      final waterLevelDiff =
          (newTankStatus.waterLevelCm - _tankStatus.waterLevelCm).abs();
      final fertLevelDiff =
          (newTankStatus.fertilizerLevelCm - _tankStatus.fertilizerLevelCm)
              .abs();

      if (waterLevelDiff > 0.5 || fertLevelDiff > 0.5) {
        needsUpdate = true;
      }

      // Cek perubahan system status
      if (newSystemStatus.waterPumpOn != _systemStatus.waterPumpOn ||
          newSystemStatus.fertilizerPumpOn != _systemStatus.fertilizerPumpOn) {
        needsUpdate = true;
      }
    }

    if (needsUpdate && mounted) {
      setState(() {
        _currentData = newData;
        _tankStatus = newTankStatus;
        _systemStatus = newSystemStatus;
        _lastDataUpdate = DateTime.now();
      });

      // Update analytics untuk data baru
      _triggerAnalyticsUpdate();
    }
  }

  // ============================================
  // TAMBAHAN: ERROR HANDLING DAN RETRY LOGIC
  // ============================================
  void _handleFirebaseError(String error) {
    // Tampilkan error di UI
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: $error'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );

    // Coba reconnect setelah 5 detik
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_isConnected) {
        final firebaseService = context.read<FirebaseService>();
        firebaseService.testConnection();
      }
    });
  }

  // ============================================
  // TAMBAHAN: MEMORY MANAGEMENT
  // ============================================
  void _cleanupOldData() {
    // Bersihkan notifikasi yang sudah lama
    final now = DateTime.now();
    _notifications.removeWhere((notification) {
      final difference = now.difference(notification.timestamp);
      return difference.inDays > 7 && notification.isRead;
    });

    // Update unread count
    _unreadNotifications = _notifications
        .where((n) =>
            !n.isRead &&
            (n.type == NotificationType.danger ||
                n.type == NotificationType.warning))
        .length;
  }

  // ============================================
  // END OF DASHBOARD SCREEN
  // ============================================
}
