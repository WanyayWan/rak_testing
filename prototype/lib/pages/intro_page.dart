import 'dart:async';
import 'package:flutter/material.dart';
import 'home_page.dart';

class IntroPage extends StatefulWidget {
  static const route = '/intro'; // so that we dont need to create the object every time  
  const IntroPage({super.key}); // constructor

  @override
  State<IntroPage> createState() => _IntroPageState(); // create the state class
  //basically this line links the IntroPage widget to its corresponding state class _IntroPageState
  // every stateful widget must have a state class and must override the createState method to return an instance of that state class

}

class _IntroPageState extends State<IntroPage> { // State class for IntroPage everytime we use stateful widget we need to create a state class
  @override
  void initState() { // initState method is called when the state object is first created
    super.initState();   // Call the superclass's initState from IntroPage
    // Auto-redirect after 3 seconds
    Timer(const Duration(seconds: 3), () {    // Timer to wait for 3 seconds
      if (!mounted) return; // Check if the widget is still in the widget tree
      Navigator.pushReplacementNamed(context, HomePage.route);   //push replacement does not allow user to go back to intro page
    });
  }

  @override
  Widget build(BuildContext context) {  // The build() method describes what this screen looks like
    return const Scaffold(  // Scaffold gives the basic screen layout (like background, body area, etc.)
    // if we dont add scaffold then it wont be consistent across different pages
      body: SafeArea( // SafeArea to avoid notches and status bars
        child: Center(  // Center the content
          child: Column(    // Column to arrange logo and text vertically
            mainAxisAlignment: MainAxisAlignment.center,  // Align items to the center vertically
            children: [ 
              // This part is for the logo and welcome text
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
              SizedBox(height: 40), // Space between text and loading spinner
              CircularProgressIndicator(), // Loading spinner
            ],
          ),
        ),
      ),
    );
  }
}
