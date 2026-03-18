// lib/screens/bridge_setup_screen.dart
//
// Shown when the bridge is not yet configured, or WhatsApp
// needs re-authentication. Handles:
//   1. Bridge URL + secret input
//   2. QR code display for WhatsApp pairing
//   3. Connection status feedback

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/bridge_service.dart';
import '../services/tracker_service.dart';
import '../theme/app_theme.dart';

class BridgeSetupScreen extends StatefulWidget {
  const BridgeSetupScreen({super.key});

  @override
  State<BridgeSetupScreen> createState() => _BridgeSetupScreenState();
}

class _BridgeSetupScreenState extends State<BridgeSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostCtrl = TextEditingController(text: 'http://');
  final _secretCtrl = TextEditingController();
  bool _loading = false;
  bool _testPassed = false;
  String? _testError;

  @override
  void initState() {
    super.initState();
    final bridge = context.read<BridgeService>();
    if (bridge.bridgeHost.isNotEmpty) {
      _hostCtrl.text = bridge.bridgeHost;
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _testAndConnect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _testError = null; _testPassed = false; });

    final bridge = context.read<BridgeService>();
    final reachable = await bridge.testConnection(
      _hostCtrl.text.trim(),
      _secretCtrl.text.trim(),
    );

    if (!reachable) {
      setState(() {
        _loading = false;
        _testError = 'Cannot reach bridge at ${_hostCtrl.text.trim()}\n'
            'Check that the Node.js bridge is running and the URL is correct.';
      });
      return;
    }

    await bridge.saveConfig(
      bridgeHost: _hostCtrl.text.trim(),
      apiSecret: _secretCtrl.text.trim(),
    );

    // Attach bridge to tracker
    if (mounted) {
      context.read<TrackerService>().attachBridge(bridge);
    }

    setState(() { _loading = false; _testPassed = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BridgeService>(
      builder: (ctx, bridge, _) {
        // Already connected → show QR or success
        if (bridge.isConfigured) {
          return _buildConnectedView(bridge);
        }
        return _buildSetupForm();
      },
    );
  }

  // ── Setup form ─────────────────────────────────────────
  Widget _buildSetupForm() {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSecondary,
        title: const Text('Connect Bridge'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryGreen.withOpacity(0.3), width: 2),
                      ),
                      child: const Icon(Icons.wifi_tethering,
                          size: 40, color: AppTheme.primaryGreen),
                    ),
                    const SizedBox(height: 16),
                    const Text('Bridge Configuration',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter your Node.js bridge server details',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Steps info
              _StepCard(
                number: '1',
                text: 'Deploy the wastat-bridge Node.js server on your VPS\n'
                    '(e.g. http://YOUR_VPS_IP:3000)',
              ),
              const SizedBox(height: 10),
              _StepCard(
                number: '2',
                text: 'Copy the API_SECRET from your bridge .env file',
              ),
              const SizedBox(height: 10),
              _StepCard(
                number: '3',
                text: 'Enter the details below and connect',
              ),

              const SizedBox(height: 28),

              _Label('Bridge URL (HTTP port)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _hostCtrl,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'http://1.2.3.4:3000',
                  prefixIcon: Icon(Icons.link, color: AppTheme.textSecondary),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.startsWith('http')) return 'Must start with http:// or https://';
                  return null;
                },
              ),

              const SizedBox(height: 20),
              _Label('API Secret'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _secretCtrl,
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Your API_SECRET from .env',
                  prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length < 8) return 'Secret too short';
                  return null;
                },
              ),

              if (_testError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_testError!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _testAndConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Test & Connect',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Connected view: QR or success ─────────────────────
  Widget _buildConnectedView(BridgeService bridge) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSecondary,
        title: const Text('WhatsApp Pairing'),
        actions: [
          TextButton(
            onPressed: () => _confirmDisconnect(bridge),
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: switch (bridge.waState) {
        WhatsAppState.connected   => _buildWaConnected(bridge),
        WhatsAppState.qrPending   => _buildQrView(bridge),
        WhatsAppState.disconnected => _buildWaDisconnected(bridge),
      },
    );
  }

  Widget _buildWaConnected(BridgeService bridge) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppTheme.onlineColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  size: 56, color: AppTheme.onlineColor),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            const Text('WhatsApp Connected!',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (bridge.connectedPhone != null)
              Text('+${bridge.connectedPhone}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 16),
            const Text(
              'Presence tracking is live.\nGo back to the contacts tab to start tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 32),
            _StatusRow(label: 'Bridge', connected: true),
            const SizedBox(height: 8),
            _StatusRow(label: 'WhatsApp Web', connected: true),
          ],
        ),
      ),
    );
  }

  Widget _buildQrView(BridgeService bridge) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Scan with WhatsApp',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Open WhatsApp → Linked Devices → Link a Device\nthen scan the QR code below',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 28),

            // QR code display
            if (bridge.qrCodeBase64 != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withOpacity(0.3),
                      blurRadius: 30, spreadRadius: 2,
                    )
                  ],
                ),
                child: Image.memory(
                  _decodeBase64Image(bridge.qrCodeBase64!),
                  width: 240, height: 240,
                  fit: BoxFit.contain,
                ),
              ).animate().fadeIn().scale(begin: const Offset(0.85, 0.85))
            else
              const SizedBox(
                width: 240, height: 240,
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                ),
              ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.awayColor.withOpacity(0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.timer_outlined,
                      color: AppTheme.awayColor, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'QR codes expire in 60 seconds. '
                      'If it expires, the bridge will generate a new one automatically.',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaDisconnected(BridgeService bridge) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 60, color: AppTheme.textTertiary),
            const SizedBox(height: 20),
            const Text('Waiting for WhatsApp',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'The bridge is connected but WhatsApp\nhas not authenticated yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            _StatusRow(label: 'Bridge', connected: bridge.bridgeState == BridgeState.connected),
            const SizedBox(height: 8),
            _StatusRow(label: 'WhatsApp Web', connected: false),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppTheme.primaryGreen),
            const SizedBox(height: 12),
            const Text('Waiting for QR code from bridge...',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Uint8List _decodeBase64Image(String dataUrl) {
    // data:image/png;base64,XXXX → decode XXXX
    final base64Str = dataUrl.contains(',')
        ? dataUrl.split(',')[1]
        : dataUrl;
    return base64Decode(base64Str);
  }

  void _confirmDisconnect(BridgeService bridge) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Disconnect?'),
        content: const Text(
          'This will remove your bridge configuration and stop tracking.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              bridge.clearConfig();
            },
            child: const Text('Disconnect',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5));
}

class _StepCard extends StatelessWidget {
  final String number;
  final String text;
  const _StepCard({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool connected;
  const _StatusRow({required this.label, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: connected ? AppTheme.onlineColor : AppTheme.offlineColor,
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(width: 6),
        Text(
          connected ? 'Connected' : 'Disconnected',
          style: TextStyle(
              color: connected ? AppTheme.onlineColor : AppTheme.offlineColor,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
