# Smart Lock Authentication System  
### BLE-Based Offline Cryptographic Access Control using Ed25519

---

## Overview

This project presents a **secure, lightweight, and fully offline smart lock system** using **Bluetooth Low Energy (BLE)** and **Ed25519 digital signatures**.

The system eliminates reliance on cloud infrastructure and static credentials by implementing a **nonce-based challenge-response authentication mechanism** directly on an ESP32 microcontroller.

---

## Key Features

- Fully Offline Authentication (No Internet Required)  
- Ed25519 Cryptographic Signatures  
- Replay Attack Protection using Nonce  
- BLE Communication (Proximity-based access)  
- Low Latency (~18 ms)  
- Lightweight Embedded Implementation  
- Identity-Based Access Control  



## System Architecture
```
Guest App → BLE → ESP32 Smart Lock
↓
Nonce Generation
↓
Signature Verification
↓
Unlock
```


## Authentication Flow

1. ESP32 generates a random **nonce**
2. Mobile app signs the nonce using **private key**
3. ESP32 verifies signature using **public key**
4. If valid →  Unlock

---

## Security Model

| Component     | Purpose                          |
|--------------|----------------------------------|
| Nonce        | Prevent replay attacks           |
| Ed25519      | Strong authentication            |
| Private Key  | User identity (secret)           |
| Public Key   | Stored for verification          |
| BLE          | Communication channel            |

---

## Hardware Requirements

- ESP32 DevKit (BLE-enabled)
- Relay Module
- 12V Solenoid Lock
- Power Supply
- (Optional) DS3231 RTC Module
- (Optional) SSD1306 OLED Display

---

## Software Stack

- Embedded: Arduino (ESP32)
- Crypto: Monocypher (Ed25519)
- Mobile App: Flutter
- Communication: BLE (GATT)
- Storage: NVS (Non-Volatile Storage)

---

## Mobile App Features

- Ed25519 key pair generation  
- Secure key storage (Android Keystore)  
- BLE communication  
- Nonce signing  
- Authentication request handling  

---

## Experimental Setup

- Device: ESP32 (240 MHz dual-core)  
- Crypto: Ed25519 signatures  
- Communication: BLE GATT  
- Testing:
  - 100+ replay attack simulations  
  - Microsecond latency measurement  

---

## Performance Results

| Metric             | Value      |
|-------------------|-----------|
| Avg Latency       | ~18.3 ms  |
| Min               | ~18.29 ms |
| Max               | ~18.80 ms |
| Replay Detection  | 100%      |
| False Acceptance  | 0%        |
| False Rejection   | ~0%       |

---

## Comparison

| Method        | Internet | Security | Replay Protection |
|--------------|---------|----------|------------------|
| RFID         | No      | Low      | No               |
| OTP (Cloud)  | Yes     | Medium   | Yes              |
| BLE Token    | No      | Medium   | No               |
| **Proposed** | No      | High     | Yes              |

---

## Setup Instructions

### 1. Upload ESP32 Code

- Open Arduino IDE  
- Install libraries:
  - RTClib  
  - Adafruit SSD1306  
  - ArduinoJson  
  - Monocypher  
- Upload code to ESP32  

---

### 2. Generate Keys

Use Python or mobile app to generate:
- Public Key  
- Private Key  

---

### 3. Run System

- Power ESP32  
- Connect via BLE  
- Receive nonce  
- Sign nonce  
- Send signature  
- Unlock  

---

---

## Future Work

- Multi-user support (DID-based system)  
- Access revocation mechanism  
- OTA firmware updates  
- Biometric authentication integration  
- Large-scale IoT deployment  

---

## Authors

- Chethana R  
- Darshan N  
- Rithika Shetty  
- Sanjay N  

---

## Conclusion

This project demonstrates that **strong cryptographic security can be achieved on embedded systems** while maintaining **offline functionality and real-time performance**.

---

## Tagline

**Secure identity. Offline access. Real-time protection.**

