import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class FoodNutritionPage extends StatefulWidget {
  const FoodNutritionPage({super.key});

  @override
  State<FoodNutritionPage> createState() => _FoodNutritionPageState();
}

class _FoodNutritionPageState extends State<FoodNutritionPage> {
  // ── API ───────────────────────────────────────────────────────────────────
  static const String _apiKey =
      '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';

  // ── State ─────────────────────────────────────────────────────────────────
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  File? _imageFile;
  Uint8List? _webImage;

  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;

  String _selectedLanguage = 'English';
  final List<String> _languages = ['English', 'Hindi', 'Marathi'];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    // Welcome message
    _messages.add({
      'text': '👋 Hi! I\'m your **Fitness AI Coach**.\n\nAsk me anything about food, nutrition, calories, diet plans, or upload a food photo for instant analysis! 🥗',
      'isUser': false,
      'englishText': null,
      'selectedLanguage': 'English',
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _speechLocale(String lang) {
    switch (lang) {
      case 'Hindi': return 'hi_IN';
      case 'Marathi': return 'mr_IN';
      default: return 'en_IN';
    }
  }

  String _formatText(String text) {
    for (final h in [
      '## Food Name', '## Estimated Calories', '## Protein',
      '## Carbohydrates', '## Fats', '## Fiber', '## Vitamins',
      '## Minerals', '## Health Benefits', '## Who Should Eat This',
      '## Who Should Avoid or Limit This', '## Best Time to Eat',
      '## Fitness / Diet Advice',
    ]) {
      text = text.replaceAll(h, '\n\n$h');
    }
    return text.trim();
  }

  String _cleanResponse(String text) {
    text = text.replaceAll(RegExp(r'^Okay,.*?\n', multiLine: false), '');
    text = text.replaceAll(RegExp(r'^Sure,.*?\n', multiLine: false), '');
    text = text.replaceAll(RegExp(r"^Let's.*?\n", multiLine: false), '');
    text = text.replaceAll(RegExp(r"^Here'?s.*?\n", multiLine: false), '');
    return text.trim();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── API calls ─────────────────────────────────────────────────────────────

  Future<String> _callApi(List<Map<String, dynamic>> content,
      {double temperature = 0.3}) async {
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
                {'role': 'user', 'content': content}
              ],
              'temperature': temperature,
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
        if (text != null && text.trim().isNotEmpty) {
          return _cleanResponse(_formatText(text));
        }
        return 'No response from AI.';
      } else if (response.statusCode == 429) {
        return 'AI is busy right now. Please try again in a few seconds.';
      } else {
        return 'API Error: ${data['error']?['message'] ?? 'Unknown error'}';
      }
    } catch (e) {
      return 'Something went wrong. Please check your internet and try again.';
    }
  }

  Future<String> _translate(String text, String lang) async {
    if (lang == 'English') return text;
    final prompt = '''
You are a professional translator for food, nutrition, and fitness content.
Translate the following English text into proper $lang.
Keep all numbers, units (kcal, g, mg), and food names unchanged.
Keep the exact same structure and formatting.
Return ONLY the translated final answer.

English Text:
$text
''';
    return _callApi([
      {'type': 'text', 'text': prompt}
    ], temperature: 0.2);
  }

