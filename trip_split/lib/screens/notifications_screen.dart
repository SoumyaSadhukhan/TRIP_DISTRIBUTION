// lib/screens/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/notification.dart';
import '../models/settlement_proposal.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../widgets/settlement_popup_dialog.dart';
import 'friends_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;

  static const Color _primaryIndigo = Color(0xFF4F46E5);
  static const Color _emerald = Color(0xFF059669);

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final notifs = await auth.apiService.getNotifications(userId: user.id, token: user.token);

    if (mounted) {
      setState(() {
        _notifications = notifs;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;
    await auth.apiService.markNotificationsRead(userId: user.id, token: user.token);
    _fetchNotifications();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read.')),
      );
    }
  }

  void _showSendNotificationDialog() {
    final toUserIdController = TextEditingController();
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Alert Notification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: toUserIdController,
              decoration: const InputDecoration(labelText: 'Recipient User ID', hintText: 'Enter recipient user ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(labelText: 'Message', hintText: 'e.g. Please review the trip settlement'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final user = auth.currentUser;
              if (user != null && toUserIdController.text.isNotEmpty && messageController.text.isNotEmpty) {
                await auth.apiService.sendNotification(
                  toUserId: toUserIdController.text.trim(),
                  message: messageController.text.trim(),
                  token: user.token,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notification sent successfully!')),
                  );
                }
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettlementDetails(NotificationModel item) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    // Fetch pending settlements to find proposal details
    final pending = await auth.apiService.getPendingSettlements(
      userId: user.id,
      phone: user.phone,
      token: user.token,
    );

    SettlementProposal? proposal;
    if (item.settlementId != null && item.settlementId!.isNotEmpty) {
      try {
        proposal = pending.firstWhere((p) => p.settlementId == item.settlementId);
      } catch (_) {
        proposal = null;
      }
    }

    if (proposal == null && item.tripId != null) {
      try {
        proposal = pending.firstWhere((p) => p.tripId == item.tripId);
      } catch (_) {
        proposal = null;
      }
    }

    proposal ??= SettlementProposal(
      settlementId: item.settlementId ?? '',
      tripId: item.tripId ?? '',
      tripName: item.tripName ?? 'Trip',
      fromPersonId: '',
      fromPersonName: 'Member',
      toPersonId: '',
      toPersonName: user.fullName,
      amount: item.amount,
      status: 'PENDING',
      settledAt: item.createdAt,
      isPayer: item.title.toLowerCase().contains('request') || item.message.toLowerCase().contains('request'),
      isPayee: !item.title.toLowerCase().contains('request'),
    );

    if (mounted) {
      SettlementPopupDialog.show(
        context,
        proposal: proposal,
        onActionComplete: () {
          _fetchNotifications();
          final tripProvider = context.read<TripProvider>();
          auth.apiService.getTrips(userId: user.id, phone: user.phone, token: user.token).then((trips) {
            if (trips.isNotEmpty) tripProvider.updateFromRemote(trips);
          });
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications & Real-time Alerts'),
        backgroundColor: const Color(0xFF1E1B4B),
        actions: [
          IconButton(
            tooltip: 'Send alert notification',
            icon: const Icon(Icons.add_alert_rounded),
            onPressed: _showSendNotificationDialog,
          ),
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: _markAllRead,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchNotifications,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
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
                          child: const Icon(Icons.notifications_none_rounded, color: _primaryIndigo, size: 48),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'All Caught Up!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You will receive instant alerts here when members add expenses or send payment request statements.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _notifications[index];
                    final dateStr = DateFormat('MMM d, h:mm a').format(item.createdAt);
                    final isSettlement = item.type.contains('SETTLEMENT');
                    final isProposal = item.type == 'SETTLEMENT_PROPOSAL';
                    final isFriendRequest = item.type == 'FRIEND_REQUEST';
                    final isTripInvite = item.type == 'TRIP_INVITE' || item.type == 'COLLAB_INVITE';
                    final statementRef = (item.settlementId != null && item.settlementId!.isNotEmpty)
                        ? (item.settlementId!.length >= 8 ? 'ST-${item.settlementId!.substring(0, 8).toUpperCase()}' : 'ST-${item.settlementId!.toUpperCase()}')
                        : null;

                    Color iconBgColor = _primaryIndigo.withValues(alpha: 0.1);
                    Color iconColor = _primaryIndigo;
                    IconData iconData = Icons.notifications_active_rounded;

                    if (isSettlement) {
                      iconBgColor = _emerald.withValues(alpha: 0.12);
                      iconColor = _emerald;
                      iconData = Icons.receipt_long_rounded;
                    } else if (isFriendRequest) {
                      iconBgColor = const Color(0xFF4F46E5).withValues(alpha: 0.12);
                      iconColor = const Color(0xFF4F46E5);
                      iconData = Icons.person_add_rounded;
                    } else if (isTripInvite) {
                      iconBgColor = const Color(0xFF7C3AED).withValues(alpha: 0.12);
                      iconColor = const Color(0xFF7C3AED);
                      iconData = Icons.flight_takeoff_rounded;
                    }

                    return Card(
                      elevation: (isSettlement || isTripInvite) ? 3 : 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: isSettlement
                              ? _emerald.withValues(alpha: 0.4)
                              : (isTripInvite
                                  ? const Color(0xFF7C3AED).withValues(alpha: 0.4)
                                  : (isFriendRequest ? const Color(0xFF4F46E5).withValues(alpha: 0.3) : Colors.grey.shade200)),
                          width: (isSettlement || isTripInvite) ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: iconBgColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    iconData,
                                    color: iconColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                          ),
                                          Text(
                                            dateStr,
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.message,
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.3),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          if (item.tripName != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '🌴 ${item.tripName}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          if (statementRef != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _primaryIndigo.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '📄 $statementRef',
                                                style: const TextStyle(fontSize: 11, color: _primaryIndigo, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          if (isTripInvite)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                '✈ Trip Invite',
                                                style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          if (isFriendRequest)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                '👥 Friend Request',
                                                style: TextStyle(fontSize: 11, color: Color(0xFF4F46E5), fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          if (item.amount > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _emerald.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '₹${item.amount.toStringAsFixed(2)}',
                                                style: const TextStyle(fontSize: 11, color: _emerald, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (isProposal) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _emerald,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _openSettlementDetails(item),
                                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                                    label: const Text(
                                      'View Statement & Pay / Edit',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (isFriendRequest) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF4F46E5),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const FriendsScreen(initialTab: 1),
                                        ),
                                      ).then((_) => _fetchNotifications());
                                    },
                                    icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                                    label: const Text(
                                      'View in Trip Friends',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (isTripInvite && item.tripId != null) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () async {
                                      final auth = context.read<AuthProvider>();
                                      final user = auth.currentUser;
                                      if (user == null || item.tripId == null) return;
                                      await auth.apiService.declineTripInvite(tripId: item.tripId!, token: user.token);
                                      await auth.apiService.markNotificationsRead(notificationId: item.id, token: user.token);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Trip invitation declined.')),
                                        );
                                      }
                                      _fetchNotifications();
                                    },
                                    child: const Text('Decline', style: TextStyle(fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () async {
                                      final auth = context.read<AuthProvider>();
                                      final user = auth.currentUser;
                                      if (user == null || item.tripId == null) return;
                                      final res = await auth.apiService.acceptTripInvite(tripId: item.tripId!, token: user.token);
                                      if (!mounted) return;
                                      if (res['success'] == true) {
                                        await auth.apiService.markNotificationsRead(notificationId: item.id, token: user.token);
                                        if (!mounted) return;
                                        final tripProvider = context.read<TripProvider>();
                                        final trips = await auth.apiService.getTrips(userId: user.id, phone: user.phone, token: user.token);
                                        if (trips.isNotEmpty) tripProvider.updateFromRemote(trips);
                                        _fetchNotifications();
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Joined "${item.tripName ?? 'Trip'}" successfully!'),
                                            backgroundColor: const Color(0xFF059669),
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(res['message'] ?? 'Failed to accept invitation.'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                    label: const Text(
                                      'Accept to Join Trip',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
