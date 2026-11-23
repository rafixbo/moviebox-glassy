import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/about_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'services/app_update.dart';
import 'theme.dart';
import 'widgets/glass.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MovieBoxGlassyApp());
}

class MovieBoxGlassyApp extends StatelessWidget {
  const MovieBoxGlassyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MovieBox Glassy',
      theme: GlassTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const _UpdateGate(child: Shell()),
    );
  }
}

/// Runs the remote update check once at startup. Fail-open: any failure
/// (offline, bad JSON) simply shows the app. A forced update blocks the
/// app behind a full-screen glassy update screen.
class _UpdateGate extends StatefulWidget {
  final Widget child;
  const _UpdateGate({required this.child});

  @override
  State<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<_UpdateGate> {
  UpdateInfo? _forcedInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final result = await AppUpdate.instance.check();
    if (result == null || !mounted) return;
    if (result.state == UpdateState.forced) {
      setState(() => _forcedInfo = result.info);
    } else {
      await showUpdateDialog(context,
          info: result.info, forced: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _forcedInfo;
    if (info == null) return widget.child;
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update_rounded,
                      size: 48, color: GlassTheme.accent),
                  const SizedBox(height: 16),
                  const Text('Update required',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    'MovieBox Glassy ${info.latestVersion} is required to continue.',
                    textAlign: TextAlign.center,
                  ),
                  if (info.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(info.notes,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: GlassTheme.muted)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        final url = Platform.isWindows
                            ? info.windowsUrl
                            : info.apkUrl;
                        final uri = Uri.tryParse(url);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: const Text('Update now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _pages = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  static const _titles = ['MovieBox Glassy', 'Search', 'Library'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Column(
          children: [
            AppBar(
              title: Text(_titles[_index]),
              actions: [
                IconButton(
                  tooltip: 'About & updates',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ],
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: _pages[_index],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded), label: 'Home'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded), label: 'Search'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.video_library_rounded), label: 'Library'),
            ],
          ),
        ),
      ),
    );
  }
}
