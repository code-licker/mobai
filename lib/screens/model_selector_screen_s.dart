import 'dart:ui';

import 'package:flutter/material.dart';

class ModelSelectorScreenS extends StatefulWidget {
  const ModelSelectorScreenS({super.key});

  @override
  State<ModelSelectorScreenS> createState() => _ModelSelectorScreenSState();
}

class _ModelSelectorScreenSState extends State<ModelSelectorScreenS> {
  @override
  Widget build(BuildContext context) {
    return safeAreaWidget();
  }

  Widget safeAreaWidget() {
    return SafeArea(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Color.fromARGB(255, 215, 75, 0),
                          width: 2,
                        ),
                      ),
                    ),
                    Card.outlined(
                      // color: Color.fromARGB(255, 215, 134, 0),
                      child: SizedBox(
                        height: 100,
                        width: double.infinity,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.pink, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget originalScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [const Text('New Screen S')],
        ),
      ),
    );
  }
}
