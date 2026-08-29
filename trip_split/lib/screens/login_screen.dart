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
  int _selectedDietType = 0;

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isActionLoading = false;
  bool _isOtpLoading = false;

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
    try {
      final phone = await context.read<AuthProvider>().storageService.getSavedPhone();
      if (phone != null && phone.isNotEmpty && mounted) {
        setState(() {
          _loginPhoneController.text = phone;
        });
      }
    } catch (_) {}
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

    setState(() => _isActionLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final phone = _loginPhoneController.text.trim();
      final password = _loginPasswordController.text;

      final success = await authProvider.login(phone, password);
      if (success && mounted) {
        _onLoginSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login error: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isActionLoading = false);
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    setState(() => _isActionLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.loginWithBiometrics();
      if (success && mounted) {
        _onLoginSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
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

    setState(() => _isOtpLoading = true);
    try {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send OTP: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isOtpLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

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

    setState(() => _isActionLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.register(
        phone: phone,
        fullName: name,
        password: password,
        confirmPassword: confirm,
        otp: otp,
        dietType: _selectedDietType,
      );

      if (success && mounted) {
        _onLoginSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showForgotPasswordSheet() {
    final phoneCtrl = TextEditingController(text: _loginPhoneController.text);
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscurePass = true;
    bool otpSent = false;
    bool isResetting = false;
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
                        try {
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
                        } catch (_) {}
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
                      'OTP Code: $localOtp',
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

                // Confirm New Password
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
                    onPressed: isResetting ? null : () async {
                      setSheetState(() => isResetting = true);
                      try {
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
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      } finally {
                        setSheetState(() => isResetting = false);
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isResetting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Update Password'),
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
    final ipCtrl = TextEditingController(text: currentIp.isEmpty ? '10.130.176.248' : currentIp);
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
                    Icon(Icons.dns_rounded, color: _primaryIndigo, size: 26),
                    SizedBox(width: 10),
                    Text(
                      'API Server Config & IP',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Current Active Base URL: ${apiService.baseUrl}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryIndigo),
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter your Host PC IP Address and Port:',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Quick Host Presets:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    '10.130.176.248',
                    'localhost',
                    '127.0.0.1',
                    '10.0.2.2',
                    '192.168.1.111',
                  ].map((host) => ActionChip(
                    avatar: Icon(
                      host == 'localhost' || host == '127.0.0.1' ? Icons.laptop_rounded : Icons.wifi_rounded,
                      size: 14,
                      color: _primaryIndigo,
                    ),
                    label: Text(host, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      setSheetState(() {
                        final currentPort = ipCtrl.text.contains(':') ? ipCtrl.text.split(':').last : '5000';
                        ipCtrl.text = '$host:$currentPort';
                        testStatus = '';
                      });
                    },
                  )).toList(),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Quick Port Selectors:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    '5000',
                    '5246',
                    '7266',
                    '8080',
                  ].map((port) => ActionChip(
                    avatar: const Icon(Icons.numbers_rounded, size: 14, color: _primaryIndigo),
                    label: Text('Port $port', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      setSheetState(() {
                        final host = ipCtrl.text.contains(':') ? ipCtrl.text.split(':').first : (ipCtrl.text.isEmpty ? '10.130.176.248' : ipCtrl.text);
                        ipCtrl.text = '$host:$port';
                        testStatus = '';
                      });
                    },
                  )).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ipCtrl,
                  decoration: InputDecoration(
                    labelText: 'API Server IP : Port',
                    hintText: 'e.g. 10.130.176.248:5000 or localhost:5246',
                    prefixIcon: const Icon(Icons.computer_rounded),
                    suffixIcon: TextButton(
                      onPressed: testing ? null : () async {
                        setSheetState(() {
                          testing = true;
                          testStatus = 'Connecting to ASP.NET Core API...';
                        });
                        try {
                          final ok = await apiService.testConnection(ipCtrl.text.trim());
                          setSheetState(() {
                            testing = false;
                            testStatus = ok
                                ? 'Connected to ASP.NET Core Web API successfully!'
                                : 'Could not connect. Check PC firewall & active API port.';
                          });
                        } catch (e) {
                          setSheetState(() {
                            testing = false;
                            testStatus = 'Error: $e';
                          });
                        }
                      },
                      child: testing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Test Connection'),
                    ),
                  ),
                ),
                if (testStatus.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: testStatus.contains('successfully') ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: testStatus.contains('successfully') ? Colors.green.shade300 : Colors.orange.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          testStatus.contains('successfully') ? Icons.check_circle : Icons.warning_amber_rounded,
                          color: testStatus.contains('successfully') ? Colors.green.shade700 : Colors.orange.shade800,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            testStatus,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: testStatus.contains('successfully') ? Colors.green.shade900 : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save & Apply IP Config'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      try {
                        await apiService.setCustomServerIp(ipCtrl.text.trim());
                        if (mounted) {
                          Navigator.pop(sheetCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Active API Base URL set to ${apiService.baseUrl}'),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        }
                      } catch (_) {}
                    },
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
    final isCompact = size.height < 700;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1B4B),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    // Header Section
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: isCompact ? 10 : 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.flight_takeoff_rounded, color: Colors.white, size: 24),
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
                            tooltip: 'Server & Wi-Fi Settings',
                            onPressed: _showServerConfigSheet,
                          ),
                        ],
                      ),
                    ),

                    // Title Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isSignUp ? 'Create Account' : 'Welcome Back',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isCompact ? 22 : 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isSignUp
                                  ? 'Verify phone via OTP & store in SQL database'
                                  : 'Sign in to access your synchronized trips',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Scrollable Card Container
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8F9FF),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: isCompact ? 16 : 24,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // Tab Switcher
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: TabBar(
                                    controller: _tabController,
                                    indicator: BoxDecoration(
                                      color: _primaryIndigo,
                                      borderRadius: BorderRadius.circular(12),
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
                                const SizedBox(height: 18),

                                // Error Banner
                                if (auth.errorMessage != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 14),
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

                                // Success Banner
                                if (auth.successMessage != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 14),
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

                                // SIGN IN FORM
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
                                  const SizedBox(height: 14),
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
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _showForgotPasswordSheet,
                                      child: const Text('Forgot Password?', style: TextStyle(color: _primaryIndigo, fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: (_isActionLoading || auth.isLoading) ? null : _handleLogin,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _primaryIndigo,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: (_isActionLoading || auth.isLoading)
                                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                          : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.fingerprint_rounded, color: _primaryIndigo),
                                    label: const Text('Sign In with Biometrics / PIN', style: TextStyle(color: _primaryIndigo, fontWeight: FontWeight.w600)),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 48),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: BorderSide(color: _primaryIndigo.withValues(alpha: 0.3)),
                                    ),
                                    onPressed: _handleBiometricLogin,
                                  ),
                                ] else ...[
                                  // REGISTER WITH OTP FORM
                                  TextFormField(
                                    controller: _regNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Full Name',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _regPhoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: InputDecoration(
                                      labelText: 'Phone Number',
                                      prefixIcon: const Icon(Icons.phone_android_rounded),
                                      suffixIcon: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: TextButton(
                                          onPressed: _isOtpLoading ? null : _handleSendRegOtp,
                                          child: _isOtpLoading
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Text('Get OTP', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryIndigo)),
                                        ),
                                      ),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required' : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _regOtpController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 6,
                                    decoration: const InputDecoration(
                                      labelText: '6-Digit OTP Code',
                                      prefixIcon: Icon(Icons.pin_rounded),
                                      counterText: '',
                                    ),
                                    validator: (v) => (v == null || v.trim().length != 6) ? 'Enter 6-digit OTP' : null,
                                  ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<int>(
                                    value: _selectedDietType,
                                    decoration: const InputDecoration(
                                      labelText: 'Dietary Preference',
                                      prefixIcon: Icon(Icons.restaurant_rounded),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 0, child: Text('Vegetarian')),
                                      DropdownMenuItem(value: 1, child: Text('Non-Vegetarian')),
                                      DropdownMenuItem(value: 2, child: Text('Non-Veg + Alcoholic')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedDietType = val);
                                    },
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
                                    validator: (v) => (v == null || v.length < 4) ? 'Minimum 4 characters required' : null,
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
                                      if (v == null || v.isEmpty) return 'Please confirm your password';
                                      if (v != _regPasswordController.text) return 'Passwords do not match';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: (_isActionLoading || auth.isLoading) ? null : _handleRegister,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _violet,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: (_isActionLoading || auth.isLoading)
                                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                          : const Text('Create Account & Verify OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
