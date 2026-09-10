import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobai/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: HomeScreen(),
      title: 'MobAI App',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
      ),
    ),
  );
}
