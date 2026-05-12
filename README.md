# Smart Lock Authentication System  
### BLE-Based Offline Cryptographic Access Control using Ed25519

---

## Overview

This project presents a **secure, lightweight, and fully offline smart lock authentication system** using **Bluetooth Low Energy (BLE)** and **Ed25519 digital signatures** on an ESP32 microcontroller.

The system eliminates dependence on cloud infrastructure and static credentials by implementing a **nonce-based cryptographic challenge-response mechanism** directly on embedded hardware.

The project demonstrates that strong cryptographic authentication can be achieved efficiently on constrained IoT devices while maintaining real-time performance.

---

## Key Features

### Current Implementation

- Fully Offline Authentication (No Internet Required)
- BLE-based proximity authentication
- Nonce-based replay attack prevention
- Ed25519 digital signature verification
- Real-time cryptographic verification (~18 ms)
- Lightweight embedded implementation on ESP32
- Secure unlock control using relay/MOSFET

---

### Proposed / Extended Architecture

- Owner-authorized guest delegation
- Multi-user identity management
- Expiry-based access control
- One-time guest access
- Decentralized Identity (DID) integration
- Access revocation mechanism

---

## System Architecture

```text
                    ┌──────────────────────────┐
                    │     Mobile Application   │
                    │──────────────────────────│
                    │ • Generates key pair     │
                    │ • Stores private key     │
                    │ • Connects via BLE       │
                    │ • Signs nonce            │
                    └────────────┬─────────────┘
                                 │
                                 │ BLE Communication
                                 ▼
              ┌────────────────────────────────────┐
              │          ESP32 Smart Lock          │
              │────────────────────────────────────│
              │ • BLE GATT Server                 │
              │ • Random Nonce Generation         │
              │ • SHA-512 Hashing                 │
              │ • Ed25519 Signature Verification  │
              │ • Replay Attack Protection        │
              │ • Unlock Control Logic            │
              └────────────┬──────────────────────┘
                           │
                           │ GPIO Signal
                           ▼
              ┌──────────────────────────┐
              │ Relay / Solenoid Lock    │
              │──────────────────────────│
              │ • Physical Lock Control  │
              └──────────────────────────┘
```

---

## Authentication Workflow

```text
1. Mobile app connects to ESP32 via BLE
2. ESP32 generates a random nonce
3. Nonce is sent to the mobile app
4. App signs nonce using private key
5. Signed response is sent to ESP32
6. ESP32 recomputes hash and verifies signature
7. If valid → Unlock
8. If invalid → Access denied
```

---

## Security Features

| Feature | Purpose |
|----------|----------|
| Nonce-based Authentication | Prevent replay attacks |
| Ed25519 Signatures | Strong identity verification |
| SHA-512 Hashing | Message integrity |
| BLE Proximity | Localized communication |
| Offline Verification | No cloud dependency |
| Public-Key Cryptography | No shared secret exposure |

---

## Hardware Requirements

- ESP32 DevKit (BLE-enabled)
- Relay Module / MOSFET
- 12V Solenoid Lock
- Power Supply
- Jumper Wires
- Breadboard / PCB

### Optional Components

- DS3231 RTC Module
- SSD1306 OLED Display

---

## Software Stack

| Component | Technology |
|-----------|------------|
| Embedded Firmware | Arduino Framework |
| Cryptography | Monocypher (Ed25519) |
| Mobile Application | Flutter |
| Communication | BLE GATT |
| JSON Handling | ArduinoJson |

---

## Mobile App Features

- Ed25519 key pair generation
- Secure private key storage
- BLE communication with ESP32
- Nonce signing
- Authentication handling

---

## Experimental Setup

| Parameter | Details |
|-----------|---------|
| Hardware | ESP32 DevKit |
| Clock Speed | 240 MHz Dual-Core |
| Cryptography | Ed25519 |
| Communication | BLE GATT |
| Measurement | Microsecond-level timing |
| Testing | 100+ replay attack simulations |

---

## Performance Results

| Metric | Value |
|--------|-------|
| Average Latency | ~18.3 ms |
| Minimum Latency | ~18.29 ms |
| Maximum Latency | ~18.80 ms |
| Replay Detection Rate | 100% |
| False Acceptance Rate | 0% |
| False Rejection Rate | ~0% |

---

## Performance Analysis

- Stable execution across repeated runs
- Low latency suitable for real-time applications
- Minimal execution variance (~0.5 ms)
- Efficient cryptographic verification on constrained hardware
- Strong replay attack resistance

---

## Comparative Analysis

| Method | Internet Dependency | Security | Replay Protection | Latency |
|--------|---------------------|----------|-------------------|---------|
| RFID | No | Low | No | ~5 ms |
| OTP (Cloud) | Yes | Medium | Yes | >500 ms |
| BLE Token | No | Medium | No | ~10 ms |
| **Proposed System** | No | High | Yes | ~18 ms |

---

## Setup Instructions

### 1. Upload ESP32 Firmware

Install required Arduino libraries:

- BLEDevice
- ArduinoJson
- Monocypher
- RTClib (optional)
- Adafruit SSD1306 (optional)

Upload firmware to ESP32 using Arduino IDE.

---

### 2. Run Flutter App

```bash
cd software
flutter pub get
flutter run
```

---

### 3. Authentication Process

1. Power ESP32
2. Open mobile app
3. Connect via BLE
4. Receive nonce
5. Sign nonce
6. Send signed response
7. Unlock on successful verification

---

## Security Considerations

### Replay Attack Prevention
Each authentication request uses a newly generated nonce, ensuring previously captured messages cannot be reused.

### Offline Operation
Authentication is performed entirely on-device without requiring cloud communication.

### Cryptographic Integrity
ESP32 independently reconstructs and hashes messages before verification, ensuring no client-side computation is blindly trusted.

---

## Proposed Future Work

- Multi-user support using DID
- Guest delegation model
- Expiry-based access control
- One-time authentication tokens
- Secure access revocation
- OTA firmware updates
- Biometric integration
- Post-Quantum Cryptography migration

---

## Authors

- Chethana R
- Darshan N
- Rithika Shetty
- Sanjay N

---

## References

1. Lam & Chi (2016) – IoT Identity Framework  
2. Cao et al. (2023) – Blockchain Systems  
3. NIST SP 800-63-3 (2017) – Digital Identity Guidelines  
4. Shafique et al. (2020) – IoT Security Review  
5. Basir & Omar (2020) – Decentralized Identity Models  

---

## Conclusion

This project demonstrates that **strong cryptographic authentication can be implemented efficiently on embedded IoT hardware while maintaining low latency, offline capability, and robust replay attack protection**.

The system validates the feasibility of lightweight decentralized authentication mechanisms for next-generation smart lock applications.

---