  // ── Image picking ─────────────────────────────────────────────────────────

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
          SnackBar(content: Text('Failed to load image: $e')),
        );
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
                  borderRadius: BorderRadius.circular(2)),
            ),
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

  // ── Send / Analyze ────────────────────────────────────────────────────────

  Future<void> _analyzeImage() async {
    if (_webImage == null) return;
    final imageBytes = _webImage!;
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

    final base64Image = base64Encode(imageBytes);
    final prompt = '''
You are an expert fitness nutrition coach and food analyst.
Analyze the uploaded food image carefully and provide the answer in this format:

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

## Health Benefits
[answer]

## Fitness / Diet Advice
[answer]

Keep it clean, structured, and easy to read.
Reply only in English.
''';

    final content = [
      {'type': 'text', 'text': prompt},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
      },
    ];

    final englishResponse = await _callApi(content);
    String finalResponse = englishResponse;
    if (_selectedLanguage != 'English') {
      finalResponse = await _translate(englishResponse, _selectedLanguage);
    }

    if (mounted) {
      setState(() {
        _messages.add({
          'text': finalResponse,
          'englishText': englishResponse,
          'isUser': false,
          'selectedLanguage': _selectedLanguage,
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
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

    final prompt = '''
You are an expert fitness nutrition coach.
Answer the user's question in a simple, friendly, and useful way.
You can help with diet plans, calories, protein, carbs, fats, vitamins, minerals,
weight loss, weight gain, muscle gain, healthy eating, workout nutrition, meal timing.
Keep the answer practical and easy to understand.
Reply only in English.

User question: $text
''';

    final englishResponse =
        await _callApi([{'type': 'text', 'text': prompt}]);
    String finalResponse = englishResponse;
    if (_selectedLanguage != 'English') {
      finalResponse = await _translate(englishResponse, _selectedLanguage);
    }

    if (mounted) {
      setState(() {
        _messages.add({
          'text': finalResponse,
          'englishText': englishResponse,
          'isUser': false,
          'selectedLanguage': _selectedLanguage,
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _translateMessage(int index, String newLang) async {
    final englishText = _messages[index]['englishText'];
    if (englishText == null || englishText.toString().trim().isEmpty) return;

    setState(() {
      _messages[index]['text'] = 'Translating...';
      _messages[index]['selectedLanguage'] = newLang;
    });

    final translated = await _translate(englishText.toString(), newLang);

    if (mounted) {
      setState(() {
        _messages[index]['text'] = translated;
        _messages[index]['selectedLanguage'] = newLang;
      });
    }
  }

  Future<void> _toggleListening() async {
    if (!_isListening) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }

      final available = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (e) {
          setState(() => _isListening = false);
        },
      );

      if (available) {
        setState(() => _isListening = true);
        await _speech.listen(
          localeId: _speechLocale(_selectedLanguage),
          partialResults: true,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          listenMode: stt.ListenMode.dictation,
          onResult: (result) {
            setState(() {
              _controller.value = TextEditingValue(
                text: result.recognizedWords,
                selection: TextSelection.collapsed(
                    offset: result.recognizedWords.length),
              );
            });
          },
        );
      }
    } else {
      await _speech.stop();
      setState(() => _isListening = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0715),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0715),
        elevation: 0,
        title: const Text('🥗 Food & Nutrition AI',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language, color: Colors.white),
            color: const Color(0xFF1A2A44),
            onSelected: (val) {
              setState(() => _selectedLanguage = val);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Language set to $val')));
            },
            itemBuilder: (_) => _languages
                .map((l) => PopupMenuItem(
                      value: l,
                      child: Text(l,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: l == _selectedLanguage
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _ChatBubble(
                  message: _messages[index],
                  languages: _languages,
                  onLanguageChanged: (lang) => _translateMessage(index, lang),
                );
              },
            ),
          ),

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Column(children: [
                CircularProgressIndicator(color: Color(0xFFFF6200)),
                SizedBox(height: 6),
                Text('Analyzing / Thinking...',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),

          // Input bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? Colors.red
                          : const Color(0xFFFF6200),
                    ),
                    onPressed: _isLoading ? null : _toggleListening,
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFFFF6200)),
                    onPressed: _isLoading ? null : _sendMessage,
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.languages,
    required this.onLanguageChanged,
  });

  final Map<String, dynamic> message;
  final List<String> languages;
  final void Function(String) onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message['isUser'] ?? false;
    final File? imageFile = message['imageFile'];
    final Uint8List? webImage = message['webImage'];
    final String selectedLang = message['selectedLanguage'] ?? 'English';
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
          // Image preview
          if (imageFile != null || webImage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: kIsWeb
                    ? Image.memory(webImage!,
                        height: 180, width: 220, fit: BoxFit.cover)
                    : Image.file(imageFile!,
                        height: 180, width: 220, fit: BoxFit.cover),
              ),
            ),

          // Text bubble
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
                        onSelected: onLanguageChanged,
                        itemBuilder: (_) => languages
                            .map((l) => PopupMenuItem(
                                  value: l,
                                  child: Text(l,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: l == selectedLang
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                ))
                            .toList(),
                      ),
                    ),
                  if (isUser)
                    Text(
                      message['text'] ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, height: 1.5),
                    )
                  else
                    MarkdownBody(
                      data: message['text'] ?? '',
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                            color: Colors.white, fontSize: 15, height: 1.6),
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
                        listBullet:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
