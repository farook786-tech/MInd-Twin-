import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';

class EthicsControlScreen extends StatefulWidget {
  const EthicsControlScreen({super.key});

  @override
  State<EthicsControlScreen> createState() => _EthicsControlScreenState();
}

class _EthicsControlScreenState extends State<EthicsControlScreen> {
  late final DatabaseService _dbService;
  late final AuthService _authService;
  late final BackendApiService _backendApiService;
  final TextEditingController _backendUrlController = TextEditingController();
  
  bool _hipaaCompliantSharing = true;
  bool _federatedResearch = false;
  bool _anonymousDataSharing = true;
  bool _thirdPartyAnalytics = false;
  bool _isLoading = false;
  bool _isTestingBackend = false;
  bool _isAutoDetectingBackend = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _dbService = DatabaseService();
    _authService = AuthService();
    _backendApiService = BackendApiService();
    _loadPrivacySettings();
    _loadBackendUrl();
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadBackendUrl() async {
    final manual = await _backendApiService.getManualBaseUrl();
    if (!mounted) return;
    _backendUrlController.text = manual ?? '';
  }

  Future<void> _saveAndTestBackendUrl() async {
    final raw = _backendUrlController.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Enter backend URL like http://192.168.1.10:5000';
      });
      return;
    }

    setState(() {
      _isTestingBackend = true;
      _statusMessage = null;
    });

    await _backendApiService.setManualBaseUrl(raw);
    final ok = await _backendApiService.testConnection(baseUrl: raw);

    if (!mounted) return;
    setState(() {
      _isTestingBackend = false;
      _statusMessage = ok
          ? 'Cloud backend connected successfully.'
          : 'Could not reach backend. Ensure phone and server are on same Wi-Fi and URL is correct.';
    });
  }

  Future<void> _autoDetectBackendUrl() async {
    setState(() {
      _isAutoDetectingBackend = true;
      _statusMessage = 'Scanning local network for MindTwin backend...';
    });

    final detected = await _backendApiService.autoDetectAndSaveBackendUrl();

    if (!mounted) return;
    setState(() {
      _isAutoDetectingBackend = false;
      if (detected != null) {
        _backendUrlController.text = detected;
        _statusMessage = 'Backend auto-detected and saved: $detected';
      } else {
        _statusMessage = 'Auto-detect failed. Enter URL manually (example: http://192.168.1.10:5000).';
      }
    });
  }

  Future<void> _loadPrivacySettings() async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _hipaaCompliantSharing = prefs.getBool('privacy_${userId}_hipaa') ?? true;
      _federatedResearch = prefs.getBool('privacy_${userId}_federated') ?? false;
      _anonymousDataSharing = prefs.getBool('privacy_${userId}_anonymous') ?? true;
      _thirdPartyAnalytics = prefs.getBool('privacy_${userId}_analytics') ?? false;
    });
  }

  Future<void> _savePrivacySettings() async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_${userId}_hipaa', _hipaaCompliantSharing);
    await prefs.setBool('privacy_${userId}_federated', _federatedResearch);
    await prefs.setBool('privacy_${userId}_anonymous', _anonymousDataSharing);
    await prefs.setBool('privacy_${userId}_analytics', _thirdPartyAnalytics);

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Preferences saved. Sharing rules are now active for this account.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Ethics'),
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.security,
                      size: 40,
                      color: Color(0xFF6366f1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your Data, Your Choice',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Control how your data is used and shared',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Data Controls Section
            Text(
              'Data Sharing Preferences',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // HIPAA Compliant Sharing
            _buildControlCard(
              title: 'HIPAA-Compliant Sharing',
              description: 'Share data with your care team following HIPAA',
              value: _hipaaCompliantSharing,
              onChanged: (value) {
                setState(() => _hipaaCompliantSharing = value);
                _savePrivacySettings();
              },
              icon: Icons.health_and_safety,
              recommended: true,
            ),
            const SizedBox(height: 12),

            // Federated Research
            _buildControlCard(
              title: 'Federated Research',
              description: 'Help improve AI while keeping data private',
              value: _federatedResearch,
              onChanged: (value) {
                setState(() => _federatedResearch = value);
                _savePrivacySettings();
              },
              icon: Icons.science,
              recommended: false,
            ),
            const SizedBox(height: 12),

            // Anonymous Data Sharing
            _buildControlCard(
              title: 'Anonymous Sharing',
              description: 'Share fully anonymized insights for research',
              value: _anonymousDataSharing,
              onChanged: (value) {
                setState(() => _anonymousDataSharing = value);
                _savePrivacySettings();
              },
              icon: Icons.cloud_upload,
              recommended: false,
            ),
            const SizedBox(height: 12),

            // Third Party Analytics
            _buildControlCard(
              title: 'Third-Party Analytics',
              description: 'Allow usage data collection for app improvement',
              value: _thirdPartyAnalytics,
              onChanged: (value) {
                setState(() => _thirdPartyAnalytics = value);
                _savePrivacySettings();
              },
              icon: Icons.analytics,
              recommended: false,
            ),
            const SizedBox(height: 32),

            if (_statusMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.safeGreen.withValues(alpha: 0.12),
                  border: Border.all(color: AppTheme.safeGreen.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),

            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cloud Sync Server URL',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _backendUrlController,
                    decoration: const InputDecoration(
                      hintText: 'http://192.168.1.10:5000',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isTestingBackend ? null : _saveAndTestBackendUrl,
                      icon: _isTestingBackend
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_done),
                      label: Text(_isTestingBackend ? 'Testing...' : 'Save & Test Connection'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isAutoDetectingBackend ? null : _autoDetectBackendUrl,
                      icon: _isAutoDetectingBackend
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                      label: Text(
                        _isAutoDetectingBackend
                            ? 'Detecting...'
                            : 'Auto Detect Server',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Data Rights Section
            Text(
              'Your Rights',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Export Data
            _buildActionButton(
              icon: Icons.download,
              title: 'Download Total Data (PDF)',
              description: 'Generate a complete PDF summary of your records',
              onPressed: _downloadTotalDataPdf,
              color: AppTheme.safeGreen,
              isLoading: _isLoading,
            ),
            const SizedBox(height: 12),

            // View Privacy Policy
            _buildActionButton(
              icon: Icons.description,
              title: 'Privacy Policy',
              description: 'Read our full privacy policy and terms',
              onPressed: _showPrivacyPolicy,
              color: AppTheme.primaryIndigo,
              isLoading: false,
            ),
            const SizedBox(height: 12),

            // Delete Data
            _buildActionButton(
              icon: Icons.delete_forever,
              title: 'Delete All Data',
              description: 'Permanently remove all your data',
              onPressed: _deleteData,
              color: AppTheme.riskRed,
              isLoading: false,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required bool recommended,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryIndigo),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (recommended)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.safeGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RECOMMENDED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF22c55e),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primaryIndigo,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onPressed,
    required Color color,
    required bool isLoading,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadTotalDataPdf() async {
    setState(() => _isLoading = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      final logs = await _dbService.getDailyLogs(userId);
      final journals = await _dbService.getVoiceJournals(userId);
      final alerts = await _dbService.getCrisisAlerts(userId);

      final pdf = pw.Document();
      final generatedAt = DateTime.now();

      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('MindTwin Patient Data Export', style: const pw.TextStyle(fontSize: 22)),
            ),
            pw.Text('Generated: ${generatedAt.toIso8601String()}'),
            pw.Text('User ID: $userId'),
            pw.SizedBox(height: 10),
            pw.Text('Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Bullet(text: 'Daily Logs: ${logs.length}'),
            pw.Bullet(text: 'Voice Journals: ${journals.length}'),
            pw.Bullet(text: 'Crisis Alerts: ${alerts.length}'),
            pw.SizedBox(height: 16),
            pw.Text('Daily Logs', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (logs.isEmpty)
              pw.Text('No daily logs found.')
            else
              ...logs.take(200).map(
                (log) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(
                    '${log.date}: mood ${log.moodScore.toStringAsFixed(1)}, anxiety ${log.anxietyLevel.toStringAsFixed(1)}, sleep ${log.sleepHours.toStringAsFixed(1)}h, wellbeing ${log.wellbeingScore.toStringAsFixed(1)}',
                  ),
                ),
              ),
            pw.SizedBox(height: 16),
            pw.Text('Voice Journals', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (journals.isEmpty)
              pw.Text('No voice journals found.')
            else
              ...journals.take(200).map(
                (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(
                    '${entry['date'] ?? entry['timestamp'] ?? 'Unknown date'}: duration ${entry['duration'] ?? '-'} sec, sentiment ${entry['sentimentScore'] ?? '-'}',
                  ),
                ),
              ),
            pw.SizedBox(height: 16),
            pw.Text('Crisis Alerts', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (alerts.isEmpty)
              pw.Text('No crisis alerts found.')
            else
              ...alerts.take(200).map(
                (alert) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Text(
                    '${alert.timestamp.toIso8601String()}: ${alert.severity.toUpperCase()} - ${alert.reason} (${alert.status})',
                  ),
                ),
              ),
          ],
        ),
      );
      
      // Get the application's document directory
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'mindtwin_total_data_$timestamp.pdf';
      final filePath = '${appDir.path}/$fileName';
      
      // Create and write the file
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      
      // Save export date to database
      await _dbService.setDataExportDate(userId);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ PDF downloaded: $fileName'),
            backgroundColor: AppTheme.safeGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ PDF export error: $e'),
            backgroundColor: AppTheme.riskRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteData() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text(
          '⚠️ Delete All Data?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete all your data. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFef4444))),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);
      
      final userId = _authService.currentUserId;
      if (userId == null) throw Exception('Not authenticated');

      // Delete only current user data
      await _dbService.deleteUserData(userId);
      await _dbService.setDataDeleteDate(userId);
      
      // Logout
      await _authService.logout();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ All data deleted. Goodbye!'),
            backgroundColor: Color(0xFFef4444),
          ),
        );
        
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text(
          'Privacy Policy',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '🔒 Your Privacy Matters',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '''MindTwin is committed to protecting your privacy:

• Your health data is YOUR property
• We never sell your data
• End-to-end encryption for transmissions
• Local-first storage architecture
• HIPAA & GDPR compliant
• Right to deletion & portability
• Regular security audits
• Transparent data practices

Contact: privacy@mindtwin.ai''',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
