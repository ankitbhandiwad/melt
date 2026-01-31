import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

void main() {
  runApp(const AdvisorApp());
}

class AdvisorApp extends StatelessWidget {
  const AdvisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      fontFamily: 'Georgia',
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF1E3A5F),
        onPrimary: Colors.white,
        secondary: Color(0xFFE4572E),
        onSecondary: Colors.white,
        surface: Color(0xFFF6F1EA),
        onSurface: Color(0xFF1E1F23),
        error: Color(0xFFB00020),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF2ECE4),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      ),
    );

    return MaterialApp(
      title: 'Melt Advisor',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const SetupScreen(),
    );
  }
}

class UserProfile {
  const UserProfile({required this.language, required this.age});

  final String language;
  final int age;
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _ageController = TextEditingController(text: '25');
  String _language = 'English';
  bool _acceptedNotice = false;

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  void _continue() {
    final age = int.tryParse(_ageController.text.trim()) ?? 18;
    final profile = UserProfile(language: _language, age: age.clamp(7, 99));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvisorScreen(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF6EFE7), Color(0xFFE7D8C8)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text('Pocket Advisor', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Set up your profile so guidance matches your language and age.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preferred language', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _language,
                        items: const [
                          DropdownMenuItem(value: 'English', child: Text('English')),
                          DropdownMenuItem(value: 'Spanish', child: Text('Español')),
                          DropdownMenuItem(value: 'French', child: Text('Français')),
                          DropdownMenuItem(value: 'Mandarin', child: Text('中文')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _language = value);
                          }
                        },
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Your age', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Enter age',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: _acceptedNotice,
                            onChanged: (value) {
                              setState(() => _acceptedNotice = value ?? false);
                            },
                          ),
                          Expanded(
                            child: Text(
                              'I understand this is not legal advice and is for guidance only.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _acceptedNotice ? _continue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<AdvisorScreen> createState() => _AdvisorScreenState();
}

class _AdvisorScreenState extends State<AdvisorScreen> {
  final List<_TranscriptLine> _transcript = [];
  final List<String> _adviceHistory = [];
  final SpeechToText _speech = SpeechToText();
  final AdvisorService _advisorService = AdvisorService();
  bool _isRecording = false;
  bool _isSending = false;
  bool _speechAvailable = false;
  String _livePreview = '';
  String _lastFinalResult = '';
  String _lastContextFingerprint = '';
  String? _advisorError;
  List<_AdvisorSource> _sources = [];
  StreamSubscription? _linuxAudioSub;
  VoskFlutterPlugin? _vosk;
  Model? _voskModel;
  Recognizer? _voskRecognizer;
  bool _voskReady = false;
  bool _voskInitializing = false;

  static const int _voskSampleRate = 16000;

  final List<String> _keywords = [
    'police',
    'officer',
    'detained',
    'arrest',
    'weapon',
    'search',
    'traffic',
    'badge',
  ];

  @override
  void dispose() {
    _speech.stop();
    _linuxAudioSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    if (Platform.isLinux) {
      await _initVosk();
      return;
    }
    if (!_isSpeechSupported()) {
      setState(() {
        _speechAvailable = false;
        _livePreview = 'Speech recognition is not supported on this platform.';
      });
      return;
    }

    try {
      final available = await _speech.initialize(
        onError: (error) {
          setState(() {
            _isRecording = false;
            _livePreview = 'Speech error: ${error.errorMsg}';
          });
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening') {
            setState(() => _isRecording = false);
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = available);
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _livePreview = 'Speech plugin unavailable on this platform.';
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (Platform.isLinux) {
      await _toggleLinuxRecording();
      return;
    }
    if (_isRecording) {
      await _speech.stop();
      setState(() {
        _isRecording = false;
        _livePreview = '';
      });
      return;
    }

    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) {
        setState(() => _livePreview = 'Speech recognition not available.');
        return;
      }
    }

    final localeId = _localeForLanguage(widget.profile.language);
    final started = await _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: localeId,
      listenMode: ListenMode.dictation,
    );

    if (!mounted) return;
    setState(() {
      _isRecording = started;
      _livePreview = started ? '' : 'Unable to start listening.';
    });
  }

  void _onSpeechResult(dynamic result) {
    final words = (result.recognizedWords ?? '').toString().trim();
    if (words.isEmpty) return;

    final bool isFinal = result.finalResult == true;
    if (isFinal) {
      if (words == _lastFinalResult) return;
      _lastFinalResult = words;
      setState(() => _livePreview = '');
      _addTranscript(words);
    } else {
      setState(() => _livePreview = words);
    }
  }

  String _localeForLanguage(String language) {
    switch (language) {
      case 'Spanish':
        return 'es_ES';
      case 'French':
        return 'fr_FR';
      case 'Mandarin':
        return 'zh_CN';
      default:
        return 'en_US';
    }
  }

  bool _isSpeechSupported() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isLinux;
  }

