// lib/widgets/settlement_popup_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/settlement_proposal.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';

class SettlementPopupDialog extends StatefulWidget {
  final SettlementProposal proposal;
  final VoidCallback onDismiss;
  final VoidCallback onActionComplete;

  const SettlementPopupDialog({
    super.key,
    required this.proposal,
    required this.onDismiss,
    required this.onActionComplete,
  });

  static Future<void> show(
    BuildContext context, {
    required SettlementProposal proposal,
    required VoidCallback onActionComplete,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SettlementPopupDialog(
        proposal: proposal,
        onDismiss: () => Navigator.of(ctx).pop(),
        onActionComplete: () {
          Navigator.of(ctx).pop();
          onActionComplete();
        },
      ),
    );
  }

  @override
  State<SettlementPopupDialog> createState() => _SettlementPopupDialogState();
}

class _SettlementPopupDialogState extends State<SettlementPopupDialog> {
  late SettlementProposal _currentProposal;
  bool _isProcessing = false;
  bool _isEditingAmount = false;
  String? _statusText;
  late final TextEditingController _amountController;

  static const Color _indigo = Color(0xFF4F46E5);
  static const Color _violet = Color(0xFF7C3AED);
  static const Color _emerald = Color(0xFF059669);
  static const Color _amber = Color(0xFFD97706);

