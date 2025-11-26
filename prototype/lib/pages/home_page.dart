//this is the first page after the intro page

import 'package:flutter/material.dart';
import '../widgets/menu_button.dart';
import 'create_page.dart';
import 'package:prototype/pages/edit_delete_page.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';


class HomePage extends StatelessWidget {    // stateless widget as no state to manage 
  static const route = '/home'; // route name for navigation
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
    decoration: const BoxDecoration(
          /*     image: DecorationImage(
            image: AssetImage('assets/images/RAK_logo.png'),
            fit: BoxFit.cover,
          ), */
        ), 
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(2, 4),
                      ),
                    ],
                  ),
                  child: Column(
                  children:  const [
                       Image(
                        image: AssetImage('assets/images/RAK_logo.png'),
                        height: 120,
                      ),  
                  //    SizedBox(height: 8),
                   /*   Text(
                        'R.A.K. MATERIALS CONSULTANTS\nPTE. LTD.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue,
                        ),
                      ), */
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                MenuButton(
                  label: 'CREATE',
                  onPressed: () {
                    Navigator.pushNamed(context, CreatePage.route);
                  },
                ),
                const SizedBox(height: 16),

                MenuButton(
                  label: 'EDIT/DELETE',
                  onPressed: () {
                    Navigator.pushNamed(context, EditDeletePage.route);
                  },
                ),
                const SizedBox(height: 16),

                MenuButton(
  label: 'EXIT',
  onPressed: () async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit'),
        content: const Text('Close the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      // Close the app (Android). On iOS, exiting programmatically is discouraged.
      if (Platform.isAndroid) {
        SystemNavigator.pop(); // preferred over exit(0)
      } else if (Platform.isIOS) {
        // Apple discourages forced exit; if you really need it for internal builds:
        // import 'dart:io' and uncomment next line (may be rejected by App Review)
        // exit(0);
        SystemNavigator.pop(); // often just backgrounds the app on iOS
      } else {
        SystemNavigator.pop();
      }
    }
  },
)
,

                const Spacer(),

                const Text(
                  'Service to others\nleads to greatness.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}