import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'package:ftcmanageapp/program-files/frontend/setup.dart';
import 'package:ftcmanageapp/program-files/frontend/dashboard.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';

/// The login and registration page for the application.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Text controllers for input fields
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _teamController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  String? _info;

  // Toggle between Login and Registration mode
  bool _isRegisterMode = false;

  /// Handles the form submission for both login and registration.
  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final team = _teamController.text.trim();

    setState(() {
      _error = null;
      _info = null;
    });

    if (!_isRegisterMode) {
      // Login Logic
      if (email.isEmpty || password.isEmpty) {
        setState(() => _error = "Please fill in email and password.");
        return;
      }

      try {
        setState(() => _loading = true);

        // Authenticate user with Firebase
        final UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (!mounted) return;

        // Load personalized theme settings
        final themeService = context.read<ThemeService>();
        await themeService.loadFromFirestore();

        if (!mounted) return;

        // Check if the user has completed the initial setup
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .get();
        
        final hasSetup = userDoc.data()?.containsKey('setupData') ?? false;

        if (!mounted) return;

        // Redirect based on setup status
        if (hasSetup) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SetupPage()),
          );
        }
      } on FirebaseAuthException catch (e) {
        setState(() => _error = e.message ?? "Login failed.");
      } finally {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    } else {
      // Registration Logic
      if (email.isEmpty || password.isEmpty || team.isEmpty || confirmPassword.isEmpty) {
        setState(
              () => _error =
          "Please fill in all fields to create an account.",
        );
        return;
      }

      if (password != confirmPassword) {
        setState(() => _error = "Passwords do not match.");
        return;
      }

      try {
        setState(() => _loading = true);

        // Create new user account in Firebase
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // Set display name to team number
        await cred.user?.updateDisplayName('Team $team');

        // Initialize user document in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'email': email,
          'teamNumber': team,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;

        // Initialize theme settings for the new user
        final themeService = context.read<ThemeService>();
        await themeService.loadFromFirestore();

        if (!mounted) return;

        // New users are sent directly to the Setup page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SetupPage()),
        );
      } on FirebaseAuthException catch (e) {
        setState(() => _error = e.message ?? "Account creation failed.");
      } finally {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    }
  }

  /// Sends a password reset email to the entered address.
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();

    setState(() {
      _error = null;
      _info = null;
    });

    if (email.isEmpty) {
      setState(() => _error = "Please enter your email first.");
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() {
        _info = "Password reset email sent. Check your inbox (and spam folder).";
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? "Failed to send reset email.";
      });
    }
  }

  /// Toggles between login and register UI modes.
  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _error = null;
      _info = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _teamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleText = _isRegisterMode ? "Create account" : "Team login";
    final buttonText = _isRegisterMode ? "Create account" : "Log in";
    final switchText = _isRegisterMode
        ? "Already have an account? Log in"
        : "No account yet? Create one";

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isRegisterMode
                        ? "Fill in your details to create an account."
                        : "Log in to continue.",
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  
                  Text(
                    "Please create one account per team.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_isRegisterMode) ...[
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Confirm Password",
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_isRegisterMode) ...[
                    TextField(
                      controller: _teamController,
                      decoration: const InputDecoration(
                        labelText: "Team number",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_info != null) ...[
                    Text(
                      _info!,
                      style: const TextStyle(color: Colors.green),
                    ),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(buttonText),
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (!_isRegisterMode)
                    TextButton(
                      onPressed: _forgotPassword,
                      child: const Text("Forgot password?"),
                    ),

                  TextButton(
                    onPressed: _toggleMode,
                    child: Text(switchText),
                  ),
                  
                  const Divider(height: 32),
                  
                  Text(
                    "Disclaimer: This application is provided 'as is' without warranties of any kind. We are not liable for data loss, security breaches, inaccuracies, or service interruptions. By using this app, you accept all risks and agree that the developers are not responsible for any damages incurred.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.textTheme.bodySmall?.color?.withAlpha(150),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
