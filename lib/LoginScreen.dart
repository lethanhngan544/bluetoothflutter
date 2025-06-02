import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart'; // For hashing
import 'dart:convert'; // For utf8 encoding
import "BluetoothApp.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  // --- Pre-compute the hash of the expected password ---
  // In a real app, this hash would likely come from a secure server or storage
  final String _targetPasswordHash =
      sha256.convert(utf8.encode("password")).toString();
  final String _targetUsername = "admin";
  // ----------------------------------------------------

  Future<void> _attemptLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null; // Clear previous errors
    });

    final username = _usernameController.text;
    final password = _passwordController.text;

    // --- Simulate network delay/processing ---
    await Future.delayed(const Duration(seconds: 1));
    // ----------------------------------------

    // --- Hash the entered password ---
    final enteredPasswordHash =
        sha256.convert(utf8.encode(password)).toString();
    // -------------------------------

    // --- Compare username and hashed password ---
    if (username == _targetUsername &&
        enteredPasswordHash == _targetPasswordHash) {
      if (mounted) {
        // Check if the widget is still in the tree
        // Navigate to BluetoothApp on success, replacing the login screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const BluetoothApp()),
        );
      }
    } else {
      setState(() {
        _errorMessage = "Invalid username or password.";
        _isLoading = false;
      });
    }
    // No need to set _isLoading = false on success because we navigate away
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Login Required"),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          // Prevents overflow on small screens
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Icon(Icons.lock_outline,
                  size: 80, color: Colors.blueAccent),
              const SizedBox(height: 30),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
                enabled: !_isLoading, // Disable field when loading
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage, // Show error message here
                ),
                obscureText: true, // Hide password characters
                enabled: !_isLoading, // Disable field when loading
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Login'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                      onPressed: _attemptLogin,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
