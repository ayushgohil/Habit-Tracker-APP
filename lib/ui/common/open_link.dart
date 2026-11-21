import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a habit's link in the browser or the app it points to.
abstract class LinkOpener {
  Future<bool> open(String url);
}

class UrlLauncherOpener implements LinkOpener {
  @override
  Future<bool> open(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Ember link: $error');
      return false;
    }
  }
}

/// The opener in use. Tests replace it.
LinkOpener linkOpener = UrlLauncherOpener();
