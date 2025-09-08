import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart'; // Import the service
import 'package:zarq_messenger/starfield_background.dart';


class RegisterScreen extends StatefulWidget {
  final User user;
  final VoidCallback onRegistrationComplete;

  const RegisterScreen({
    super.key,
    required this.user,
    required this.onRegistrationComplete,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  // Define the backend URL once to avoid repetition and potential typos.
  final String backendBaseUrl = 'http://192.168.29.81:8080';


  Future<void> _completeRegistration() async {
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number cannot be empty.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() { _isLoading = true; });
    print("[RegisterFlow] Starting registration completion for new user: ${widget.user.uid}");

    try {
      // --- Step 1: Create the user profile on the backend ---
      print("[RegisterFlow] Step 1: Creating profile on backend...");
      final token = await widget.user.getIdToken();
      final profileUrl = Uri.parse('$backendBaseUrl/profiles/create');
      final response = await http.post(
        profileUrl,
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: json.encode({'phoneNumber': _phoneController.text}),
      );

      if (!mounted) return;

      if (response.statusCode == 201) {
        print("[RegisterFlow] -> Profile created successfully on backend.");
        
        // --- REMOVED: All old key generation logic is gone from here. ---
        // The AuthWrapper will now handle key generation automatically.

        // --- Step 2: Signal that registration is complete ---
        print("[RegisterFlow] Profile creation complete. Calling onRegistrationComplete callback.");
        widget.onRegistrationComplete();

      } else {
        print("[RegisterFlow] ERROR: Profile creation failed. Server response: ${response.statusCode} ${response.body}");
        throw Exception('Profile Creation Failed: ${response.body}');
      }
    } catch (e) {
      print("[RegisterFlow] ERROR: An exception occurred during registration. Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred during registration: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
  }

  

  Future<void> _cancelRegistration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Registration?'),
        content: const Text(
          'This will delete your new account, and you will have to sign up again. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() { _isLoading = true; });
      try {
        print("Cancelling registration, deleting Firebase user...");
        await widget.user.delete();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not cancel registration: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const StarfieldBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Complete Registration'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                FirebaseAuth.instance.signOut();
              },
              tooltip: 'Go Back',
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Welcome, ${widget.user.displayName ?? "New User"}!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    const Text(
                      'Just one last step to secure your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 48.0),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: 'Enter your Phone Number',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 15.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      ElevatedButton(
                        onPressed: _completeRegistration,
                        child: const Text(
                          'Complete Registration',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    TextButton(
                      onPressed: _isLoading ? null : _cancelRegistration,
                      child: const Text('Cancel and Go Back'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
