import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPrefTimeoutKey = 'command_timeout_sec';
const int kDefaultTimeoutSec = 15;
const List<int> kTimeoutOptions = [10, 15, 20, 30];

// Call this once at app start to load saved timeout
Future<int> loadSavedTimeout() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(kPrefTimeoutKey) ?? kDefaultTimeoutSec;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedTimeout = kDefaultTimeoutSec;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final saved = await loadSavedTimeout();
    setState(() {
      _selectedTimeout = saved;
      _loading = false;
    });
  }

  Future<void> _saveTimeout(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPrefTimeoutKey, value);
    setState(() => _selectedTimeout = value);
    if (mounted) {
      ToastMsg.show(context, 'Waktu tersimpan — ${value}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.grey[50],
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Konfigurasi',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Pengaturan Aplikasi',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Section header
        const Text('Timeout Perintah',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Jika Perangkat tidak merespon pada jeda waktu dibawah, '
          'Aplikasi akan mereset perintah dan membuka fungsi tombol.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),

        // Timeout options
        ...kTimeoutOptions.map((sec) => _buildTimeoutTile(sec)),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),

        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text('Tips',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700])),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Percepat atau Perlambat waktu reset berdasarkan performa Internet. '
                'Jika Internet kurang stabil perlambat waktu reset.',
                style: TextStyle(fontSize: 13, color: Colors.blue[800]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeoutTile(int sec) {
    final isSelected = _selectedTimeout == sec;
    return GestureDetector(
      onTap: () => _saveTimeout(sec),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[500] : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.blue[600]! : Colors.grey[200]!,
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? Colors.white : Colors.grey[400],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$sec detik',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    sec == 10
                        ? 'Cepat — Khusus tombol Short Press'
                        : sec == 15
                            ? 'Normal — Kecepatan Yang Disarankan Untuk Kedua Tombol'
                            : sec == 20
                                ? 'Safe — Jeda tambahan'
                                : 'Slow — Toleransi Maximum',
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.85)
                          : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            if (sec == kDefaultTimeoutSec)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.blue[600],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Simple toast without depending on toast_widget.dart
class ToastMsg {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}