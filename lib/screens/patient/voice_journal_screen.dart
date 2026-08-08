import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';

class VoiceJournalScreen extends StatefulWidget {
  const VoiceJournalScreen({super.key});

  @override
  State<VoiceJournalScreen> createState() => _VoiceJournalScreenState();
}

class _VoiceJournalScreenState extends State<VoiceJournalScreen> {
  late final AudioRecorder _recorder;
  late final AudioPlayer _audioPlayer;
  late final DatabaseService _dbService;
  late final AuthService _authService;
  
  bool _isRecording = false;
  int _recordingDuration = 0;
  List<Map<String, dynamic>> _journals = [];
  String? _playingId;
  bool _isPlaying = false;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _dbService = DatabaseService();
    _authService = AuthService();
    _loadJournals();
  }

  Future<void> _startRecording() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice journaling is not available on web')),
      );
      return;
    }
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        
        // Create directory if it doesn't exist
        final journalDir = Directory('${dir.path}/voice_journals');
        if (!await journalDir.exists()) {
          await journalDir.create(recursive: true);
        }
        
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${journalDir.path}/journal_$timestamp.m4a';
        
        // Fixed RecordConfig for record v6.2.0
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
          path: path,
        );
        
        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
        });
        
        _startTimer();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
    } catch (e) {
      print('Recording error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      _stopTimer();
      
      setState(() => _isRecording = false);

      if (path != null) {
        final userId = _authService.currentUserId!;
        await _dbService.insertVoiceJournal(
          id: const Uuid().v4(),
          patientId: userId,
          filePath: path,
          transcription: 'User recorded voice entry at ${DateTime.now().toString()}',
          duration: _recordingDuration,
          date: DateTime.now().toIso8601String(),
          sentimentScore: 0.5,
        );
        
        _loadJournals();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Voice journal saved!'),
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

  Future<void> _loadJournals() async {
    try {
      final userId = _authService.currentUserId;
      if (userId != null) {
        final journals = await _dbService.getVoiceJournals(userId);
        if (!mounted) return;
        setState(() => _journals = journals);
      }
    } catch (e) {
      print('Error loading journals: $e');
    }
  }

  void _startTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRecording && mounted) {
        setState(() => _recordingDuration++);
      }
    });
  }

  void _stopTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Journal'),
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
                  Text(
                    '🎙️ Voice Journal',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share your thoughts and feelings',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Recording Interface
            Center(
              child: Column(
                children: [
                  // Record/Stop Button
                  GestureDetector(
                    onTap: _isRecording ? _stopRecording : _startRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            (_isRecording ? AppTheme.riskRed : AppTheme.primaryIndigo)
                                .withValues(alpha: 0.8),
                            (_isRecording ? AppTheme.riskRed : AppTheme.primaryIndigo)
                                .withValues(alpha: 0.3),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording
                                    ? AppTheme.riskRed
                                    : AppTheme.primaryIndigo)
                                .withValues(alpha: 0.5),
                            blurRadius: 30,
                            spreadRadius: _isRecording ? 10 : 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Timer
                  if (_isRecording)
                    Text(
                      '${(_recordingDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordingDuration % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.riskRed,
                        fontFamily: 'monospace',
                      ),
                    )
                  else
                    const Text(
                      'Tap to record',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white60,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Recent Entries
            if (_journals.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Entries',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ..._journals.take(5).map((journal) => AppCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _playJournal(journal['filePath'] ?? '', journal['id']),
                                  child: Icon(
                                    _playingId == journal['id'] && _isPlaying ? Icons.pause_circle : Icons.play_circle,
                                    color: AppTheme.primaryIndigo,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.mic, color: AppTheme.primaryIndigo, size: 20),
                              ],
                            ),
                            Text(
                              journal['date']?.toString().split('T')[0] ?? 'Unknown',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          journal['transcription'] ?? 'Voice journal entry',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '⏱️ ${journal['duration'] ?? 0}s',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopTimer();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playJournal(String filePath, String journalId) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playback is not available on web')),
      );
      return;
    }
    try {
      if (_playingId == journalId && _isPlaying) {
        // Stop playing
        await _audioPlayer.stop();
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _playingId = null;
        });
      } else {
        // Play the file
        if (filePath.isNotEmpty && File(filePath).existsSync()) {
          await _audioPlayer.play(DeviceFileSource(filePath));
          if (!mounted) return;
          setState(() {
            _isPlaying = true;
            _playingId = journalId;
          });
          
          _audioPlayer.onPlayerComplete.listen((_) {
            if (mounted) {
              setState(() {
                _isPlaying = false;
                _playingId = null;
              });
            }
          });
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audio file not found')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: $e')),
      );
    }
  }
}

