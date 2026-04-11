import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/treatment_plan.dart';
import '../../models/patient.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';

class TreatmentPlanScreen extends StatefulWidget {
  final Patient patient;

  const TreatmentPlanScreen({super.key, required this.patient});

  @override
  State<TreatmentPlanScreen> createState() => _TreatmentPlanScreenState();
}

class _TreatmentPlanScreenState extends State<TreatmentPlanScreen> {
  final DatabaseService _dbService = DatabaseService();
  final BackendApiService _backendApiService = BackendApiService();
  TreatmentPlan? _activePlan;
  List<TreatmentPlan> _allPlans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);
    try {
      final activePlan = await _dbService.getActiveTreatmentPlan(widget.patient.id);
      final allPlans = await _dbService.getTreatmentPlans(widget.patient.id);
      setState(() {
        _activePlan = activePlan;
        _allPlans = allPlans;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading treatment plans: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Treatment Plan'),
            Text(
              widget.patient.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activePlan == null
              ? _buildEmptyState()
              : _buildActivePlanView(),
      floatingActionButton: _activePlan == null
          ? FloatingActionButton.extended(
              onPressed: _showCreatePlanDialog,
              backgroundColor: AppTheme.primaryIndigo,
              icon: const Icon(Icons.add),
              label: const Text('Create Plan'),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_alt_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No active treatment plan',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
          ),
          const SizedBox(height: 32),
          if (_allPlans.isNotEmpty) ...[
            TextButton.icon(
              onPressed: _showPlanHistory,
              icon: const Icon(Icons.history),
              label: const Text('View Plan History'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivePlanView() {
    final plan = _activePlan!;
    final progress = plan.overallProgressPercentage ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Card(
            color: AppTheme.cardDark,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Active Plan',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.history, color: Colors.white),
                        onPressed: _showPlanHistory,
                        tooltip: 'View history',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Created: ${DateFormat('MMM dd, yyyy').format(plan.createdAt)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Overall Progress', style: TextStyle(color: Colors.white70)),
                          Text('$progress%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progress / 100,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(progress >= 75 ? AppTheme.safeGreen : AppTheme.primaryIndigo),
                        minHeight: 8,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Diagnosis section
          _buildSection(
            '🏥 Diagnosis',
            [
              _buildInfoRow('Primary', plan.primaryDiagnosis),
              if (plan.secondaryDiagnoses != null)
                _buildInfoRow('Secondary', plan.secondaryDiagnoses!),
              if (plan.diagnosticCodes != null)
                _buildInfoRow('ICD-10 Codes', plan.diagnosticCodes!),
            ],
          ),
          const SizedBox(height: 16),
          
          // Treatment approach section
          _buildSection(
            '💡 Treatment Approach',
            [
              _buildInfoRow('Method', plan.treatmentApproach),
              _buildInfoRow('Frequency', plan.sessionFrequency),
              _buildInfoRow('Duration', '${plan.estimatedDurationWeeks} weeks'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (plan.includesIndividualTherapy) _buildBadge('Individual Therapy'),
                  if (plan.includesGroupTherapy) _buildBadge('Group Therapy'),
                  if (plan.includesMedication) _buildBadge('Medication'),
                ],
              ),
              if (plan.medicationNotes != null) ...[
                const SizedBox(height: 12),
                const Text('Medication Notes:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(plan.medicationNotes!, style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          
          // Treatment goals
          _buildSection(
            '🎯 Treatment Goals (${plan.goals.length})',
            [],
          ),
          const SizedBox(height: 8),
          ...plan.goals.map((goal) => _buildGoalCard(goal)),
          
          const SizedBox(height: 24),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _updateProgress,
                  icon: const Icon(Icons.edit),
                  label: const Text('Update Progress'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryIndigo,
                    side: const BorderSide(color: AppTheme.primaryIndigo),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _completePlan,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Complete Plan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.safeGreen,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmAndSendPlan(plan),
              icon: const Icon(Icons.send),
              label: const Text('Send Plan To Patient App'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      color: AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...children,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label:', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryIndigo),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.primaryIndigo, fontSize: 12),
      ),
    );
  }

  Widget _buildGoalCard(TreatmentGoal goal) {
    final progress = goal.progressPercentage ?? 0;
    final statusColor = _getStatusColor(goal.status);

    return Card(
      color: AppTheme.backgroundDark,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal.description,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    goal.status.toUpperCase(),
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Target: ${goal.targetDate}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(statusColor),
              minHeight: 6,
            ),
            const SizedBox(height: 4),
            Text(
              '$progress% complete',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
            ),
            if (goal.progressNotes != null) ...[
              const SizedBox(height: 8),
              Text(
                goal.progressNotes!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'achieved':
        return AppTheme.safeGreen;
      case 'in-progress':
        return AppTheme.primaryIndigo;
      case 'discontinued':
        return AppTheme.riskRed;
      default:
        return Colors.grey;
    }
  }

  Future<void> _confirmAndSendPlan(TreatmentPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Send Treatment Plan To Patient?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Send the active treatment plan to ${plan.patientName} now?\n\nDiagnosis: ${plan.primaryDiagnosis}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Local Only'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Confirm & Send'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treatment plan saved locally only.')),
      );
      return;
    }

    final synced = await _backendApiService.sendSharedTreatmentPlan({
      'id': plan.id,
      'patientExternalId': plan.patientId,
      'patientName': plan.patientName,
      'therapistExternalId': plan.therapistId,
      'therapistName': plan.therapistName,
      'primaryDiagnosis': plan.primaryDiagnosis,
      'treatmentApproach': plan.treatmentApproach,
      'sessionFrequency': plan.sessionFrequency,
      'estimatedDurationWeeks': plan.estimatedDurationWeeks,
      'goals': plan.goals.map((g) => g.toJson()).toList(),
      'status': plan.status,
      'notes': plan.progressSummary,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Treatment plan sent to patient app.'
              : 'Treatment plan saved locally. Sending failed.',
        ),
        backgroundColor: synced ? AppTheme.safeGreen : AppTheme.warningAmber,
      ),
    );
  }

  void _showCreatePlanDialog() {
    showDialog(
      context: context,
      builder: (context) => _TreatmentPlanFormDialog(
        patient: widget.patient,
        therapistId: AuthService().currentUserId ?? '',
        onSave: (plan) async {
          await _dbService.insertTreatmentPlan(plan);
          await _loadPlans();
          await _confirmAndSendPlan(plan);
        },
      ),
    );
  }

  void _showPlanHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Treatment Plan History', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _allPlans.length,
            itemBuilder: (context, index) {
              final plan = _allPlans[index];
              return ListTile(
                title: Text(plan.primaryDiagnosis, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Created: ${DateFormat('MMM dd, yyyy').format(plan.createdAt)}',
                  style: const TextStyle(color: Colors.white54),
                ),
                trailing: Text(
                  plan.status.toUpperCase(),
                  style: TextStyle(color: _getStatusColor(plan.status)),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _updateProgress() {
    // TODO: Open dialog to update goals progress
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Goal progress update coming soon')),
    );
  }

  void _completePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Complete Treatment Plan?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Mark this treatment plan as completed? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.safeGreen),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _activePlan != null) {
      final updated = TreatmentPlan(
        id: _activePlan!.id,
        patientId: _activePlan!.patientId,
        patientName: _activePlan!.patientName,
        therapistId: _activePlan!.therapistId,
        therapistName: _activePlan!.therapistName,
        primaryDiagnosis: _activePlan!.primaryDiagnosis,
        secondaryDiagnoses: _activePlan!.secondaryDiagnoses,
        diagnosticCodes: _activePlan!.diagnosticCodes,
        treatmentApproach: _activePlan!.treatmentApproach,
        sessionFrequency: _activePlan!.sessionFrequency,
        estimatedDurationWeeks: _activePlan!.estimatedDurationWeeks,
        goals: _activePlan!.goals,
        includesIndividualTherapy: _activePlan!.includesIndividualTherapy,
        includesGroupTherapy: _activePlan!.includesGroupTherapy,
        includesMedication: _activePlan!.includesMedication,
        medicationNotes: _activePlan!.medicationNotes,
        status: 'completed',
        createdAt: _activePlan!.createdAt,
        lastReviewedAt: _activePlan!.lastReviewedAt,
        completedAt: DateTime.now(),
        progressSummary: _activePlan!.progressSummary,
        overallProgressPercentage: 100,
      );
      await _dbService.updateTreatmentPlan(updated);
      _loadPlans();
    }
  }
}

class _TreatmentPlanFormDialog extends StatefulWidget {
  final Patient patient;
  final String therapistId;
  final Function(TreatmentPlan) onSave;

  const _TreatmentPlanFormDialog({
    required this.patient,
    required this.therapistId,
    required this.onSave,
  });

  @override
  State<_TreatmentPlanFormDialog> createState() => _TreatmentPlanFormDialogState();
}

class _TreatmentPlanFormDialogState extends State<_TreatmentPlanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _primaryDiagnosisController = TextEditingController();
  final _secondaryDiagnosesController = TextEditingController();
  final _diagnosticCodesController = TextEditingController();
  final _medicationNotesController = TextEditingController();
  String _treatmentApproach = 'CBT';
  String _sessionFrequency = 'weekly';
  int _estimatedDurationWeeks = 12;
  bool _includesIndividual = true;
  bool _includesGroup = false;
  bool _includesMedication = false;
  final List<TreatmentGoal> _goals = [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardDark,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'New Treatment Plan',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Diagnosis
                      const Text('Primary Diagnosis *', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _primaryDiagnosisController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'e.g., Major Depressive Disorder',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                          filled: true,
                          fillColor: AppTheme.backgroundDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _secondaryDiagnosesController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Secondary Diagnoses',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: AppTheme.backgroundDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _diagnosticCodesController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'ICD-10 Codes',
                          hintText: 'e.g., F32.1, F41.1',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                          filled: true,
                          fillColor: AppTheme.backgroundDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Treatment approach
                      const Text('Treatment Approach *', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _treatmentApproach,
                        dropdownColor: AppTheme.backgroundDark,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppTheme.backgroundDark,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'CBT', child: Text('Cognitive Behavioral Therapy (CBT)', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'DBT', child: Text('Dialectical Behavior Therapy (DBT)', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'Psychodynamic', child: Text('Psychodynamic Therapy', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'Humanistic', child: Text('Humanistic Therapy', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'Integrative', child: Text('Integrative Approach', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) => setState(() => _treatmentApproach = v!),
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Frequency', style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: _sessionFrequency,
                                  dropdownColor: AppTheme.backgroundDark,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: AppTheme.backgroundDark,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'weekly', child: Text('Weekly', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 'biweekly', child: Text('Bi-weekly', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 'monthly', child: Text('Monthly', style: TextStyle(color: Colors.white))),
                                  ],
                                  onChanged: (v) => setState(() => _sessionFrequency = v!),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Duration (weeks)', style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<int>(
                                  initialValue: _estimatedDurationWeeks,
                                  dropdownColor: AppTheme.backgroundDark,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: AppTheme.backgroundDark,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 8, child: Text('8 weeks', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 12, child: Text('12 weeks', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 16, child: Text('16 weeks', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 24, child: Text('24 weeks', style: TextStyle(color: Colors.white))),
                                    DropdownMenuItem(value: 52, child: Text('52 weeks (1 year)', style: TextStyle(color: Colors.white))),
                                  ],
                                  onChanged: (v) => setState(() => _estimatedDurationWeeks = v!),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Modalities
                      const Text('Treatment Modalities', style:TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _includesIndividual,
                        onChanged: (v) => setState(() => _includesIndividual = v ?? true),
                        title: const Text('Individual Therapy', style: TextStyle(color: Colors.white)),
                        activeColor: AppTheme.primaryIndigo,
                        tileColor: AppTheme.backgroundDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _includesGroup,
                        onChanged: (v) => setState(() => _includesGroup = v ?? false),
                        title: const Text('Group Therapy', style: TextStyle(color: Colors.white)),
                        activeColor: AppTheme.primaryIndigo,
                        tileColor: AppTheme.backgroundDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _includesMedication,
                        onChanged: (v) => setState(() => _includesMedication = v ?? false),
                        title: const Text('Medication Management', style: TextStyle(color: Colors.white)),
                        activeColor: AppTheme.primaryIndigo,
                        tileColor: AppTheme.backgroundDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      if (_includesMedication) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _medicationNotesController,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Medication Notes',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: AppTheme.backgroundDark,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      
                      // Goals
                      Row(
                        children: [
                          const Text('Treatment Goals', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addGoal,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Goal'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._goals.map((goal) => _buildGoalItem(goal)),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _savePlan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryIndigo,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Create Treatment Plan', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalItem(TreatmentGoal goal) {
    return Card(
      color: AppTheme.backgroundDark,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(goal.description, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text('Target: ${goal.targetDate}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
          onPressed: () => setState(() => _goals.remove(goal)),
        ),
      ),
    );
  }

  void _addGoal() {
    showDialog(
      context: context,
      builder: (context) {
        final descController = TextEditingController();
        final targetController = TextEditingController(text: '3 months');
        
        return AlertDialog(
          backgroundColor: AppTheme.cardDark,
          title: const Text('Add Goal', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Goal Description',
                  hintText: 'e.g., Reduce anxiety symptoms by 50%',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: AppTheme.backgroundDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: targetController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Target Date/Timeframe',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: AppTheme.backgroundDark,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (descController.text.trim().isNotEmpty) {
                  setState(() {
                    _goals.add(TreatmentGoal(
                      id: const Uuid().v4(),
                      description: descController.text.trim(),
                      targetDate: targetController.text.trim(),
                      status: 'not-started',
                      progressPercentage: 0,
                    ));
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryIndigo),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _savePlan() {
    if (!_formKey.currentState!.validate()) return;
    if (_goals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one treatment goal')),
      );
      return;
    }

    final plan = TreatmentPlan(
      id: const Uuid().v4(),
      patientId: widget.patient.id,
      patientName: widget.patient.name,
      therapistId: widget.therapistId,
      therapistName: 'Therapist',
      primaryDiagnosis: _primaryDiagnosisController.text.trim(),
      secondaryDiagnoses: _secondaryDiagnosesController.text.trim().isNotEmpty 
          ? _secondaryDiagnosesController.text.trim() 
          : null,
      diagnosticCodes: _diagnosticCodesController.text.trim().isNotEmpty 
          ? _diagnosticCodesController.text.trim() 
          : null,
      treatmentApproach: _treatmentApproach,
      sessionFrequency: _sessionFrequency,
      estimatedDurationWeeks: _estimatedDurationWeeks,
      goals: _goals,
      includesIndividualTherapy: _includesIndividual,
      includesGroupTherapy: _includesGroup,
      includesMedication: _includesMedication,
      medicationNotes: _includesMedication && _medicationNotesController.text.trim().isNotEmpty 
          ? _medicationNotesController.text.trim() 
          : null,
      status: 'active',
      createdAt: DateTime.now(),
      overallProgressPercentage: 0,
    );

    widget.onSave(plan);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Treatment plan created successfully'),
        backgroundColor: AppTheme.safeGreen,
      ),
    );
  }
}
