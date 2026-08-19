// lib/services/calculation_service.dart
import '../models/enums.dart';
import '../models/person.dart';
import '../models/trip.dart';


class SettlementResult {
  final String fromId;
  final String toId;
  final double amount;
  final String fromName;
  final String toName;

  SettlementResult({
    required this.fromId,
    required this.toId,
    required this.amount,
    required this.fromName,
    required this.toName,
  });
}

class PersonBalance {
  final Person person;
  double paid;
  double owed;
  double get net => paid - owed;

  PersonBalance(this.person, {this.paid = 0.0, this.owed = 0.0});
}

class CalculationService {
  static List<PersonBalance> calculateBalances(Trip trip) {
    final balances = <String, PersonBalance>{};
    
    // Initialize
    for (var person in trip.allMembers) {
      balances[person.id] = PersonBalance(person);
    }

    // Process each expense
    for (var expense in trip.expenses) {
      final splitAmount = expense.amount / expense.splitAmongIds.length;
      
      // Add to payer's paid amount
      if (balances.containsKey(expense.paidById)) {
        balances[expense.paidById]!.paid += expense.amount;
      }

      // Add to each participant's owed amount
      for (var participantId in expense.splitAmongIds) {
        if (balances.containsKey(participantId)) {
          balances[participantId]!.owed += splitAmount;
        }
      }
    }

    return balances.values.toList();
  }

  static List<SettlementResult> calculateSettlements(Trip trip) {
    final balances = calculateBalances(trip);
    final debtors = balances.where((b) => b.net < -0.01).toList()
      ..sort((a, b) => a.net.compareTo(b.net));
    final creditors = balances.where((b) => b.net > 0.01).toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    final settlements = <SettlementResult>[];

    int i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];
      
      final amount = [-debtor.net, creditor.net].reduce((a, b) => a < b ? a : b);
      
      if (amount > 0.01) {
        settlements.add(SettlementResult(
          fromId: debtor.person.id,
          toId: creditor.person.id,
          amount: double.parse(amount.toStringAsFixed(2)),
          fromName: debtor.person.name,
          toName: creditor.person.name,
        ));
      }

      debtor.paid += amount;
      creditor.owed += amount;

      if (debtor.net.abs() < 0.01) i++;
      if (creditor.net.abs() < 0.01) j++;
    }

    return settlements;
  }

  static List<String> getEligibleParticipants(ExpenseCategory category, List<Person> allMembers) {
    if (category.isSharedByAll) {
      return allMembers.map((p) => p.id).toList();
    }

    return allMembers.where((person) {
      final diet = person.dietType;
      
      if (category.isVegOnly) return diet.eatsVeg;
      if (category == ExpenseCategory.nonVeg) return diet.eatsNonVeg;
      if (category == ExpenseCategory.alcohol) return diet.drinksAlcohol;
      if (category == ExpenseCategory.mixed) return diet.eatsNonVeg;
      if (category == ExpenseCategory.mixedAlcohol) return diet.eatsNonVeg && diet.drinksAlcohol;
      
      return true;
    }).map((p) => p.id).toList();
  }

  static String getSplitLogicDescription(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.veg:
        return 'Split among all (vegetarian food)';
      case ExpenseCategory.nonVeg:
        return 'Split among non-vegetarians only';
      case ExpenseCategory.alcohol:
        return 'Split among alcohol consumers only';
      case ExpenseCategory.mixed:
        return 'Split among non-vegetarians (includes veg portion)';
      case ExpenseCategory.mixedAlcohol:
        return 'Split among non-veg alcohol consumers';
      case ExpenseCategory.transport:
      case ExpenseCategory.accommodation:
      case ExpenseCategory.misc:
        return 'Split equally among everyone';
    }
  }
}