  Future<void> _initVosk() async {
    if (_voskReady || _voskInitializing) return;
    _voskInitializing = true;
    try {
      _vosk = VoskFlutterPlugin.instance();
      final loader = ModelLoader();
      final modelPath = await loader.loadFromAssets(_voskModelAsset());
      _voskModel = await _vosk!.createModel(modelPath);
      _voskRecognizer = await _vosk!.createRecognizer(
        model: _voskModel!,
        sampleRate: _voskSampleRate,
      );
      _voskReady = true;
      setState(() {
        _speechAvailable = true;
        _livePreview = widget.profile.language == 'English'
            ? ''
            : 'Linux speech uses an English model unless you add another.';
      });
    } catch (error) {
      final text = error.toString();
      final missingAsset = text.contains('Unable to load asset') ||
          text.contains('No such file') ||
          text.contains('not found');
      setState(() {
        _speechAvailable = false;
        _livePreview = missingAsset
            ? 'Missing Vosk model asset at ${_voskModelAsset()}.'
            : 'Vosk init error: $error';
      });
    } finally {
      _voskInitializing = false;
    }
  }

  Future<void> _toggleLinuxRecording() async {
    if (_isRecording) {
      await _stopLinuxRecording();
      setState(() {
        _isRecording = false;
        _livePreview = '';
      });
      return;
    }

    if (!_voskReady) {
      await _initVosk();
      if (!_voskReady) {
        setState(() => _livePreview = 'Vosk is not ready.');
        return;
      }
    }

    try {
      await Recorder.instance.init(
        format: PCMFormat.s16le,
        sampleRate: _voskSampleRate,
        channels: RecorderChannels.mono,
      );
      Recorder.instance.start();
      Recorder.instance.startStreamingData();

      _linuxAudioSub?.cancel();
      _linuxAudioSub = Recorder.instance.uint8ListStream.listen(
        (data) async {
          final bytes = Uint8List.fromList(data.rawData);
          final ready = await _voskRecognizer!.acceptWaveformBytes(bytes);
          if (ready) {
            final result = await _voskRecognizer!.getResult();
            _handleVoskResult(result, isFinal: true);
          } else {
            final partial = await _voskRecognizer!.getPartialResult();
            _handleVoskResult(partial, isFinal: false);
          }
        },
        onError: (error) {
          setState(() => _livePreview = 'Audio stream error: $error');
        },
      );

      setState(() {
        _isRecording = true;
        _livePreview = 'Listening…';
      });
    } catch (error) {
      setState(() => _livePreview = 'Recorder error: $error');
    }
  }

  Future<void> _stopLinuxRecording() async {
    await _linuxAudioSub?.cancel();
    _linuxAudioSub = null;
    try {
      Recorder.instance.stopStreamingData();
      Recorder.instance.stop();
    } catch (_) {}
  }

  void _handleVoskResult(String jsonString, {required bool isFinal}) {
    final text = _extractVoskText(jsonString, isFinal: isFinal);
    if (text.isEmpty) return;
    if (isFinal) {
      if (text == _lastFinalResult) return;
      _lastFinalResult = text;
      setState(() => _livePreview = '');
      _addTranscript(text);
    } else {
      setState(() => _livePreview = text);
    }
  }

