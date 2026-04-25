import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  Stream<String> getStatusStream() {
    return _databaseRef.child('esp32/status').onValue.map((event) {
      return event.snapshot.value?.toString() ?? 'idle';
    });
  }

  Stream<String> getCommandStream() {
    return _databaseRef.child('esp32/command').onValue.map((event) {
      return event.snapshot.value?.toString() ?? '0';
    });
  }

  // Streams raw lastseen value — home_screen uses this to drive the timeout timer
  Stream<int> getLastSeenStream() {
    return _databaseRef.child('esp32/lastseen').onValue.map((event) {
      final val = event.snapshot.value;
      if (val == null) return 0;
      return int.tryParse(val.toString()) ?? 0;
    });
  }

  Future<void> sendCommand(String command) async {
    await _databaseRef.child('esp32/command').set(command);
  }

  Future<void> resetCommand() async {
    await _databaseRef.child('esp32/command').set('0');
    await _databaseRef.child('esp32/status').set('idle');
  }
}