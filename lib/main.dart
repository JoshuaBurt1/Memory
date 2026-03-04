import 'package:flutter/material.dart';
import 'firebase_config.dart';
import 'home_screen.dart';

void main() async { 
  WidgetsFlutterBinding.ensureInitialized();  
  await FirebaseConfig.init(); 
  runApp(const GridsGameApp());
}

class GridsGameApp extends StatelessWidget {
  const GridsGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memory',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(), 
    );
  }
}