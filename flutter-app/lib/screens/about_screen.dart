import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _status = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) {
        setState(() => _version = '${p.version} (${p.buildNumber})');
      }
    });
  }

  Future<void> _check({bool silent = false}) async {
    setState(() {
      _checking = true;
      _status = '';
    });
    final result = await AppUpdate.instance.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (result == null) {
      setState(() => _status = 'You are on the latest version.');
      return;
    }
    final (info: info, state: state) = result;
    if (!silent) {
      await showUpdateDialog(context, info: info, forced: state == UpdateState.forced);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: GlassBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MovieBox Glassy',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Version $_version',
                      style: const TextStyle(color: GlassTheme.muted)),
                  const SizedBox(height: 12),
                  const Text(
                    'A smooth, glassy, compact movie & TV streaming client '
                    'for Android and Windows. No account, no ads.',
                    style: TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              onTap: _checking ? null : () => _check(),
              child: Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: GlassTheme.accent2),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Check for updates',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (_checking)
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right, color: GlassTheme.muted),
                ],
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4),
                child: Text(_status,
                    style: const TextStyle(color: GlassTheme.muted)),
              ),
            const SizedBox(height: 12),
            const GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Credits',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text(
                    'Streaming data comes from the MovieBox API, as used by '
                    'mesamirh/MovieBox-Tui (github.com/mesamirh/MovieBox-Tui). '
                    'This app hosts no media and is a third-party client '
                    'for personal use only.',
                    style: TextStyle(color: GlassTheme.muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glassy update dialog. `forced` hides the Later button.
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  required bool forced,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (context) => AlertDialog(
      backgroundColor: GlassTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(forced ? 'Update required' : 'Update available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${info.latestVersion} (build ${info.latestBuild}) is available.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(info.notes, style: const TextStyle(color: GlassTheme.muted)),
          ],
        ],
      ),
      actions: [
        if (!forced)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
        FilledButton(
          onPressed: () async {
            final url = Platform.isWindows ? info.windowsUrl : info.apkUrl;
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            if (context.mounted && !forced) Navigator.pop(context);
          },
          child: const Text('Update now'),
        ),
      ],
    ),
  );
}
