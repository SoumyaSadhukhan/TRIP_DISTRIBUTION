// lib/screens/add_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/expense.dart';
import '../models/trip.dart';
import '../providers/trip_provider.dart';
import '../services/calculation_service.dart';

class AddExpenseScreen extends StatefulWidget {
  final String tripId;

  const AddExpenseScreen({super.key, required this.tripId});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _descController = TextEditingController();
  final _amountController = TextEditingController();
  final _uuid = const Uuid();

  ExpenseCategory _selectedCategory = ExpenseCategory.mixed;
  String? _selectedPayerId;
  List<String> _selectedParticipants = [];

  @override
  Widget build(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, child) {
        final trip = provider.getTrip(widget.tripId);
        if (trip == null) return const Scaffold(body: Center(child: Text('Trip not found')));

        final allMembers = trip.allMembers;
        final eligibleParticipants = CalculationService.getEligibleParticipants(_selectedCategory, allMembers);

        // Auto-select eligible participants when category changes
        if (!eligibleParticipants.toSet().containsAll(_selectedParticipants)) {
          _selectedParticipants = List.from(eligibleParticipants);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Add Expense'),
            actions: [
              TextButton(
                onPressed: _selectedPayerId != null && _descController.text.isNotEmpty && _amountController.text.isNotEmpty
                    ? () => _saveExpense(trip)
                    : null,
                child: const Text('Save', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g., Dinner at Beach Shack',
                    prefixIcon: Icon(Icons.edit),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    hintText: '0.00',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 24),
                Text(
                  'Category',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExpenseCategory.values.map((category) {
                    final isSelected = _selectedCategory == category;
                    return ChoiceChip(
                      avatar: Icon(category.icon, size: 18, color: isSelected ? Colors.white : category.color),
                      label: Text(category.label),
                      selected: isSelected,
                      selectedColor: category.color,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : null,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                      onSelected: (_) => setState(() => _selectedCategory = category),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          CalculationService.getSplitLogicDescription(_selectedCategory),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Paid By',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...allMembers.map((member) => RadioListTile<String>(
                      title: Text(member.name),
                      secondary: CircleAvatar(
                        backgroundColor: member.dietType.color.withOpacity(0.2),
                        child: Text(member.name[0].toUpperCase()),
                      ),
                      value: member.id,
                      groupValue: _selectedPayerId,
                      activeColor: Theme.of(context).colorScheme.primary,
                      onChanged: (value) => setState(() => _selectedPayerId = value),
                    )),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Split Among',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedParticipants = List.from(eligibleParticipants)),
                      child: const Text('Select All Eligible'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_selectedParticipants.length} of ${eligibleParticipants.length} eligible selected',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...eligibleParticipants.map((id) {
                  final member = allMembers.firstWhere((m) => m.id == id);
                  final isSelected = _selectedParticipants.contains(id);
                  return CheckboxListTile(
                    title: Text(member.name),
                    secondary: CircleAvatar(
                      backgroundColor: member.dietType.color.withOpacity(0.2),
                      child: Text(member.name[0].toUpperCase()),
                    ),
                    value: isSelected,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedParticipants.add(id);
                        } else {
                          _selectedParticipants.remove(id);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  void _saveExpense(Trip trip) {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one participant')),
      );
      return;
    }

    final expense = Expense(
      id: _uuid.v4(),
      description: _descController.text.trim(),
      amount: amount,
      category: _selectedCategory,
      paidById: _selectedPayerId!,
      date: DateTime.now(),
      splitAmongIds: List.from(_selectedParticipants),
    );

    context.read<TripProvider>().addExpense(trip.id, expense);
    Navigator.pop(context);
  }
}