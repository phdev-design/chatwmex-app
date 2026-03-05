import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

class PdfPreviewScreen extends StatefulWidget {
  final String pdfUrl;
  final String fileName;

  const PdfPreviewScreen({
    super.key,
    required this.pdfUrl,
    required this.fileName,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  bool _fallbackTriggered = false;
  
  // 1. 建立控制器來操作 PDF (縮放、跳頁等)
  final PdfViewerController _pdfViewerController = PdfViewerController();
  
  // 2. 狀態變數：紀錄頁碼與載入狀態
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isReady = false;

  Future<void> _fallbackToExternal() async {
    if (_fallbackTriggered) return;
    _fallbackTriggered = true;
    final uri = Uri.tryParse(widget.pdfUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  // --- 縮放控制邏輯 ---
  void _zoomIn() {
    _pdfViewerController.zoomLevel = _pdfViewerController.zoomLevel + 0.5;
  }

  void _zoomOut() {
    // 防止縮放比例小於 1.0 導致畫面變太小或當機
    final newZoom = _pdfViewerController.zoomLevel - 0.5;
    _pdfViewerController.zoomLevel = newZoom < 1.0 ? 1.0 : newZoom;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          // 只有當文件成功載入後，才顯示縮放按鈕
          if (_isReady) ...[
            IconButton(
              icon: const Icon(Icons.zoom_out),
              onPressed: _zoomOut,
              tooltip: '縮小',
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in),
              onPressed: _zoomIn,
              tooltip: '放大',
            ),
          ],
        ],
      ),
      // 使用 Stack 讓我們可以把頁碼浮動在 PDF 畫面上方
      body: Stack(
        children: [
          SfPdfViewer.network(
            widget.pdfUrl,
            controller: _pdfViewerController,
            canShowScrollHead: false, // 我們自己做了頁碼，所以關閉套件預設的側邊滾動提示
            onDocumentLoaded: (PdfDocumentLoadedDetails details) {
              // 文件載入完成時，取得總頁數並更新狀態
              if (!mounted) return;
              setState(() {
                _totalPages = details.document.pages.count;
                _currentPage = 1;
                _isReady = true;
              });
            },
            onPageChanged: (PdfPageChangedDetails details) {
              // 使用者滑動切換頁面時，即時更新目前頁碼
              if (!mounted) return;
              setState(() {
                _currentPage = details.newPageNumber;
              });
            },
            onDocumentLoadFailed: (_) {
              _fallbackToExternal();
            },
          ),
          
          // 懸浮的底部頁碼指示器 (例如： 1 / 5)
          if (_isReady && _totalPages > 0)
            Positioned(
              bottom: 24, // 距離底部 24 pixels
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_currentPage / $_totalPages',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}