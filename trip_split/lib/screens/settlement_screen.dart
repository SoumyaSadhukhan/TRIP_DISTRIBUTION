// lib/screens/settlement_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../services/calculation_service.dart';
import '../services/pdf_service.dart';

class SettlementScreen extends StatelessWidget {
  final String tripId;

  const SettlementScreen({super.key, required this.tripId});

  static const Color _indigo = Color(0xFF4F46E5);
  static const Color _violet = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, child) {
        final trip = provider.getTrip(tripId);
        if (trip == null) {
          return const Scaffold(body: Center(child: Text('Trip not found')));
        }

        final settlements = provider.getSettlements(tripId);
        final balances = provider.getBalances(tripId);
        final auth = context.read<AuthProvider>();

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FF),
          body: CustomScrollView(
            slivers: [
              // ── AppBar ─────────────────────────────────────────────
              SliverAppBar(
                backgroundColor: const Color(0xFF312E81),
                surfaceTintColor: Colors.transparent,
                pinned: true,
                expandedHeight: 120,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 16),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                    ),
                    tooltip: 'Download PDF',
                    onPressed: () => PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser),
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 64, bottom: 16),
                  title: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settlements',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white),
                      ),
                      Text(
                        'Who pays whom',
                        style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF312E81), _indigo, _violet],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -20,
                          top: -20,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (settlements.isEmpty)
                SliverFillRemaining(
                  child: _buildAllSettledState(context, auth, trip),
                )
              else ...[
                // ── Balance summary card ──────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade100),
                        boxShadow: [
                          BoxShadow(
                            color: _indigo.withValues(alpha: 0.07),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Member Balances',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.people_rounded, size: 14, color: _indigo),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${balances.length} Members',
                                        style: const TextStyle(
                                          color: _indigo,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: balances
                                  .map((b) => _BalanceRow(balance: b))
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── My Personal Share ─────────────────────────────────
                SliverToBoxAdapter(
                  child: _MyPersonalShareCard(
                    settlements: settlements,
                    balances: balances,
                    currentUser: auth.currentUser,
                    trip: trip,
                  ),
                ),

                // ── Transactions header ───────────────────────────────

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Transfers Needed',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                            letterSpacing: -0.3,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${settlements.length} transfers',
                            style: const TextStyle(
                              color: Color(0xFFD97706),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Transfer cards ────────────────────────────────────
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final s = settlements[index];
                      return _TransferCard(
                        fromName: s.fromName,
                        toName: s.toName,
                        amount: s.amount,
                        trip: trip,
                      );
                    },
                    childCount: settlements.length,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
          ),
          floatingActionButton: settlements.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_indigo, _violet]),
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: _indigo.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: () => PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white),
                    label: const Text(
                      'Export PDF',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildAllSettledState(BuildContext context, AuthProvider auth, dynamic trip) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD1FAE5), Color(0xFFA7F3D0)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, size: 52, color: Color(0xFF059669)),
          ),
          const SizedBox(height: 20),
          const Text(
            'All Settled Up! 🎉',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1F2937)),
          ),
          const SizedBox(height: 8),
          Text(
            'Everyone has paid their fair share',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
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
                onTap: () => PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Export Summary PDF',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                      ),
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

// ── Balance Row ───────────────────────────────────────────────────────────────

class _BalanceRow extends StatelessWidget {
  final dynamic balance;

  const _BalanceRow({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isPositive = balance.net >= 0;
    final color = isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final authUser = context.watch<AuthProvider>().currentUser;
    final isYou = authUser != null && (
      balance.person.userId == authUser.id ||
      (balance.person.phone != null && balance.person.phone!.isNotEmpty && balance.person.phone == authUser.phone) ||
      balance.person.name.trim().toLowerCase() == authUser.fullName.trim().toLowerCase()
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPositive ? Icons.add_rounded : Icons.remove_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isYou ? '${balance.person.name} (You)' : balance.person.name,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isYou ? const Color(0xFF4F46E5) : const Color(0xFF1F2937)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${isPositive ? '+' : ''}₹${balance.net.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transfer Card ─────────────────────────────────────────────────────────────

class _TransferCard extends StatelessWidget {
  final String fromName;
  final String toName;
  final double amount;
  final dynamic trip;

  const _TransferCard({
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.trip,
  });

  void _showRecordPaymentDialog(BuildContext context, AuthProvider auth) {
    final amountController = TextEditingController(text: amount.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Record Settlement Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('$fromName ➔ $toName', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final pAmount = double.tryParse(amountController.text.trim());
                  if (pAmount != null && pAmount > 0 && auth.currentUser != null) {
                    final members = trip.allMembers;
                    final fromPerson = members.firstWhere(
                      (m) => m.name.trim().toLowerCase() == fromName.trim().toLowerCase(),
                      orElse: () => null,
                    );
                    final toPerson = members.firstWhere(
                      (m) => m.name.trim().toLowerCase() == toName.trim().toLowerCase(),
                      orElse: () => null,
                    );
                    if (fromPerson != null && toPerson != null) {
                      final success = await auth.apiService.recordSettlementRequest(
                        tripId: trip.id,
                        fromPersonId: fromPerson.id,
                        toPersonId: toPerson.id,
                        amount: pAmount,
                        createdByUserId: auth.currentUser!.id,
                        token: auth.currentUser!.token,
                      );
                      if (context.mounted) Navigator.pop(context);
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Settlement payment request sent for approval!')),
                        );
                      }
                    }
                  }
                },
                child: const Text('Send Payment Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authUser = auth.currentUser;
    final isFromYou = authUser != null && fromName.trim().toLowerCase() == authUser.fullName.trim().toLowerCase();
    final isToYou = authUser != null && toName.trim().toLowerCase() == authUser.fullName.trim().toLowerCase();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.call_made_rounded, color: Colors.red.shade500, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isFromYou ? '$fromName (You)' : fromName,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isFromYou ? const Color(0xFF4F46E5) : const Color(0xFF1F2937)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
                      child: Row(
                        children: [
                          Container(width: 1, height: 20, color: Colors.grey.shade200),
                          const SizedBox(width: 12),
                          Text(
                            'pays to',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.call_received_rounded, color: Colors.green.shade600, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isToYou ? '$toName (You)' : toName,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isToYou ? const Color(0xFF4F46E5) : const Color(0xFF1F2937)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showRecordPaymentDialog(context, auth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.payment_rounded, size: 15, color: Color(0xFF4F46E5)),
                    SizedBox(width: 4),
                    Text(
                      'Record / Pay Amount',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── My Personal Share Card ────────────────────────────────────────────────────


class _MyPersonalShareCard extends StatelessWidget {
  final List<SettlementResult> settlements;
  final List<PersonBalance> balances;
  final UserModel? currentUser;
  final Trip trip;

  const _MyPersonalShareCard({
    required this.settlements,
    required this.balances,
    required this.currentUser,
    required this.trip,
  });

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) return const SizedBox.shrink();

    final phone = currentUser!.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final last10 = phone.length >= 10 ? phone.substring(phone.length - 10) : phone;

    // Find this user's person ID(s) in the trip
    final myPersonIds = <String>{};
    for (final group in trip.groups) {
      for (final member in group.members) {
        if (member.userId == currentUser!.id) {
          myPersonIds.add(member.id);
        } else if (member.phone != null && member.phone!.replaceAll(RegExp(r'[^0-9]'), '').endsWith(last10) && last10.isNotEmpty) {
          myPersonIds.add(member.id);
        } else if (member.name.toLowerCase() == currentUser!.fullName.toLowerCase()) {
          myPersonIds.add(member.id);
        }
      }
    }

    if (myPersonIds.isEmpty) {
      return const SizedBox.shrink();
    }

    // Find settlements I owe and settlements owed to me
    final iOwe = <SettlementResult>[];
    final owedToMe = <SettlementResult>[];

    for (final s in settlements) {
      if (myPersonIds.contains(s.fromId)) {
        iOwe.add(s);
      }
      if (myPersonIds.contains(s.toId)) {
        owedToMe.add(s);
      }
    }

    if (iOwe.isEmpty && owedToMe.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalIOwe = iOwe.fold<double>(0, (sum, s) => sum + s.amount);
    final totalOwedToMe = owedToMe.fold<double>(0, (sum, s) => sum + s.amount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_pin_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'My Personal Share',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Summary Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('You Owe', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalIOwe.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('You Get', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalOwedToMe.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Detail items
              if (iOwe.isNotEmpty) ...[
                ...iOwe.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_upward_rounded, color: Colors.orangeAccent, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Pay ${s.toName}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '₹${s.amount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                )),
              ],
              if (owedToMe.isNotEmpty) ...[
                ...owedToMe.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_downward_rounded, color: Colors.greenAccent, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Get from ${s.fromName}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '₹${s.amount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}