  String _extractVoskText(String jsonString, {required bool isFinal}) {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final key = isFinal ? 'text' : 'partial';
      return (decoded[key] ?? '').toString().trim();
    } catch (_) {
      return jsonString.trim();
    }
  }

  String _voskModelAsset() {
    if (widget.profile.language != 'English') {
      return 'assets/models/vosk-model-small-en-us-0.15.zip';
    }
    return 'assets/models/vosk-model-small-en-us-0.15.zip';
  }

  void _addTranscript(String text) {
    setState(() {
      _transcript.insert(0, _TranscriptLine(DateTime.now(), text));
    });

    final lower = text.toLowerCase();
    if (_keywords.any(lower.contains)) {
      _sendToAdvisor();
    }
  }

  Future<void> _sendToAdvisor() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 5));
    final recentLines = _transcript
        .where((line) => line.time.isAfter(cutoff))
        .map((line) => line.text)
        .toList();
    final contextLines = recentLines.isNotEmpty
        ? recentLines
        : _transcript.take(8).map((e) => e.text).toList();
    final fingerprint = contextLines.join('|');
    if (fingerprint == _lastContextFingerprint) {
      setState(() => _isSending = false);
      return;
    }
    _lastContextFingerprint = fingerprint;

    final result = await _advisorService.getAdvice(
      profile: widget.profile,
      contextLines: contextLines,
    );

    setState(() {
      if (result.error != null) {
        _advisorError = result.error;
      } else {
        _advisorError = null;
        _adviceHistory.insert(0, result.advice);
        _sources = result.sources;
      }
      _isSending = false;
    });
  }

  String _buildAdvice(List<String> contextLines) {
    final language = widget.profile.language;
    final isMinor = widget.profile.age < 18;
    final base = isMinor
        ? 'Stay calm. Keep your hands visible. Say, "I want a parent or guardian here."'
        : 'Stay calm. Keep your hands visible. Ask, "Am I free to leave?" and say you do not consent to searches.';
    final extra =
        'Repeat your name and confirm you will follow instructions while staying silent about details.';

    final translated = _translate(language, '$base $extra');
    final summary = contextLines.reversed.join(' • ');
    return '$translated\n\nRecent context: $summary';
  }

  String _translate(String language, String message) {
    if (language == 'Spanish') {
      return 'Mantén la calma. Mantén las manos visibles. Pregunta: "¿Estoy libre para irme?" y di que no consientes registros. Repite tu nombre y sigue instrucciones sin hablar de detalles.';
    }
    if (language == 'French') {
      return 'Reste calme. Garde tes mains visibles. Demande: "Suis-je libre de partir ?" et dis que tu ne consens pas aux fouilles. Répète ton nom et suis les instructions sans donner de détails.';
    }
    if (language == 'Mandarin') {
      return '保持冷静，双手可见。询问：“我可以离开吗？”并表示不同意搜查。重复姓名，遵从指令，但不谈细节。';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastAdvice = _adviceHistory.isNotEmpty ? _adviceHistory.first : null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2ECE4), Color(0xFFE9DBCC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Advisor Live',
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    _RecordingPulse(active: _isRecording),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Panel(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Profile', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.profile.language} · Age ${widget.profile.age}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      FilledButton(
                        onPressed: _toggleRecording,
                        style: FilledButton.styleFrom(
                          backgroundColor: _isRecording
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        child: Text(_isRecording ? 'Stop' : 'Start recording'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Panel(
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Guidance only. If you need emergency help, call local emergency services.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Live transcript', style: theme.textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _transcript.isEmpty && _livePreview.isEmpty
                                    ? Center(
                                        child: Text(
                                          _isRecording
                                              ? 'Listening…'
                                              : 'Press start to capture audio.',
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      )
                                    : Builder(
                                        builder: (context) {
                                          final displayLines = [
                                            if (_livePreview.isNotEmpty)
                                              _TranscriptLine(
                                                DateTime.now(),
                                                _livePreview,
                                                isPartial: true,
                                              ),
                                            ..._transcript,
                                          ];
                                          return ListView.separated(
                                            itemCount: displayLines.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 12),
                                            itemBuilder: (context, index) {
                                              final line = displayLines[index];
                                              return _TranscriptTile(line: line);
                                            },
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Advisor', style: theme.textTheme.titleMedium),
                                  const SizedBox(width: 8),
                                  if (_isSending)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: _advisorError != null
                                      ? Center(
                                          child: Text(
                                            _advisorError!,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(color: theme.colorScheme.error),
                                          ),
                                        )
                                      : lastAdvice == null
                                          ? Center(
                                              child: Text(
                                                'Waiting for key phrases…',
                                                style: theme.textTheme.bodyMedium,
                                              ),
                                            )
                                          : SingleChildScrollView(
                                              key: ValueKey(lastAdvice),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    lastAdvice,
                                                    style: theme.textTheme.bodyLarge,
                                                  ),
                                                  if (_sources.isNotEmpty) ...[
                                                    const SizedBox(height: 12),
                                                    Text(
                                                      'Sources',
                                                      style: theme.textTheme.titleMedium,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    for (final source in _sources)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(bottom: 6),
                                                        child: _SourceLink(source: source),
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                ),
                              ),
                              if (_adviceHistory.length > 1) ...[
                                const Divider(height: 24),
                                Text('Earlier guidance', style: theme.textTheme.bodyMedium),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    itemCount: _adviceHistory.length - 1,
                                    itemBuilder: (context, index) {
                                      final entry = _adviceHistory[index + 1];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          entry.split('\n').first,
                                          style: theme.textTheme.bodyMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    },
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
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.source});

  final _AdvisorSource source;

  Future<void> _open() async {
    final uri = Uri.tryParse(source.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: _open,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
      ),
      child: Text(
        '${source.title} — ${source.url}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RecordingPulse extends StatefulWidget {
  const _RecordingPulse({required this.active});

  final bool active;

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didUpdateWidget(covariant _RecordingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final double scale =
            widget.active ? 1.0 + (_controller.value * 0.2) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: widget.active ? theme.colorScheme.secondary : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class _TranscriptLine {
  const _TranscriptLine(this.time, this.text, {this.isPartial = false});

  final DateTime time;
  final String text;
  final bool isPartial;
}

class _TranscriptTile extends StatelessWidget {
  const _TranscriptTile({required this.line});

  final _TranscriptLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = '${line.time.hour.toString().padLeft(2, '0')}:'
        '${line.time.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: line.isPartial ? const Color(0xFFF1E4D6) : const Color(0xFFF9F5F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            line.text,
            style: line.isPartial
                ? theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)
                : theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _AdvisorSource {
  const _AdvisorSource({required this.title, required this.url});

  final String title;
  final String url;
}

class AdvisorResult {
  const AdvisorResult({
    required this.advice,
    required this.sources,
    this.error,
  });

  final String advice;
  final List<_AdvisorSource> sources;
  final String? error;
}

class AdvisorService {
  static const String _defaultBaseUrl = 'https://api.openai.com/v1/responses';
  static const String _defaultModel = 'gpt-4o';

  final String _apiKey =
      const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  final String _baseUrl =
      const String.fromEnvironment('OPENAI_API_BASE', defaultValue: _defaultBaseUrl);
  final String _model =
      const String.fromEnvironment('OPENAI_MODEL', defaultValue: _defaultModel);

  Future<AdvisorResult> getAdvice({
    required UserProfile profile,
    required List<String> contextLines,
  }) async {
    if (_apiKey.isEmpty) {
      return const AdvisorResult(
        advice: '',
        sources: [],
        error: 'Missing OPENAI_API_KEY. Provide --dart-define=OPENAI_API_KEY=...',
      );
    }

    final isMinor = profile.age < 18;
    final instructions = _buildInstructions(profile, isMinor);
    final input = _buildInput(profile, contextLines);

    final payload = <String, dynamic>{
      'model': _model,
      'instructions': instructions,
      'input': input,
      'temperature': 0.2,
      'max_output_tokens': 320,
      'parallel_tool_calls': false,
      'max_tool_calls': 1,
      'tools': [
        {'type': 'web_search'},
      ],
      'include': ['web_search_call.action.sources'],
    };

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AdvisorResult(
          advice: '',
          sources: const [],
          error: 'OpenAI error ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final advice = _extractOutputText(data) ?? 'No response text.';
      final sources = _extractSources(data);

      return AdvisorResult(advice: advice, sources: sources);
    } catch (error) {
      return AdvisorResult(
        advice: '',
        sources: const [],
        error: 'Network error: $error',
      );
    }
  }

  String _buildInstructions(UserProfile profile, bool isMinor) {
    final tone = isMinor ? 'simple, calm, short sentences' : 'clear and direct';
    return 'You are a fast safety advisor for Michigan, USA. '
        'Use web search to identify relevant Michigan laws and procedures. '
        'Respond in ${profile.language}. '
        'Keep advice brief and actionable, focused on immediate rights and safety. '
        'Tone: $tone. '
        'Include a short disclaimer: not legal advice. '
        'If the user appears in danger, say to call local emergency services.';
  }

  String _buildInput(UserProfile profile, List<String> contextLines) {
    final context = contextLines.join('\n');
    return 'Context transcript (last 5 minutes):\n$context\n\n'
        'Task: identify applicable Michigan laws/procedures and give immediate steps '
        'the user can take right now. Prefer quick response time and avoid long explanations.';
  }

  String? _extractOutputText(Map<String, dynamic> data) {
    if (data['output_text'] is String) {
      return data['output_text'] as String;
    }
    final output = data['output'];
    if (output is List) {
      final buffer = StringBuffer();
      for (final item in output) {
        if (item is Map<String, dynamic> &&
            item['type'] == 'message' &&
            item['content'] is List) {
          for (final content in item['content'] as List) {
            if (content is Map<String, dynamic> && content['type'] == 'output_text') {
              buffer.writeln(content['text']);
            }
          }
        }
      }
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  List<_AdvisorSource> _extractSources(Map<String, dynamic> data) {
    final output = data['output'];
    if (output is! List) return const [];
    final sources = <_AdvisorSource>[];
    for (final item in output) {
      if (item is Map<String, dynamic> && item['type'] == 'web_search_call') {
        final action = item['action'];
        final actionSources = action is Map<String, dynamic> ? action['sources'] : null;
        if (actionSources is List) {
          for (final source in actionSources) {
            if (source is Map<String, dynamic>) {
              final title = source['title']?.toString() ?? 'Source';
              final url = source['url']?.toString() ?? '';
              if (url.isNotEmpty) {
                sources.add(_AdvisorSource(title: title, url: url));
              }
            }
          }
        }
      }
    }
    return sources;
  }
}
