// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const Color _primaryIndigo = Color(0xFF4F46E5);
  static const Color _violet = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _confirmPasswordController.clear();
    });
    _animController
      ..reset()
      ..forward();
    context.read<AuthProvider>().clearError();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final tripProvider = context.read<TripProvider>();

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    bool success = false;

    if (_isSignUp) {
      success = await authProvider.register(username, password);
    } else {
      success = await authProvider.login(username, password);
    }

    if (success && mounted) {
      final user = authProvider.currentUser;
      if (user != null) {
        tripProvider.loadUserTrips(
          user.trips,
          onSave: (trips) => authProvider.saveCurrentUserData(trips),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background top half ──────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.44,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF312E81), // deep indigo
                    _primaryIndigo,
                    _violet,
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // ── Decorative circles ────────────────────────────────────
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          // ── Bottom white surface ──────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: size.height * 0.62,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
            ),
          ),
          // ── Content ───────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // App Logo
                  _buildLogo(),
                  const SizedBox(height: 14),
                  // App name
                  const Text(
                    'EquiTrip',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Smart Group Expense Splitter',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // ── White card form ────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                              blurRadius: 40,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Mode tab switcher
                              _buildTabSwitcher(),
                              const SizedBox(height: 24),

                              // Error banner
                              if (auth.errorMessage != null) ...[
                                _buildErrorBanner(auth.errorMessage!),
                                const SizedBox(height: 16),
                              ],

                              // Username
                              _buildField(
                                key: const Key('username_field'),
                                controller: _usernameController,
                                label: 'Username',
                                hint: 'e.g., john_doe',
                                icon: Icons.person_outline_rounded,
                                action: TextInputAction.next,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Please enter a username';
                                  if (v.trim().length < 3) return 'At least 3 characters';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),

                              // Password
                              _buildPasswordField(
                                key: const Key('password_field'),
                                controller: _passwordController,
                                label: 'Password',
                                hint: 'Enter your password',
                                obscure: _obscurePassword,
                                onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                                action: _isSignUp ? TextInputAction.next : TextInputAction.done,
                                onSubmit: () { if (!_isSignUp) _submit(); },
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Please enter a password';
                                  if (v.length < 4) return 'At least 4 characters';
                                  return null;
                                },
                              ),

                              // Confirm password (signup only)
                              if (_isSignUp) ...[
                                const SizedBox(height: 14),
                                _buildPasswordField(
                                  key: const Key('confirm_password_field'),
                                  controller: _confirmPasswordController,
                                  label: 'Confirm Password',
                                  hint: 'Re-enter your password',
                                  obscure: _obscureConfirmPassword,
                                  onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                  action: TextInputAction.done,
                                  onSubmit: _submit,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return 'Please confirm your password';
                                    if (v != _passwordController.text) return 'Passwords do not match';
                                    return null;
                                  },
                                ),
                              ],

                              const SizedBox(height: 22),

                              // Submit button
                              _buildSubmitButton(auth),

                              const SizedBox(height: 18),

                              // Toggle mode link
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _isSignUp ? 'Already have an account? ' : "Don't have an account? ",
                                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                                  ),
                                  GestureDetector(
                                    key: const Key('toggle_mode_link'),
                                    onTap: _toggleMode,
                                    child: Text(
                                      _isSignUp ? 'Sign In' : 'Create Account',
                                      style: const TextStyle(
                                        color: _primaryIndigo,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: Color(0xFF4F46E5), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your data is securely saved to local device storage',
                            style: TextStyle(fontSize: 12, color: Colors.indigo.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          'assets/icon/applogo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tabOption('Sign In', !_isSignUp, () { if (_isSignUp) _toggleMode(); }),
          _tabOption('Create Account', _isSignUp, () { if (!_isSignUp) _toggleMode(); }),
        ],
      ),
    );
  }

  Widget _tabOption(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2))]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
              color: selected ? const Color(0xFF4F46E5) : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputAction action,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
      ),
      textInputAction: action,
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required TextInputAction action,
    required VoidCallback onSubmit,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF9CA3AF), size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: const Color(0xFF9CA3AF),
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
      textInputAction: action,
      onFieldSubmitted: (_) => onSubmit(),
      validator: validator,
    );
  }

  Widget _buildSubmitButton(AuthProvider auth) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: auth.isLoading
            ? null
            : const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
        borderRadius: BorderRadius.circular(14),
        color: auth.isLoading ? const Color(0xFFE5E7EB) : null,
        boxShadow: auth.isLoading
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('submit_button'),
          borderRadius: BorderRadius.circular(14),
          onTap: auth.isLoading ? null : _submit,
          child: Center(
            child: auth.isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF4F46E5)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isSignUp ? 'Create Account' : 'Sign In',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
