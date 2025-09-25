import 'dart:async';
import 'package:flutter/material.dart';
import 'home_page.dart';

class IntroPage extends StatefulWidget {
  static const route = '/intro';
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  @override
  void initState() {
    super.initState();
    // Auto-redirect after 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, HomePage.route);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // your logo
              Image(
                image: AssetImage('assets/images/logo.png'),
                height: 100,
              ),
              SizedBox(height: 20),
              Text(
                'Welcome to\nR.A.K. MATERIALS CONSULTANTS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue,
                ),
              ),
              SizedBox(height: 40),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
