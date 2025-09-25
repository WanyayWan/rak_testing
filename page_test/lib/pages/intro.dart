import 'package:flutter/material.dart';
import 'package:page_test/pages/user.dart';

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intro Page'),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text("hola"),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserPage()
              ),
            );
          }, 
        ),
      ),
    );
  }
}


