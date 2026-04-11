import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

class InterventionRecommendationsScreen extends StatefulWidget {
  final String patientId;

  const InterventionRecommendationsScreen({
    super.key,
    required this.patientId,
  });

  @override
  State<InterventionRecommendationsScreen> createState() =>
      _InterventionRecommendationsScreenState();
}

class _InterventionRecommendationsScreenState
    extends State<InterventionRecommendationsScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _patientData;
  List<Map<String, dynamic>> _interventions = [];
  bool _loading = true;
  bool _showAddForm = false;
  String? _therapistId;

  // Form Controllers
  late TextEditingController _typeController;
  late TextEditingController _descriptionController;
  String _selectedEvidenceLevel = 'clinical-guidance';
  List<String> _cbtExercises = [];
  List<String> _medicationOptions = [];
  List<String> _lifestyleChanges = [];

  @override
  void initState() {
    super.initState();
    _typeController = TextEditingController();
    _descriptionController = TextEditingController();
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _typeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoad() async {
    try {
      _therapistId = _authService.currentUserId ?? 'therapist_main';

      final patients = await _dbService.getAllPatients();
      final patient = patients.firstWhere((p) => p.id == widget.patientId, orElse: () => throw Exception('Patient not found'));
      setState(() => _patientData = {
        'id': patient.id,
        'name': patient.name,
        'email': patient.email,
      });

      await _loadInterventions();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadInterventions() async {
    setState(() => _loading = true);
    try {
      final interventions = await _backendApiService
          .getPatientInterventions(widget.patientId);

      if (!mounted) return;
      setState(() {
        _interventions = interventions.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _submitIntervention() async {
    if (_typeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an intervention type')),
      );
      return;
    }

    try {
      await _backendApiService.createIntervention(
        patientId: widget.patientId,
        therapistId: _therapistId,
        type: _typeController.text,
        evidenceLevel: _selectedEvidenceLevel,
        description: _descriptionController.text,
        cbtInterventions: _cbtExercises,
        medicationSuggestions: _medicationOptions,
        lifestyleRecommendations: _lifestyleChanges,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Intervention recorded successfully')),
      );

      _typeController.clear();
      _descriptionController.clear();
      setState(() {
        _showAddForm = false;
        _selectedEvidenceLevel = 'clinical-guidance';
        _cbtExercises = [];
        _medicationOptions = [];
        _lifestyleChanges = [];
      });

      await _loadInterventions();
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
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lightbulb_outline_rounded,
                      color: AppTheme.primaryIndigo, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Evidence-Based Interventions',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 6),
            if (_patientData != null)
              Text(
                _patientData!['name'] ?? '',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadInterventions,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInterventions,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInterventionGuides(),
                  const SizedBox(height: 24),
                  _buildCurrentInterventions(),
                  const SizedBox(height: 24),
                  if (!_showAddForm)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _showAddForm = true),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add New Intervention'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryIndigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (_showAddForm) ...[
                    _buildAddInterventionForm(),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInterventionGuides() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evidence-Based Intervention Framework',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _buildGuideCard(
            'Cognitive Behavioral Therapy (CBT)',
            'RCT-supported intervention for depression',
            'Behavioral activation, cognitive restructuring, '
                'problem-solving training',
            const Color(0xFF42A5F5),
            Icons.psychology_rounded,
          ),
          const SizedBox(height: 12),
          _buildGuideCard(
            'Medication Management',
            'Pharmacological treatment options',
            'SSRIs, SNRIs, tricyclics based on clinical assessment',
            const Color(0xFFEF5350),
            Icons.local_pharmacy_rounded,
          ),
          const SizedBox(height: 12),
          _buildGuideCard(
            'Lifestyle Interventions',
            'Behavioral modifications for symptom improvement',
            'Exercise, sleep hygiene, social engagement, '
                'stress management',
            Colors.green,
            Icons.favorite_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildGuideCard(
    String title,
    String subtitle,
    String description,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentInterventions() {
    if (_interventions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 48,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No interventions recorded yet',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add evidence-based interventions tailored to this patient',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Treatment Plan',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_interventions.length, (index) {
          final intervention = _interventions[index];
          return _buildInterventionCard(intervention);
        }),
      ],
    );
  }

  Widget _buildInterventionCard(Map<String, dynamic> intervention) {
    final type = intervention['type'] as String? ?? '';
    final evidenceLevel = intervention['evidenceLevel'] as String? ?? '';
    final description = intervention['description'] as String? ?? '';
    final cbtInterventions =
        (intervention['cbtInterventions'] as List?)?.cast<String>() ?? [];
    final medicationSuggestions =
        (intervention['medicationSuggestions'] as List?)?.cast<String>() ?? [];
    final lifestyleRecommendations = (intervention['lifestyleRecommendations']
        as List?)
        ?.cast<String>() ?? [];

    Color startColor;
    IconData icon;

    if (type.toLowerCase().contains('cbt') ||
        type.toLowerCase().contains('behavioral')) {
      startColor = const Color(0xFF42A5F5);
      icon = Icons.psychology_rounded;
    } else if (type.toLowerCase().contains('medication')) {
      startColor = const Color(0xFFEF5350);
      icon = Icons.local_pharmacy_rounded;
    } else if (type.toLowerCase().contains('lifestyle')) {
      startColor = Colors.green;
      icon = Icons.favorite_rounded;
    } else {
      startColor = Colors.grey;
      icon = Icons.lightbulb_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: startColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: startColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Evidence: ${_formatEvidenceLevel(evidenceLevel)}',
                            style: TextStyle(
                              color: startColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
          if (cbtInterventions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInterventionList(
              'CBT Exercises',
              cbtInterventions,
              const Color(0xFF42A5F5),
            ),
          ],
          if (medicationSuggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInterventionList(
              'Medication Options',
              medicationSuggestions,
              const Color(0xFFEF5350),
            ),
          ],
          if (lifestyleRecommendations.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildInterventionList(
              'Lifestyle Changes',
              lifestyleRecommendations,
              Colors.green,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInterventionList(
    String title,
    List<String> items,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items
              .map((item) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: color.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildAddInterventionForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryIndigo.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New Intervention',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          // Intervention Type Dropdown
          const Text(
            'Intervention Type',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _typeController.text.isEmpty ? null : _typeController.text,
            onChanged: (value) {
              if (value != null) {
                _typeController.text = value;
              }
            },
            items: [
              'Cognitive Behavioral Therapy (CBT)',
              'Behavioral Activation',
              'Cognitive Restructuring',
              'Medication Management',
              'Lifestyle Intervention',
              'Social Support Enhancement',
              'Sleep Hygiene Training',
              'Exercise Program',
            ]
                .map((type) =>
                    DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.backgroundDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
            dropdownColor: AppTheme.cardDark,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          // Evidence Level
          const Text(
            'Evidence Level',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['RCT', 'clinical-guidance', 'case-study']
                .map((level) => Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedEvidenceLevel = level),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedEvidenceLevel == level
                            ? AppTheme.primaryIndigo
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedEvidenceLevel == level
                              ? AppTheme.primaryIndigo
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _formatEvidenceLevel(level),
                          style: TextStyle(
                            color: _selectedEvidenceLevel == level
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ))
                .toList(),
          ),
          const SizedBox(height: 16),
          // Description
          const Text(
            'Description (Optional)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Additional notes or treatment rationale...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: AppTheme.backgroundDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: AppTheme.primaryIndigo,
                ),
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _showAddForm = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _submitIntervention,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save Intervention'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryIndigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatEvidenceLevel(String level) {
    if (level == 'RCT') return 'RCT Evidence';
    if (level == 'clinical-guidance') return 'Clinical Guidance';
    if (level == 'case-study') return 'Case Study';
    return level;
  }
}
