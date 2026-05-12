// lib/services/ble_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:smartlock_app/services/auth_service.dart';

enum ConnectionStatus { searching, connected, disconnected }

// IMPORTANT: These UUIDs must match your ESP32 code exactly.
const String SMARTLOCK_SERVICE_UUID = "12345678-1234-1234-1234-1234567890AB";
const String NONCE_CHAR_UUID = "12345678-1234-1234-1234-1234567890AC";
const String VP_INPUT_CHAR_UUID = "12345678-1234-1234-1234-1234567890AD";

class BleService {
  final String targetDeviceName;
  final VoidCallback onConnectedShowNotification;
  final AuthService authService;

  // Streams for UI
  final StreamController<String> _nonceController = StreamController<String>.broadcast();
  Stream<String> get nonceStream => _nonceController.stream;

  final StreamController<String> _deviceDataController = StreamController<String>.broadcast();
  Stream<String> get deviceDataStream => _deviceDataController.stream;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  // BLE state
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _nonceSub;
  Timer? _rescanTimer;

  BluetoothDevice? currentDevice;
  BluetoothCharacteristic? _nonceChar;
  BluetoothCharacteristic? _vpInputChar;

  // Buffer per device to assemble fragmented notifications
  final Map<String, StringBuffer> _incomingBuffers = {};
  
  // Track last processed nonce to prevent duplicate sends
  String? _lastProcessedNonce;
  
  // Store pending nonce waiting for user authentication
  String? _pendingNonce;

  BleService(this.targetDeviceName, {required this.onConnectedShowNotification, required this.authService});

  void _triggerNotification() {
    debugPrint("🔔 NOTIFICATION TRIGGERED: TAP TO UNLOCK!");
    onConnectedShowNotification();
  }

