import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../services/firebase_service.dart';

class NotificationsScreen extends StatefulWidget {
  final List<SoilNotification> notifications;
  final VoidCallback onMarkAsRead;

  const NotificationsScreen({
    Key? key,
    required this.notifications,
    required this.onMarkAsRead,
  }) : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<SoilNotification> _notifications = [];
  bool _isLoading = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Inisialisasi tanpa setState terlebih dahulu
    _notifications = widget.notifications.map((notification) {
      return notification.copyWith(isRead: true);
    }).toList();

    // Tunda callback dan sorting sampai setelah frame selesai
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onMarkAsRead(); // Panggil callback untuk menandai sudah dibaca
        _sortNotifications(); // Panggil sorting tanpa risiko error
        _isInitialized = true;
      }
    });
  }

  @override
  void didUpdateWidget(NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update notifications jika widget berubah
    if (widget.notifications != oldWidget.notifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _notifications = widget.notifications.map((notification) {
              return notification.copyWith(isRead: true);
            }).toList();
          });
          _sortNotifications();
        }
      });
    }
  }

  void _sortNotifications() {
    if (!mounted) return;

    // Simpan notifikasi lama untuk perbandingan
    final oldNotifications = List<SoilNotification>.from(_notifications);

    // Sort the list
    _notifications.sort((a, b) {
      final priority = {
        NotificationType.danger: 4,
        NotificationType.warning: 3,
        NotificationType.info: 2,
        NotificationType.success: 1,
      };

      final priorityCompare = priority[b.type]!.compareTo(priority[a.type]!);
      if (priorityCompare != 0) return priorityCompare;

      return b.timestamp.compareTo(a.timestamp);
    });

    // Hanya panggil setState jika ada perubahan
    if (!_listsEqual(oldNotifications, _notifications)) {
      setState(() {});
    }
  }

  bool _listsEqual(List<SoilNotification> a, List<SoilNotification> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Color _getNotificationColor(NotificationType type) {
    return type.color;
  }

  IconData _getNotificationIcon(NotificationType type) {
    return type.icon;
  }

  String _getNotificationTypeText(NotificationType type) {
    return type.displayName;
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} menit lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hari lalu';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks minggu lalu';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  Future<void> _refreshNotifications() async {
    if (_isLoading || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Refresh dengan memanggil data dari Firebase
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);
      final currentData = firebaseService.currentSensorData;
      final tankStatus = firebaseService.tankStatus;

      if (currentData != null) {
        final newNotifications = await _generateNotificationsFromFirebaseData(
            currentData, tankStatus);

        if (mounted) {
          setState(() {
            _notifications =
                newNotifications.map((n) => n.copyWith(isRead: true)).toList();
          });
          _sortNotifications();
        }
      }
    } catch (e) {
      print('Error refreshing notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat notifikasi terbaru'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<SoilNotification>> _generateNotificationsFromFirebaseData(
      SensorData data, TankStatus tankStatus) async {
    List<SoilNotification> notifications = [];

    try {
      // Check for critical conditions
      if (data.soilMoisture < 20) {
        notifications.add(SoilNotification.create(
          title: '🔴 KRITIS: Kelembapan Tanah Sangat Rendah',
          message:
              'Kelembapan tanah: ${data.soilMoisture.toStringAsFixed(1)}%. '
              'SIARKAN TANAMAN SEGERA!',
          type: NotificationType.danger,
        ));
      } else if (data.soilMoisture < 40) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: Kelembapan Tanah Rendah',
          message:
              'Kelembapan tanah: ${data.soilMoisture.toStringAsFixed(1)}%. '
              'Pertimbangkan penyiraman dalam waktu dekat.',
          type: NotificationType.warning,
        ));
      } else if (data.soilMoisture > 80) {
        notifications.add(SoilNotification.create(
          title: '🔴 KRITIS: Kelembapan Tanah Terlalu Tinggi',
          message:
              'Kelembapan tanah: ${data.soilMoisture.toStringAsFixed(1)}%. '
              'Risiko kelebihan air dan busuk akar.',
          type: NotificationType.danger,
        ));
      }

      // Check pH conditions
      if (data.pH < 5.0) {
        notifications.add(SoilNotification.create(
          title: '🔴 KRITIS: pH Tanah Terlalu Asam',
          message: 'pH tanah: ${data.pH.toStringAsFixed(1)}. '
              'Pertimbangkan pengapuran segera.',
          type: NotificationType.danger,
        ));
      } else if (data.pH < 6.0) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: pH Tanah Agak Asam',
          message: 'pH tanah: ${data.pH.toStringAsFixed(1)}. '
              'Monitor dan pertimbangkan penyesuaian pH.',
          type: NotificationType.warning,
        ));
      } else if (data.pH > 8.0) {
        notifications.add(SoilNotification.create(
          title: '🔴 KRITIS: pH Tanah Terlalu Basa',
          message: 'pH tanah: ${data.pH.toStringAsFixed(1)}. '
              'Pertimbangkan pengasaman segera.',
          type: NotificationType.danger,
        ));
      } else if (data.pH > 7.5) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: pH Tanah Agak Basa',
          message: 'pH tanah: ${data.pH.toStringAsFixed(1)}. '
              'Monitor perubahan pH tanah.',
          type: NotificationType.warning,
        ));
      }

      // Check temperature conditions
      if (data.temperature > 35) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: Suhu Udara Tinggi',
          message: 'Suhu udara: ${data.temperature.toStringAsFixed(1)}°C. '
              'Risiko stress panas pada tanaman.',
          type: NotificationType.warning,
        ));
      } else if (data.temperature < 15) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: Suhu Udara Rendah',
          message: 'Suhu udara: ${data.temperature.toStringAsFixed(1)}°C. '
              'Pertumbuhan tanaman mungkin melambat.',
          type: NotificationType.warning,
        ));
      }

      // Check nutrient levels
      if (data.nitrogen < 20) {
        notifications.add(SoilNotification.create(
          title: '🔵 INFORMASI: Kadar Nitrogen Rendah',
          message: 'Nitrogen: ${data.nitrogen.toStringAsFixed(0)} mg/kg. '
              'Pertimbangkan pemupukan nitrogen.',
          type: NotificationType.info,
        ));
      }

      if (data.phosphorus < 15) {
        notifications.add(SoilNotification.create(
          title: '🔵 INFORMASI: Kadar Fosfor Rendah',
          message: 'Fosfor: ${data.phosphorus.toStringAsFixed(0)} mg/kg. '
              'Pertimbangkan pemupukan fosfor.',
          type: NotificationType.info,
        ));
      }

      if (data.potassium < 100) {
        notifications.add(SoilNotification.create(
          title: '🔵 INFORMASI: Kadar Kalium Rendah',
          message: 'Kalium: ${data.potassium.toStringAsFixed(0)} mg/kg. '
              'Pertimbangkan pemupukan kalium.',
          type: NotificationType.info,
        ));
      }

      // PERBAIKAN DI SINI: Gunakan waterLevelCm dan fertilizerLevelCm
      // Check tank levels
      if (tankStatus.isWaterTankCritical) {
        notifications.add(SoilNotification.create(
          title: '🔴 KRITIS: Tangki Air Hampir Habis',
          message:
              'Level tangki air: ${tankStatus.waterLevelCm.toStringAsFixed(1)} cm (${tankStatus.waterTankPercent.toStringAsFixed(0)}%). ' // PERBAIKAN: waterLevelCm
              'SEGERA ISI ULANG!',
          type: NotificationType.danger,
        ));
      } else if (tankStatus.isWaterTankLow) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: Tangki Air Rendah',
          message:
              'Level tangki air: ${tankStatus.waterLevelCm.toStringAsFixed(1)} cm (${tankStatus.waterTankPercent.toStringAsFixed(0)}%). ' // PERBAIKAN: waterLevelCm
              'Persiapkan pengisian.',
          type: NotificationType.warning,
        ));
      }

      if (tankStatus.isFertilizerTankCritical) {
        notifications.add(SoilNotification.create(
          title: '🔴 KRITIS: Tangki Pupuk Hampir Habis',
          message:
              'Level tangki pupuk: ${tankStatus.fertilizerLevelCm.toStringAsFixed(1)} cm (${tankStatus.fertilizerTankPercent.toStringAsFixed(0)}%). ' // PERBAIKAN: fertilizerLevelCm
              'SEGERA ISI ULANG!',
          type: NotificationType.danger,
        ));
      } else if (tankStatus.isFertilizerTankLow) {
        notifications.add(SoilNotification.create(
          title: '🟡 PERINGATAN: Tangki Pupuk Rendah',
          message:
              'Level tangki pupuk: ${tankStatus.fertilizerLevelCm.toStringAsFixed(1)} cm (${tankStatus.fertilizerTankPercent.toStringAsFixed(0)}%). ' // PERBAIKAN: fertilizerLevelCm
              'Persiapkan pengisian.',
          type: NotificationType.warning,
        ));
      }

      // Add system notification if no critical/warning notifications
      if (notifications.isEmpty ||
          notifications.every((n) =>
              n.type == NotificationType.success ||
              n.type == NotificationType.info)) {
        notifications.add(SoilNotification.create(
          title: '🟢 SUKSES: Semua Kondisi Normal',
          message: 'Semua parameter sensor dalam kondisi optimal. '
              'Sistem berjalan dengan baik.',
          type: NotificationType.success,
        ));
      }

      // Limit number of notifications
      if (notifications.length > 20) {
        notifications = notifications.sublist(0, 20);
      }

      return notifications;
    } catch (e) {
      print('Error generating notifications: $e');
      return [
        SoilNotification.create(
          title: '⚠️ Error Memuat Notifikasi',
          message: 'Terjadi kesalahan saat memuat notifikasi: $e',
          type: NotificationType.warning,
        ),
      ];
    }
  }

  void _deleteNotification(SoilNotification notification) {
    if (!mounted) return;

    final deletedNotification = notification.copyWith();

    setState(() {
      _notifications.remove(notification);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notifikasi dihapus'),
        duration: Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Batal',
          onPressed: () {
            if (mounted) {
              setState(() {
                _notifications.add(deletedNotification);
                _sortNotifications();
              });
            }
          },
        ),
      ),
    );
  }

  void _clearAllNotifications() {
    if (!mounted || _notifications.isEmpty) return;

    final clearedCount = _notifications.length;
    final clearedNotifications = List<SoilNotification>.from(_notifications);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus Semua Notifikasi?'),
        content: Text(
            'Anda akan menghapus semua $clearedCount notifikasi. Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (mounted) {
                setState(() {
                  _notifications.clear();
                });
              }
              Navigator.pop(context);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$clearedCount notifikasi telah dihapus'),
                    duration: Duration(seconds: 2),
                    action: SnackBarAction(
                      label: 'Batal',
                      onPressed: () {
                        if (mounted) {
                          setState(() {
                            _notifications = clearedNotifications;
                            _sortNotifications();
                          });
                        }
                      },
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Hapus Semua'),
          ),
        ],
      ),
    );
  }

  void _markAllAsRead() {
    if (!mounted) return;

    setState(() {
      // Buat list baru dengan notifikasi yang sudah dibaca menggunakan copyWith
      _notifications = _notifications.map((notification) {
        return notification.copyWith(isRead: true);
      }).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Semua notifikasi ditandai sebagai sudah dibaca'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildNotificationItem(SoilNotification notification, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: _getNotificationColor(notification.type).withOpacity(0.05),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: _getNotificationColor(notification.type).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getNotificationColor(notification.type).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: _getNotificationColor(notification.type),
              width: 1.5,
            ),
          ),
          child: Icon(
            _getNotificationIcon(notification.type),
            color: _getNotificationColor(notification.type),
            size: 20,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getNotificationColor(notification.type),
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!notification.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              notification.message,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _getNotificationColor(notification.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _getNotificationColor(notification.type)
                        .withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _getNotificationTypeText(notification.type),
                  style: TextStyle(
                    fontSize: 10,
                    color: _getNotificationColor(notification.type),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                _getTimeAgo(notification.timestamp),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          color: Colors.grey,
          onPressed: () => _deleteNotification(notification),
          tooltip: 'Hapus notifikasi',
        ),
        onTap: () {
          _showNotificationDetails(notification);
        },
        onLongPress: () {
          _showNotificationActions(notification);
        },
      ),
    );
  }

  void _showNotificationDetails(SoilNotification notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getNotificationIcon(notification.type),
              color: _getNotificationColor(notification.type),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notification.title,
                style: TextStyle(
                  color: _getNotificationColor(notification.type),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notification.message,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getNotificationColor(notification.type)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _getNotificationColor(notification.type),
                      ),
                    ),
                    child: Text(
                      _getNotificationTypeText(notification.type),
                      style: TextStyle(
                        color: _getNotificationColor(notification.type),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDateTime(notification.timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              if (!notification.isRead) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue[100]!),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info, size: 16, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Notifikasi belum dibaca',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteNotification(notification);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showNotificationActions(SoilNotification notification) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red),
              title: Text('Hapus Notifikasi'),
              onTap: () {
                Navigator.pop(context);
                _deleteNotification(notification);
              },
            ),
            if (!notification.isRead)
              ListTile(
                leading: Icon(Icons.mark_email_read, color: Colors.green),
                title: Text('Tandai Sudah Dibaca'),
                onTap: () {
                  Navigator.pop(context);
                  if (mounted) {
                    setState(() {
                      final index = _notifications.indexOf(notification);
                      if (index != -1) {
                        _notifications[index] =
                            notification.copyWith(isRead: true);
                      }
                    });
                  }
                },
              ),
            ListTile(
              leading: Icon(Icons.share, color: Colors.blue),
              title: Text('Bagikan'),
              onTap: () {
                Navigator.pop(context);
                _shareNotification(notification);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: Colors.green),
              title: Text('Salin Pesan'),
              onTap: () {
                Navigator.pop(context);
                _copyNotificationMessage(notification);
              },
            ),
            ListTile(
              leading: Icon(Icons.close, color: Colors.grey),
              title: Text('Batal'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _shareNotification(SoilNotification notification) {
    // Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fitur berbagi akan datang'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyNotificationMessage(SoilNotification notification) {
    // Implement copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pesan disalin ke clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final isConnected = firebaseService.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi Kondisi Tanah'),
        backgroundColor: Colors.green[700],
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              tooltip: 'Tandai semua sudah dibaca',
            ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshNotifications,
            tooltip: 'Refresh',
          ),
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAllNotifications,
              tooltip: 'Hapus Semua',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status Bar
          if (!isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange[50],
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tidak terhubung ke server. Notifikasi mungkin tidak terbaru.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Summary Card
          if (_notifications.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: ${_notifications.length} notifikasi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Terakhir update: ${_getTimeAgo(DateTime.now())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green[100]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active,
                            size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          '${_notifications.where((n) => !n.isRead).length} belum dibaca',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Empty State or List
          Expanded(
            child: !_isInitialized && !_isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Menyiapkan notifikasi...'),
                      ],
                    ),
                  )
                : _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Memuat notifikasi...'),
                          ],
                        ),
                      )
                    : _notifications.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_off,
                                  size: 72,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Tidak Ada Notifikasi',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 40),
                                  child: Text(
                                    'Semua kondisi tanah dalam keadaan normal. '
                                    'Sistem akan memberitahu Anda jika ada perubahan kondisi.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _refreshNotifications,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              await _refreshNotifications();
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _notifications.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                return _buildNotificationItem(
                                    _notifications[index], index);
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshNotifications,
        backgroundColor: Colors.green[700],
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.refresh, color: Colors.white),
        tooltip: 'Refresh notifikasi',
      ),
    );
  }
}
