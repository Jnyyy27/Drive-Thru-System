import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceAssistantController extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _speechReady = false;
  bool _ttsReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String? _statusText;

  // Tracks the last partial result so the status-based fallback can fire it.
  String _lastWords = '';
  ValueChanged<String>? _pendingOnFinalResult;

  bool get speechReady => _speechReady;
  bool get ttsReady => _ttsReady;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String? get statusText => _statusText;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _speechReady = await _speech.initialize(
      onStatus: _handleSpeechStatus,
      onError: (error) {
        _isListening = false;
        _statusText = 'Voice input error: ${error.errorMsg}';
        notifyListeners();
      },
    );

    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      _tts.setStartHandler(() {
        _isSpeaking = true;
        _statusText = 'Speaking assistant reply...';
        notifyListeners();
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      _tts.setCancelHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      _tts.setErrorHandler((message) {
        _isSpeaking = false;
        _statusText = 'Voice output error: $message';
        notifyListeners();
      });
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }

    if (!_speechReady && !_ttsReady) {
      _statusText = 'Voice features are not available on this device.';
    }

    _initialized = true;
    notifyListeners();
  }

  Future<bool> startListening({
    required ValueChanged<String> onResult,
    ValueChanged<String>? onFinalResult,
  }) async {
    await initialize();
    if (!_speechReady) {
      // Retry initialization in case mic permission/state changed after first attempt.
      _initialized = false;
      await initialize();
    }
    if (!_speechReady) {
      _statusText = 'Speech recognition is not available.';
      notifyListeners();
      return false;
    }

    if (_isSpeaking) {
      await stopSpeaking();
    }

    _lastWords = '';
    _pendingOnFinalResult = onFinalResult;
    _statusText = 'Listening...';
    _isListening = true;
    notifyListeners();

    // Reset any stale speech session before starting a fresh listen.
    await _speech.cancel();

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        // Auto-end the listening session when user pauses speaking.
        pauseFor: const Duration(seconds: 4),
        // Hard cap each session so status done/notListening is guaranteed.
        listenFor: const Duration(seconds: 45),
      ),
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          _lastWords = result.recognizedWords;
        }
        onResult(result.recognizedWords);
        if (result.finalResult) {
          // result.finalResult path: fire and clear immediately.
          final cb = _pendingOnFinalResult;
          _pendingOnFinalResult = null;
          if (cb != null && _lastWords.trim().isNotEmpty) {
            cb(_lastWords);
          }
          _statusText = 'Voice message captured.';
          notifyListeners();
        }
      },
    );

    return true;
  }

  Future<void> stopListening() async {
    // Discard any pending auto-send when the user manually stops listening.
    _pendingOnFinalResult = null;
    if (_speech.isListening) {
      await _speech.stop();
    }
    _isListening = false;
    notifyListeners();
  }

  Future<bool> speak(String text) async {
    await initialize();
    if (!_ttsReady) {
      _statusText = 'Text-to-speech is not available.';
      notifyListeners();
      return false;
    }

    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      _statusText = 'No assistant reply available to read.';
      notifyListeners();
      return false;
    }

    if (_speech.isListening) {
      await stopListening();
    }

    await _tts.stop();
    await _tts.speak(cleaned);
    return true;
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  void clearStatus() {
    _statusText = null;
    notifyListeners();
  }

  void _handleSpeechStatus(String status) {
    if (status == 'listening') {
      _isListening = true;
    }
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      // Fallback: fire the pending callback if finalResult never came through.
      final cb = _pendingOnFinalResult;
      final words = _lastWords;
      _pendingOnFinalResult = null;
      if (cb != null && words.trim().isNotEmpty) {
        cb(words);
        _statusText = 'Voice message captured.';
      } else if (words.trim().isEmpty) {
        _statusText = 'No speech detected. Tap mic and try again.';
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }
}
