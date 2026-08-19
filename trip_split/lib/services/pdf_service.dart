// lib/services/pdf_service.dart
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/enums.dart';
import '../models/person.dart';
import '../models/trip.dart';
import '../models/user.dart';
import 'calculation_service.dart';

class PdfService {
  /// Generates PDF document bytes for a given trip
  static Future<Uint8List> generateTripReport({
    required Trip trip,
    UserModel? currentUser,
  }) async {
    final pdf = pw.Document();
    final DateFormat formatter = DateFormat('MMM dd, yyyy');
    final String generatedDate = formatter.format(DateTime.now());

    final balances = CalculationService.calculateBalances(trip);
    final settlements = CalculationService.calculateSettlements(trip);
    final double totalExpenses = trip.expenses.fold(0.0, (sum, e) => sum + e.amount);

    // Primary Colors
    final PdfColor primaryColor = PdfColor.fromHex('#4F46E5'); // Indigo 600
    final PdfColor secondaryColor = PdfColor.fromHex('#8B5CF6'); // Purple 500
    final PdfColor accentGreen = PdfColor.fromHex('#10B981'); // Emerald 500
    final PdfColor accentRed = PdfColor.fromHex('#EF4444'); // Red 500
    final PdfColor neutralBg = PdfColor.fromHex('#F9FAFB'); // Gray 50
    final PdfColor borderGray = PdfColor.fromHex('#E5E7EB');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 24,
                        height: 24,
                        decoration: pw.BoxDecoration(
                          color: primaryColor,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            'T',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        'EquiTrip Report',
                        style: pw.TextStyle(
                          color: primaryColor,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Generated on $generatedDate',
                    style: const pw.TextStyle(
                      color: PdfColors.grey700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: borderGray, thickness: 1),
              pw.SizedBox(height: 12),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Divider(color: borderGray, thickness: 1),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'EquiTrip | Smart Expense & Settlement Calculator',
                    style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) => [
          // Trip Header Title Banner
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: neutralBg,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: borderGray),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  trip.name,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey900,
                  ),
                ),
                if (trip.description != null && trip.description!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    trip.description!,
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    if (currentUser != null) ...[
                      pw.Text(
                        'User: ${currentUser.username}',
                        style: pw.TextStyle(fontSize: 10, color: primaryColor, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(width: 16),
                    ],
                    pw.Text(
                      'Created: ${formatter.format(trip.createdAt)}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // Overview Key Metrics Row
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildMetricCard(
                  title: 'Total Expenses',
                  value: 'Rs. ${totalExpenses.toStringAsFixed(2)}',
                  color: primaryColor,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  title: 'Total Members',
                  value: '${trip.allMembers.length}',
                  color: secondaryColor,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildMetricCard(
                  title: 'Settlements Needed',
                  value: '${settlements.length}',
                  color: settlements.isEmpty ? accentGreen : accentRed,
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 24),

          // SECTION 1: FINAL SETTLEMENT TRANSACTIONS
          pw.Text(
            '1. Final Settlement Transactions (Who Pays Whom)',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 8),

          if (settlements.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#ECFDF5'), // Green 50
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#A7F3D0')),
              ),
              child: pw.Center(
                child: pw.Text(
                  '🎉 All expenses are fully settled! No payments are owed.',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#065F46'),
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: borderGray, width: 0.8),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: primaryColor),
                  children: [
                    _buildTableCell('Payer (From)', isHeader: true),
                    _buildTableCell('', isHeader: true),
                    _buildTableCell('Receiver (To)', isHeader: true),
                    _buildTableCell('Amount', isHeader: true, alignRight: true),
                  ],
                ),
                ...settlements.map((s) {
                  return pw.TableRow(
                    children: [
                      _buildTableCell(s.fromName, isBold: true),
                      _buildTableCell('->', alignCenter: true),
                      _buildTableCell(s.toName, isBold: true),
                      _buildTableCell(
                        'Rs. ${s.amount.toStringAsFixed(2)}',
                        isBold: true,
                        alignRight: true,
                        textColor: accentRed,
                      ),
                    ],
                  );
                }),
              ],
            ),

          pw.SizedBox(height: 24),

          // SECTION 2: MEMBER BALANCES SUMMARY
          pw.Text(
            '2. Member Balances Summary',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 8),

          pw.Table(
            border: pw.TableBorder.all(color: borderGray, width: 0.8),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.5),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#4B5563')),
                children: [
                  _buildTableCell('Member Name', isHeader: true),
                  _buildTableCell('Diet Preference', isHeader: true),
                  _buildTableCell('Total Paid', isHeader: true, alignRight: true),
                  _buildTableCell('Share Owed', isHeader: true, alignRight: true),
                  _buildTableCell('Net Balance', isHeader: true, alignRight: true),
                ],
              ),
              ...balances.map((b) {
                final isPositive = b.net >= 0;
                return pw.TableRow(
                  children: [
                    _buildTableCell(b.person.name, isBold: true),
                    _buildTableCell(b.person.dietType.label),
                    _buildTableCell('Rs. ${b.paid.toStringAsFixed(2)}', alignRight: true),
                    _buildTableCell('Rs. ${b.owed.toStringAsFixed(2)}', alignRight: true),
                    _buildTableCell(
                      '${isPositive ? '+' : ''}Rs. ${b.net.toStringAsFixed(2)}',
                      isBold: true,
                      alignRight: true,
                      textColor: isPositive ? accentGreen : accentRed,
                    ),
                  ],
                );
              }),
            ],
          ),

          pw.SizedBox(height: 24),

          // SECTION 3: ITEMIZED EXPENSES LOG
          pw.Text(
            '3. Itemized Expenses Log (${trip.expenses.length} Total)',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 8),

          if (trip.expenses.isEmpty)
            pw.Text(
              'No expenses recorded yet.',
              style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 11),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: borderGray, width: 0.8),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.8),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#4B5563')),
                  children: [
                    _buildTableCell('Date', isHeader: true),
                    _buildTableCell('Description', isHeader: true),
                    _buildTableCell('Category', isHeader: true),
                    _buildTableCell('Paid By', isHeader: true),
                    _buildTableCell('Amount', isHeader: true, alignRight: true),
                  ],
                ),
                ...trip.expenses.map((e) {
                  final payer = trip.allMembers.firstWhere(
                    (m) => m.id == e.paidById,
                    orElse: () => Person(id: '', name: 'Unknown', dietType: DietType.vegetarian),
                  );
                  return pw.TableRow(
                    children: [
                      _buildTableCell(formatter.format(e.date)),
                      _buildTableCell(e.description, isBold: true),
                      _buildTableCell(e.category.label),
                      _buildTableCell(payer.name),
                      _buildTableCell('Rs. ${e.amount.toStringAsFixed(2)}', alignRight: true, isBold: true),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Opens standard print / download / share dialog for the PDF
  static Future<void> downloadOrPrintPdf({
    required Trip trip,
    UserModel? currentUser,
  }) async {
    final pdfBytes = await generateTripReport(trip: trip, currentUser: currentUser);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '${trip.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_Settlement_Report.pdf',
    );
  }

  static pw.Widget _buildMetricCard({
    required String title,
    required String value,
    required PdfColor color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F3F4F6'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 1.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    bool alignRight = false,
    bool alignCenter = false,
    PdfColor? textColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: alignRight
            ? pw.TextAlign.right
            : (alignCenter ? pw.TextAlign.center : pw.TextAlign.left),
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : (textColor ?? PdfColors.grey900),
        ),
      ),
    );
  }
}
