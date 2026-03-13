// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/date_symbol_data_local.dart'; // ← обязательно для DateFormat('ru')
import 'utils/cleanup.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart'; // главный экран

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация локалей для intl (чтобы DateFormat работал с 'ru')
  await initializeDateFormatting('ru', null); // русский язык + дефолтные данные

  // Инициализация Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await cleanupOldClasses();  // один раз при старте

  // Отключаем локальный кэш Firestore (рекомендуется на Windows для стабильности)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  // Опционально: очистка кэша при запуске (можно убрать в продакшене)
  try {
    await FirebaseFirestore.instance.clearPersistence();
    debugPrint('Firestore persistence cleared');
  } catch (e) {
    debugPrint('Failed to clear persistence: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(), // всегда стартуем с главной
    );
  }
}