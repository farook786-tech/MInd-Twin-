import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/backend_api_service.dart';
import '../../core/theme/app_theme.dart';

class BackendConfigScreen extends StatefulWidget {
  final VoidCallback? onConfigComplete;
  
  const BackendConfigScreen({super.key, this.onConfigComplete});

  @override
  State<BackendConfigScreen> createState() => _BackendConfigScreenState();
}

class _BackendConfigScreenState extends State<BackendConfigScreen> {
  final BackendApiService _apiService = BackendApiService();
  final TextEditingController _urlController = TextEditingController();
  bool _isDetecting = false;
  bool _isTestingConnection = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final saved = await _apiService.getManualBaseUrl();
    if (saved != null) {
      _urlController.text = saved;
    }
  }

  Future<void> _autoDetect() async {
    setState(() {
      _isDetecting = true;
      _statusMessage = null;
      _isSuccess = false;
    });

    try {
      final detected = await _apiService.autoDetectAndSaveBackendUrl();
      if (detected != null) {
        setState(() {
          _urlController.text = detected;
          _statusMessage = '✅ Auto-detected: $detected';
          _isSuccess = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Backend auto-detected: $detected'),
              backgroundColor: AppTheme.safeGreen,
            ),
          );
        }
      } else {
        setState(() {
          _statusMessage = '❌ Could not auto-detect backend. Please enter manually.';
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Auto-detection error: $e';
        _isSuccess = false;
      });
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  Future<void> _testConnection() async {
    if (_urlController.text.isEmpty) {
      setState(() {
        _statusMessage = '❌ Please enter a backend URL';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _statusMessage = null;
      _isSuccess = false;
    });

    try {
      final ok = await _apiService.testConnection(baseUrl: _urlController.text);
      if (ok) {
        await _apiService.setManualBaseUrl(_urlController.text);
        setState(() {
          _statusMessage = '✅ Connection successful! Backend saved.';
          _isSuccess = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Backend configured successfully'),
              backgroundColor: Color(0xFF22c55e),
            ),
          );
        }
      } else {
        setState(() {
          _statusMessage =
              '❌ Connection failed. Check your URL and ensure backend is running.';
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Connection error: $e';
        _isSuccess = false;
      });
    } finally {
      setState(() {
        _isTestingConnection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Configuration'),
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                border: Border.all(color: AppTheme.primaryIndigo.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connect to MindTwin Backend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb
                        ? 'Web browsers cannot auto-detect the backend. Please enter your backend IP/URL manually.'
                        : 'Choose how you want to connect to your backend server.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Auto-detect button (skip on web)
            if (!kIsWeb) ...[
              const Text(
                'Option 1: Auto-Detect (Recommended)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isDetecting ? null : _autoDetect,
                  icon: _isDetecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.radar),
                  label: Text(
                    _isDetecting ? 'Detecting...' : 'Auto-Detect Backend',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Option 2: Manual Entry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else
              const Text(
                'Enter Backend URL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 12),

            // URL input field
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'http://192.168.1.100:5000',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                labelText: 'Backend URL',
                labelStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(Icons.link, color: Colors.white70),
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Help text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info, color: Colors.lightBlue, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Examples:',
                        style: TextStyle(
                          color: Colors.lightBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Local Network: http://192.168.1.100:5000\n'
                    '• Localhost: http://localhost:5000\n'
                    '• Cloud URL: https://api.mindtwin.app',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Status message
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? AppTheme.safeGreen.withValues(alpha: 0.1)
                      : AppTheme.riskRed.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isSuccess
                        ? AppTheme.safeGreen.withValues(alpha: 0.5)
                        : AppTheme.riskRed.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _isSuccess ? Colors.green[300] : Colors.red[300],
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Test & Save button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isTestingConnection || _urlController.text.isEmpty
                    ? null
                    : _testConnection,
                icon: _isTestingConnection
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  _isTestingConnection ? 'Testing...' : 'Test & Save Configuration',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.safeGreen,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Close button
            if (_isSuccess)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    widget.onConfigComplete?.call();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
