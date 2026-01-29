import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ftcmanageapp/program-files/frontend/setup.dart';
import 'package:ftcmanageapp/program-files/frontend/dashboard.dart';
import 'package:ftcmanageapp/program-files/backend/settings/theme.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-top.dart';
import 'package:ftcmanageapp/program-files/backend/widgets/appbar-bottom.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _teamController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _error;
  String? _info;
  bool _isRegisterMode = false;

  static const String _webClientId = "284022673738-8d6lo37ir1pq6sce7jacc8sf18vvs2co.apps.googleusercontent.com";

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadSavedCredentials());
  }

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

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });

    try {
      UserCredential userCred;
      if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({'prompt': 'select_account'});
        userCred = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) { setState(() => _loading = false); return; }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
        userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final User? user = userCred.user;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!userDoc.exists || userDoc.data()?['teamNumber'] == null) {
          final teamNumber = await _promptForTeamNumber();
          if (teamNumber != null) {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'email': user.email, 'teamNumber': teamNumber, 'createdAt': FieldValue.serverTimestamp()
            }, SetOptions(merge: true));
          } else {
            await FirebaseAuth.instance.signOut(); setState(() => _loading = false); return;
          }
        }
        if (!mounted) return;
        context.read<ThemeService>().loadFromFirestore();
        final hasSetup = (await FirebaseFirestore.instance.collection('users').doc(user.uid).get()).data()?.containsKey('setupData') ?? false;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => hasSetup ? const DashboardPage() : const SetupPage()), (route) => false);
      }
    } catch (e) {
      setState(() => _error = "Google Sign-In failed.");
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<String?> _promptForTeamNumber() async {
    String? result; final controller = TextEditingController();
    await showDialog(context: context, barrierDismissible: false, builder: (context) => AlertDialog(title: const Text("Final Step"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter your FTC Team Number."), const SizedBox(height: 16), TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Team Number", prefixIcon: Icon(Icons.tag)))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")), ElevatedButton(onPressed: () { if (controller.text.trim().isNotEmpty) { result = controller.text.trim(); Navigator.pop(context); } }, child: const Text("Continue"))]));
    return result;
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { setState(() => _error = "Please enter your email to reset password."); return; }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() { _info = "Password reset email sent. Check your inbox."; _error = null; });
    } catch (e) { setState(() => _error = "Could not send reset email."); }
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) { setState(() => _error = "Fill in all fields."); return; }
    setState(() { _error = null; _info = null; _loading = true; });
    try {
      if (!_isRegisterMode) {
        final UserCredential cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        await _saveCredentials();
        if (!mounted) return;
        context.read<ThemeService>().loadFromFirestore();
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).get();
        final hasSetup = userDoc.exists && (userDoc.data()?.containsKey('setupData') ?? false);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => hasSetup ? const DashboardPage() : const SetupPage()), (route) => false);
      } else {
        final confirmPassword = _confirmPasswordController.text.trim();
        final team = _teamController.text.trim();
        if (team.isEmpty || confirmPassword.isEmpty) throw Exception("Fill in all fields.");
        if (password != confirmPassword) throw Exception("Passwords do not match.");
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
        await cred.user?.updateDisplayName('Team $team');
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({'email': email, 'teamNumber': team, 'createdAt': FieldValue.serverTimestamp()});
        if (!mounted) return;
        context.read<ThemeService>().loadFromFirestore();
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const SetupPage()), (route) => false);
      }
    } on FirebaseAuthException catch (e) { setState(() => _error = e.message); }
    catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  void _toggleMode() { setState(() { _isRegisterMode = !_isRegisterMode; _error = null; _info = null; }); }

  @override
  void dispose() {
    _emailController.dispose(); _passwordController.dispose();
    _confirmPasswordController.dispose(); _teamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: TopAppBar(title: _isRegisterMode ? "Register Team" : "Team Login", showThemeToggle: true, showLogout: false, showBackButton: false),
      bottomNavigationBar: BottomNavBar(currentIndex: 0, onTabSelected: (_) {}, items: const []),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Text(_isRegisterMode ? "Create Account" : "Welcome Back!", style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email))),
                const SizedBox(height: 16),
                TextField(controller: _passwordController, obscureText: _obscurePassword, decoration: InputDecoration(labelText: "Password", prefixIcon: const Icon(Icons.lock), suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
                
                if (!_isRegisterMode) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (val) => setState(() => _rememberMe = val ?? false),
                          ),
                          const Text("Remember me"),
                        ],
                      ),
                      TextButton(onPressed: _forgotPassword, child: const Text("Forgot password?")),
                    ],
                  ),
                ],

                if (_isRegisterMode) ...[
                  const SizedBox(height: 16),
                  TextField(controller: _confirmPasswordController, obscureText: _obscurePassword, decoration: const InputDecoration(labelText: "Confirm Password", prefixIcon: Icon(Icons.lock_outline))),
                  const SizedBox(height: 16),
                  TextField(controller: _teamController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Team Number", prefixIcon: Icon(Icons.tag))),
                ],
                const SizedBox(height: 16),
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
                if (_info != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_info!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center)),
                SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _loading ? null : _submit, child: _loading ? const CircularProgressIndicator(color: Colors.white) : Text(_isRegisterMode ? "Register" : "Login"))),
                if (!_isRegisterMode) ...[
                  const SizedBox(height: 24),
                  Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text("OR", style: TextStyle(color: theme.hintColor))), const Expanded(child: Divider())]),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, height: 50, child: OutlinedButton(onPressed: _loading ? null : _signInWithGoogle, style: OutlinedButton.styleFrom(side: BorderSide(color: theme.dividerColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.login, size: 20), const SizedBox(width: 12), Flexible(child: Text("Continue with Google", style: theme.textTheme.labelLarge, overflow: TextOverflow.ellipsis))]))),
                ],
                const SizedBox(height: 32),
                TextButton(onPressed: _toggleMode, child: Text(_isRegisterMode ? "Back to Login" : "New Team? Register here")),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text("By using this app, you accept all risks and agree that the developers are not responsible for any damages incurred.", style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.hintColor), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
