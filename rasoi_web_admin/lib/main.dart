import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Set this to your deployed Rasoi Care backend once it's live
/// (see README.md "Deploy it for real"), e.g.
/// "https://rasoicare-backend.onrender.com" — then rebuild the APK.
const String kBackendBaseUrl = "https://your-rasoi-care-backend.example.com";
const String kAppPath = "/admin";

void main() => runApp(const RasoiCareApp());

class RasoiCareApp extends StatelessWidget {
  const RasoiCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rasoi Care Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1F3D2B)),
      home: const WebShell(path: kAppPath),
    );
  }
}

class WebShell extends StatefulWidget {
  final String path;
  const WebShell({super.key, required this.path});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  bool get _isConfigured => !kBackendBaseUrl.contains("your-rasoi-care-backend.example.com");

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF6F4EF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (error) => setState(() {
            _loading = false;
            _error = error.description;
          }),
        ),
      );
    if (_isConfigured) {
      _controller.loadRequest(Uri.parse("$kBackendBaseUrl${widget.path}"));
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConfigured) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🍳', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 16),
                const Text(
                  'Backend not configured yet',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This app is a thin wrapper around the real Rasoi Care '
                  'web app (admin.html, served by the Flask backend). '
                  'Deploy app.py (see README.md → "Deploy it for real"), '
                  'then set kBackendBaseUrl in lib/main.dart to your public '
                  'URL and rebuild.',
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Container(
                color: const Color(0xFFF6F4EF),
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not reach the server', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _retry, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
