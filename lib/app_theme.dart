import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final ThemeData zarqDarkTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: Colors.deepPurple[400],

  // Define the color scheme
  colorScheme: ColorScheme.dark(
    primary: Colors.deepPurple[400]!,
    secondary: Colors.tealAccent[400]!, // Accent color
    background: const Color(0xFF121212), // Very dark background
    surface: const Color(0xFF1E1E1E), // Color for cards, sheets
  ),

  // Define the font
  textTheme: GoogleFonts.poppinsTextTheme(
    ThemeData.dark().textTheme,
  ),

  // Style for the top AppBar
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    titleTextStyle: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white,),
  ),

  // Style for buttons
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.deepPurple[400],
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30.0),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
    ),
  ),
);