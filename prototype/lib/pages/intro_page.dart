import 'dart:async';
import 'package:flutter/material.dart';
import 'home_page.dart';

class IntroPage extends StatefulWidget {
  static const route = '/intro'; // so that we dont need to create the object every time  
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> { // State class for IntroPage everytime we use stateful widget we need to create a state class
  @override
  void initState() {
    super.initState();   // Call the superclass's initState from IntroPage
    // Auto-redirect after 3 seconds
    Timer(const Duration(seconds: 3), () {    // Timer to wait for 3 seconds
      if (!mounted) return; // Check if the widget is still in the widget tree
      Navigator.pushReplacementNamed(context, HomePage.route);   //push replacement does not allow user to go back to intro page
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
