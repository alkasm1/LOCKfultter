import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class KeyState extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  static const _keyName = 'keynova_lock_hash';

  String? _storedHash;
  String? get storedHash => _storedHash;

  KeyState() {
    _load();
  }

  Future<void> _load() async {
    _storedHash = await _storage.read(key: _keyName);
    notifyListeners();
  }

  Future<void> setHash(String hash) async {
    await _storage.write(key: _keyName, value: hash);
    _storedHash = hash;
    notifyListeners();
  }

  Future<void> removeHash() async {
    await _storage.delete(key: _keyName);
    _storedHash = null;
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => KeyState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Keynova Lock',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
        ),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> assetImages = [
    'assets/images/key1.png',
    // 'assets/images/key2.png',
  ];

  String? selectedAsset;
  File? galleryImage;
  final TextEditingController _passwordController = TextEditingController();
  String statusMessage = '';

  @override
  void initState() {
    super.initState();
    if (assetImages.isNotEmpty) selectedAsset = assetImages.first;
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }

  Future<Uint8List> _loadGalleryBytes(File imageFile) async {
    return await imageFile.readAsBytes();
  }

  String _computeHash(Uint8List imageBytes, String password) {
    final pwBytes = utf8.encode(password);
    final combined = Uint8List(imageBytes.length + pwBytes.length)
      ..setAll(0, imageBytes)
      ..setAll(imageBytes.length, pwBytes);
    final digest = sha256.convert(combined);
    return base64.encode(digest.bytes);
  }

  Future<Uint8List?> _getSelectedImageBytes() async {
    if (galleryImage != null) {
      return _loadGalleryBytes(galleryImage!);
    } else if (selectedAsset != null) {
      return _loadAssetBytes(selectedAsset!);
    }
    return null;
  }

  Future<void> _pickGalleryImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        galleryImage = File(picked.path);
        selectedAsset = null; // تعطيل اختيار الأصول عند اختيار من المعرض
      });
    }
  }

  Future<void> _setKey(BuildContext ctx) async {
    final keyState = Provider.of<KeyState>(ctx, listen: false);
    if (_passwordController.text.isEmpty) {
      setState(() => statusMessage = 'أدخل كلمة مرور.');
      return;
    }
    final bytes = await _getSelectedImageBytes();
    if (bytes == null) {
      setState(() => statusMessage = 'اختر صورة (من المضمنة أو من المعرض).');
      return;
    }
    try {
      final hash = _computeHash(bytes, _passwordController.text);
      await keyState.setHash(hash);
      setState(() => statusMessage = 'تم تعيين المفتاح بنجاح.');
      _passwordController.clear();
    } catch (e) {
      setState(() => statusMessage = 'خطأ أثناء تعيين المفتاح: $e');
    }
  }

  Future<void> _unlock(BuildContext ctx) async {
    final keyState = Provider.of<KeyState>(ctx, listen: false);
    if (keyState.storedHash == null) {
      setState(() => statusMessage = 'لا يوجد مفتاح محفوظ. عيّن مفتاحاً أولاً.');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => statusMessage = 'أدخل كلمة المرور للتحقق.');
      return;
    }
    final bytes = await _getSelectedImageBytes();
    if (bytes == null) {
      setState(() => statusMessage = 'اختر صورة للتحقق.');
      return;
    }
    try {
      final hash = _computeHash(bytes, _passwordController.text);
      if (hash == keyState.storedHash) {
        setState(() => statusMessage = 'نجح: القفل مفتوح ✅');
      } else {
        setState(() => statusMessage = 'فشل: الصورة أو كلمة المرور غير صحيحة ❌');
      }
      _passwordController.clear();
    } catch (e) {
      setState(() => statusMessage = 'خطأ أثناء الفحص: $e');
    }
  }

  Future<void> _removeKey(BuildContext ctx) async {
    final keyState = Provider.of<KeyState>(ctx, listen: false);
    await keyState.removeHash();
    setState(() => statusMessage = 'تم إزالة المفتاح.');
  }

  @override
  Widget build(BuildContext context) {
    final stored = context.watch<KeyState>().storedHash != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Keynova Lock — قفل بصري')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const Text('اختر صورة المفتاح:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedAsset,
                    hint: const Text('— اختر من المضمنة —'),
                    items: assetImages
                        .map((a) => DropdownMenuItem(
                              value: a,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: Image.asset(a, fit: BoxFit.cover),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(a.split('/').last)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        selectedAsset = v;
                        galleryImage = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _pickGalleryImage,
                  icon: const Icon(Icons.photo),
                  label: const Text('من المعرض'),
                ),
              ],
            ),
            if (galleryImage != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 100,
                height: 100,
                child: Image.file(galleryImage!, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _setKey(context),
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('تعيين مفتاح جديد'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _unlock(context),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('فتح القفل'),
                ),
                ElevatedButton.icon(
                  onPressed: stored ? () => _removeKey(context) : null,
                  icon: const Icon(Icons.delete),
                  label: const Text('إزالة المفتاح'),
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith(
                        (states) => states.contains(MaterialState.disabled)
                            ? null
                            : Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              statusMessage,
              style: const TextStyle(fontSize: 16),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(stored
                  ? 'حالة: مفتاح محفوظ'
                  : 'حالة: لا يوجد مفتاح محفوظ'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
