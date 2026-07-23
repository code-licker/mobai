import 'package:flutter/material.dart';

class ModelSelectorScreen extends StatefulWidget {
  const ModelSelectorScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _ModelSelectorScreenState();
  }
}

class _ModelSelectorScreenState extends State {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Center(
            child: Text(
              'Select a Model',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
            ),
          ),
        ],
      ),
    );
  }
}
