// lib/screens/trip_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trip_split/screens/add_expense_screen.dart';
import '../models/enums.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../models/trip.dart';
import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../services/calculation_service.dart';
import '../services/pdf_service.dart';
import 'settlement_screen.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, child) {
        final trip = provider.getTrip(widget.tripId);
        if (trip == null) return const Scaffold(body: Center(child: Text('Trip not found')));

        final auth = context.read<AuthProvider>();

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 140,
                  floating: true,
                  pinned: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf),
                      onPressed: () {
                        PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser);
                      },
                      tooltip: 'Download PDF Report',
                    ),
                    IconButton(
                      icon: const Icon(Icons.account_balance),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettlementScreen(tripId: widget.tripId),
                          ),
                        );
                      },
                      tooltip: 'View Settlements',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    title: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (trip.description != null)
                          Text(
                            trip.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Expenses',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₹${provider.getTotalExpense(widget.tripId).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.payments,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'Groups', icon: Icon(Icons.people)),
                        Tab(text: 'Expenses', icon: Icon(Icons.receipt)),
                        Tab(text: 'Balances', icon: Icon(Icons.pie_chart)),
                      ],
                    ),
                  ),
                  pinned: true,
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _GroupsTab(trip: trip),
                _ExpensesTab(trip: trip),
                _BalancesTab(trip: trip),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (_tabController.index == 0) {
                _showAddGroupDialog(context, trip);
              } else if (_tabController.index == 1) {
                _showAddExpenseDialog(context, trip);
              }
            },
            icon: const Icon(Icons.add),
            label: Text(_tabController.index == 0 ? 'Add Group' : 'Add Expense'),
          ),
        );
      },
    );
  }

  void _showAddGroupDialog(BuildContext context, Trip trip) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g., Veg Friends, Drinkers',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<TripProvider>().addGroup(trip.id, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context, Trip trip) {
    if (trip.allMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add people to groups first!')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(tripId: trip.id),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

class _GroupsTab extends StatelessWidget {
  final Trip trip;

  const _GroupsTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    if (trip.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_add, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create a group',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trip.groups.length,
      itemBuilder: (context, index) {
        final group = trip.groups[index];
        return _GroupCard(group: group, tripId: trip.id);
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Group group;
  final String tripId;

  const _GroupCard({required this.group, required this.tripId});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: Text('${group.members.length} members'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit Group Name',
              onPressed: () => _showEditGroupDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              tooltip: 'Delete Group',
              onPressed: () => _confirmDeleteGroup(context),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                ...group.members.map((member) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: member.dietType.color.withValues(alpha: 0.2),
                        child: Icon(
                          _getDietIcon(member.dietType),
                          color: member.dietType.color,
                          size: 18,
                        ),
                      ),
                      title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        member.dietType.label,
                        style: TextStyle(
                          color: member.dietType.color,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.indigo),
                            tooltip: 'Edit Member',
                            onPressed: () => _showPersonDialog(context, personToEdit: member),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            tooltip: 'Delete Member',
                            onPressed: () {
                              context.read<TripProvider>().deletePerson(tripId, group.id, member.id);
                            },
                          ),
                        ],
                      ),
                    )),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Colors.black12,
                    child: Icon(Icons.add, color: Colors.black54),
                  ),
                  title: const Text('Add Person'),
                  onTap: () => _showPersonDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditGroupDialog(BuildContext context) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Group Name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<TripProvider>().editGroup(tripId, group.id, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${group.name}"?'),
        content: const Text('This will delete the group and all its members.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<TripProvider>().deleteGroup(tripId, group.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _getDietIcon(DietType type) {
    switch (type) {
      case DietType.vegetarian:
        return Icons.eco;
      case DietType.nonVegetarian:
        return Icons.restaurant;
      case DietType.nonVegAlcoholic:
        return Icons.wine_bar;
    }
  }

  void _showPersonDialog(BuildContext context, {Person? personToEdit}) {
    final isEditing = personToEdit != null;
    final nameController = TextEditingController(text: isEditing ? personToEdit.name : '');
    DietType selectedDiet = isEditing ? personToEdit.dietType : DietType.nonVegetarian;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                    isEditing ? 'Edit ${personToEdit.name}' : 'Add Person to ${group.name}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Diet / Expense Preference',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  ...DietType.values.map((diet) => RadioListTile<DietType>(
                        title: Row(
                          children: [
                            Icon(_getDietIcon(diet), color: diet.color, size: 20),
                            const SizedBox(width: 12),
                            Text(diet.label),
                          ],
                        ),
                        value: diet,
                        groupValue: selectedDiet,
                        activeColor: diet.color,
                        onChanged: (value) => setState(() => selectedDiet = value!),
                      )),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        if (isEditing) {
                          context.read<TripProvider>().editPerson(
                                tripId,
                                group.id,
                                personToEdit.id,
                                name,
                                selectedDiet,
                              );
                        } else {
                          context.read<TripProvider>().addPerson(
                                tripId,
                                group.id,
                                name,
                                selectedDiet,
                              );
                        }
                        Navigator.pop(context);
                      }
                    },
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(isEditing ? 'Save Changes' : 'Add Person', style: const TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final Trip trip;

  const _ExpensesTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    if (trip.expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No expenses yet',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add an expense',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trip.expenses.length,
      itemBuilder: (context, index) {
        final expense = trip.expenses.reversed.toList()[index];
        final payer = trip.allMembers.firstWhere(
          (m) => m.id == expense.paidById,
          orElse: () => Person(id: '', name: 'Unknown', dietType: DietType.vegetarian),
        );

        return Dismissible(
          key: Key(expense.id),
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
          onDismissed: (_) => context.read<TripProvider>().deleteExpense(trip.id, expense.id),
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddExpenseScreen(
                      tripId: trip.id,
                      expenseToEdit: expense,
                    ),
                  ),
                );
              },
              leading: CircleAvatar(
                backgroundColor: expense.category.color.withValues(alpha: 0.2),
                child: Icon(expense.category.icon, color: expense.category.color),
              ),
              title: Text(
                expense.description,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Paid by ${payer.name}'),
                  const SizedBox(height: 2),
                  Text(
                    '${expense.splitAmongIds.length} people sharing',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${expense.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.indigo),
                    tooltip: 'Edit Expense',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddExpenseScreen(
                            tripId: trip.id,
                            expenseToEdit: expense,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BalancesTab extends StatelessWidget {
  final Trip trip;

  const _BalancesTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    final balances = CalculationService.calculateBalances(trip);

    if (balances.isEmpty) {
      return const Center(child: Text('No members added yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: balances.length,
      itemBuilder: (context, index) {
        final balance = balances[index];
        final isPositive = balance.net >= 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
              child: Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            title: Text(
              balance.person.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Paid: ₹${balance.paid.toStringAsFixed(2)}'),
                Text('Owed: ₹${balance.owed.toStringAsFixed(2)}'),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${isPositive ? '+' : ''}₹${balance.net.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}