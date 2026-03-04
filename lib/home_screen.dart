import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Conditional import for web-only functionality
import 'dart:html' as html; 

import 'game_screen.dart';
import 'highscores_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _showEmailLogin = false;
  bool _isRegistering = false;
  bool _isGuestMode = false;

  // --- PWA Logic Variables ---
  dynamic _deferredPrompt;
  bool _showInstallButton = false;

  @override
  void initState() {
    super.initState();
    _setupPWAInstallLogic();
  }

  // --- PWA Logic ---
  void _setupPWAInstallLogic() {
    if (kIsWeb) {
      // 1. Check if already installed
      if (_isAlreadyInstalled()) return;

      // 2. Listen for the 'beforeinstallprompt' event
      html.window.addEventListener('beforeinstallprompt', (event) {
        // Prevent the browser's default mini-infobar
        event.preventDefault();
        _deferredPrompt = event;

        // Only show button if on a mobile device
        if (_isMobileDevice()) {
          setState(() => _showInstallButton = true);
        }
      });

      // 3. Hide the button once successfully installed
      html.window.addEventListener('appinstalled', (event) {
        setState(() => _showInstallButton = false);
      });

      // 4. iOS Fallback: Safari doesn't fire 'beforeinstallprompt'
      if (_isIOSDevice() && !_isAlreadyInstalled()) {
        setState(() => _showInstallButton = true);
      }
    }
  }

  bool _isAlreadyInstalled() {
    final isStandalone = html.window.matchMedia('(display-mode: standalone)').matches;
    bool isIosStandalone = false;
    try {
      isIosStandalone = (html.window.navigator as dynamic).standalone == true;
    } catch (e) {
      isIosStandalone = false; 
    }
    return isStandalone || isIosStandalone;
  }

  bool _isMobileDevice() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final isModernIpad = userAgent.contains("macintosh") && html.window.navigator.maxTouchPoints! > 0;
    
    return userAgent.contains("iphone") || 
           userAgent.contains("android") || 
           userAgent.contains("ipad") ||
           isModernIpad;
  }

  bool _isIOSDevice() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final isModernIpad = userAgent.contains("macintosh") && html.window.navigator.maxTouchPoints! > 0;
    return userAgent.contains("iphone") || userAgent.contains("ipad") || isModernIpad;
  }

  Future<void> _handlePWAInstall() async {
    if (_deferredPrompt != null) {
      _deferredPrompt.prompt();
      _deferredPrompt = null;
      setState(() => _showInstallButton = false);
    } else if (_isIOSDevice()) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Install on iOS", style: TextStyle(color: Colors.blue)),
          content: const Text(
            "To install MEMORY, tap the 'Share' icon in your Safari menu bar and select 'Add to Home Screen'.",
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Got it!", style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        )
      );
    }
  }

  // --- Auth Logic ---

  Future<void> _handleGoogleSignIn() async {
    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      UserCredential userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      setState(() => _isGuestMode = false); // Ensure guest mode is off on real login
      await _syncUserProfile(userCredential.user);
    } catch (e) {
      _showError("Google Sign-In Error: $e");
    }
  }

  Future<void> _handleEmailAuth() async {
    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text.trim();
      if (email.isEmpty || password.isEmpty) return;

      UserCredential userCredential;
      if (_isRegistering) {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, 
          password: password
        );
        await userCredential.user?.updateDisplayName(_nameController.text.trim());
      } else {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, 
          password: password
        );
      }
      setState(() => _isGuestMode = false);
      await _syncUserProfile(userCredential.user);
    } on FirebaseAuthException catch (e) {
      _showError(e.code == 'operation-not-allowed' 
          ? "Enable Email/Password in Firebase Console!" 
          : e.message ?? "Auth failed");
    }
  }

  Future<void> _syncUserProfile(User? user) async {
    if (user == null) return;
    String? nameToSave = user.displayName ?? _nameController.text.trim();
    if (nameToSave.isEmpty) nameToSave = "Player";

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'last_login': FieldValue.serverTimestamp(),
      'display_name': nameToSave,
      'gems': FieldValue.increment(0), 
    }, SetOptions(merge: true));
    
    if (mounted) setState(() {});
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      bottomNavigationBar: _buildUniversalHighscoreFooter(),
      body: Stack(
        children: [
          SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_showInstallButton) ...[
                    _buildPWAInstallButton(),
                    const SizedBox(height: 20),
                  ],

                  // Show Menu if logged in OR if Guest Mode is active
                  if (user == null && !_isGuestMode) _buildLoginOptions() else _buildGameMenu(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPWAInstallButton() {
    return ElevatedButton.icon(
      onPressed: _handlePWAInstall,
      icon: const Icon(Icons.install_mobile, size: 18),
      label: const Text("INSTALL APP", style: TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildUniversalHighscoreFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const HighscoresScreen())
              ),
              icon: const Icon(Icons.leaderboard, color: Colors.blueGrey),
              label: const Text(
                "VIEW ALL HIGH SCORES", 
                style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoginOptions() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.shade100, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "MEMORY",
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.blue,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),

                if (!_showEmailLogin) ...[
                  _buildGoogleButton(),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      side: const BorderSide(color: Colors.blue),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => setState(() => _showEmailLogin = true),
                    child: const Text("Sign in with Email"),
                  ),
                  const Divider(height: 30),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      // Transition to Game Menu as Guest
                      setState(() {
                        _isGuestMode = true;
                        _nameController.text = "Guest";
                      });
                    },
                    child: const Text("Play as Guest",
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                ] else ...[
                  if (_isRegistering)
                    _buildCompactField(_nameController, "Player Name"),
                  
                  _buildCompactField(_emailController, "Email"),
                  _buildCompactField(_passwordController, "Password (min 6 chars)", obscure: true),
                  
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRegistering ? Colors.green : Colors.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _handleEmailAuth,
                      child: Text(
                        _isRegistering ? "CREATE ACCOUNT" : "LOGIN",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _isRegistering = !_isRegistering),
                    child: Text(
                      _isRegistering ? "Already have an account? Login" : "NEW USER? REGISTER HERE",
                      style: TextStyle(
                        fontSize: 12,
                        color: _isRegistering ? Colors.blue : Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showEmailLogin = false),
                    child: const Text("Back", style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactField(TextEditingController controller, String hint, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: const Color(0xFFF0F7FF),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return OutlinedButton.icon(
      onPressed: _handleGoogleSignIn,
      icon: SvgPicture.string('<svg width="18" height="18" viewBox="0 0 533.5 544.3" xmlns="http://www.w3.org/2000/svg"><path fill="#EA4335" d="M533.5 278.4c0-18.6-1.5-37-4.7-54.8H272.1v103.8h147.1c-6.2 33.4-25.9 61.7-55.1 80.7v66h88.9c52.1-48 80.5-118.7 80.5-195.7z"/><path fill="#34A853" d="M272.1 544.3c74.1 0 136.3-24.5 181.7-66.2l-88.9-66c-24.7 16.6-56.4 26.5-92.7 26.5-71.3 0-131.7-48.1-153.4-112.6H27.6v70.7c45.2 89.6 137.9 147.6 244.5 147.6z"/><path fill="#4A90E2" d="M118.7 326c-10.4-31-10.4-64.5 0-95.5V159.7H27.6c-37.7 75.2-37.7 165.1 0 240.3l91.1-74z"/><path fill="#FBBC05" d="M272.1 106.1c40.3-.6 79.3 14.7 109.1 43.1l81.5-81.5C413.9 24.9 344.7-1 272.1 0 165.5 0 72.8 58 27.6 147.6l91.1 70.8c21.7-64.5 82.2-112.3 153.4-112.3z"/></svg>', height: 18),
      label: const Text('Sign in with Google'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50), side: const BorderSide(color: Colors.blue), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildGameMenu() {
    final User? user = FirebaseAuth.instance.currentUser;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: AspectRatio(
        aspectRatio: 1.0, 
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0), // Reduced vertical padding
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade100, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "MEMORY",
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.blue, letterSpacing: 2), // Slightly smaller title
                      ),
                      const SizedBox(height: 20), // Reduced spacing
                      TextField(
                        controller: _nameController,
                        textAlign: TextAlign.center,
                        readOnly: _isGuestMode,
                        style: const TextStyle(fontSize: 14), // Smaller font for consistency
                        decoration: InputDecoration(
                          hintText: "Enter Player Name",
                          contentPadding: const EdgeInsets.symmetric(vertical: 12), // Tighter field
                          filled: true,
                          fillColor: _isGuestMode ? Colors.grey.shade100 : Colors.blue.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text("GAME MODE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade300, letterSpacing: 1.2)),
                          const Expanded(child: Divider(indent: 10)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            elevation: 0, // Matches flat look of login options
                            padding: const EdgeInsets.symmetric(vertical: 14), // Smaller vertical padding
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            String name = _nameController.text.trim().isEmpty ? "Guest" : _nameController.text.trim();
                            Navigator.push(context, MaterialPageRoute(builder: (context) => GameScreen(playerName: name)));
                          },
                          child: const Text("Memory Game", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), // Smaller font
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          if (_isGuestMode) {
                            setState(() {
                              _isGuestMode = false;
                              _nameController.clear();
                            });
                          } else {
                            await FirebaseAuth.instance.signOut();
                            setState(() {});
                          }
                        },
                        child: Text(_isGuestMode ? "Exit Guest Mode" : "Sign Out", 
                            style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_isGuestMode && user != null)
              Positioned(
                top: 15,
                right: 15,
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    final int gems = data?['gems'] ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.diamond, color: Colors.cyan, size: 14), // Slightly smaller icon
                          const SizedBox(width: 6),
                          Text("$gems", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.blue)),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}