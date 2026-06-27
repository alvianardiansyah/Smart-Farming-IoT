import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../models/sensor_data.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SensorData> _displayData = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  final int _maxDataCount = 20; // Maksimal 20 data

  @override
  void initState() {
    super.initState();
    _loadLatestData();
  }

  Future<void> _loadLatestData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      // Refresh data dari Firebase
      await firebaseService.refreshHistoricalData();

      // Ambil semua data dari Firebase
      final List<SensorData> allData = firebaseService.historicalData;

      // Debug: tampilkan data yang diterima
      print(
          '📊 [HistoryScreen] Semua data dari Firebase: ${allData.length} items');

      // Urutkan dari terbaru ke terlama
      allData.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Ambil hanya 20 data terbaru
      _displayData = allData.length <= _maxDataCount
          ? List<SensorData>.from(allData)
          : List<SensorData>.from(allData.sublist(0, _maxDataCount));

      print(
          '📊 [HistoryScreen] Data ditampilkan: ${_displayData.length} dari ${allData.length} total');
      
      // Tampilkan info tentang data yang diabaikan (jika ada)
      if (allData.length > _maxDataCount) {
        final ignoredCount = allData.length - _maxDataCount;
        print('ℹ️ [HistoryScreen] $ignoredCount data terlama diabaikan');
      }

      // Log data yang ditampilkan
      if (_displayData.isNotEmpty) {
        print('📝 [HistoryScreen] Data pertama (terbaru):');
        print('    Waktu: ${_formatDateTime(_displayData.first.timestamp)}');
        print('    Data: ${_displayData.first.toMap()}');
        
        print('📝 [HistoryScreen] Data terakhir (dalam 20 data):');
        print('    Waktu: ${_formatDateTime(_displayData.last.timestamp)}');
        print('    Data: ${_displayData.last.toMap()}');
      }

    } catch (e) {
      print('❌ [HistoryScreen] Error load data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      // Refresh data dari Firebase
      await firebaseService.refreshHistoricalData();

      // Ambil semua data dari Firebase
      final List<SensorData> allData = firebaseService.historicalData;

      // Urutkan dari terbaru ke terlama
      allData.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Ambil hanya 20 data terbaru
      _displayData = allData.length <= _maxDataCount
          ? List<SensorData>.from(allData)
          : List<SensorData>.from(allData.sublist(0, _maxDataCount));

      // Tampilkan snackbar untuk konfirmasi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Data berhasil diperbarui'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );

      print('🔄 [HistoryScreen] Refresh selesai: ${_displayData.length} data ditampilkan');
      
      // Info jika ada data yang diabaikan
      if (allData.length > _maxDataCount) {
        final ignoredCount = allData.length - _maxDataCount;
        print('ℹ️ [HistoryScreen] $ignoredCount data terlama diabaikan');
        
        // Tampilkan toast info tambahan
        Future.delayed(Duration(milliseconds: 100), () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ℹ️ Menampilkan 20 data terbaru dari ${allData.length} total'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.blue,
            ),
          );
        });
      }

    } catch (e) {
      print('❌ [HistoryScreen] Error refresh: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Gagal memperbarui data: $e'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  String _formatDateTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 10) {
      return 'Baru saja';
    } else if (difference.inMinutes < 1) {
      return '${difference.inSeconds} detik lalu';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else {
      return _formatDate(timestamp);
    }
  }

  // Fungsi untuk mendapatkan rentang tanggal dari data
  String _getDateRangeText() {
    if (_displayData.isEmpty) return 'Tidak ada data';
    
    final newest = _displayData.first.timestamp;
    final oldest = _displayData.last.timestamp;
    
    // Jika semua data dalam hari yang sama
    if (_formatDate(newest) == _formatDate(oldest)) {
      return 'Data tanggal ${_formatDate(newest)}';
    } else {
      return 'Data dari ${_formatDate(oldest)} hingga ${_formatDate(newest)}';
    }
  }

  // Dialog detail (tidak berubah)
  Widget _buildSensorDetailDialog(SensorData data) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Detail Data Sensor',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body dengan scroll
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // INFO WAKTU
                    _buildSectionTitle('INFORMASI WAKTU', Colors.blue[700]!),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(data.timestamp),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                Text(
                                  _formatDateTime(data.timestamp),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SUHU
                    _buildSectionTitle('SUHU', Colors.orange[700]!),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildParameterCard(
                            'Suhu Udara',
                            '${data.temperature.toStringAsFixed(1)}°C',
                            Icons.thermostat,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildParameterCard(
                            'Suhu Tanah',
                            '${data.soilTemperature.toStringAsFixed(1)}°C',
                            Icons.grass,
                            Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: _buildParameterCard(
                        'Kelembapan Tanah',
                        '${data.soilMoisture.toStringAsFixed(1)}%',
                        Icons.water_drop,
                        Colors.blue,
                        width: 200,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // KIMIA TANAH
                    _buildSectionTitle('KIMIA TANAH', Colors.purple[700]!),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildParameterCard(
                            'pH Tanah',
                            data.pH.toStringAsFixed(1),
                            Icons.science,
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (data.conductivity != null)
                          Expanded(
                            child: _buildParameterCard(
                              'Konduktivitas',
                              '${data.conductivity!.toStringAsFixed(2)} mS/cm',
                              Icons.electrical_services,
                              Colors.teal,
                            ),
                          )
                        else
                          Expanded(
                            child: _buildParameterCard(
                              'Konduktivitas',
                              'Tidak ada',
                              Icons.electrical_services,
                              Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // NUTRISI (NPK)
                    _buildSectionTitle(
                        'NUTRISI TANAH (NPK)', Colors.green[700]!),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNPKCard('Nitrogen (N)',
                            '${data.nitrogen.toStringAsFixed(0)}', Colors.blue),
                        _buildNPKCard(
                            'Fosfor (P)',
                            '${data.phosphorus.toStringAsFixed(0)}',
                            Colors.orange),
                        _buildNPKCard(
                            'Kalium (K)',
                            '${data.potassium.toStringAsFixed(0)}',
                            Colors.purple),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info, size: 14, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Text(
                            'N:${data.nitrogen} | P:${data.phosphorus} | K:${data.potassium}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tombol tutup
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'TUTUP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildParameterCard(
      String title, String value, IconData icon, Color color,
      {double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNPKCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Text(
            title.split(' ')[0],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title.split(' ')[1],
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final isFirebaseConnected = firebaseService.isConnected;
    final totalDataInFirebase = firebaseService.historicalData.length;
    final displayedCount = _displayData.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Data Sensor'),
        backgroundColor: Colors.green[700],
        actions: [
          // Debug button
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () async {
              print('🐛 [HistoryScreen] Debug button pressed');
              final firebaseService =
                  Provider.of<FirebaseService>(context, listen: false);
              await firebaseService.debugCurrentData();
              await firebaseService.debugHistoricalData();
              
              // Tampilkan info tentang data
              print('📊 [Firebase] Total data: ${firebaseService.historicalData.length}');
              print('📊 [HistoryScreen] Data ditampilkan: $_displayData');
            },
            tooltip: 'Debug data',
          ),
          // Refresh button
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Info
          Card(
            margin: const EdgeInsets.all(12),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!, width: 1),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.format_list_numbered,
                                size: 20, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(
                              '20 DATA TERBARU',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getDateRangeText(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Info status
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Status koneksi dan jumlah data
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isFirebaseConnected
                                  ? Icons.cloud_done
                                  : Icons.cloud_off,
                              size: 16,
                              color: isFirebaseConnected
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isFirebaseConnected ? 'Terhubung' : 'Terputus',
                              style: TextStyle(
                                fontSize: 12,
                                color: isFirebaseConnected
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.data_usage,
                                size: 16, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              '$displayedCount/$totalDataInFirebase data',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Divider(height: 1, color: Colors.grey[300]),
                        const SizedBox(height: 6),

                        // Info data terlama vs terbaru
                        if (_displayData.isNotEmpty)
                          Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.new_releases,
                                      size: 14, color: Colors.green[700]),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Terbaru: ${_formatTimeAgo(_displayData.first.timestamp)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history,
                                      size: 14, color: Colors.orange[700]),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Terlama (dalam 20): ${_formatTimeAgo(_displayData.last.timestamp)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Text(
                            'Menunggu data sensor...',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Data List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.green),
                        SizedBox(height: 12),
                        Text(
                          'Memuat 20 data terbaru...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : !isFirebaseConnected && _displayData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Tidak terhubung ke Firebase',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _displayData.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history_toggle_off,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Belum ada data sensor',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Data akan muncul setelah ESP32 mengirim data',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _refreshData,
                                  child: Text('Refresh Data'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refreshData,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: _displayData.length,
                              itemBuilder: (context, index) {
                                final data = _displayData[index];
                                final isNewest = index == 0;
                                final isOldest = index == _displayData.length - 1;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  elevation: 1,
                                  child: InkWell(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) =>
                                            _buildSensorDetailDialog(data),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        children: [
                                          // Waktu dengan indikator
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  if (isNewest)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green[100],
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.new_releases, 
                                                              size: 12, 
                                                              color: Colors.green[800]),
                                                          SizedBox(width: 2),
                                                          Text(
                                                            'TERBARU',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.green[800],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                  else if (isOldest && _displayData.length == 20)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange[100],
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.history, 
                                                              size: 12, 
                                                              color: Colors.orange[800]),
                                                          SizedBox(width: 2),
                                                          Text(
                                                            'TERLAMA',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.orange[800],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  if (!isNewest && !isOldest)
                                                    Icon(
                                                      Icons.access_time,
                                                      size: 14,
                                                      color: Colors.green[700],
                                                    ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    _formatTimeAgo(data.timestamp),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                      color: isNewest 
                                                          ? Colors.green[800]
                                                          : isOldest 
                                                              ? Colors.orange[800]
                                                              : Colors.green[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                _formatDateTime(data.timestamp),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // Tiga parameter utama
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              // Parameter 1: Suhu Udara
                                              _buildSimpleParameter(
                                                'Suhu',
                                                '${data.temperature.toStringAsFixed(1)}°C',
                                                Icons.thermostat,
                                                Colors.orange,
                                              ),

                                              // Parameter 2: Kelembapan Tanah
                                              _buildSimpleParameter(
                                                'Lembab',
                                                '${data.soilMoisture.toStringAsFixed(1)}%',
                                                Icons.water_drop,
                                                Colors.blue,
                                              ),

                                              // Parameter 3: pH
                                              _buildSimpleParameter(
                                                'pH',
                                                data.pH.toStringAsFixed(1),
                                                Icons.science,
                                                Colors.purple,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),

                                          // Indikator klik untuk detail
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green[50],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Tekan untuk detail lengkap',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.green[700],
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.touch_app,
                                                  size: 10,
                                                  color: Colors.green[700],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleParameter(
      String title, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}