// lib/screens/settlement_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../services/calculation_service.dart';

class SettlementScreen extends StatelessWidget {
  final String tripId;

  const SettlementScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, child) {
        final settlements = provider.getSettlements(tripId);
        final balances = provider.getBalances(tripId);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Settlements'),
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
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Summary',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            ...balances.map((b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(b.person.name, style: const TextStyle(fontSize: 16)),
                                      Text(
                                        '${b.net >= 0 ? '+' : ''}₹${b.net.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: b.net >= 0 ? Colors.green : Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Text(
                          'Transactions',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                                        Text(
                                          settlement.fromName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'pays',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          settlement.toName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '₹${settlement.amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
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
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
        );
      },
    );
  }
}