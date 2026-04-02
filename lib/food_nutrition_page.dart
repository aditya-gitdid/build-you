import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'food_log_page.dart';

// ── API Service ───────────────────────────────────────────────────────────────

class _ApiService {
  static String get _apiKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';

  static Future<String> sendMessage(
    String message, {
    Uint8List? imageBytes,
  }) async {
    try {
      if (_apiKey.isEmpty) {
        return 'API key not set. Please add OPENROUTER_API_KEY to your .env file.';
      }
      if (imageBytes == null && message.trim().isEmpty) {
        return 'Please upload a food image or ask a question.';
      }

      final List<Map<String, dynamic>> content = [];
      final String prompt;

      if (imageBytes != null) {
        prompt = '''
You are an expert fitness nutrition coach and food analyst.
Analyze the uploaded food image carefully and provide the FINAL answer in this format:

## Food Name
[answer]

## Estimated Calories
[answer]

## Protein
[answer]

## Carbohydrates
[answer]

## Fats
[answer]

## Fiber
[answer]

## Vitamins & Minerals
[answer]

## Health Benefits
[answer]

## Who Should Avoid
[answer]

## Best Time to Eat
[answer]

## Fitness / Diet Advice
[answer]

- Put EACH section on a NEW line with ONE empty line between sections.
- If this is NOT food, clearly say so.
- Return ONLY the final answer.

User question: ${message.trim().isNotEmpty ? message : "Analyze this food completely in English."}
''';
      } else {
        prompt = '''
You are an expert fitness nutrition coach.
Answer the user's question in a simple, friendly, and useful way.
You can help with diet plans, calories, protein, carbs, fats, vitamins, weight loss, weight gain, muscle gain, healthy eating, workout nutrition, meal timing, and Indian foods.
Keep the answer practical, neat, and easy to understand.
Return ONLY the final answer.

User question: $message
''';
      }

      content.add({'type': 'text', 'text': prompt});

      if (imageBytes != null) {
        content.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
          },
        });
      }

      final response = await http
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://yourapp.com',
              'X-Title': 'Fitness AI Coach',
            },
            body: jsonEncode({
              'model': imageBytes != null
                  ? 'google/gemini-2.0-flash-001'
                  : 'openrouter/auto',
              'messages': [
                {'role': 'user', 'content': content}
              ],
              'temperature': 0.3,
              'max_tokens': 1000,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final msg = data['choices']?[0]?['message'];
        String? text = msg?['content'];
        if (text == null || text.trim().isEmpty) text = msg?['reasoning'];
        if ((text == null || text.trim().isEmpty) &&
            msg?['reasoning_details'] is List) {
          text = (msg['reasoning_details'] as List)
              .map((e) => e['text']?.toString() ?? '')
              .join('\n');
        }
        if (text != null && text.trim().isNotEmpty) return _clean(text);
        return 'No response from AI.';
      } else if (response.statusCode == 429) {
        return 'AI is busy right now. Please try again in a few seconds.';
      } else {
        final err = data['error']?['message'] ?? 'Unknown error';
        return 'API Error: $err';
      }
    } catch (e) {
      return 'Something went wrong. Please check your internet and try again.';
    }
  }

  static Future<String> translate(String text, String lang) async {
    if (lang == 'English' || _apiKey.isEmpty) return text;
    try {
      final response = await http
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://yourapp.com',
              'X-Title': 'Fitness AI Coach',
            },
            body: jsonEncode({
              'model': 'openrouter/auto',
              'messages': [
                {
                  'role': 'user',
                  'content':
                      'Translate the following English text into proper $lang. Keep all numbers, units, food names, structure and formatting unchanged. Return ONLY the translated final answer.\n\nEnglish Text:\n$text',
                }
              ],
              'temperature': 0.2,
              'max_tokens': 1000,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final t = data['choices']?[0]?['message']?['content'] as String?;
        if (t != null && t.trim().isNotEmpty) return _clean(t);
      }
      return text;
    } catch (_) {
      return text;
    }
  }

  static String _clean(String text) {
    text = text.replaceAll(RegExp(r'^Okay,.*?\n', multiLine: false), '');
    text = text.replaceAll(RegExp(r'^Sure,.*?\n', multiLine: false), '');
    text = text.replaceAll(RegExp(r"^Let's.*?\n", multiLine: false), '');
    text = text.replaceAll(RegExp(r"^Here'?s.*?\n", multiLine: false), '');
    return text.trim();
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class FoodNutritionPage extends StatefulWidget {
  const FoodNutritionPage({super.key});

  @override
  State<FoodNutritionPage> createState() => _FoodNutritionPageState();
}

class _FoodNutritionPageState extends State<FoodNutritionPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final List<Map<String, dynamic>> _messages = [];

  File? _imageFile;
  Uint8List? _webImage;
  bool _isLoading = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;

  String _lang = 'English';
  final List<String> _langs = ['English', 'Hindi', 'Marathi'];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _messages.add({
      'text':
          '👋 Hi! I\'m your **Fitness AI Coach**.\n\nAsk me anything about food, nutrition, calories, or upload a food photo for instant analysis! 🥗',
      'isUser': false,
      'englishText': null,
      'selectedLanguage': 'English',
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _speech.stop();
    super.dispose();
  }

  String _locale(String lang) {
    switch (lang) {
      case 'Hindi': return 'hi_IN';
      case 'Marathi': return 'mr_IN';
      default: return 'en_IN';
    }
  }

  String _format(String text) {
    for (final h in [
      '## Food Name', '## Estimated Calories', '## Protein',
      '## Carbohydrates', '## Fats', '## Fiber',
      '## Vitamins & Minerals', '## Health Benefits',
      '## Who Should Avoid', '## Best Time to Eat',
      '## Fitness / Diet Advice',
    ]) {
      text = text.replaceAll(h, '\n\n$h');
    }
    return text.trim();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
          source: source, imageQuality: 80, maxWidth: 800, maxHeight: 800);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _webImage = bytes;
        _imageFile = kIsWeb ? null : File(picked.path);
      });
      await _analyzeImage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load image: $e')));
      }
    }
  }

  void _showImageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2A44),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFF3A4C68),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Color(0xFFFF6200)),
              title: const Text('Take a photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Color(0xFFFF6200)),
              title: const Text('Choose from gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _analyzeImage() async {
    if (_webImage == null) return;
    final bytes = _webImage!;
    final imgFile = _imageFile;
    final imgWeb = _webImage;

    setState(() {
      _messages.add({
        'isUser': true,
        'imageFile': imgFile,
        'webImage': imgWeb,
        'text': '',
      });
      _isLoading = true;
      _imageFile = null;
      _webImage = null;
    });
    _scrollToBottom();

    String eng = await _ApiService.sendMessage(
        'Analyze this food completely in English.',
        imageBytes: bytes);
    eng = _format(eng);

    String finalText = eng;
    if (_lang != 'English') {
      finalText = _format(await _ApiService.translate(eng, _lang));
    }

    if (mounted) {
      setState(() {
        _messages.add({
          'text': finalText,
          'englishText': eng,
          'isUser': false,
          'selectedLanguage': _lang,
          'isImageAnalysis': true,
          'rawAnalysis': eng,
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }
    _controller.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      _messages.add({'text': text, 'isUser': true});
      _isLoading = true;
    });
    _scrollToBottom();

    String eng = await _ApiService.sendMessage(text);
    eng = _format(eng);
    String finalText = eng;
    if (_lang != 'English') {
      finalText = _format(await _ApiService.translate(eng, _lang));
    }

    if (mounted) {
      setState(() {
        _messages.add({
          'text': finalText,
          'englishText': eng,
          'isUser': false,
          'selectedLanguage': _lang,
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _translateMsg(int index, String newLang) async {
    final eng = _messages[index]['englishText'];
    if (eng == null || eng.toString().trim().isEmpty) return;
    setState(() {
      _messages[index]['text'] = 'Translating...';
      _messages[index]['selectedLanguage'] = newLang;
    });
    final translated = newLang == 'English'
        ? eng.toString()
        : _format(await _ApiService.translate(eng.toString(), newLang));
    if (mounted) {
      setState(() {
        _messages[index]['text'] = translated;
        _messages[index]['selectedLanguage'] = newLang;
      });
    }
  }

  Future<void> _saveToLog(Map<String, dynamic> message) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final analysis = message['rawAnalysis'] as String? ?? message['englishText'] as String? ?? '';
    // Extract food name from first line of analysis
    final lines = analysis.split('\n').where((l) => l.trim().isNotEmpty).toList();
    String foodName = 'Food';
    for (final line in lines) {
      if (!line.startsWith('#') && line.trim().isNotEmpty) {
        foodName = line.trim().replaceAll('*', '').replaceAll('#', '').trim();
        if (foodName.length > 40) foodName = foodName.substring(0, 40);
        break;
      }
      if (line.contains('## Food Name')) {
        final idx = lines.indexOf(line);
        if (idx + 1 < lines.length) {
          foodName = lines[idx + 1].trim().replaceAll('*', '');
        }
        break;
      }
    }
    try {
      await FoodLogService.saveEntry(
        uid: uid,
        foodName: foodName,
        analysisText: analysis,
        date: DateTime.now(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Saved to Food Log!',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFF1B5E20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _toggleMic() async {
    if (!_isListening) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Microphone permission denied')));
        }
        return;
      }
      final available = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (_) => setState(() => _isListening = false),
      );
      if (available) {
        setState(() => _isListening = true);
        await _speech.listen(
          localeId: _locale(_lang),
          partialResults: true,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          listenMode: stt.ListenMode.dictation,
          onResult: (r) => setState(() {
            _controller.value = TextEditingValue(
              text: r.recognizedWords,
              selection: TextSelection.collapsed(
                  offset: r.recognizedWords.length),
            );
          }),
        );
      }
    } else {
      await _speech.stop();
      setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0715),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0715),
        elevation: 0,
        title: const Text('🥗 Food & Nutrition AI',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language, color: Colors.white),
            color: const Color(0xFF1A2A44),
            onSelected: (v) {
              setState(() => _lang = v);
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Language set to $v')));
            },
            itemBuilder: (_) => _langs
                .map((l) => PopupMenuItem(
                      value: l,
                      child: Text(l,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: l == _lang
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _Bubble(
                message: _messages[i],
                langs: _langs,
                onLangChanged: (l) => _translateMsg(i, l),
                onSaveToLog: _messages[i]['isImageAnalysis'] == true
                    ? () => _saveToLog(_messages[i])
                    : null,
              ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Column(children: [
                CircularProgressIndicator(color: Color(0xFFFF6200)),
                SizedBox(height: 6),
                Text('Analyzing / Thinking...',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          SafeArea(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: const Color(0xFF0F1A2E),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: Color(0xFFFF6200)),
                    onPressed: _isLoading
                        ? null
                        : () => _pickImage(ImageSource.camera),
                  ),
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined,
                        color: Color(0xFFFF6200)),
                    onPressed: _isLoading ? null : _showImageSheet,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_isLoading,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening...'
                            : 'Ask about food or nutrition...',
                        hintStyle:
                            const TextStyle(color: Color(0xFF8FA0BA)),
                        filled: true,
                        fillColor: const Color(0xFF1A2A44),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? Colors.red
                          : const Color(0xFFFF6200),
                    ),
                    onPressed: _isLoading ? null : _toggleMic,
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFFFF6200)),
                    onPressed: _isLoading ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat Bubble ───────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.langs,
    required this.onLangChanged,
    this.onSaveToLog,
  });

  final Map<String, dynamic> message;
  final List<String> langs;
  final void Function(String) onLangChanged;
  final VoidCallback? onSaveToLog;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message['isUser'] ?? false;
    final File? imgFile = message['imageFile'];
    final Uint8List? imgWeb = message['webImage'];
    final String selLang = message['selectedLanguage'] ?? 'English';
    final bool canTranslate = !isUser &&
        message['englishText'] != null &&
        message['englishText'].toString().trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (imgFile != null || imgWeb != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: kIsWeb
                    ? Image.memory(imgWeb!,
                        height: 180, width: 220, fit: BoxFit.cover)
                    : Image.file(imgFile!,
                        height: 180, width: 220, fit: BoxFit.cover),
              ),
            ),
          if ((message['text'] ?? '').toString().isNotEmpty)
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFF1A2A44),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canTranslate)
                    Align(
                      alignment: Alignment.topRight,
                      child: PopupMenuButton<String>(
                        tooltip: 'Change language',
                        color: const Color(0xFF2A2A2A),
                        icon: const Icon(Icons.language,
                            color: Colors.white70, size: 18),
                        onSelected: onLangChanged,
                        itemBuilder: (_) => langs
                            .map((l) => PopupMenuItem(
                                  value: l,
                                  child: Text(l,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: l == selLang
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                ))
                            .toList(),
                      ),
                    ),
                  if (isUser)
                    Text(message['text'] ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.5))
                  else
                    MarkdownBody(
                      data: message['text'] ?? '',
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.6),
                        strong: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                        h2: const TextStyle(
                            color: Color(0xFFFF8B2D),
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                        h3: const TextStyle(
                            color: Color(0xFFFF8B2D),
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                        listBullet: const TextStyle(
                            color: Colors.white, fontSize: 15),
                      ),
                    ),
                  // Save to Food Log button
                  if (!isUser &&
                      message['isImageAnalysis'] == true &&
                      onSaveToLog != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onSaveToLog,
                        icon: const Icon(Icons.save_alt_rounded,
                            size: 16),
                        label: const Text('Save to Food Log'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10)),
                          textStyle:
                              const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
