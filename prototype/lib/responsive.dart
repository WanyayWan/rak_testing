import 'package:flutter/material.dart';

bool isTablet(BuildContext context) {
  final size = MediaQuery.of(context).size;
  return size.shortestSide >= 600; // common breakpoint for tablets
}