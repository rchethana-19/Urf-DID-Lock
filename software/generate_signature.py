#!/usr/bin/env python3
"""
Generate Ed25519 signature for message using the private key seed
"""

from nacl.signing import SigningKey
from binascii import unhexlify, hexlify

# Your private key seed (32 bytes)
PRIVATE_SEED_HEX = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'
PUBLIC_KEY_HEX = '55fd8a0c84bb7dfadf178295e2489b5c773b99f83adfcd243af4d7c8064c2ce1'

# Message to sign
nonce = "32AC8271"
vc = "valid_access"
message = f"{nonce}|{vc}"

print(f"Message to sign: {message}")
print(f"Message bytes: {message.encode('utf-8')}")
print(f"Message hex: {message.encode('utf-8').hex()}")

# Create signing key from seed
seed_bytes = unhexlify(PRIVATE_SEED_HEX)
signing_key = SigningKey(seed_bytes)

# Sign the message
message_bytes = message.encode('utf-8')
signature = signing_key.sign(message_bytes)

# Extract just the signature (first 64 bytes)
signature_bytes = signature.signature
signature_hex = hexlify(signature_bytes).decode('utf-8')

print(f"\n✅ Signature generated:")
print(f"Signature hex (128 chars): {signature_hex}")
print(f"Signature length: {len(signature_hex)}")

# Verify the public key matches
derived_public_key = signing_key.verify_key
derived_public_key_hex = hexlify(derived_public_key.encode()).decode('utf-8')
print(f"\n🔑 Derived public key: {derived_public_key_hex}")
print(f"🔑 Expected public key: {PUBLIC_KEY_HEX}")

if derived_public_key_hex.lower() == PUBLIC_KEY_HEX.lower():
    print("✅ Public key matches!")
else:
    print("⚠️ WARNING: Public key mismatch!")

# Create VP JSON payload
import json
vp_payload = {
    "nonce": nonce,
    "vc": vc,
    "signature_hex": signature_hex
}

print(f"\n📦 VP JSON Payload:")
print(json.dumps(vp_payload, indent=2))
