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

  // Login controllers
  final _loginPhoneController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  // Register controllers
  final _regNameController = TextEditingController();
  final _regPhoneController = TextEditingController();
  final _regOtpController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  late TabController _tabController;

  static const Color _primaryIndigo = Color(0xFF4F46E5);
  static const Color _violet = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _isSignUp = _tabController.index == 1;
        });
        context.read<AuthProvider>().clearMessages();
      }
    });
    _loadSavedPhone();
  }

  Future<void> _loadSavedPhone() async {
    final phone = await context.read<AuthProvider>().storageService.getSavedPhone();
    if (phone != null && phone.isNotEmpty && mounted) {
      setState(() {
        _loginPhoneController.text = phone;
      });
    }
  }

  @override
  void dispose() {
    _loginPhoneController.dispose();
    _loginPasswordController.dispose();
    _regNameController.dispose();
    _regPhoneController.dispose();
    _regOtpController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onLoginSuccess() {
    final authProvider = context.read<AuthProvider>();
    final tripProvider = context.read<TripProvider>();
    final user = authProvider.currentUser;
    if (user != null) {
      tripProvider.loadUserTrips(
        user.trips,
        onSave: (trips) => authProvider.saveCurrentUserData(trips),
      );
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final phone = _loginPhoneController.text.trim();
    final password = _loginPasswordController.text;

    final success = await authProvider.login(phone, password);
    if (success && mounted) {
      _onLoginSuccess();
    }
  }

  Future<void> _handleBiometricLogin() async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.loginWithBiometrics();
    if (success && mounted) {
      _onLoginSuccess();
    }
  }

  Future<void> _handleSendRegOtp() async {
    final phone = _regPhoneController.text.trim();
    if (phone.isEmpty || phone.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.sendOtp(phone, purpose: 'REGISTER');
    if (success && mounted && authProvider.lastSentOtp != null) {
      _regOtpController.text = authProvider.lastSentOtp!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.mark_email_read_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('OTP sent to $phone: ${authProvider.lastSentOtp}'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final phone = _regPhoneController.text.trim();
    final name = _regNameController.text.trim();
    final otp = _regOtpController.text.trim();
    final password = _regPasswordController.text;
    final confirm = _regConfirmPasswordController.text;

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please request and enter the 6-digit OTP.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final success = await authProvider.register(
      phone: phone,
      fullName: name,
      password: password,
      confirmPassword: confirm,
      otp: otp,
    );

    if (success && mounted) {
      _onLoginSuccess();
    }
  }

  void _showForgotPasswordSheet() {
    final phoneCtrl = TextEditingController(text: _loginPhoneController.text);
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscurePass = true;
    bool otpSent = false;
    String? localOtp;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(Icons.lock_reset_rounded, color: _primaryIndigo, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Reset Password',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your registered phone number to receive an OTP and set a new password.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),

                // Phone field
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                    suffixIcon: TextButton(
                      onPressed: () async {
                        final auth = context.read<AuthProvider>();
                        final success = await auth.sendOtp(
                          phoneCtrl.text.trim(),
                          purpose: 'FORGOT_PASSWORD',
                        );
                        if (success) {
                          setSheetState(() {
                            otpSent = true;
                            localOtp = auth.lastSentOtp;
                            if (localOtp != null) otpCtrl.text = localOtp!;
                          });
                        }
                      },
                      child: Text(otpSent ? 'Resend' : 'Send OTP'),
                    ),
                  ),
                ),
                if (localOtp != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '🔐 Simulated SMS OTP: $localOtp',
                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // OTP field
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '6-Digit OTP Code',
                    prefixIcon: Icon(Icons.pin_rounded),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),

                // New Password
                TextField(
                  controller: newPassCtrl,
                  obscureText: obscurePass,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setSheetState(() => obscurePass = !obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Confirm Password
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: obscurePass,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      final ok = await auth.resetPassword(
                        phone: phoneCtrl.text.trim(),
                        otp: otpCtrl.text.trim(),
                        newPassword: newPassCtrl.text,
                        confirmPassword: confirmPassCtrl.text,
                      );
                      if (ok && mounted) {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password reset successfully! Please sign in.'),
                            backgroundColor: Color(0xFF059669),
                          ),
                        );
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Update Password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showServerConfigSheet() async {
    final apiService = context.read<AuthProvider>().apiService;
    final currentIp = await apiService.getCustomServerIp() ?? '';
    final ipCtrl = TextEditingController(text: currentIp);
    String testStatus = '';
    bool testing = false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(Icons.wifi_tethering_rounded, color: _primaryIndigo, size: 26),
                    SizedBox(width: 10),
                    Text(
                      'Host PC Server / Wi-Fi IP',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'When connected to the same Wi-Fi or Mobile Hotspot, enter your host PC IP address below:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Suggested Host PC IP Addresses:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    '192.168.1.111',
                    '10.234.230.248',
                    '10.100.83.76',
                    '127.0.0.1',
                  ].map((ip) => ActionChip(
                    label: Text(ip, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      setSheetState(() {
                        ipCtrl.text = ip;
                        testStatus = '';
                      });
                    },
                  )).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ipCtrl,
                  decoration: InputDecoration(
                    labelText: 'Server IP Address (Port 5000)',
                    hintText: 'e.g. 192.168.1.111',
                    prefixIcon: const Icon(Icons.computer_rounded),
                    suffixIcon: TextButton(
                      onPressed: testing ? null : () async {
                        setSheetState(() {
                          testing = true;
                          testStatus = 'Connecting...';
                        });
                        final ok = await apiService.testConnection(ipCtrl.text.trim());
                        setSheetState(() {
                          testing = false;
                          testStatus = ok
                              ? 'Connected to SQL Server backend successfully!'
                              : 'Could not connect. Check PC firewall & Wi-Fi.';
                        });
                      },
                      child: const Text('Test'),
                    ),
                  ),
                ),
                if (testStatus.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    testStatus,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: testStatus.contains('successfully') ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await apiService.setCustomServerIp(ipCtrl.text.trim());
                      if (mounted) {
                        Navigator.pop(sheetCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Server IP updated to: ${ipCtrl.text.trim()}'),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    },
                    child: const Text('Save Server IP'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient header ─────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.38,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E1B4B),
                    _primaryIndigo,
                    _violet,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.flight_takeoff_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EquiTrip',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  'Smart Trip Expense Splitter',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.wifi_tethering_rounded, color: Colors.white, size: 20),
                            ),
                            tooltip: 'Server & Wi-Fi / Hotspot IP Settings',
                            onPressed: _showServerConfigSheet,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        _isSignUp ? 'Create Account' : 'Welcome Back',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSignUp
                            ? 'Verify phone via OTP & store in database'
                            : 'Sign in to access your synchronized trips',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Main Card Form ─────────────────────────────────────────
          Positioned.fill(
            top: size.height * 0.30,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Tab Bar (Login vs Register)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            color: _primaryIndigo,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.grey.shade700,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Sign In'),
                            Tab(text: 'Register with OTP'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Error message alert
                      if (auth.errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  auth.errorMessage!,
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Success message alert
                      if (auth.successMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline_rounded, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  auth.successMessage!,
                                  style: TextStyle(color: Colors.green.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── LOGIN FORM ────────────────────────────────
                      if (!_isSignUp) ...[
                        TextFormField(
                          controller: _loginPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'e.g. 9876543210',
                            prefixIcon: Icon(Icons.phone_android_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _loginPasswordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordSheet,
                            child: const Text('Forgot Password? (OTP Reset)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: auth.isLoading ? null : _handleLogin,
                            child: auth.isLoading
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Biometric / Fingerprint / Device PIN Quick Unlock Button
                        OutlinedButton.icon(
                          onPressed: auth.isLoading ? null : _handleBiometricLogin,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(color: _primaryIndigo.withValues(alpha: 0.3)),
                          ),
                          icon: const Icon(Icons.fingerprint_rounded, color: _primaryIndigo, size: 24),
                          label: const Text(
                            'Quick Sign In with Fingerprint / PIN',
                            style: TextStyle(color: _primaryIndigo, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],

                      // ── REGISTER FORM ─────────────────────────────
                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _regNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            hintText: 'e.g. John Doe',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _regPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'e.g. 9876543210',
                            prefixIcon: const Icon(Icons.phone_android_rounded),
                            suffixIcon: TextButton(
                              onPressed: auth.isLoading ? null : _handleSendRegOtp,
                              child: Text(auth.isOtpSent ? 'Resend' : 'Send OTP'),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
                        ),
                        if (auth.lastSentOtp != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.sms_rounded, color: Color(0xFF059669), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Simulated SMS OTP Code: ${auth.lastSentOtp}',
                                    style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _regOtpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: '6-Digit OTP Code',
                            hintText: 'Enter code sent to phone',
                            prefixIcon: Icon(Icons.pin_rounded),
                            counterText: '',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter OTP to verify account' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _regPasswordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Password required';
                            if (v.length < 4) return 'Password must be at least 4 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _regConfirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Confirm password';
                            if (v != _regPasswordController.text) return 'Passwords do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: auth.isLoading ? null : _handleRegister,
                            child: auth.isLoading
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Create Account & Sign In'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
