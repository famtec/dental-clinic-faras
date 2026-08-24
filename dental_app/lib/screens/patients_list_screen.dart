import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/patient.dart';
import '../services/api_service.dart';

class PatientsListScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onSessionExpired;

  const PatientsListScreen({
    super.key,
    required this.apiService,
    required this.onSessionExpired,
  });

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  List<Patient>? _patients;
  String? _errorMessage;
  bool _isSubscriptionBlocked = false;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSubscriptionBlocked = false;
    });
    try {
      final patients = await widget.apiService.fetchPatients();
      patients.sort((a, b) => a.fullName.compareTo(b.fullName));
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionExpired) {
        widget.onSessionExpired();
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _isSubscriptionBlocked = e.isSubscriptionBlocked;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'تعذر تحميل قائمة المرضى. حاول مرة أخرى.';
        _isLoading = false;
      });
    }
  }

  Future<void> _callPatient(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الاتصال.')));
      }
    }
  }

  void _showPatientDetails(Patient patient) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.indigo.shade100,
                child: const Icon(Icons.person, color: Colors.indigo, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                patient.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _detailRow('الهاتف', patient.phone.isEmpty ? '—' : patient.phone),
              _detailRow('إجمالي تكلفة العلاج',
                  '${patient.totalTreatmentCost.toStringAsFixed(0)} ل.س'),
              _detailRow(
                  'المبلغ المدفوع', '${patient.paidAmount.toStringAsFixed(0)} ل.س'),
              _detailRow('المتبقي', '${patient.remainingBalance.toStringAsFixed(0)} ل.س'),
              const SizedBox(height: 20),
              if (patient.phone.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _callPatient(patient.phone),
                  icon: const Icon(Icons.call),
                  label: const Text('اتصال بالمريض'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSubscriptionBlocked ? Icons.lock_outline : Icons.error_outline,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final allPatients = _patients ?? [];
    final query = _searchQuery.trim();
    final filtered = query.isEmpty
        ? allPatients
        : allPatients
            .where((patient) =>
                patient.fullName.contains(query) || patient.phone.contains(query))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الهاتف',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(
                        allPatients.isEmpty ? Icons.people_outline : Icons.search_off,
                        size: 56,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        allPatients.isEmpty ? 'لا يوجد مرضى مسجّلون بعد' : 'لا نتائج مطابقة',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final patient = filtered[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: const Icon(Icons.person, color: Colors.indigo),
                          ),
                          title: Text(patient.fullName,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              patient.phone.isEmpty ? 'بدون رقم هاتف' : patient.phone),
                          trailing: patient.phone.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.call, color: Colors.green),
                                  onPressed: () => _callPatient(patient.phone),
                                ),
                          onTap: () => _showPatientDetails(patient),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
