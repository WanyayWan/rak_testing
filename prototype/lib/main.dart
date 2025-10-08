import 'package:flutter/material.dart';
import 'pages/create_page.dart';
import 'pages/intro_page.dart';
import 'pages/home_page.dart';
import 'pages/details_page.dart';
import 'pages/edit_delete_page.dart';
//import 'pages/annotate_photo_page.dart';
import 'pages/location_page.dart';

void main() => runApp(const RakApp());

class RakApp extends StatelessWidget {  
  const RakApp({super.key}); // constructor

  @override
  Widget build(BuildContext context) {
    return MaterialApp(    // root widget setting up the themee and global app-feature
      debugShowCheckedModeBanner: false,  // the debugging icon to be false
      initialRoute: IntroPage.route,     //This line indicate which page to be started first
      routes: {
        IntroPage.route: (_) => const IntroPage(),
        HomePage.route:  (_) => const HomePage(),
        CreatePage.route: (_) => const CreatePage(),
        DetailsPage.route: (_) => const DetailsPage(),
        EditDeletePage.route: (_) => const EditDeletePage(),
        LocationPage.route: (_) => const LocationPage(),
      },
    );
  }
}
