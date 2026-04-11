import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session_note.dart';
import '../../models/patient.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

class SessionNotesScreen extends StatefulWidget {
  final Patient patient;

  const SessionNotesScreen({super.key, required this.patient});

  @override
  State<SessionNotesScreen> createState() => _SessionNotesScreenState();
}

class _SessionNotesScreenState extends State<SessionNotesScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  List<SessionNote> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final notes = await _dbService.getSessionNotes(widget.patient.id);
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading session notes: $e');
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
            const Text('Session Notes'),
            Text(
              widget.patient.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.note_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        'No session notes yet',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return _buildNoteCard(note);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateNoteDialog,
        backgroundColor: AppTheme.primaryIndigo,
        icon: const Icon(Icons.add),
        label: const Text('New Note'),
      ),
    );
  }

  Widget _buildNoteCard(SessionNote note) {
    final riskColor = _getRiskColor(note.riskLevel);
    
    return Card(
      color: AppTheme.cardDark,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showNoteDetailsDialog(note),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: riskColor, width: 1.5),
                    ),
                    child: Text(
                      note.riskLevel.toUpperCase(),
                      style: TextStyle(
                        color: riskColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('MMM dd, yyyy').format(note.sessionDate),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                note.chiefComplaint,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Assessment: ${note.assessment}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.timer, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    '${note.durationMinutes} min',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                  ),
                  const SizedBox(width: 16),
                  if (note.isLocked) ...[
                    Icon(Icons.lock, size: 14, color: Colors.amber.withValues(alpha: 0.8)),
                    const SizedBox(width: 4),
                    Text(
                      'Locked',
                      style: TextStyle(color: Colors.amber.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateNoteDialog() {
    showDialog(
      context: context,
      builder: (context) => _SessionNoteFormDialog(
        patient: widget.patient,
        therapistId: _authService.currentUserId ?? '',
        onSave: (note) async {
          await _dbService.insertSessionNote(note);
          _loadNotes();
        },
      ),
    );
  }

  void _showNoteDetailsDialog(SessionNote note) {
    showDialog(
      context: context,
      builder: (context) => _SessionNoteDetailsDialog(note: note),
    );
  }

  Color _getRiskColor(String riskLevel) {
    switch (riskLevel) {
      case 'low':
        return AppTheme.safeGreen;
      case 'moderate':
        return AppTheme.warningAmber;
      case 'high':
        return Colors.orange;
      case 'crisis':
        return AppTheme.riskRed;
      default:
        return Colors.grey;
    }
  }
}

class _SessionNoteFormDialog extends StatefulWidget {
  final Patient patient;
  final String therapistId;
  final Function(SessionNote) onSave;

  const _SessionNoteFormDialog({
    required this.patient,
    required this.therapistId,
    required this.onSave,
  });

  @override
  State<_SessionNoteFormDialog> createState() => _SessionNoteFormDialogState();
}

class _SessionNoteFormDialogState extends State<_SessionNoteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _sessionDate = DateTime.now();
  int _durationMinutes = 50;
  String _riskLevel = 'low';
  bool _suicidalIdeation = false;
  bool _homicidalIdeation = false;
  int _patientEngagement = 5;
  String _progress = 'good';
  
  final _chiefComplaintController = TextEditingController();
  final _subjectiveController = TextEditingController();
  final _objectiveController = TextEditingController();
  final _assessmentController = TextEditingController();
  final _planController = TextEditingController();
  final _interventionsController = TextEditingController();
  final _homeworkController = TextEditingController();
  final _riskNotesController = TextEditingController();
  final _moodController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardDark,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'New Session Note',
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
            const SizedBox(height: 16),
            
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Session metadata
                      Row(
                        children: [
                          Expanded(
                            child: _buildDateField(),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDurationField(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // SOAP Notes format
                      _buildSectionTitle('Chief Complaint'),
                      _buildTextField(_chiefComplaintController, 'What brings the patient in today?', maxLines: 2),
                      const SizedBox(height: 20),
                      
                      _buildSectionTitle('Subjective (Patient\'s Report)'),
                      _buildTextField(_subjectiveController, 'Patient\'s description of symptoms, feelings, concerns', maxLines: 4),
                      const SizedBox(height: 20),
                      
                      _buildSectionTitle('Objective (Observations)'),
                      _buildTextField(_objectiveController, 'Appearance, behavior, affect, speech, thought process', maxLines: 4),
                      const SizedBox(height: 20),
                      
                      _buildSectionTitle('Assessment (Clinical Impression)'),
                      _buildTextField(_assessmentController, 'Diagnosis, severity, progress evaluation', maxLines: 3),
                      const SizedBox(height: 20),
                      
                      _buildSectionTitle('Plan (Treatment)'),
                      _buildTextField(_planController, 'Next steps, modifications to treatment', maxLines: 3),
                      const SizedBox(height: 20),
                      
                      _buildSectionTitle('Interventions Used'),
                      _buildTextField(_interventionsController, 'CBT, DBT, mindfulness, etc.', maxLines: 2),
                      const SizedBox(height: 20),
                      
                      _buildSectionTitle('Homework Assigned'),
                      _buildTextField(_homeworkController, 'Tasks for patient to complete', maxLines: 2),
                      const SizedBox(height: 24),
                      
                      // Risk assessment
                      _buildSectionTitle('Risk Assessment'),
                      const SizedBox(height: 12),
                      _buildRiskLevelDropdown(),
                      const SizedBox(height: 16),
                      
                      CheckboxListTile(
                        value: _suicidalIdeation,
                        onChanged: (value) => setState(() => _suicidalIdeation = value ?? false),
                        title: const Text('Suicidal Ideation', style: TextStyle(color: Colors.white)),
                        activeColor: AppTheme.riskRed,
                        tileColor: AppTheme.backgroundDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      const SizedBox(height: 8),
                      
                      CheckboxListTile(
                        value: _homicidalIdeation,
                        onChanged: (value) => setState(() => _homicidalIdeation = value ?? false),
                        title: const Text('Homicidal Ideation', style: TextStyle(color: Colors.white)),
                        activeColor: AppTheme.riskRed,
                        tileColor: AppTheme.backgroundDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildTextField(_riskNotesController, 'Risk assessment details', maxLines: 2),
                      const SizedBox(height: 24),
                      
                      // Session metrics
                      _buildSectionTitle('Session Metrics'),
                      const SizedBox(height: 12),
                      _buildTextField(_moodController, 'Patient mood during session', maxLines: 1),
                      const SizedBox(height: 16),
                      
                      Text('Patient Engagement (1-10)', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                      Slider(
                        value: _patientEngagement.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: _patientEngagement.toString(),
                        activeColor: AppTheme.primaryIndigo,
                        onChanged: (value) => setState(() => _patientEngagement = value.toInt()),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildProgressDropdown(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            
            // Save button
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveNote,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryIndigo,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save Session Note', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: AppTheme.backgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      validator: (value) {
        if (controller == _chiefComplaintController || 
            controller == _subjectiveController || 
            controller == _assessmentController || 
            controller == _planController) {
          if (value == null || value.trim().isEmpty) {
            return 'This field is required';
          }
        }
        return null;
      },
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Session Date', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _sessionDate,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now(),
            );
            if (date != null) setState(() => _sessionDate = date);
          },
          icon: const Icon(Icons.calendar_today),
          label: Text(DateFormat('MMM dd, yyyy').format(_sessionDate)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.backgroundDark),
        ),
      ],
    );
  }

  Widget _buildDurationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Duration (min)', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _durationMinutes,
          dropdownColor: AppTheme.backgroundDark,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.backgroundDark,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(value: 30, child: Text('30 min', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 50, child: Text('50 min', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 60, child: Text('60 min', style: TextStyle(color: Colors.white))),
            DropdownMenuItem(value: 90, child: Text('90 min', style: TextStyle(color: Colors.white))),
          ],
          onChanged: (value) => setState(() => _durationMinutes = value!),
        ),
      ],
    );
  }

  Widget _buildRiskLevelDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _riskLevel,
      dropdownColor: AppTheme.backgroundDark,
      decoration: InputDecoration(
        labelText: 'Risk Level',
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppTheme.backgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: const [
        DropdownMenuItem(value: 'low', child: Text('✅ Low Risk', style: TextStyle(color: Colors.white))),
        DropdownMenuItem(value: 'moderate', child: Text('⚠️ Moderate Risk', style: TextStyle(color: Colors.white))),
        DropdownMenuItem(value: 'high', child: Text('🔶 High Risk', style: TextStyle(color: Colors.white))),
        DropdownMenuItem(value: 'crisis', child: Text('🚨 Crisis', style: TextStyle(color: Colors.white))),
      ],
      onChanged: (value) => setState(() => _riskLevel = value!),
    );
  }

  Widget _buildProgressDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _progress,
      dropdownColor: AppTheme.backgroundDark,
      decoration: InputDecoration(
        labelText: 'Overall Progress',
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppTheme.backgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: const [
        DropdownMenuItem(value: 'excellent', child: Text('Excellent Progress', style: TextStyle(color: Colors.white))),
        DropdownMenuItem(value: 'good', child: Text('Good Progress', style: TextStyle(color: Colors.white))),
        DropdownMenuItem(value: 'fair', child: Text('Fair Progress', style: TextStyle(color: Colors.white))),
        DropdownMenuItem(value: 'poor', child: Text('Poor/No Progress', style: TextStyle(color: Colors.white))),
      ],
      onChanged: (value) => setState(() => _progress = value!),
    );
  }

  void _saveNote() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final note = SessionNote(
      id: const Uuid().v4(),
      patientId: widget.patient.id,
      patientName: widget.patient.name,
      therapistId: widget.therapistId,
      therapistName: 'Therapist', // TODO: Get from auth
      sessionDate: _sessionDate,
      durationMinutes: _durationMinutes,
      chiefComplaint: _chiefComplaintController.text.trim(),
      subjectiveNotes: _subjectiveController.text.trim(),
      objectiveObservations: _objectiveController.text.trim(),
      assessment: _assessmentController.text.trim(),
      plan: _planController.text.trim(),
      interventionsUsed: _interventionsController.text.trim().isNotEmpty 
          ? _interventionsController.text.trim() 
          : null,
      homeworkAssigned: _homeworkController.text.trim().isNotEmpty 
          ? _homeworkController.text.trim() 
          : null,
      riskLevel: _riskLevel,
      riskNotes: _riskNotesController.text.trim().isNotEmpty 
          ? _riskNotesController.text.trim() 
          : null,
      suicidalIdeation: _suicidalIdeation,
      homicidalIdeation: _homicidalIdeation,
      patientEngagement: _patientEngagement,
      mood: _moodController.text.trim().isNotEmpty 
          ? _moodController.text.trim() 
          : null,
      progress: _progress,
      createdAt: DateTime.now(),
    );

    widget.onSave(note);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Session note saved successfully'),
        backgroundColor: AppTheme.safeGreen,
      ),
    );
  }
}

