// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'trip_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _syncTimer;
  int _unreadNotifs = 0;

  static const List<Color> _cardGradients = [
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFFDC2626),
  ];

  bool _isApiConnected = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    // 1. Initial sync on app start
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnectionAndSync(force: true));
    // 2. Lightweight heartbeat check every 20s (zero DB load, only syncs on reconnection or local edits)
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkConnectionAndSync());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectionAndSync({bool force = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final wasConnected = _isApiConnected;
      final isNowConnected = await auth.apiService.testConnection(auth.apiService.baseUrl);

      if (mounted && _isApiConnected != isNowConnected) {
        setState(() => _isApiConnected = isNowConnected);
      }

      // Reconnection event detected: transitioned from offline -> online!
      final justReconnected = !wasConnected && isNowConnected;
      final tripProvider = context.read<TripProvider>();
      final hasPendingChanges = tripProvider.hasPendingSync;

      // Smart Sync Rules:
      // - Only sync if forced (app start or pull-to-refresh),
      // - Or if newly reconnected to API,
      // - Or if online and has pending local changes to push.
      // - Otherwise, DO NOT spam the server!
      if (isNowConnected && (force || justReconnected || hasPendingChanges)) {
        await _performDatabaseSync(auth, user, tripProvider);
      }
    } catch (_) {
      if (mounted && _isApiConnected) {
        setState(() => _isApiConnected = false);
      }
    }
  }

  Future<void> _performDatabaseSync(AuthProvider auth, dynamic user, TripProvider tripProvider) async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);

    try {
      // 1. PUSH local offline trips to SQL Server DB if pending changes exist
      final localTrips = tripProvider.trips;
      if (localTrips.isNotEmpty && tripProvider.hasPendingSync) {
        final ok = await auth.apiService.syncTrips(
          userId: user.id,
          trips: localTrips,
          token: user.token,
        );
        if (ok) {
          tripProvider.clearPendingSync();
        }
      }

      // 2. FETCH updated remote trips from SQL Server DB
      final remoteTrips = await auth.apiService.getTrips(
        userId: user.id,
        phone: user.phone,
        token: user.token,
      );
      if (mounted && remoteTrips.isNotEmpty) {
        tripProvider.updateFromRemote(remoteTrips);
      }

      // 3. FETCH live notification count
      final notifs = await auth.apiService.getNotifications(
        user.id,
        token: user.token,
      );
      if (mounted) {
        final unread = notifs.where((n) => !n.isRead).length;
        if (unread != _unreadNotifs) {
          setState(() => _unreadNotifs = unread);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout_rounded, color: Colors.red.shade600, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Log Out?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Your data is safely saved and will be available when you sign in again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF374151))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        context.read<TripProvider>().clearTrips();
                        context.read<AuthProvider>().logout();
                      },
                      child: const Text('Log Out'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showApiStatusDialog(BuildContext context) {
    final api = context.read<AuthProvider>().apiService;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              _isApiConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: _isApiConnected ? Colors.green : Colors.amber.shade700,
            ),
            const SizedBox(width: 10),
            Text(
              _isApiConnected ? 'SQL DB Live' : 'Phone Storage Mode',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          _isApiConnected
              ? 'Connected live to ASP.NET Core Web API at ${api.baseUrl}.\nAll trips, expenses, and settlements are synchronized with your SQL Server database (SPLIT_BILL_DB).'
              : 'Your ASP.NET Core Web API is currently OFF or unreachable.\nData is saved locally on your phone. Whenever you start your API project on PC, the app syncs everything with SQL Server.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final username = auth.currentUser?.username ?? 'User';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _checkConnectionAndSync(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Premium SliverAppBar ─────────────────────────────────
            SliverAppBar(
              backgroundColor: const Color(0xFF1E1B4B),
              surfaceTintColor: Colors.transparent,
              expandedHeight: 200,
              floating: false,
              pinned: true,
              stretch: true,
              actions: [
                GestureDetector(
                  onTap: () => _showApiStatusDialog(context),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isSyncing
                          ? Colors.blue.withValues(alpha: 0.3)
                          : (_isApiConnected ? Colors.green.withValues(alpha: 0.25) : Colors.amber.withValues(alpha: 0.25)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isSyncing ? Colors.lightBlueAccent : (_isApiConnected ? Colors.greenAccent : Colors.amberAccent),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSyncing)
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              color: Colors.lightBlueAccent,
                              strokeWidth: 1.5,
                            ),
                          )
                        else
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isApiConnected ? Colors.greenAccent : Colors.amberAccent,
                            ),
                          ),
                        const SizedBox(width: 6),
                        Text(
                          _isSyncing
                              ? 'Syncing DB...'
                              : (_isApiConnected ? 'SQL DB Live' : 'Phone Storage'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 20),
                      ),
                      if (_unreadNotifs > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Center(
                              child: Text(
                                '$_unreadNotifs',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: 'Notifications',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                    _checkConnectionAndSync();
                  },
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.people_alt_rounded, color: Colors.white, size: 20),
                  ),
                  tooltip: 'Trip Friends',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_circle_outlined, color: Colors.white, size: 20),
                  ),
                  tooltip: 'My Profile & Diet',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                  ),
                  tooltip: 'Log Out',
                  onPressed: () => _confirmLogout(context),
                ),
                const SizedBox(width: 8),
              ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EquiTrip',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Hello, $username 👋',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF312E81),
                      Color(0xFF4F46E5),
                      Color(0xFF7C3AED),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 60,
                      bottom: 20,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    // App logo watermark
                    Positioned(
                      right: 20,
                      top: 28,
                      child: Opacity(
                        opacity: 0.25,
                        child: Image.asset(
                          'assets/icon/applogo.png',
                          width: 70,
                          height: 70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Stats summary bar ────────────────────────────────────
          SliverToBoxAdapter(
            child: Consumer<TripProvider>(
              builder: (context, provider, _) {
                final tripCount = provider.trips.length;
                final totalSpend = provider.trips.fold<double>(
                  0,
                  (sum, t) => sum + provider.getTotalExpense(t.id),
                );
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _statItem('Trips', '$tripCount', Icons.flight_takeoff_rounded),
                      ),
                      Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.25)),
                      Expanded(
                        child: _statItem('Total Spend', '₹${totalSpend.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Section header ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Your Trips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),

          // ── Trip list ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Consumer<TripProvider>(
              builder: (context, provider, child) {
                if (provider.trips.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: provider.trips.length,
                  itemBuilder: (context, index) {
                    final trip = provider.trips[index];
                    final total = provider.getTotalExpense(trip.id);
                    final memberCount = trip.allMembers.length;
                    final accent = _cardGradients[index % _cardGradients.length];

                    final authUser = context.watch<AuthProvider>().currentUser;
                    final isOwner = authUser != null && (trip.userId == authUser.id || trip.isOwner);

                    return Dismissible(
                      key: Key(trip.id),
                      direction: isOwner ? DismissDirection.endToStart : DismissDirection.none,
                      confirmDismiss: (_) async {
                        if (!isOwner) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Only the trip creator can delete this trip.')),
                          );
                          return false;
                        }

                        if (memberCount > 0) {
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              icon: const Icon(Icons.block_rounded, color: Colors.red, size: 44),
                              title: const Text('Cannot Delete Trip', style: TextStyle(fontWeight: FontWeight.w800)),
                              content: Text(
                                'This trip currently has $memberCount member(s). Admin can only delete a trip after removing all members first.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogCtx),
                                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          return false;
                        }

                        return true;
                      },
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red.shade400, Colors.red.shade600],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.delete_rounded, color: Colors.white, size: 26),
                            SizedBox(height: 4),
                            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      onDismissed: (_) {
                        provider.deleteTrip(trip.id);
                        if (authUser != null) {
                          context.read<AuthProvider>().apiService.deleteTrip(trip.id, token: authUser.token, userId: authUser.id);
                        }
                      },
                      child: _TripCard(
                        trip: trip,
                        total: total,
                        memberCount: memberCount,
                        accent: accent,
                        onEdit: () => _showTripDialog(context, tripToEdit: trip),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip.id)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showTripDialog(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            'New Trip',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flight_takeoff_rounded, size: 48, color: Color(0xFF4F46E5)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No trips yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "New Trip" below to start tracking your group expenses',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _showTripDialog(BuildContext context, {Trip? tripToEdit}) {
    final isEditing = tripToEdit != null;
    final nameController = TextEditingController(text: isEditing ? tripToEdit.name : '');
    final descController = TextEditingController(text: isEditing ? (tripToEdit.description ?? '') : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEditing ? 'Edit Trip' : 'Create New Trip',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Trip Name',
                  hintText: 'e.g., Goa Trip 2026',
                  prefixIcon: Icon(Icons.flight_rounded, size: 20),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'e.g., Weekend getaway',
                  prefixIcon: Icon(Icons.notes_rounded, size: 20),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        if (isEditing) {
                          context.read<TripProvider>().editTrip(
                                tripToEdit.id,
                                name,
                                newDescription: descController.text.trim(),
                              );
                        } else {
                          context.read<TripProvider>().addTrip(
                                name,
                                description: descController.text.trim(),
                              );
                        }
                        Navigator.pop(context);
                      }
                    },
                    child: Center(
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Trip',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final double total;
  final int memberCount;
  final Color accent;
  final VoidCallback onEdit;
  final VoidCallback onTap;

  const _TripCard({
    required this.trip,
    required this.total,
    required this.memberCount,
    required this.accent,
    required this.onEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Colored avatar
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    trip.name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Text info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _chip(Icons.people_rounded, '$memberCount people', Colors.blue),
                        const SizedBox(width: 6),
                        _chip(Icons.receipt_rounded, '${trip.expenses.length} expenses', Colors.purple),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₹${total.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_rounded, size: 18, color: Colors.grey.shade400),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}