// lib/models/enums.dart
import 'dart:ui';

import 'package:flutter/material.dart';

enum ExpenseCategory {
  veg('Vegetarian', Icons.eco, Colors.green),
  nonVeg('Non-Vegetarian', Icons.restaurant, Colors.orange),
  alcohol('Alcohol', Icons.wine_bar, Colors.purple),
  mixed('Mixed (Veg + Non-Veg)', Icons.set_meal, Colors.blue),
  mixedAlcohol('Mixed + Alcohol', Icons.local_bar, Colors.red),
  transport('Transport', Icons.directions_car, Colors.teal),
  accommodation('Accommodation', Icons.hotel, Colors.indigo),
  misc('Miscellaneous', Icons.receipt_long, Colors.grey);

  final String label;
  final IconData icon;
  final Color color;

  const ExpenseCategory(this.label, this.icon, this.color);

  bool get isVegOnly => this == ExpenseCategory.veg;
  bool get includesNonVeg => this == ExpenseCategory.nonVeg || this == ExpenseCategory.mixed || this == ExpenseCategory.mixedAlcohol;
  bool get includesAlcohol => this == ExpenseCategory.alcohol || this == ExpenseCategory.mixedAlcohol;
  bool get isSharedByAll => this == ExpenseCategory.transport || this == ExpenseCategory.accommodation || this == ExpenseCategory.misc;
}

enum DietType {
  vegetarian('Vegetarian', Colors.green),
  nonVegetarian('Non-Vegetarian', Colors.orange),
  nonVegAlcoholic('Non-Veg + Alcohol', Colors.red);

  final String label;
  final Color color;

  const DietType(this.label, this.color);

  bool get eatsVeg => true;
  bool get eatsNonVeg => this != DietType.vegetarian;
  bool get drinksAlcohol => this == DietType.nonVegAlcoholic;
}