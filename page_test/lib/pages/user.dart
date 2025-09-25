import 'package:flutter/material.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final TextEditingController mycontroller = TextEditingController();
  final TextEditingController mycontroller2 = TextEditingController();
  

  void greetUser() {
    print(mycontroller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter your name',
                ),
                controller: mycontroller,
              ),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter your age',
                ),
                controller: mycontroller2,
              ),

              //button
              ElevatedButton(   
                onPressed: greetUser,
                child: Text("Enter"),
              ),
            ],
          ),
        ),
      )
    );
  }
}

