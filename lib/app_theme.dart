import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final ThemeData zarqLightTheme = ThemeData(
  brightness: Brightness.light,
  primaryColor: const Color(0xFF3D00B8),
  scaffoldBackgroundColor: const Color(0xFFF7F7FB),
  colorScheme: ColorScheme.light(
    primary: const Color(0xFF3D00B8),
    secondary: const Color(0xFF5C1EE0),
    surface: Colors.white,
    background: const Color(0xFFF7F7FB),
  ),
  textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white,
    elevation: 0,
    iconTheme: const IconThemeData(color: Colors.black),
    titleTextStyle: GoogleFonts.poppins(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3D00B8),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
    ),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: Colors.white,
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: Colors.black,
    selectionHandleColor: Colors.black,
    selectionColor: Color(0x33000000),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black, width: 1.5),
    ),
  ),
);

final ThemeData zarqDarkTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: const Color(0xFF3D00B8),
  scaffoldBackgroundColor: const Color(0xFF0a0e21),
  colorScheme: ColorScheme.dark(
    primary: const Color(0xFF3D00B8),
    secondary: const Color(0xFF5C1EE0),
    surface: const Color(0xFF1E1E1E),
    background: const Color(0xFF0a0e21),
  ),
  textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFF0a0e21),
    elevation: 0,
    iconTheme: const IconThemeData(color: Colors.white),
    titleTextStyle: GoogleFonts.poppins(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3D00B8),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
    ),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: Colors.white,
  ),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: Colors.white,
    selectionHandleColor: Colors.white,
    selectionColor: Color(0x33FFFFFF),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white, width: 1.5),
    ),
  ),
);
