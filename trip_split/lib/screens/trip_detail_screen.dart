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

class _TripDetailScreenState extends State<TripDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const Color _indigo = Color(0xFF4F46E5);
  static const Color _violet = Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
        if (trip == null) {
          return const Scaffold(body: Center(child: Text('Trip not found')));
        }
        final auth = context.read<AuthProvider>();

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FF),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 160,
                  floating: false,
                  pinned: true,
                  stretch: true,
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
                      onPressed: () => PdfService.downloadOrPrintPdf(trip: trip, currentUser: auth.currentUser),
                      tooltip: 'Download PDF',
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SettlementScreen(tripId: widget.tripId)),
                      ),
                      tooltip: 'Settlements',
                    ),
                    const SizedBox(width: 4),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 64, bottom: 16),
                    title: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        if (trip.description != null && trip.description!.isNotEmpty)
                          Text(
                            trip.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.75),
                              fontWeight: FontWeight.w400,
                            ),
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
                            right: -30,
                            top: -30,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Summary card
                SliverToBoxAdapter(
                  child: _SummaryCard(tripId: widget.tripId, provider: provider),
                ),

                // Tab bar
                SliverPersistentHeader(
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'Groups', icon: Icon(Icons.people_rounded, size: 18)),
                        Tab(text: 'Expenses', icon: Icon(Icons.receipt_rounded, size: 18)),
                        Tab(text: 'Balances', icon: Icon(Icons.pie_chart_rounded, size: 18)),
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
          floatingActionButton: _tabController.index != 2
              ? Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_indigo, _violet],
                    ),
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
                    onPressed: () {
                      if (_tabController.index == 0) {
                        _showAddGroupDialog(context, trip);
                      } else {
                        _showAddExpenseDialog(context, trip);
                      }
                    },
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text(
                      _tabController.index == 0 ? 'Add Group' : 'Add Expense',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  void _showAddGroupDialog(BuildContext context, Trip trip) {
    final controller = TextEditingController();
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
              const Text('Add Group',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'e.g., Veg Friends, Drinkers',
                  prefixIcon: Icon(Icons.group_rounded, size: 20),
                ),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
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
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          context.read<TripProvider>().addGroup(trip.id, controller.text.trim());
                          Navigator.pop(context);
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Add Group'),
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

  void _showAddExpenseDialog(BuildContext context, Trip trip) {
    if (trip.allMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Add people to groups first!'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1F2937),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddExpenseScreen(tripId: trip.id)),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String tripId;
  final TripProvider provider;

  const _SummaryCard({required this.tripId, required this.provider});

  @override
  Widget build(BuildContext context) {
    final trip = provider.getTrip(tripId);
    final total = provider.getTotalExpense(tripId);
    final memberCount = trip?.allMembers.length ?? 0;
    final expenseCount = trip?.expenses.length ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Expenses',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _badge(Icons.people_rounded, '$memberCount members'),
                    const SizedBox(width: 8),
                    _badge(Icons.receipt_rounded, '$expenseCount items'),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sliver Tab Bar Delegate ───────────────────────────────────────────────────

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
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

// ── Groups Tab ────────────────────────────────────────────────────────────────

class _GroupsTab extends StatelessWidget {
  final Trip trip;

  const _GroupsTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    if (trip.groups.isEmpty) {
      return _EmptyTabState(
        icon: Icons.group_add_rounded,
        title: 'No groups yet',
        subtitle: 'Tap + to create your first group',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: trip.groups.length,
      itemBuilder: (context, index) {
        final group = trip.groups[index];
        return _GroupCard(group: group, tripId: trip.id);
      },
    );
  }
}

// ── Group Card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final Group group;
  final String tripId;

  const _GroupCard({required this.group, required this.tripId});

  static const List<Color> _groupColors = [
    Color(0xFF4F46E5),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFF0891B2),
    Color(0xFFD97706),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _groupColors[group.name.hashCode.abs() % _groupColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                group.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          ),
          title: Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2937)),
          ),
          subtitle: Text(
            '${group.members.length} members',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionIconBtn(context, Icons.edit_rounded, 'Edit', Colors.indigo, () => _showEditGroupDialog(context)),
              _actionIconBtn(context, Icons.delete_outline_rounded, 'Delete', Colors.red, () => _confirmDeleteGroup(context)),
              const Icon(Icons.expand_more_rounded, color: Color(0xFFD1D5DB)),
            ],
          ),
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  ...group.members.map((member) => _MemberTile(
                    member: member,
                    tripId: tripId,
                    groupId: group.id,
                    onEdit: () => _showPersonDialog(context, personToEdit: member),
                  )),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _showPersonDialog(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.indigo.shade100, width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0xFFEEF2FF),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.person_add_rounded, size: 16, color: Color(0xFF4F46E5)),
                          SizedBox(width: 6),
                          Text(
                            'Add Person',
                            style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionIconBtn(BuildContext context, IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  void _showEditGroupDialog(BuildContext context) {
    final controller = TextEditingController(text: group.name);
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
              const Text('Edit Group', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Group Name'),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    context.read<TripProvider>().editGroup(tripId, group.id, controller.text.trim());
                    Navigator.pop(context);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_rounded, color: Color(0xFFDC2626), size: 28),
              ),
              const SizedBox(height: 16),
              Text('Delete "${group.name}"?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'This will delete the group and all its members.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        context.read<TripProvider>().deleteGroup(tripId, group.id);
                        Navigator.pop(context);
                      },
                      child: const Text('Delete'),
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

  IconData _getDietIcon(DietType type) {
    switch (type) {
      case DietType.vegetarian:
        return Icons.eco_rounded;
      case DietType.nonVegetarian:
        return Icons.restaurant_rounded;
      case DietType.nonVegAlcoholic:
        return Icons.wine_bar_rounded;
    }
  }

  void _showPersonDialog(BuildContext context, {Person? personToEdit}) {
    final isEditing = personToEdit != null;
    final nameController = TextEditingController(text: isEditing ? personToEdit.name : '');
    DietType selectedDiet = isEditing ? personToEdit.dietType : DietType.nonVegetarian;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                    isEditing ? 'Edit ${personToEdit.name}' : 'Add Person to ${group.name}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_rounded, size: 20),
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Diet / Expense Preference',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  ...DietType.values.map((diet) {
                    final isSelected = selectedDiet == diet;
                    return GestureDetector(
                      onTap: () => setState(() => selectedDiet = diet),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? diet.color.withValues(alpha: 0.08) : const Color(0xFFF9FAFB),
                          border: Border.all(
                            color: isSelected ? diet.color : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(_getDietIcon(diet), color: diet.color, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              diet.label,
                              style: TextStyle(
                                color: isSelected ? diet.color : const Color(0xFF374151),
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded, color: diet.color, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          final name = nameController.text.trim();
                          if (name.isNotEmpty) {
                            if (isEditing) {
                              context.read<TripProvider>().editPerson(tripId, group.id, personToEdit.id, name, selectedDiet);
                            } else {
                              context.read<TripProvider>().addPerson(tripId, group.id, name, selectedDiet);
                            }
                            Navigator.pop(context);
                          }
                        },
                        child: Center(
                          child: Text(
                            isEditing ? 'Save Changes' : 'Add Person',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
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
      },
    );
  }
}

// ── Member Tile ───────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final Person member;
  final String tripId;
  final String groupId;
  final VoidCallback onEdit;

  const _MemberTile({
    required this.member,
    required this.tripId,
    required this.groupId,
    required this.onEdit,
  });

  IconData _getDietIcon(DietType type) {
    switch (type) {
      case DietType.vegetarian:
        return Icons.eco_rounded;
      case DietType.nonVegetarian:
        return Icons.restaurant_rounded;
      case DietType.nonVegAlcoholic:
        return Icons.wine_bar_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: member.dietType.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_getDietIcon(member.dietType), color: member.dietType.color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  member.dietType.label,
                  style: TextStyle(color: member.dietType.color, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF4F46E5)),
            onPressed: onEdit,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
            onPressed: () => context.read<TripProvider>().deletePerson(tripId, groupId, member.id),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ── Expenses Tab ──────────────────────────────────────────────────────────────

class _ExpensesTab extends StatelessWidget {
  final Trip trip;

  const _ExpensesTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    if (trip.expenses.isEmpty) {
      return _EmptyTabState(
        icon: Icons.receipt_long_rounded,
        title: 'No expenses yet',
        subtitle: 'Tap + to add your first expense',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red.shade400, Colors.red.shade600]),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.delete_rounded, color: Colors.white, size: 24),
                SizedBox(height: 4),
                Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          onDismissed: (_) => context.read<TripProvider>().deleteExpense(trip.id, expense.id),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddExpenseScreen(tripId: trip.id, expenseToEdit: expense),
              ),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                    color: expense.category.color.withValues(alpha: 0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: expense.category.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(expense.category.icon, color: expense.category.color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.description,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2937)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Paid by ${payer.name}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${expense.splitAmongIds.length} people sharing',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${expense.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: expense.category.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            expense.category.label,
                            style: TextStyle(
                              color: expense.category.color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Balances Tab ──────────────────────────────────────────────────────────────

class _BalancesTab extends StatelessWidget {
  final Trip trip;

  const _BalancesTab({required this.trip});

  @override
  Widget build(BuildContext context) {
    final balances = CalculationService.calculateBalances(trip);

    if (balances.isEmpty) {
      return _EmptyTabState(
        icon: Icons.pie_chart_rounded,
        title: 'No data yet',
        subtitle: 'Add members and expenses to see balances',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: balances.length,
      itemBuilder: (context, index) {
        final balance = balances[index];
        final isPositive = balance.net >= 0;
        final color = isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      balance.person.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2937)),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _miniStat('Paid', '₹${balance.paid.toStringAsFixed(0)}', Colors.blue),
                        const SizedBox(width: 8),
                        _miniStat('Owed', '₹${balance.owed.toStringAsFixed(0)}', Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '${isPositive ? '+' : ''}₹${balance.net.abs().toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $val',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Empty Tab State ───────────────────────────────────────────────────────────

class _EmptyTabState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyTabState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)]),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: const Color(0xFF4F46E5)),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
        ],
      ),
    );
  }
}