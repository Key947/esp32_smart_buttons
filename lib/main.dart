import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyDupWssdSilcfcu_MaFmflsLwF6yQ8FBwk',
      appId: '1:659958599416:android:8295d38c44bdfecb2bb50d',
      messagingSenderId: '659958599416',
      projectId: 'esp32-pc-control',
      databaseURL: 'https://esp32-pc-control-default-rtdb.asia-southeast1.firebasedatabase.app',
      storageBucket: 'esp32-pc-control.firebasestorage.app',
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Smart Buttons',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}