import 'package:flutter/material.dart';
import 'package:mobai/screens/model_selector_screen.dart';
import 'package:mobai/screens/model_selector_screen_s.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MobAI Chat', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ModelSelectorScreen(),
                    ),
                  );
                },
                child: const Text('New Chat'),
              ),
              ElevatedButton(
                onPressed: () => onNewChatPressed(context),
                child: const Text('New Chat S'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void onNewChatPressed(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ModelSelectorScreenS()),
    );
  }
}
