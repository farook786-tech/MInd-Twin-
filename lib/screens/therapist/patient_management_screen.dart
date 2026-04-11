import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../services/database_service.dart';
import '../../models/patient.dart';
import 'treatment_report_screen.dart';

class PatientManagementScreen extends StatefulWidget {
  const PatientManagementScreen({super.key});

  @override
  State<PatientManagementScreen> createState() => _PatientManagementScreenState();
}

class _PatientManagementScreenState extends State<PatientManagementScreen> {
  late final DatabaseService _dbService;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  List<Patient> _patients = [];

  @override
  void initState() {
    super.initState();
    _dbService = DatabaseService();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    try {
      final patients = await _dbService.getAllPatients();
      setState(() => _patients = patients);
    } catch (e) {
      print('Error loading patients: $e');
    }
  }

  Future<void> _addPatient() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final age = int.tryParse(_ageController.text.trim()) ?? 0;

    if (name.isEmpty || email.isEmpty || age == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    try {
      final patient = Patient(
        id: const Uuid().v4(),
        name: name,
        email: email,
        age: age,
        currentRiskScore: 0.5,
        createdAt: DateTime.now(),
        lastCheckIn: DateTime.now(),
      );

      await _dbService.insertPatient(patient);
      _nameController.clear();
      _emailController.clear();
      _ageController.clear();

      await _loadPatients();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Patient added successfully!'),
            backgroundColor: Color(0xFF22c55e),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Patients'),
        backgroundColor: AppTheme.cardDark,
      ),
      body: Column(
        children: [
          // Add Patient Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _showAddPatientDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add New Patient'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Patients List
          Expanded(
            child: _patients.isEmpty
                ? Center(
                    child: Text(
                      'No patients yet',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _patients.length,
                    itemBuilder: (context, index) {
                      final patient = _patients[index];
                      return _buildPatientCard(patient);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Patient patient) {
    final riskColor = AppTheme.getRiskColor(patient.currentRiskScore);
    final riskPercent = (patient.currentRiskScore * 100).toInt();

    return Card(
      color: AppTheme.cardDark,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        patient.email,
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$riskPercent% Risk',
                    style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Age: ${patient.age}',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(width: 16),
                Text(
                  'Wellbeing: ${patient.wellbeingScore.toInt()}%',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TreatmentReportScreen(
                        patientId: patient.id,
                        patientName: patient.name,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.description_rounded),
                  label: const Text('Reports'),
                ),
                TextButton.icon(
                  onPressed: () => _editPatient(patient),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => _deletePatient(patient),
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPatientDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Add New Patient'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Patient Name',
                  hintText: 'e.g., John Doe',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'e.g., john@example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  hintText: 'e.g., 28',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _addPatient();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryIndigo,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editPatient(Patient patient) {
    _nameController.text = patient.name;
    _emailController.text = patient.email;
    _ageController.text = patient.age.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Edit Patient'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Patient Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updatedPatient = patient.copyWith(
                name: _nameController.text,
                email: _emailController.text,
                age: int.parse(_ageController.text),
              );
              await _dbService.updatePatient(updatedPatient);
              _nameController.clear();
              _emailController.clear();
              _ageController.clear();
              await _loadPatients();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryIndigo,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePatient(Patient patient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient?'),
        content: Text('Are you sure you want to delete ${patient.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.riskRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbService.deletePatient(patient.id);
      await _loadPatients();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _ageController.dispose();
    super.dispose();
  }
}
