import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../services/firebase_service.dart';
import '../widgets/toast_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final Connectivity _connectivity = Connectivity();
  
  bool _isOnline = true;
  String _status = 'idle';
  String _command = '0';
  bool _isProcessing = false;
  
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<String>? _commandSubscription;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _listenToConnectivity();
    _listenToFirebase();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _statusSubscription?.cancel();
    _commandSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  void _listenToConnectivity() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
  }

  void _listenToFirebase() {
    _statusSubscription = _firebaseService.getStatusStream().listen((status) {
      setState(() {
        _status = status;
        _updateProcessingState();
      });
    });

    _commandSubscription = _firebaseService.getCommandStream().listen((command) {
      setState(() {
        _command = command;
        _updateProcessingState();
      });
    });
  }

  void _updateProcessingState() {
    setState(() {
      _isProcessing = _status != 'idle' || _command != '0';
    });
  }

  Future<void> _handleButton(int buttonNum) async {
    if (!_isOnline) {
      ToastWidget.show(context, 'Internet not available');
      return;
    }

    if (_isProcessing) {
      return;
    }

    try {
      await _firebaseService.sendCommand(buttonNum.toString());
      if (mounted) {
        ToastWidget.show(context, 'Button $buttonNum activated');
      }
      
      // Wait for ESP32 to process and show deactivation toast
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted && _command == '0') {
        ToastWidget.show(context, 'Button $buttonNum deactivated');
      }
    } catch (e) {
      if (mounted) {
        ToastWidget.show(context, 'Error: Failed to send command');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey[50]!, Colors.grey[100]!],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildConnectionStatus(),
              Expanded(
                child: _buildDeviceList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[100]!),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // Menu functionality placeholder
            },
            icon: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 2, width: 20, color: Colors.grey[700]),
                const SizedBox(height: 4),
                Container(height: 2, width: 20, color: Colors.grey[700]),
                const SizedBox(height: 4),
                Container(height: 2, width: 20, color: Colors.grey[700]),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ESP32 Smart Buttons',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Manage your devices',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              // Settings functionality placeholder
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              onPressed: () {
                // Add functionality placeholder
              },
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.purple[50]!],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isOnline ? Icons.wifi : Icons.wifi_off,
                color: _isOnline ? Colors.green[600] : Colors.red[600],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _isOnline ? 'Connected' : 'Offline',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isProcessing ? Colors.blue[500] : Colors.green[500],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isProcessing ? 'Processing...' : 'Ready',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Devices',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDeviceButton(
            buttonNum: 1,
            title: 'Device Control 1',
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          _buildDeviceButton(
            buttonNum: 2,
            title: 'Device Control 2',
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceButton({
    required int buttonNum,
    required String title,
    required Color color,
  }) {
    final isActive = _isProcessing && _command == buttonNum.toString();
    final isDisabled = !_isOnline || _isProcessing;

    return GestureDetector(
      onTap: isDisabled ? null : () => _handleButton(buttonNum),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue[500] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Colors.blue[600]! : Colors.grey[200]!,
            width: 2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withValues(alpha: 0.2) : color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.power_settings_new,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isActive ? 'Activating...' : 'Tap to activate',
                      style: TextStyle(
                        fontSize: 14,
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              _buildToggleSwitch(isActive),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 48,
      height: 24,
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withValues(alpha: 0.3) : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 300),
        alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}