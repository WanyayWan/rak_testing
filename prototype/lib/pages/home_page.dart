//this is the first page after the intro page

import 'package:flutter/material.dart';
import '../widgets/menu_button.dart';
import 'create_page.dart';
import 'package:prototype/pages/edit_delete_page.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

import '../responsive.dart'; // ✅ added for tablet detection

class HomePage extends StatelessWidget {
  static const route = '/home';
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool tablet = isTablet(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tablet ? 600 : double.infinity, // ⭐ center on tablet
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tablet ? 32 : 24,
                  vertical: tablet ? 24 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ----- Logo Box -----
                    Container(
                      padding: EdgeInsets.all(tablet ? 20 : 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 8,
                            offset: const Offset(2, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/images/RAK_logo.png',
                            height: tablet ? 180 : 120,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: tablet ? 60 : 40),

                    // ----- Menu Buttons -----
                    MenuButton(
                      label: 'CREATE',
                      fontSize: tablet ? 22 : 18,
                      height: tablet ? 60 : 50,
                      onPressed: () {
                        Navigator.pushNamed(context, CreatePage.route);
                      },
                    ),

                    SizedBox(height: tablet ? 24 : 16),

                    MenuButton(
                      label: 'EDIT/DELETE',
                      fontSize: tablet ? 22 : 18,
                      height: tablet ? 60 : 50,
                      onPressed: () {
                        Navigator.pushNamed(context, EditDeletePage.route);
                      },
                    ),

                    SizedBox(height: tablet ? 24 : 16),

                    MenuButton(
                      label: 'EXIT',
                      fontSize: tablet ? 22 : 18,
                      height: tablet ? 60 : 50,
                      onPressed: () async {
                        final shouldExit = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Exit'),
                            content: const Text('Close the app?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );

                        if (shouldExit == true) {
                          if (Platform.isAndroid) {
                            SystemNavigator.pop();
                          } else if (Platform.isIOS) {
                            SystemNavigator.pop();
                          } else {
                            SystemNavigator.pop();
                          }
                        }
                      },
                    ),

                    const Spacer(),

                    Text(
                      'Service to others\nleads to greatness.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: tablet ? 26 : 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
