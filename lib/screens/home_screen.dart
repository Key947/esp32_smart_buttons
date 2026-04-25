import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../services/firebase_service.dart';
import '../widgets/toast_widget.dart';
import 'settings_screen.dart';

// If phone_time - lastseen > this, ESP32 is offline (seconds)
const _kEsp32OfflineThresholdSec = 20;
// Default command timeout — overridden by saved preference
const _kDefaultCommandTimeoutSec = 15;

enum Esp32State { initializing, online, dormant, offline }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final Connectivity _connectivity = Connectivity();

  // Internet connectivity
  bool _isOnline = true;

  // ESP32 state machine
  Esp32State _esp32State = Esp32State.initializing;
  int _lastSeenValue = 0;

  // Firebase values
  String _command = '0';

  // Per-button loading state
  int _commandTimeoutSec = _kDefaultCommandTimeoutSec;
  final Map<int, bool> _buttonLoading = {1: false, 2: false};
  final Map<int, Timer?> _commandTimeoutTimers = {1: null, 2: null};

  // Periodic poll to check if lastseen timestamp is stale
  Timer? _staleCheckTimer;

  // Subscriptions
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamSubscription<String>? _commandSub;
  StreamSubscription<int>? _lastSeenSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkConnectivity();
    _listenToConnectivity();
    _listenToFirebase();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _commandSub?.cancel();
    _lastSeenSub?.cancel();
    _staleCheckTimer?.cancel();
    _commandTimeoutTimers[1]?.cancel();
    _commandTimeoutTimers[2]?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final saved = await loadSavedTimeout();
    if (mounted) setState(() => _commandTimeoutSec = saved);
  }

  // ─── Connectivity ────────────────────────────────────────────────────────────

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  void _listenToConnectivity() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
  }

  // ─── Firebase ────────────────────────────────────────────────────────────────

  void _listenToFirebase() {
    // Command stream — detect when ESP32 resets command to 0
    _commandSub = _firebaseService.getCommandStream().listen((command) {
      setState(() => _command = command);
      if (command == '0') {
        for (int btn in [1, 2]) {
          if (_buttonLoading[btn] == true) {
            _clearButtonState(btn, showToast: true);
          }
        }
      }
      // ESP32 entered dormant — briefly block buttons, auto-clears after 1.5s
      if (command == '99') {
        setState(() => _esp32State = Esp32State.dormant);
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted && _esp32State == Esp32State.dormant) {
            setState(() => _esp32State = Esp32State.online);
          }
        });
      }
    });

    // Lastseen stream — NTP unix timestamp written by ESP32 every 7.5s.
    // We compare it against phone's real time — no timer drift possible.
    _lastSeenSub = _firebaseService.getLastSeenStream().listen((value) {
      if (value == 0) return; // no data in DB yet

      final prevValue = _lastSeenValue;
      _lastSeenValue = value;

      if (prevValue == 0) {
        // First value arrived — stay Initializing until we see it CHANGE.
        // This prevents a stale DB value from falsely showing Device Online.
        _startStaleCheck();
        return;
      }

      if (value != prevValue) {
        // Timestamp changed — ESP32 is actively writing, mark online.
        if (_esp32State != Esp32State.online &&
            _esp32State != Esp32State.dormant) {
          setState(() => _esp32State = Esp32State.online);
        }
      }

      // Always re-evaluate staleness on every update
      _checkStaleness();
    });
  }

  // Poll every 5s to catch stale timestamps even if stream goes quiet
  void _startStaleCheck() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkStaleness();
    });
  }

  void _checkStaleness() {
    if (_lastSeenValue == 0) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ageSec = nowSec - _lastSeenValue;

    if (ageSec > _kEsp32OfflineThresholdSec) {
      if (_esp32State != Esp32State.offline && mounted) {
        setState(() => _esp32State = Esp32State.offline);
        for (int btn in [1, 2]) {
          if (_buttonLoading[btn] == true) _clearButtonState(btn);
        }
        ToastWidget.show(context, 'Device went offline');
      }
    } else if (_esp32State == Esp32State.offline && mounted) {
      // Timestamp became fresh again — recovered
      setState(() => _esp32State = Esp32State.online);
    }
  }

  // ─── Button logic ─────────────────────────────────────────────────────────

  // Only online allows taps — initializing, dormant, offline all block.
  bool get _buttonsEnabled =>
      _isOnline &&
      _esp32State == Esp32State.online &&
      !_buttonLoading.values.any((v) => v);

  void _clearButtonState(int buttonNum, {bool showToast = false}) {
    _commandTimeoutTimers[buttonNum]?.cancel();
    _commandTimeoutTimers[buttonNum] = null;
    setState(() => _buttonLoading[buttonNum] = false);
    if (showToast && mounted) {
      ToastWidget.show(context, 'Button $buttonNum deactivated');
    }
  }

  Future<void> _handleButton(int buttonNum) async {
    if (!_buttonsEnabled) return;
    if (_buttonLoading[buttonNum] == true) return;

    setState(() => _buttonLoading[buttonNum] = true);

    try {
      await _firebaseService.sendCommand(buttonNum.toString());
      if (mounted) ToastWidget.show(context, 'Button $buttonNum activating...');

      // Safety timeout — reset if ESP32 never responds
      _commandTimeoutTimers[buttonNum]?.cancel();
      _commandTimeoutTimers[buttonNum] = Timer(
        Duration(seconds: _commandTimeoutSec),
        () async {
          if (_buttonLoading[buttonNum] == true) {
            // Only force-reset Firebase if ESP32 is not already handling it.
            // If dormant, ESP32 will self-reset to idle — dont interfere.
            if (_esp32State != Esp32State.dormant) {
              await _firebaseService.resetCommand();
              if (mounted) {
                ToastWidget.show(context, 'Button $buttonNum timed out — reset');
              }
            }
            _clearButtonState(buttonNum);
          }
        },
      );
    } catch (e) {
      if (mounted) ToastWidget.show(context, 'Failed to send command');
      _clearButtonState(buttonNum);
    }
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────────

  String get _esp32StatusLabel {
    if (!_isOnline) return 'Device Offline';
    switch (_esp32State) {
      case Esp32State.initializing:
        return 'Initializing...';
      case Esp32State.online:
        final anyLoading = _buttonLoading.values.any((v) => v);
        return anyLoading ? 'Activating' : 'Device Online';
      case Esp32State.dormant:
        return 'Dormant';
      case Esp32State.offline:
        return 'Device Offline';
    }
  }

  Color get _esp32StatusColor {
    if (!_isOnline) return Colors.red;
    switch (_esp32State) {
      case Esp32State.initializing:
        return Colors.grey;
      case Esp32State.online:
        final anyLoading = _buttonLoading.values.any((v) => v);
        return anyLoading ? Colors.blue : Colors.green;
      case Esp32State.dormant:
        return Colors.orange;
      case Esp32State.offline:
        return Colors.red;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
              _buildStatusBar(),
              Expanded(child: _buildDeviceList()),
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
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
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
                Text('ESP32 Smart Buttons',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Manage your devices',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                );
                // Reload timeout in case user changed it
                final saved = await loadSavedTimeout();
                if (mounted) setState(() => _commandTimeoutSec = saved);
              },
              icon: const Icon(Icons.settings_outlined)),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final internetColor = _isOnline ? Colors.green[600]! : Colors.red[600]!;
    final internetIcon = _isOnline ? Icons.wifi : Icons.wifi_off;
    final internetLabel = _isOnline ? 'DB Connected' : 'DB Disconnected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
              Icon(internetIcon, color: internetColor, size: 20),
              const SizedBox(width: 8),
              Text(internetLabel,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: internetColor)),
            ],
          ),
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _esp32StatusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _esp32StatusLabel,
                  key: ValueKey(_esp32StatusLabel),
                  style: const TextStyle(
                      fontSize: 14, color: Colors.black54),
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
          const Text('Your Devices',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildDeviceButton(
              buttonNum: 1,
              title: 'Device Control 1',
              color: Colors.blue),
          const SizedBox(height: 16),
          _buildDeviceButton(
              buttonNum: 2,
              title: 'Device Control 2',
              color: Colors.purple),
        ],
      ),
    );
  }

  Widget _buildDeviceButton({
    required int buttonNum,
    required String title,
    required Color color,
  }) {
    final isLoading = _buttonLoading[buttonNum] ?? false;
    final isActive = isLoading && _command == buttonNum.toString();
    final canTap = _buttonsEnabled && !isLoading;
    // Grey out if ESP32 offline, internet down, or initializing
    final isDisabled = !_buttonsEnabled && !isLoading;

    return GestureDetector(
      onTap: canTap ? () => _handleButton(buttonNum) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? color : Colors.grey[200]!,
            width: isActive ? 2 : 1.5,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.45 : 1.0,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDisabled
                      ? Colors.grey[400]
                      : isActive
                          ? color.withValues(alpha: 0.85)
                          : color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.power_settings_new,
                        color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(
                      isLoading
                          ? 'Waiting for ESP32...'
                          : isDisabled
                              ? (_esp32State == Esp32State.offline || !_isOnline)
                                  ? (_esp32State == Esp32State.dormant ? 'Dormant — resuming...' : 'Device offline')
                                  : 'Initializing...'
                              : 'Tap to activate',
                      style: TextStyle(
                          fontSize: 13,
                          color: isDisabled
                              ? Colors.grey[400]
                              : Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              _buildToggleSwitch(isActive, isDisabled, color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(bool isActive, bool isDisabled, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 50,
      height: 28,
      decoration: BoxDecoration(
        color: isDisabled
            ? Colors.grey[300]
            : isActive
                ? color
                : Colors.grey[300],
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 300),
        alignment:
            isActive ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }
}