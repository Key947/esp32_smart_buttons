import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  // Listen to status changes
  Stream<String> getStatusStream() {
    return _databaseRef.child('esp32/status').onValue.map((event) {
      return event.snapshot.value?.toString() ?? 'idle';
    });
  }

  // Listen to command changes
  Stream<String> getCommandStream() {
    return _databaseRef.child('esp32/command').onValue.map((event) {
      return event.snapshot.value?.toString() ?? '0';
    });
  }

  // Send command to Firebase
  Future<void> sendCommand(String command) async {
    try {
      await _databaseRef.child('esp32/command').set(command);
    } catch (e) {
      print('Error sending command: $e');
      rethrow;
    }
  }

  // Get current status (one-time read)
  Future<String> getCurrentStatus() async {
    try {
      final snapshot = await _databaseRef.child('esp32/status').get();
      return snapshot.value?.toString() ?? 'idle';
    } catch (e) {
      print('Error getting status: $e');
      return 'idle';
    }
  }

  // Get current command (one-time read)
  Future<String> getCurrentCommand() async {
    try {
      final snapshot = await _databaseRef.child('esp32/command').get();
      return snapshot.value?.toString() ?? '0';
    } catch (e) {
      print('Error getting command: $e');
      return '0';
    }
  }
}