import 'package:flutter/material.dart';
import 'pages/create_page.dart';
import 'pages/intro_page.dart';
import 'pages/home_page.dart';
import 'pages/details_page.dart';
import 'pages/edit_delete_page.dart';
import 'pages/location_page.dart';

void main() => runApp(const RakApp());

class RakApp extends StatelessWidget {
  const RakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // 🌟 Modern polished theme
      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E), // deep navy blue
          brightness: Brightness.light,
        ),

        scaffoldBackgroundColor: const Color(0xFFF6F7FB),

        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),



        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFEDEFF2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),

        iconTheme: const IconThemeData(
          size: 22,
          color: Colors.black87,
        ),
      ),

      initialRoute: IntroPage.route,

      routes: {
        IntroPage.route: (_) => const IntroPage(),
        HomePage.route: (_) => const HomePage(),
        CreatePage.route: (_) => const CreatePage(),
        DetailsPage.route: (_) => const DetailsPage(),
        EditDeletePage.route: (_) => const EditDeletePage(),
        LocationPage.route: (_) => const LocationPage(),
      },
    );
  }
}
