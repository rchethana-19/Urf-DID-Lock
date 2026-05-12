import 'dart:async';
import 'package:flutter/material.dart';
import 'package:smartlock_app/services/auth_service.dart';
import 'package:smartlock_app/services/ble_service.dart';
import 'package:smartlock_app/screens/views/locked_view.dart';
import 'package:smartlock_app/screens/views/tap_to_unlock_view.dart';
import 'package:smartlock_app/screens/views/authenticated_ready_view.dart';
import 'package:smartlock_app/screens/views/unlocked_view.dart';
import 'package:smartlock_app/services/debug/verify_signature.dart';

class LockHomeScreen extends StatefulWidget {
  const LockHomeScreen({super.key});

  @override
  State<LockHomeScreen> createState() => _LockHomeScreenState();
}

class _LockHomeScreenState extends State<LockHomeScreen> {
  // Services
  final AuthService _authService = AuthService();
  
  void _handleNotificationTrigger() {
    // Placeholder for local notification (e.g., flutter_local_notifications package)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔔 NOTIFICATION: Tap to Unlock!"),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
  
  // Initialize BleService with the target name and AuthService injection
  late final BleService _bleService = BleService(
    "DID-LOCK", // The new, specific target name
    onConnectedShowNotification: _handleNotificationTrigger,
    authService: _authService, // Injected dependency
  );
  

  // State variables
  bool _connected = false;
  bool _authenticated = false;
  bool _unlocked = false; // New state: true only after VP is sent
  String? _qrPayload; 
  String? _provisioningKey; // Public Key storage
  bool _showProvisioningKey = false; 

  StreamSubscription<ConnectionStatus>? _bleStatusSub;
  StreamSubscription<String>? _nonceSub;
  
  // NEW: Function to hide the key permanently
  Future<void> _markProvisioningComplete() async {
    await _authService.setProvisioningComplete(true);
    setState(() {
      _showProvisioningKey = false;
    });
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Public Key hidden. Provisioning complete.")),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Key setup is critical for the flow. We ensure keys exist before anything else.
    _authService.ensureKeyPair().then((_) async {
      final isComplete = await _authService.isProvisioningComplete();
      
      setState(() {
        _provisioningKey = _authService.getProvisioningPublicKey();
        // Show the key ONLY if provisioning is NOT yet complete
        _showProvisioningKey = !isComplete; 
      });
      // Start BLE scan AFTER keys are confirmed ready
      _bleService.startScan();
    });

    _bleStatusSub = _bleService.statusStream.listen((status) {
      setState(() {
        _connected = status == ConnectionStatus.connected;
        if (!_connected) {
          _authenticated = false;
          _unlocked = false;
          _qrPayload = null;
        }
      });
    });

    // Listen for nonce - just store it, don't auto-send even if authenticated.
    // We deliberately avoid logging the raw nonce value.
    _nonceSub = _bleService.nonceStream.listen((nonce) {
      debugPrint("📥 Challenge received from device");
      debugPrint("⏳ Challenge stored, waiting for user to click unlock button");
    });
  }

  // Authentication logic (Triggers key usage)
  Future<void> handleAuthentication() async {
    // 1. Ensure keys are loaded/generated (safe to call multiple times)
    await _authService.ensureKeyPair(); 
    
    // 2. Perform biometric authentication
    final didAuthenticate = await _authService.authenticate();

    if (didAuthenticate) {
      // Get the Public Key immediately after successful authentication
      final publicKey = _authService.getProvisioningPublicKey();
      
      setState(() {
        _authenticated = true;
        _provisioningKey = publicKey;
        // Don't unlock yet - wait for second click
      });
      
      debugPrint("✅ Authentication successful - waiting for unlock button click");
    }
  }

  // Second step: Actually unlock and send VP
  Future<void> handleUnlock() async {
    if (!_authenticated || !_connected) {
      debugPrint("⚠️ Cannot unlock: not authenticated or not connected");
      return;
    }

    debugPrint("🔓 Unlock button clicked - sending VP");
    
    final success = await _bleService.sendVpForPendingNonce();
    if (success) {
      setState(() {
        _unlocked = true;
      });
      debugPrint("✅ VP sent successfully - lock unlocked");
    } else {
      debugPrint("⚠️ Failed to send VP or no pending nonce");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No nonce available. Waiting for device..."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
  
  // Placeholder for QR regeneration (kept for code completeness)
  Future<void> regenerateQr() async {
    if (!_authenticated || !_connected) return;
    
    // NOTE: This uses a static nonce 'DEBUG_NONCE' for manual testing.
    final payload = await _authService.signChallengeAndBuildVpJson(nonce: 'DEBUG_NONCE');
    setState(() => _qrPayload = payload);
  }

  // Dispose of resources
  @override
  void dispose() {
    debugPrint("🧹 Disposing LockHomeScreen Resources...");
    _bleStatusSub?.cancel();
    _nonceSub?.cancel();
    _bleService.dispose();
    super.dispose();
  }

  // Build method remains clean
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F4),
      appBar: AppBar(
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
        title: const Text(
          "SmartLock",
          style: TextStyle(
            color: Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Debug Button
          TextButton(
            onPressed: () async {
              final result = await verifyVpLocally(
                nonce: "CECE562F",
                vc: "valid_access",
                signatureHex:
                    "9c9c001dac5ad4a84458036060888026c0bf76db38c968a06beb5b61c3569e3f75ff62faede0e71b2e44a8245bbe2215c1cf06debf7e17bfbe46291d8dc09704",
                publicKeyHex:
                    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
              );

              debugPrint("LOCAL VERIFY: $result");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Local verification: $result"),
                    backgroundColor: Colors.blueAccent,
                  ),
                );
              }
            },
            child: const Text(
              "Test Sig",
              style: TextStyle(color: Colors.blueAccent, fontSize: 14),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(right: 18.0),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (_connected && _authenticated
                        ? Colors.blueAccent
                        : Colors.redAccent)
                    .withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _connected && _unlocked
                    ? Icons.lock_open_rounded
                    : Icons.lock_rounded,
                color: _connected && _unlocked
                    ? Colors.blueAccent
                    : Colors.redAccent,
                size: 24,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: !_connected
            ? const LockedView()
            : !_authenticated
                ? TapToUnlockView(onTap: handleAuthentication)
                : !_unlocked
                    ? AuthenticatedReadyView(onUnlock: handleUnlock)
                    // 💡 FIX: Added missing 'onProvisioningComplete' parameter
                    : UnlockedView(
                        qrPayload: _qrPayload,
                        onRegenerate: regenerateQr,
                        provisioningKey: _showProvisioningKey ? _provisioningKey : null, 
                        onProvisioningComplete: _markProvisioningComplete, // <-- THIS WAS MISSING
                      ),
      ),
    );
  }
}