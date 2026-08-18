// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import 'trip_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            floating: true,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'TripSplit',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.tertiary,
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer<TripProvider>(
              builder: (context, provider, child) {
                if (provider.trips.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(48.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.card_travel,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No trips yet',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a trip to start splitting expenses',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.trips.length,
                  itemBuilder: (context, index) {
                    final trip = provider.trips[index];
                    final total = provider.getTotalExpense(trip.id);
                    final memberCount = trip.allMembers.length;

                    return Dismissible(
                      key: Key(trip.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => provider.deleteTrip(trip.id),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Text(
                              trip.name[0].toUpperCase(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            trip.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('$memberCount people • ${trip.expenses.length} expenses'),
                              const SizedBox(height: 4),
                              Text(
                                'Total: ₹${total.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TripDetailScreen(tripId: trip.id),
                              ),
                            );
                          },
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTripDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Trip'),
      ),
    );
  }

  void _showCreateTripDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create New Trip',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Trip Name',
                  hintText: 'e.g., Goa Trip 2026',
                  prefixIcon: Icon(Icons.edit),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'e.g., Weekend getaway with college friends',
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    context.read<TripProvider>().addTrip(
                          nameController.text.trim(),
                          description: descController.text.trim(),
                        );
                    Navigator.pop(context);
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Create Trip', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}