import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ModelSelectorScreen extends StatefulWidget {
  const ModelSelectorScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _ModelSelectorScreenState();
  }
}

class _ModelSelectorScreenState extends State {
  late Future<Post> post;

  @override
  void initState() {
    super.initState();
    post = fetchSomething();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MobAI')),
      body: Center(
        child: Column(
          children: [
            const Text(
              'Select a Model',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
            ),
            FutureBuilder(
              future: post,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                } else if (snapshot.hasData) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('ID: ${snapshot.data!.id}'),
                      Text('Title: ${snapshot.data!.title}'),
                      Text('Body: ${snapshot.data!.body}'),
                    ],
                  );
                } else {
                  return const Text('No Data');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Post> fetchSomething() async {
    final url = Uri.parse('https://jsonplaceholder.typicode.com/posts/1');
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        debugPrint(res.body);
        return Post.fromJson(jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint(e.toString());
    }
    throw Exception('Failed to load Post');
  }
}

// DataModel Class
class Post {
  final int id;
  final String title;
  final String body;

  Post({required this.id, required this.title, required this.body});

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(id: json['id'], title: json['title'], body: json['body']);
  }
}
