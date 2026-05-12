// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:smartlock_app/services/auth_service.dart';
import 'package:smartlock_app/services/ble_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();
  late final BleService _bleService = BleService(
    "DID-LOCK",
    onConnectedShowNotification: () {},
    authService: _authService,
  );

  bool _isUnlocking = false;
  bool _authenticated = false; // Track authentication state
  bool _waitingForNonce = false;
  String? _receivedNonce;
  // Device messages are no longer shown in the UI to avoid exposing
  // raw nonce or device data.
  final List<String> _deviceMessages = [];
  List<String> _logs = [];
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _addLog("Dashboard initialized");
    
    // Listen to BLE connection status
    _bleService.statusStream.listen((status) {
      setState(() {
        _connected = status == ConnectionStatus.connected;
        if (_connected) {
          _addLog("BLE device connected");
        } else {
          _addLog("BLE device disconnected");
        }
      });
    });

    // Listen for nonce values from the BLE service. We use this only for state,
    // and do NOT log or display the raw nonce value.
    _bleService.nonceStream.listen((nonce) {
      setState(() {
        _receivedNonce = nonce;
        _waitingForNonce = false;
        _isUnlocking = false;
      });
      _addLog("Challenge received from device");
    });

    // Device data stream is no longer surfaced in the UI or logs to avoid
    // exposing nonce or other raw device data.
    _bleService.deviceDataStream.listen((data) {
      // Intentionally left blank – we keep the subscription so the stream
      // remains consumed, but we do not store or log the payload.
    });

    // Start BLE scan
    _authService.ensureKeyPair().then((_) {
      _bleService.startScan();
      _addLog("BLE scan started");
    });
  }

  void _addLog(String message) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _logs.insert(0, "[$timestamp] $message");
      if (_logs.length > 50) {
        _logs = _logs.take(50).toList();
      }
    });
  }

  Future<void> _handleUnlock() async {
    if (_isUnlocking) return;
    
    // If not authenticated yet, do authentication first
    if (!_authenticated) {
      setState(() {
        _isUnlocking = true;
      });
      
      _addLog("Unlock button pressed - Starting biometric authentication...");

      // Step 1: Biometric authentication
      try {
        await _authService.ensureKeyPair();
        final didAuthenticate = await _authService.authenticate();

        if (didAuthenticate) {
          setState(() {
            _authenticated = true;
            _isUnlocking = false;
          });
          _addLog("Biometric authentication successful - Click unlock again to send VP");
        } else {
          _addLog("Biometric authentication failed");
          setState(() {
            _isUnlocking = false;
          });
        }
      } catch (e) {
        _addLog("Error during authentication: $e");
        setState(() {
          _isUnlocking = false;
        });
      }
    } else {
      // Step 2: Actually unlock and send VP
      setState(() {
        _isUnlocking = true;
        _waitingForNonce = false;
      });
      
      _addLog("Unlock button clicked - Sending VP to device...");
      
      final success = await _bleService.sendVpForPendingNonce();
      if (success) {
        setState(() {
          // Unlock flow completed; return UI to initial authenticate state
          _authenticated = false;
          _waitingForNonce = false;
          _receivedNonce = null;
          _isUnlocking = false;
        });
        _addLog("VP sent successfully - Lock unlocked, returning to authenticate state");
      } else {
        setState(() {
          // Even on failure, require a fresh authentication for the next attempt
          _authenticated = false;
          _isUnlocking = false;
        });
        _addLog("No pending nonce to send or send failed - returning to authenticate state");
      }
    }
  }


  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Dashboard",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF2F6F4),
                Colors.white,
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF2F6F4),
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
        children: [
              const SizedBox(height: 20),
              
          // ------------------------------------
              // Profile Section (Classy Design)
          // ------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Profile Image
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.3),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.2),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'profile.avif',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "User Profile",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Manage your account and settings",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // ------------------------------------
              // Lock Icon and Unlock Button
              // ------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Lock Icon
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: _connected 
                            ? Colors.blueAccent.withOpacity(0.1)
                            : Colors.redAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'lock.webp',
                        width: 80,
                        height: 80,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            _connected ? Icons.lock_open : Icons.lock,
                            size: 60,
                            color: _connected ? Colors.blueAccent : Colors.redAccent,
                          );
              },
            ),
          ),
                    const SizedBox(height: 24),
                    Text(
                      _connected ? "DID-LOCK Connected" : "DID-LOCK Disconnected",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: _connected ? Colors.blueAccent : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // We intentionally do not display the raw nonce value or
                    // any device data here, to avoid surfacing sensitive
                    // protocol details in the UI.

                    // Unlock / Authenticate Button
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _isUnlocking || !_connected
                            ? []
                            : [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                  spreadRadius: 2,
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isUnlocking || !_connected ? null : _handleUnlock,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _authenticated ? Colors.green : Colors.blueAccent,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isUnlocking
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Text(
                                    "Unlocking...",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _authenticated ? Icons.lock_open_rounded : Icons.fingerprint,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    _authenticated ? "UNLOCK" : "AUTHENTICATE",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    
                    // Nonce Comparison Button (shown after biometric)
                    // No extra button needed—nonce will appear automatically once received.
                  ],
                ),
              ),

              const SizedBox(height: 40),

          // ------------------------------------
              // Logs Section
          // ------------------------------------
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 400),
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.history, color: Colors.blueAccent),
                        SizedBox(width: 8),
                        Text(
                          "Activity Logs",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _logs.isEmpty
                          ? Center(
                              child: Text(
                                "No logs yet",
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : ListView.builder(
                              reverse: false,
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
                                    _logs[index],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: Colors.grey[700],
                                    ),
                                  ),
                );
              },
            ),
          ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
