import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _rememberMe = false;
  String? _error;
  String? _info;

  // Toggle between Login and Registration mode
  bool _isRegisterMode = false;

  @override
  void initState() {
    super.initState();
    // Load credentials after the first frame
    Future.microtask(() => _loadSavedCredentials());
  }

  /// Loads saved credentials from SharedPreferences.
  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('remembered_email');
      final savedPassword = prefs.getString('remembered_password');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (rememberMe && mounted) {
        setState(() {
          _emailController.text = savedEmail ?? '';
          _passwordController.text = savedPassword ?? '';
          _rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint("Error loading credentials: $e");
    }
  }

  /// Saves or clears credentials in SharedPreferences (safe execution).
  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailController.text.trim());
        await prefs.setString('remembered_password', _passwordController.text.trim());
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('remembered_email');
        await prefs.remove('remembered_password');
        await prefs.setBool('remember_me', false);
      }
    } catch (e) {
      debugPrint("Error saving credentials: $e");
    }
  }

  /// Handles the form submission for both login and registration.
  Future<void> _submit() async {
    if (_loading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = "Please fill in email and password.");
      return;
    }

    setState(() {
      _error = null;
      _info = null;
      _loading = true;
    });

    try {
      if (!_isRegisterMode) {
        // 1. Authenticate user with Firebase
        final UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // 2. Save credentials if needed (non-blocking)
        _saveCredentials();

        // 3. Check if the user has completed the initial setup
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .get();
        
        final hasSetup = userDoc.exists && (userDoc.data()?.containsKey('setupData') ?? false);

        if (!mounted) return;

        // 4. Load theme in background
        context.read<ThemeService>().loadFromFirestore();

        // 5. Navigate to the appropriate page
        if (hasSetup) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const SetupPage()),
            (route) => false,
          );
        }
      } else {
        // Registration Logic
        final confirmPassword = _confirmPasswordController.text.trim();
        final team = _teamController.text.trim();

        if (team.isEmpty || confirmPassword.isEmpty) {
          throw Exception("Please fill in all fields.");
        }

        if (password != confirmPassword) {
          throw Exception("Passwords do not match.");
        }

        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        await cred.user?.updateDisplayName('Team $team');

        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'email': email,
          'teamNumber': team,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        context.read<ThemeService>().loadFromFirestore();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SetupPage()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? "Login failed.");
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Sends a password reset email.
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = "Please enter your email address first.");
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() => _info = "Password reset email sent. Check your inbox.");
    } catch (e) {
      setState(() => _error = "Failed to send reset email.");
    }
  }

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
    final buttonText = _isRegisterMode ? "Register" : "Log in";
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
                        ? "Create your team account"
                        : "Welcome back!",
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
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  
                  if (!_isRegisterMode)
                    CheckboxListTile(
                      title: const Text("Remember me"),
                      value: _rememberMe,
                      onChanged: (val) => setState(() => _rememberMe = val ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                  if (_isRegisterMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscurePassword,
                      decoration: const InputDecoration(
                        labelText: "Confirm Password",
                        prefixIcon: Icon(Icons.lock_clock_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _teamController,
                      decoration: const InputDecoration(
                        labelText: "Team number",
                        prefixIcon: Icon(Icons.tag),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],

                  const SizedBox(height: 16),
                  
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    ),
                  if (_info != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_info!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center),
                    ),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(buttonText),
                    ),
                  ),

                  const SizedBox(height: 12),

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
