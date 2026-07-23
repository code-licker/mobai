import 'package:flutter/material.dart';
import 'package:mobai/model_selector_screen.dart';

void main() {
  runApp(
    MaterialApp(
      home: ModelSelectorScreen(),
      title: 'MobAI APp',
      theme: ThemeData(useMaterial3: true, fontFamily: 'RobotoMono'),
    ),
  );
}