  // ---------------------------------------------------------
  // Start BLE Scan (30s Rescan)
  // ---------------------------------------------------------
  void startScan() async {
    _rescanTimer?.cancel();

    debugPrint("🔍 Scanning for $targetDeviceName...");
    _statusController.add(ConnectionStatus.searching);

    await FlutterBluePlus.stopScan();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == targetDeviceName) {
          debugPrint("🎯 TARGET FOUND: ${r.device.id}");
          _rescanTimer?.cancel();
          FlutterBluePlus.stopScan();
          connectToDevice(r.device);
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));

    _rescanTimer = Timer(const Duration(seconds: 30), () {
      debugPrint("⏱️ 30s timeout reached. Restarting scan silently...");
      if (currentDevice == null) {
        startScan();
      }
    });
  }

  // ---------------------------------------------------------
  // Connect To Device & Discover Characteristics
  // ---------------------------------------------------------
  Future<void> connectToDevice(BluetoothDevice d) async {
    debugPrint("⏳ Connecting to ${d.id} ...");

    try {
      await d.connect(license: License.free, timeout: const Duration(seconds: 8));
      debugPrint("✅ Connected Successfully");
      currentDevice = d;
      _lastProcessedNonce = null; // Reset for new connection
      _pendingNonce = null; // Reset pending nonce for new connection
      _statusController.add(ConnectionStatus.connected);
      _triggerNotification();

      await _discoverCharacteristics(d);

      _connSub?.cancel();
      _connSub = d.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint("⚠️ DEVICE DISCONNECTED");
          _statusController.add(ConnectionStatus.disconnected);
          currentDevice = null;
          _lastProcessedNonce = null; // Reset for next connection
          _pendingNonce = null; // Reset pending nonce
          Future.delayed(const Duration(seconds: 2), () => startScan());
        }
      });
    } catch (e) {
      debugPrint("❌ Connection Failed: $e");
      _statusController.add(ConnectionStatus.disconnected);
      Future.delayed(const Duration(seconds: 3), () => startScan());
    }
  }

  Future<void> _discoverCharacteristics(BluetoothDevice d) async {
    try {
      final services = await d.discoverServices();
      debugPrint("Discovered ${services.length} services");

      // log services and characteristics (helps debug mismatches)
      for (final s in services) {
        debugPrint("Service: ${s.serviceUuid.str}");
        for (final c in s.characteristics) {
          debugPrint("  Char: ${c.characteristicUuid.str} props=${c.properties}");
        }
      }

      final service = services.firstWhere(
        (s) => s.serviceUuid.str.toUpperCase() == SMARTLOCK_SERVICE_UUID.toUpperCase(),
        orElse: () => throw Exception("Service $SMARTLOCK_SERVICE_UUID not found"),
      );

      _nonceChar = service.characteristics.firstWhere(
        (c) => c.characteristicUuid.str.toUpperCase() == NONCE_CHAR_UUID.toUpperCase(),
        orElse: () => throw Exception("Nonce char $NONCE_CHAR_UUID not found"),
      );

      _vpInputChar = service.characteristics.firstWhere(
        (c) => c.characteristicUuid.str.toUpperCase() == VP_INPUT_CHAR_UUID.toUpperCase(),
        orElse: () => throw Exception("VP char $VP_INPUT_CHAR_UUID not found"),
      );

      debugPrint("Services/Characteristics discovered successfully.");

      // enable notify and read immediate value
      final enabled = await _nonceChar!.setNotifyValue(true);
      debugPrint("Nonce notify enabled: $enabled");

      // read any current value (some devices place an initial value)
      try {
        final current = await _nonceChar!.read();
        if (current.isNotEmpty) {
          debugPrint("Initial nonce read (raw bytes): $current");
          // Don't process immediately - wait for user to click unlock
          // Store it but don't auto-send
          _handleNonceChallenge(current);
        }
      } catch (e) {
        debugPrint("Initial read failed (ok): $e");
      }

      // Subscribe to the notifications stream — use `value` not `lastValueStream`
      _nonceSub?.cancel();
      _nonceSub = _nonceChar!.value.listen(_handleNonceChallenge, onError: (e) {
        debugPrint("Nonce stream error: $e");
      });

    } catch (e) {
      debugPrint("❌ Characteristic Discovery Failed: $e");
      currentDevice?.disconnect();
    }
  }

  void _handleNonceChallenge(List<int> value) async {
    if (value.isEmpty) {
      debugPrint("Received empty nonce notification; ignoring.");
      return;
    }

    // Build quick hex/ASCII debug strings (but do NOT log raw values)
    final rawHex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    String ascii = "";
    try {
      ascii = utf8.decode(value, allowMalformed: true);
    } catch (_) {
      ascii = "";
    }

    // Only log lengths / metadata to avoid exposing nonce/device data
    debugPrint(">>> Raw bytes length: ${value.length}");
    debugPrint(">>> Raw hex length: ${rawHex.length}");
    debugPrint(">>> ASCII decoded length: ${ascii.length}");

    // If we have a connected device, use its id as key; else use 'default'
    final key = currentDevice?.id.id ?? 'default';
    _incomingBuffers.putIfAbsent(key, () => StringBuffer());

    // Append whatever we got (either ascii or hex fallback)
    if (ascii.isNotEmpty) {
      _incomingBuffers[key]!.write(ascii);
    } else {
      // If ascii decode failed, append hex string (prefix with no 0x)
      _incomingBuffers[key]!.write(rawHex);
    }

    final assembled = _incomingBuffers[key]!.toString().trim();
    debugPrint("Assembled buffer length: ${assembled.length}");

    // Normalize first to check for valid nonce format
    String nonce = assembled;
    if (nonce.startsWith("0x") || nonce.startsWith("0X")) {
      nonce = nonce.substring(2).trim();
    }
    // Extract only hex characters
    nonce = nonce.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

    debugPrint("Normalized nonce length (so far): ${nonce.length}");

    // Check completion: A valid nonce should be 8 hex characters (4 bytes)
    // Also check for newlines or if we have enough hex chars
    final hasNewline = assembled.contains('\n') || assembled.contains('\r');
    final hasValidNonceLength = nonce.length >= 8; // Standard nonce is 8 hex chars
    final hasMinimumHexChars = nonce.length >= 6; // At least 6 hex chars (3 bytes)
    final hasMinimumBufferLength = assembled.length >= 6; // Fallback for buffer length

    // Process if:
    // 1. We have a newline (definite end)
    // 2. We have 8+ hex chars (complete nonce)
    // 3. We have 6+ hex chars AND buffer is long enough (likely complete)
    final isLikelyComplete = hasNewline || hasValidNonceLength || 
        (hasMinimumHexChars && hasMinimumBufferLength);

    if (!isLikelyComplete) {
      debugPrint("⏳ Waiting for more fragments (hex chars: ${nonce.length}, buffer: ${assembled.length})");
      return; // wait for more notifications
    }

    debugPrint("✅ Completion detected - processing nonce");

    // If we have more than 8 hex chars, take only the first 8 (in case of extra data)
    if (nonce.length > 8) {
      debugPrint("⚠️ Nonce longer than expected (${nonce.length} chars), truncating to 8 chars");
      nonce = nonce.substring(0, 8);
    }

    if (nonce.isEmpty || nonce.length < 6) {
      debugPrint("❌ Parsed nonce invalid (empty or too short, length: ${nonce.length}) -> ignoring");
      _incomingBuffers[key]!.clear();
      return;
    }

    debugPrint("✅ Received Nonce Challenge (normalized, length: ${nonce.length})");

    // Check if this nonce was already sent (prevent duplicate sends)
    if (_lastProcessedNonce == nonce && _pendingNonce != nonce) {
      debugPrint("⚠️ Duplicate nonce detected (already sent), ignoring");
      _incomingBuffers[key]!.clear();
      return;
    }

    // Store nonce as pending - wait for user to click unlock button
    // Don't mark as processed yet - only mark after successful send
    _pendingNonce = nonce;
    
    // push to streams/UI so app can react (but do NOT expose raw nonce/device data)
    debugPrint("📤 Notifying UI that a challenge was received.");
    _nonceController.add(nonce);
    // NOTE: We intentionally do not send the raw nonce or hex bytes over the
    // public deviceDataStream to avoid exposing sensitive device data.
    _deviceDataController.add("Challenge received from device.");
    debugPrint("✅ Challenge notification pushed to UI stream - waiting for user authentication");

    // clear buffer for next nonce
    _incomingBuffers[key]!.clear();
    
    // DO NOT automatically sign and send - wait for user to click unlock button
  }

  // ---------------------------------------------------------
  // Send VP for Pending Nonce (Called after user authentication)
  // ---------------------------------------------------------
  Future<bool> sendVpForPendingNonce() async {
    if (_pendingNonce == null) {
      debugPrint("⚠️ No pending nonce to sign");
      return false;
    }

    if (_vpInputChar == null) {
      debugPrint("⚠️ VP input characteristic not available");
      return false;
    }

    if (currentDevice == null) {
      debugPrint("⚠️ No device connected");
      return false;
    }

    final nonce = _pendingNonce!;
    
    // Check if we already sent this exact nonce
    if (_lastProcessedNonce == nonce) {
      debugPrint("⚠️ This nonce was already sent, skipping duplicate");
      _pendingNonce = null; // Clear it anyway
      return false;
    }
    
    // Do not log the actual nonce value for privacy
    debugPrint("🔐 Signing and sending VP for received challenge");

    try {
      // sign & send VP (do not expose VP payload contents via logs or UI streams)
      final vpJsonPayload = await authService.signChallengeAndBuildVpJson(nonce: nonce);
      _deviceDataController.add("VP payload sent to device.");

      await _vpInputChar!.write(
        utf8.encode(vpJsonPayload),
        withoutResponse: false,
      );
      debugPrint("✅ Sent VP JSON payload to lock");

      // Mark as processed and clear pending nonce after successful send
      _lastProcessedNonce = nonce;
      _pendingNonce = null;
      return true;
    } catch (e) {
      debugPrint("❌ Failed to sign or send VP payload: $e");
      // Don't clear pending nonce on error - allow retry
      return false;
    }
  }

  // Get pending nonce (for UI display)
  String? get pendingNonce => _pendingNonce;

  // ---------------------------------------------------------
  // Cleanup Resources
  // ---------------------------------------------------------
  void dispose() {
    debugPrint("🧹 Disposing BLE Resources...");
    _scanSub?.cancel();
    _connSub?.cancel();
    _nonceSub?.cancel();
    _rescanTimer?.cancel();
    currentDevice?.disconnect();
    _statusController.close();
    _nonceController.close();
    _deviceDataController.close();
  }
}