/*
Smart Lock Authentication System
Authors:
- Chethana R
- Darshan N
- Rithika Shetty
- Sanjay N
RNSIT - URF Project
*/

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

extern "C" {
  #include "monocypher.h"
  #include "monocypher-ed25519.h"
}

// ---------------- MOSFET LOCK PIN ----------------
#define LOCK_PIN 13
const int unlockDuration = 3000; // 3 seconds

// ---------------- Public key (Ed25519 – matches your Dart seed)
const uint8_t publicKey[32] = {
  0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7,
  0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a,
  0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25,
  0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a
};

// ---------------- BLE UUIDs
#define SERVICE_UUID      "12345678-1234-1234-1234-1234567890AB"
#define NONCE_CHAR_UUID   "12345678-1234-1234-1234-1234567890AC"
#define VP_CHAR_UUID      "12345678-1234-1234-1234-1234567890AD"
#define STATUS_CHAR_UUID  "12345678-1234-1234-1234-1234567890AE"

BLECharacteristic *nonceChar;
BLECharacteristic *vpChar;
BLECharacteristic *statusChar;

String currentNonce = "";
bool deviceConnected = false;

// ---------------- Unlock Function ----------------
void unlockCycle() {
  Serial.println("🔓 Unlocking (MOSFET ON)");
  digitalWrite(LOCK_PIN, HIGH);
  delay(unlockDuration);
  digitalWrite(LOCK_PIN, LOW);
  Serial.println("🔒 Locked (MOSFET OFF)");
}

// ---------------- hex → bytes (64-byte sig)
bool hexToBytes(const char *hex, uint8_t *out, size_t out_len) {
  size_t hexlen = strlen(hex);
  if (hexlen < out_len * 2) return false;

  auto val = [](char c)->int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };

  for (size_t i = 0; i < out_len; i++) {
    int h = val(hex[i*2]);
    int l = val(hex[i*2 + 1]);
    if (h < 0 || l < 0) return false;
    out[i] = (uint8_t)((h << 4) | l);
  }
  return true;
}

// ---------------- BLE Callbacks ----------------
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    Serial.println("📱 BLE Connected!");

    uint32_t r = esp_random();
    char buf[9];
    sprintf(buf, "%08X", r);
    currentNonce = String(buf);

    Serial.print("🔐 New Nonce Generated: ");
    Serial.println(currentNonce);

    nonceChar->setValue(currentNonce.c_str());
    nonceChar->notify();
  }

  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    Serial.println("❌ BLE disconnected");
    currentNonce = "";
    pServer->getAdvertising()->start();
  }
};

// ---------------- VP WRITE Callback ----------------
class VPWriteCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {

    String vp = pChar->getValue();
    Serial.println("\n📩 VP Received:");
    Serial.println(vp);

    StaticJsonDocument<1024> doc;
    if (deserializeJson(doc, vp)) {
      Serial.println("❌ JSON parse failed");
      return;
    }

    const char *nonceRaw = doc["nonce"];
    const char *vc = doc["vc"];
    const char *sigHex = doc["signature_hex"];

    if (!nonceRaw || !vc || !sigHex) {
      Serial.println("❌ Missing fields");
      return;
    }

    String n = String(nonceRaw);
    n.trim();
    if (n.startsWith("0x") || n.startsWith("0X"))
      n = n.substring(2);
    n.replace(" ", "");
    n.toUpperCase();

    if (n != currentNonce) {
      Serial.println("❌ NONCE mismatch");
      statusChar->setValue("NONCE_MISMATCH");
      statusChar->notify();
      return;
    }

    if (String(vc) != "valid_access") {
      Serial.println("❌ VC invalid");
      statusChar->setValue("VC_INVALID");
      statusChar->notify();
      return;
    }

    uint8_t sig[64];
    if (!hexToBytes(sigHex, sig, 64)) {
      Serial.println("❌ Signature hex invalid");
      statusChar->setValue("SIG_BAD");
      statusChar->notify();
      return;
    }

    String msg = n + "|" + String(vc);

    uint8_t hash[64];
    crypto_sha512(hash, (const uint8_t*)msg.c_str(), msg.length());

    int ok = crypto_ed25519_check(sig, publicKey, hash, 64);

    if (ok == 0) {
      Serial.println("🔓 ACCESS GRANTED");
      statusChar->setValue("UNLOCKED");
      statusChar->notify();

      unlockCycle();   // 🔥 MOSFET CONTROL HERE

    } else {
      Serial.println("❌ Signature INVALID");
      statusChar->setValue("DENIED");
      statusChar->notify();
    }
  }
};

// ---------------- SETUP ----------------
void setup() {
  Serial.begin(115200);

  pinMode(LOCK_PIN, OUTPUT);
  digitalWrite(LOCK_PIN, LOW);

  BLEDevice::init("DID-LOCK");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCB());

  BLEService *svc = server->createService(SERVICE_UUID);

  nonceChar = svc->createCharacteristic(
    NONCE_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_READ
  );
  nonceChar->addDescriptor(new BLE2902());

  vpChar = svc->createCharacteristic(
    VP_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  vpChar->setCallbacks(new VPWriteCB());

  statusChar = svc->createCharacteristic(
    STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_READ
  );
  statusChar->addDescriptor(new BLE2902());

  svc->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->start();

  Serial.println("📡 SmartLock BLE Started – waiting for phone");
}

// ---------------- LOOP ----------------
void loop() {
  delay(100);
}