  @override
  void initState() {
    super.initState();
    _currentProposal = widget.proposal;
    _amountController = TextEditingController(
      text: _currentProposal.amount > 0 ? _currentProposal.amount.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveAmount() async {
    final text = _amountController.text.trim();
    final newAmt = double.tryParse(text);
    if (newAmt == null || newAmt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount greater than 0')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Updating settlement statement amount...';
    });

    final ok = await auth.apiService.updateSettlementAmount(
      settlementId: _currentProposal.settlementId,
      amount: newAmt,
      userId: user.id,
      token: user.token,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        if (ok) {
          _currentProposal = _currentProposal.copyWith(amount: newAmt);
          _isEditingAmount = false;
        }
      });

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Statement amount updated to ₹${newAmt.toStringAsFixed(2)}! Both users are synced.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update amount. Please try again.')),
        );
      }
    }
  }

  Future<void> _handleAccept(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final tripProvider = context.read<TripProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Accepting settlement statement...';
    });

    final ok = await auth.apiService.acceptSettlementRequest(
      settlementId: _currentProposal.settlementId,
      userId: user.id,
      token: user.token,
    );

    if (mounted) {
      setState(() => _isProcessing = false);
      if (ok) {
        // Sync trips & update state
        final remoteTrips = await auth.apiService.getTrips(
          userId: user.id,
          phone: user.phone,
          token: user.token,
        );
        if (remoteTrips.isNotEmpty) {
          tripProvider.updateFromRemote(remoteTrips);
        }

        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF065F46),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Settlement of ₹${_currentProposal.amount.toStringAsFixed(2)} accepted & confirmed! 🎉',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        widget.onActionComplete();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to accept settlement. Please try again.')),
        );
      }
    }
  }

  Future<void> _handleDecline(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Declining settlement...';
    });

    final ok = await auth.apiService.declineSettlementRequest(
      settlementId: _currentProposal.settlementId,
      userId: user.id,
      token: user.token,
    );

    if (mounted) {
      setState(() => _isProcessing = false);
      if (ok) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('Settlement request declined.'),
          ),
        );
        widget.onActionComplete();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to decline settlement.')),
        );
      }
    }
  }

  void _showUpiPaymentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _emerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: _emerald, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send Settlement Payment',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Paying ₹${_currentProposal.amount.toStringAsFixed(2)} to ${_currentProposal.toPersonName}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildPaymentAppTile(
                    icon: Icons.payments_rounded,
                    color: const Color(0xFF00796B),
                    title: 'Google Pay / PhonePe / Paytm',
                    subtitle: 'Direct UPI App transfer',
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleAccept(context);
                    },
                  ),
                  const Divider(height: 16),
                  _buildPaymentAppTile(
                    icon: Icons.qr_code_scanner_rounded,
                    color: _indigo,
                    title: 'UPI Intent / QR Payment',
                    subtitle: 'Instant settlement verification',
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleAccept(context);
                    },
                  ),
                  const Divider(height: 16),
                  _buildPaymentAppTile(
                    icon: Icons.check_circle_outline_rounded,
                    color: _violet,
                    title: 'Direct Cash / Bank Transfer',
                    subtitle: 'Confirm you have paid outside app',
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleAccept(context);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentAppTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final proposal = _currentProposal;
    final dateFormatted = DateFormat('MMM d, y • h:mm a').format(proposal.settledAt);
    final isPayer = proposal.isPayer;
    final statementRef = proposal.settlementId.length >= 8
        ? 'ST-${proposal.settlementId.substring(0, 8).toUpperCase()}'
        : 'ST-${proposal.settlementId.toUpperCase()}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 20,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header Gradient Banner (Statement style) ──
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1B4B), _indigo, _violet],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.receipt_long_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                statementRef,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            proposal.status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isPayer ? 'Payment Request Statement' : 'Settlement Statement',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.beach_access_rounded, size: 14, color: Colors.amberAccent),
                          const SizedBox(width: 6),
                          Text(
                            proposal.tripName,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Statement Card Body ──
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Transfer Member Cards
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Debtor (Payer)
                              Expanded(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.red.shade100,
                                      child: Icon(Icons.person_rounded, color: Colors.red.shade700, size: 20),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      proposal.fromPersonName,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isPayer ? FontWeight.w900 : FontWeight.w700,
                                        fontSize: 13,
                                        color: isPayer ? _indigo : const Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      isPayer ? '(You • Payer)' : '(Payer)',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),

                              // Direction Indicator
                              Expanded(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: _indigo.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.arrow_forward_rounded, size: 18, color: _indigo),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'pays to',
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),

                              // Creditor (Receiver)
                              Expanded(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.green.shade100,
                                      child: Icon(Icons.person_rounded, color: Colors.green.shade700, size: 20),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      proposal.toPersonName,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: !isPayer ? FontWeight.w900 : FontWeight.w700,
                                        fontSize: 13,
                                        color: !isPayer ? _emerald : const Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      !isPayer ? '(You • Receiver)' : '(Receiver)',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Amount & Live Editor Section ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _indigo.withValues(alpha: 0.05),
                            _violet.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _indigo.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Settlement Amount',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Color(0xFF374151),
                                ),
                              ),
                              if (!_isEditingAmount && !_isProcessing)
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setState(() {
                                      _isEditingAmount = true;
                                      _amountController.text = proposal.amount.toStringAsFixed(2);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _indigo.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_rounded, size: 13, color: _indigo),
                                        SizedBox(width: 4),
                                        Text(
                                          'Edit Amount',
                                          style: TextStyle(
                                            color: _indigo,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (!_isEditingAmount) ...[
                            Text(
                              '₹${proposal.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E1B4B),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Statement generated on $dateFormatted',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ] else ...[
                            // Edit Mode Input
                            const SizedBox(height: 4),
                            TextField(
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              autofocus: true,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _indigo),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.currency_rupee_rounded, color: _indigo),
                                labelText: 'New Settlement Amount',
                                hintText: 'Enter updated amount',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: _indigo, width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => setState(() => _isEditingAmount = false),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _indigo,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _handleSaveAmount,
                                  icon: const Icon(Icons.save_rounded, size: 16),
                                  label: const Text('Save & Sync', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Statement Memo Note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPayer
                                  ? '${proposal.toPersonName} sent this settlement statement. You can pay via UPI, record payment, or edit the amount.'
                                  : '${proposal.fromPersonName} sent this settlement statement of ₹${proposal.amount.toStringAsFixed(2)}. Accept to update balances.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (_isProcessing) ...[
                      Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 10),
                            Text(_statusText ?? 'Processing...', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                      ),
                    ] else ...[
                      // ── Action Buttons ──
                      if (isPayer) ...[
                        // Pay via UPI Button
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [_emerald, Color(0xFF047857)]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _emerald.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _showUpiPaymentSheet(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Pay Statement (₹${proposal.amount.toStringAsFixed(2)})',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Mark as Paid / Accept
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: _indigo.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _handleAccept(context),
                          child: const Text('I Have Already Paid / Accept', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ] else ...[
                        // Receiver Accept Button
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [_indigo, _violet]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _indigo.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _handleAccept(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Accept Statement (₹${proposal.amount.toStringAsFixed(2)})',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => _handleDecline(context),
                              style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                              child: const Text('Decline Statement'),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: widget.onDismiss,
                              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                              child: const Text('Remind Later'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
