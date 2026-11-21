/// Turns what was typed into a link Ember can open, or '' if there is none.
///
/// Web addresses get https:// when they have no scheme. Any app link such as
/// whatsapp://send or spotify:… is kept. Schemes that could read files or run
/// script are refused.
library;

const _blocked = {'file', 'content', 'javascript', 'data', 'about', 'blob'};

/// Returns the cleaned link, '' for blank input, or null when it can't be opened.
String? normalizeLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  if (text.contains(RegExp(r'\s'))) return null;
  var candidate = text;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(candidate) &&
      !RegExp(r'^[^/:]+:\d+(/|$)').hasMatch(candidate); // "example.com:8080" is a host and port
  if (!hasScheme) candidate = 'https://$candidate';
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.scheme.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (_blocked.contains(scheme)) return null;
  if ((scheme == 'http' || scheme == 'https') && !uri.host.contains('.') && uri.host != 'localhost') return null;
  return candidate;
}
