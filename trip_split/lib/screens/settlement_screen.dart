// lib/screens/settlement_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../services/pdf_service.dart';

class SettlementScreen extends StatelessWidget {
  final String tripId;

  const SettlementScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, child) {
        final trip = provider.getTrip(tripId);
        if (trip == null) return const Scaffold(body: Center(child: Text('Trip not found')));

        final settlements = provider.getSettlements(tripId);
        final balances = provider.getBalances(tripId);
        final auth = context.read<AuthProvider>();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settlements & Balances'),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Download PDF Report',
                onPressed: () {
                  PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser);
                },
              ),
            ],
          ),
          body: settlements.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'All settled up!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Everyone has paid their fair share',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Export Summary PDF'),
                        onPressed: () {
                          PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser);
                        },
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Card(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Member Balances',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    Chip(
                                      avatar: const Icon(Icons.people, size: 16),
                                      label: Text('${balances.length} Members'),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                const SizedBox(height: 8),
                                ...balances.map((b) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 12,
                                                backgroundColor: b.net >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                                                child: Icon(
                                                  b.net >= 0 ? Icons.add : Icons.remove,
                                                  size: 14,
                                                  color: b.net >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(b.person.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                            ],
                                          ),
                                          Text(
                                            '${b.net >= 0 ? '+' : ''}₹${b.net.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: b.net >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Final Transactions',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${settlements.length} Transfers',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final settlement = settlements[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.call_made, color: Colors.red, size: 16),
                                            const SizedBox(width: 6),
                                            Text(
                                              settlement.fromName,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.only(left: 22, top: 2, bottom: 2),
                                          child: Text('pays to', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                        ),
                                        Row(
                                          children: [
                                            const Icon(Icons.call_received, color: Colors.green, size: 16),
                                            const SizedBox(width: 6),
                                            Text(
                                              settlement.toName,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Theme.of(context).colorScheme.primaryContainer,
                                          Theme.of(context).colorScheme.secondaryContainer,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      '₹${settlement.amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: settlements.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Download PDF Report'),
          ),
        );
      },
    );
  }
}