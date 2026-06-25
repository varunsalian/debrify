import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/extracted_media.dart';

class StreamExtractor {
  HeadlessInAppWebView? _headlessWebView;
  Completer<ExtractedMedia?>? _completer;
  Timer? _timeoutTimer;

  String? _capturedVideo;
  String? _capturedAudio;
  Map<String, String>? _capturedHeaders;

  final List<String> _detectedVideoUrls = [];

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  Map<String, String> _buildHeaders(String referer) {
    final uri = Uri.tryParse(referer);
    final origin = uri != null ? '${uri.scheme}://${uri.host}' : referer;
    return {
      'User-Agent': _userAgent,
      'Referer': referer,
      'Origin': origin,
    };
  }

  Future<ExtractedMedia?> extract(
    String url, {
    Duration timeout = const Duration(seconds: 60),
    String? referer,
    String? iframeWrapperBaseUrl,
  }) async {
    await _cleanup();

    _completer = Completer<ExtractedMedia?>();
    _capturedVideo = null;
    _capturedAudio = null;
    _capturedHeaders = null;
    _detectedVideoUrls.clear();

    _timeoutTimer = Timer(timeout, () {
      if (_completer != null && !_completer!.isCompleted) {
        if (_detectedVideoUrls.isNotEmpty) {
          _capturedVideo = _selectBestQuality(_detectedVideoUrls);
          _completeWithCaptured(url);
        } else if (_capturedVideo != null) {
          _completeWithCaptured(url);
        } else {
          debugPrint('[StreamExtractor] Sniffing Session Timeout for: $url');
          _cleanup();
          _completer?.complete(null);
        }
      }
    });

    if (iframeWrapperBaseUrl != null) {
      _headlessWebView = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data: _buildIframeWrapperHtml(url),
          baseUrl: WebUri(iframeWrapperBaseUrl),
          historyUrl: WebUri(iframeWrapperBaseUrl),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSize: const Size(1280, 720),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: _getRawSpyJs(),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        ]),
        initialSettings: _wrapperSettings(),
        onLoadResource: _onLoadResource(url),
        onLoadStop: _onLoadStop(),
        onConsoleMessage: _onConsoleMessage(url),
      );
    } else {
      final initialReq = URLRequest(
        url: WebUri(url),
        headers: referer != null
            ? {
                'Referer': referer,
                'Origin': Uri.tryParse(referer)?.origin ?? referer,
              }
            : null,
      );
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: initialReq,
        initialSize: const Size(1280, 720),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: _getRawSpyJs(),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        ]),
        initialSettings: _wrapperSettings(),
        onLoadResource: _onLoadResource(url),
        onLoadStop: _onLoadStop(),
        onConsoleMessage: _onConsoleMessage(url),
      );
    }

    try {
      await _headlessWebView?.run();
    } catch (e) {
      debugPrint('[StreamExtractor] Engine Error: $e');
    }
    return _completer?.future;
  }

  InAppWebViewSettings _wrapperSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        userAgent: _userAgent,
        mediaPlaybackRequiresUserGesture: false,
        cacheEnabled: true,
        clearCache: false,
        allowsInlineMediaPlayback: true,
        useOnLoadResource: true,
        iframeAllow: 'autoplay; fullscreen; encrypted-media',
        iframeAllowFullscreen: true,
      );

  void Function(InAppWebViewController, LoadedResource) _onLoadResource(
          String fallbackReferer) =>
      (controller, resource) {
        final rUrl = resource.url.toString();
        _processUrl(rUrl, fallbackReferer);
      };

  void Function(InAppWebViewController, WebUri?) _onLoadStop() =>
      (controller, loadedUrl) async {
        debugPrint('[StreamExtractor] Page Loaded: $loadedUrl');
        await controller.evaluateJavascript(source: _getRawSpyJs());
      };

  void Function(InAppWebViewController, ConsoleMessage) _onConsoleMessage(
          String fallbackReferer) =>
      (controller, consoleMessage) {
        final msg = consoleMessage.message;
        if (msg.contains('PT_EXTRACT:')) {
          String fullMsg = msg
              .substring(
                  msg.indexOf('PT_EXTRACT:') + 'PT_EXTRACT:'.length)
              .trim();
          String streamUrl = fullMsg;
          String? frameUrl;
          if (fullMsg.contains(' | FRAME: ')) {
            final parts = fullMsg.split(' | FRAME: ');
            streamUrl = parts[0];
            frameUrl = parts[1];
          }
          streamUrl =
              streamUrl.replaceAll('"', '').replaceAll("'", "").trim();
          streamUrl = streamUrl
              .replaceFirst('[FETCH]', '')
              .replaceFirst('[XHR]', '')
              .replaceFirst('[POSTMESSAGE]', '')
              .replaceFirst('[ATTR_SRC]', '')
              .replaceFirst('[MUTATION_SRC]', '')
              .replaceFirst('[ATTR_DATA-SRC]', '')
              .replaceFirst('[VIDEO_SRC]', '')
              .replaceFirst('[SOURCE_SRC]', '')
              .replaceFirst('[MEDIA_PLAY]', '')
              .trim();
          _processUrl(streamUrl, frameUrl ?? fallbackReferer);
        }
      };

  String _buildIframeWrapperHtml(String embedUrl) {
    return '''<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="referrer" content="unsafe-url">
<title>player</title>
<style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style>
</head><body>
<iframe id="p" src="$embedUrl" allow="autoplay; fullscreen; encrypted-media" allowfullscreen referrerpolicy="unsafe-url"></iframe>
</body></html>''';
  }

  void _processUrl(String rUrl, String referer) {
    if ((rUrl.contains('.m3u8') ||
            rUrl.contains('.mp4') ||
            rUrl.contains('playlist') ||
            rUrl.contains('master') ||
            rUrl.contains('.mpd') ||
            rUrl.contains('manifest') ||
            rUrl.contains('heistotron.uk/p/') ||
            (rUrl.contains('okcdn.ru/') &&
                rUrl.contains('type=') &&
                !rUrl.contains('bytes=') &&
                !rUrl.contains('appId=')) ||
            (rUrl.contains('vkuser.net/') &&
                rUrl.contains('type=') &&
                !rUrl.contains('bytes=') &&
                !rUrl.contains('appId='))) &&
        !rUrl.contains('google')) {
      final pathOnly = Uri.tryParse(rUrl)?.path ?? rUrl;
      if (pathOnly.contains('/audio/') || pathOnly.contains('audio_')) {
        _capturedAudio = rUrl;
        _capturedHeaders ??= _buildHeaders(referer);
      } else {
        if (!_detectedVideoUrls.contains(rUrl)) {
          _detectedVideoUrls.add(rUrl);
        }
        _capturedVideo = _selectBestQuality(_detectedVideoUrls);
        _capturedHeaders ??= _buildHeaders(referer);
      }

      if (referer.contains('anitaro')) {
      } else if (_capturedVideo != null &&
          (_capturedAudio != null || !referer.contains('anitaro'))) {
        _completeWithCaptured(referer);
      }
    }
  }

  String _selectBestQuality(List<String> urls) {
    final qualityOrder = [
      '4K', '2160p', '1440p', '1080p', '720p', '480p', '360p'
    ];
    for (final quality in qualityOrder) {
      final match = urls.firstWhere(
        (url) =>
            url.toLowerCase().contains('quality=$quality'.toLowerCase()),
        orElse: () => '',
      );
      if (match.isNotEmpty) return match;
    }
    return urls.first;
  }

  void _completeWithCaptured(String referer) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(ExtractedMedia(
        url: _capturedVideo!,
        audioUrl: _capturedAudio,
        headers: _capturedHeaders ?? _buildHeaders(referer),
      ));
      _cleanup();
    }
  }

  String _getRawSpyJs() {
    return """
    (function() {
      if (window.pt_raw_injected) return;
      window.pt_raw_injected = true;

      const log = (type, url) => {
        if (!url || typeof url !== 'string' || url.startsWith('data:')) return;
        console.log('PT_EXTRACT: [' + type + '] ' + url + ' | FRAME: ' + window.location.href);
      };

      console.log('PT_LOG: Sniffer Active on ' + window.location.href);

      window.open = function() { return null; };
      window.alert = function() { return true; };

      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const url = args[0] instanceof Request ? args[0].url : args[0];
        log('FETCH', url);
        return originalFetch.apply(this, args);
      };

      const originalXHROpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        log('XHR', url);
        return originalXHROpen.apply(this, arguments);
      };

      const OriginalWorker = window.Worker;
      window.Worker = function(scriptURL, options) {
        log('WORKER', scriptURL);
        return new OriginalWorker(scriptURL, options);
      };

      const originalPostMessage = window.postMessage;
      window.postMessage = function(message, targetOrigin, transfer) {
        if (typeof message === 'string') {
           log('POSTMESSAGE', message);
        }
        return originalPostMessage.apply(this, arguments);
      };

      const originalCreateObjectURL = URL.createObjectURL;
      URL.createObjectURL = function(obj) {
        const url = originalCreateObjectURL.apply(this, arguments);
        log('BLOB_URL', url);
        return url;
      };

      const originalSetAttribute = Element.prototype.setAttribute;
      Element.prototype.setAttribute = function(name, value) {
        if (name === 'src' || name === 'data-src') {
           log('ATTR_' + name.toUpperCase(), value);
        }
        return originalSetAttribute.apply(this, arguments);
      };

      const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          mutation.addedNodes.forEach((node) => {
            if (node.tagName === 'VIDEO' || node.tagName === 'SOURCE' || node.tagName === 'IFRAME') {
              if (node.src) log('MUTATION_SRC', node.src);
            }
          });
          if (mutation.type === 'attributes' && (mutation.attributeName === 'src' || mutation.attributeName === 'data-src')) {
            log('MUTATION_ATTR', mutation.target.getAttribute(mutation.attributeName));
          }
        });
      });
      observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });

      const originalPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        if (this.src) log('MEDIA_PLAY', this.src);
        return originalPlay.apply(this, arguments);
      };

      const interact = () => {
        const centerX = window.innerWidth / 2;
        const centerY = window.innerHeight / 2;

        for(let i=0; i<3; i++) {
          const el = document.elementFromPoint(centerX, centerY);
          if (el) {
            el.click();
            el.dispatchEvent(new MouseEvent('click', { view: window, bubbles: true, cancelable: true, clientX: centerX, clientY: centerY }));
          }
        }

        const selectors = [
          '.play-icon-main', '.jw-icon-display', '.jw-display-icon-container', '.jw-icon-playback',
          '.jw-button-color', '#play-button', '.play-button', '.v-play-button',
          '.vjs-big-play-button', '[class*="play" i]', '[id*="play" i]',
          '.play-icon', '.play_icon', '.play-btn', '.play_btn',
          '.click_to_play', '.overlay', '#player_overlay', 'button', 'a'
        ];

        selectors.forEach(selector => {
          document.querySelectorAll(selector).forEach(btn => {
             const rect = btn.getBoundingClientRect();
             if (rect.width > 0 && rect.height > 0) {
                const text = (btn.innerText || btn.textContent || '').toLowerCase();
                const id = (btn.id || '').toLowerCase();
                const cls = (btn.className || '').toString().toLowerCase();

                if (text.includes('play') || id.includes('play') || cls.includes('play') || cls.includes('overlay')) {
                   btn.click();
                }
             }
          });
        });

        document.querySelectorAll('video').forEach(v => {
          if (v.paused) v.play().catch(() => v.click());
          if (v.src) log('VIDEO_SRC', v.src);
        });
      };

      setTimeout(() => {
        interact();
        setInterval(interact, 800);
      }, 1000);
    })();
    """;
  }

  Future<void> _cleanup() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    if (_headlessWebView != null) {
      try {
        await _headlessWebView?.dispose();
      } catch (e) {
        debugPrint('[StreamExtractor] Error during disposal: $e');
      }
      _headlessWebView = null;
    }
  }

  Future<void> dispose() async {
    await _cleanup();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
  }
}
