// lib/screens/friends_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/friend.dart';
import '../providers/auth_provider.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<FriendModel> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  static const Color _primaryIndigo = Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final friends = await auth.apiService.getFriends(user.id, token: user.token);
    final requests = await auth.apiService.getFriendRequests(user.id, token: user.token);
    if (mounted) {
      setState(() {
        _friends = friends;
        _requests = requests;
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptRequest(String connectionId) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final res = await auth.apiService.acceptFriendRequest(
      connectionId: connectionId,
      userId: user.id,
      token: user.token,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Friend request accepted!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      _loadData();
    }
  }

  Future<void> _declineRequest(String connectionId) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    await auth.apiService.declineFriendRequest(
      connectionId: connectionId,
      token: user.token,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request declined.')),
      );
      _loadData();
    }
  }

  void _showAddFriendDialog() {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    int selectedDiet = 0;
    bool searching = false;
    String searchStatus = '';
    String? matchedUserId;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primaryIndigo.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_add_alt_1_rounded, color: _primaryIndigo),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Add Trip Friend',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'e.g. 9876543210',
                      prefixIcon: const Icon(Icons.phone_android_rounded),
                      suffixIcon: searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search_rounded),
                              tooltip: 'Check if registered',
                              onPressed: () async {
                                final phone = phoneCtrl.text.trim();
                                if (phone.length < 6) return;

                                setDialogState(() {
                                  searching = true;
                                  searchStatus = 'Checking user database...';
                                });

                                final auth = context.read<AuthProvider>();
                                final res = await auth.apiService.searchUsers(phone, token: auth.currentUser?.token);

                                setDialogState(() {
                                  searching = false;
                                  if (res.isNotEmpty) {
                                    final matched = res.first;
                                    nameCtrl.text = matched['fullName'] ?? '';
                                    selectedDiet = matched['dietType'] ?? 0;
                                    matchedUserId = matched['userId'];
                                    final dietNames = ['Vegetarian', 'Non-Vegetarian', 'Non-Veg + Alcohol'];
                                    searchStatus = '✓ Registered User Found: ${matched['fullName']} (${dietNames[selectedDiet]})';
                                  } else {
                                    searchStatus = 'ℹ Unregistered phone. Will add to friend contacts directly.';
                                  }
                                });
                              },
                            ),
                    ),
                  ),
                  if (searchStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      searchStatus,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: searchStatus.startsWith('✓') ? Colors.green.shade700 : Colors.blue.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Friend Name',
                      hintText: 'e.g. Alex',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Dietary Preference', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Veg', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 1, label: Text('Non-Veg', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 2, label: Text('+Alcohol', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {selectedDiet},
                    onSelectionChanged: (set) => setDialogState(() => selectedDiet = set.first),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final phone = phoneCtrl.text.trim();
                            final name = nameCtrl.text.trim();
                            if (phone.isEmpty || name.isEmpty) return;

                            final auth = context.read<AuthProvider>();
                            final user = auth.currentUser;
                            if (user == null) return;

                            final res = await auth.apiService.addFriend(
                              userId: user.id,
                              friendPhone: phone,
                              friendName: name,
                              friendUserId: matchedUserId,
                              dietType: selectedDiet,
                              token: user.token,
                            );

                            if (mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['message'] ?? 'Friend request sent!'),
                                  backgroundColor: const Color(0xFF4F46E5),
                                ),
                              );
                              _loadData();
                            }
                          },
                          child: const Text('Send Request'),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Friends'),
        backgroundColor: const Color(0xFF1E1B4B),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'My Friends (${_friends.length})'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Requests'),
                  if (_requests.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_requests.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFriendDialog,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Friend'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // ── TAB 1: Connected Friends List ────────────────────
                _friends.isEmpty
                    ? _buildEmptyState('No Connected Friends Yet', 'Add friends by phone number. Once they accept your request, they will appear here.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _friends.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final friend = _friends[index];
                          final dietColor = friend.dietEnum.color;

                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _primaryIndigo.withValues(alpha: 0.12),
                                child: Text(
                                  friend.name.isNotEmpty ? friend.name[0].toUpperCase() : 'F',
                                  style: const TextStyle(color: _primaryIndigo, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      friend.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: dietColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      friend.dietName,
                                      style: TextStyle(color: dietColor, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text('📱 ${friend.phone}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: Colors.grey.shade400, size: 20),
                                onPressed: () async {
                                  final auth = context.read<AuthProvider>();
                                  await auth.apiService.deleteFriend(friend.id, token: auth.currentUser?.token);
                                  _loadData();
                                },
                              ),
                            ),
                          );
                        },
                      ),

                // ── TAB 2: Pending Friend Requests ───────────────────
                _requests.isEmpty
                    ? _buildEmptyState('No Pending Requests', 'Incoming trip friend requests sent to your phone number will show here.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final req = _requests[index];
                          final connectionId = req['id'];
                          final requesterName = req['requesterName'] ?? 'A member';
                          final requesterPhone = req['requesterPhone'] ?? '';

                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                                    child: Text(
                                      requesterName.isNotEmpty ? requesterName[0].toUpperCase() : 'R',
                                      style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        const SizedBox(height: 2),
                                        Text('📱 $requesterPhone', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444)),
                                        tooltip: 'Decline',
                                        onPressed: () => _declineRequest(connectionId),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 28),
                                        tooltip: 'Accept',
                                        onPressed: () => _acceptRequest(connectionId),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryIndigo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group_add_rounded, color: _primaryIndigo, size: 48),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _showAddFriendDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add Friend'),
            ),
          ],
        ),
      ),
    );
  }
}

