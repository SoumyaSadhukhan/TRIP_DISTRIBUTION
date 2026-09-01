// lib/screens/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/notification.dart';
import '../models/settlement_proposal.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../widgets/settlement_popup_dialog.dart';

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
  static const Color _amber = Color(0xFFD97706);

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
    final notifs = await auth.apiService.getNotifications(user.id, token: user.token);

    if (mounted) {
      setState(() {
        _notifications = notifs;
        _isLoading = false;
      });
      // Mark as read
      await auth.apiService.markNotificationsRead(userId: user.id, token: user.token);
    }
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
                    final statementRef = (item.settlementId != null && item.settlementId!.isNotEmpty)
                        ? (item.settlementId!.length >= 8 ? 'ST-${item.settlementId!.substring(0, 8).toUpperCase()}' : 'ST-${item.settlementId!.toUpperCase()}')
                        : null;

                    return Card(
                      elevation: isSettlement ? 3 : 0.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: isSettlement ? _emerald.withValues(alpha: 0.4) : Colors.grey.shade200,
                          width: isSettlement ? 1.5 : 1,
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
                                    color: isSettlement
                                        ? _emerald.withValues(alpha: 0.12)
                                        : _primaryIndigo.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSettlement
                                        ? Icons.receipt_long_rounded
                                        : Icons.notifications_active_rounded,
                                    color: isSettlement ? _emerald : _primaryIndigo,
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
