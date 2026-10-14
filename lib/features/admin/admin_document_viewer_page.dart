import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum _AdminDocumentKind { image, pdf, web }

class AdminDocumentViewerPage extends StatefulWidget {
  final String title;
  final String url;
  final String? storagePath;
  final String? contentType;

  const AdminDocumentViewerPage({
    super.key,
    required this.title,
    required this.url,
    this.storagePath,
    this.contentType,
  });

  @override
  State<AdminDocumentViewerPage> createState() => _AdminDocumentViewerPageState();
}

class _AdminDocumentViewerPageState extends State<AdminDocumentViewerPage> {
  WebViewController? _controller;
  late final _AdminDocumentKind _kind;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _kind = _resolveDocumentKind();
    if (_kind == _AdminDocumentKind.image) {
      _loading = false;
      return;
    }

    final targetUrl = _kind == _AdminDocumentKind.pdf
        ? 'https://docs.google.com/gview?embedded=1&url=${Uri.encodeComponent(widget.url)}'
        : widget.url;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _loadFailed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(targetUrl));
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  _AdminDocumentKind _resolveDocumentKind() {
    final contentType = (widget.contentType ?? '').trim().toLowerCase();
    if (contentType.startsWith('image/')) {
      return _AdminDocumentKind.image;
    }
    if (contentType == 'application/pdf') {
      return _AdminDocumentKind.pdf;
    }

    final lower = '${widget.storagePath ?? ''} ${widget.url} ${widget.title}'
        .toLowerCase();
    if (_matchesAny(lower, const ['.jpg', '.jpeg', '.png', '.webp', '.gif'])) {
      return _AdminDocumentKind.image;
    }
    if (_matchesAny(lower, const ['.pdf'])) {
      return _AdminDocumentKind.pdf;
    }
    return _AdminDocumentKind.web;
  }

  bool _matchesAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) return true;
    }
    return false;
  }

  Widget _buildImageViewer() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined,
                        size: 56, color: Colors.white70),
                    const SizedBox(height: 12),
                    const Text(
                      'Nao foi possivel carregar esta imagem dentro do app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openExternal,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Abrir externamente'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWebViewer() {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: Text('Documento indisponivel.'));
    }

    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_loadFailed)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    _kind == _AdminDocumentKind.pdf
                        ? 'O PDF nao carregou bem dentro do app.'
                        : 'Nao foi possivel carregar este documento dentro do app.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir no navegador'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () {
              if (_kind == _AdminDocumentKind.image) {
                setState(() => _loadFailed = false);
                return;
              }
              setState(() {
                _loading = true;
                _loadFailed = false;
              });
              _controller?.reload();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: _kind == _AdminDocumentKind.image
          ? _buildImageViewer()
          : _buildWebViewer(),
    );
  }
}