class _SessionNoteDetailsDialog extends StatelessWidget {
  final SessionNote note;

  const _SessionNoteDetailsDialog({required this.note});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardDark,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Session Note',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (note.isLocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock, size: 14, color: Colors.amber),
                        SizedBox(width: 4),
                        Text('Locked', style: TextStyle(color: Colors.amber, fontSize: 12)),
                      ],
                    ),
                  ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white24),
            const SizedBox(height: 16),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Date', DateFormat('MMM dd, yyyy').format(note.sessionDate)),
                    _buildInfoRow('Duration', '${note.durationMinutes} minutes'),
                    _buildInfoRow('Risk Level', note.riskLevel.toUpperCase()),
                    if (note.mood != null) _buildInfoRow('Mood', note.mood!),
                    if (note.patientEngagement != null) 
                      _buildInfoRow('Engagement', '${note.patientEngagement}/10'),
                    if (note.progress != null) _buildInfoRow('Progress', note.progress!),
                    const SizedBox(height: 24),
                    
                    _buildSection('Chief Complaint', note.chiefComplaint),
                    _buildSection('Subjective', note.subjectiveNotes),
                    _buildSection('Objective', note.objectiveObservations),
                    _buildSection('Assessment', note.assessment),
                    _buildSection('Plan', note.plan),
                    if (note.interventionsUsed != null) 
                      _buildSection('Interventions Used', note.interventionsUsed!),
                    if (note.homeworkAssigned != null) 
                      _buildSection('Homework Assigned', note.homeworkAssigned!),
                    
                    if (note.suicidalIdeation || note.homicidalIdeation) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.riskRed.withValues(alpha: 0.1),
                          border: Border.all(color: AppTheme.riskRed),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '⚠️ Risk Indicators',
                              style: TextStyle(color: AppTheme.riskRed, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (note.suicidalIdeation) 
                              const Text('• Suicidal ideation present', style: TextStyle(color: Colors.white)),
                            if (note.homicidalIdeation) 
                              const Text('• Homicidal ideation present', style: TextStyle(color: Colors.white)),
                            if (note.riskNotes != null) ...[
                              const SizedBox(height: 8),
                              Text(note.riskNotes!, style: const TextStyle(color: Colors.white)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label:', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style:  TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }
}
