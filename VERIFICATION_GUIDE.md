# Verification Guide: TLS Fingerprint Randomization

This guide explains how to verify that fingerprint randomization is working correctly.

## Overview

Three critical aspects need verification:

1. **JA3 Fingerprint Randomization** - Each connection has different fingerprint
2. **ECH Functionality** - Encrypted Client Hello is working (if enabled)
3. **Padding Boundaries** - ClientHello doesn't exceed safe limits

## Prerequisites

### Required Tools

```bash
# Ubuntu/Debian
sudo apt-get install tshark wireshark dnsutils

# CentOS/RHEL
sudo yum install wireshark bind-utils

# macOS
brew install wireshark
```

### Optional Tools

```bash
# For ECH testing with curl (requires curl 8.2+)
# See: https://github.com/curl/curl/blob/master/docs/ECH.md

# For JA3 calculation
pip install ja3
```

## Quick Verification

### 1. Build Test Client

```bash
cd /workspaces/rustls
source $HOME/.cargo/env
cargo build --example test_randomization
```

### 2. Run Automated Tests

```bash
# Run all verification tests
sudo ./tools/run_all_verifications.sh ./target/debug/examples/test_randomization

# This will:
# - Check ECH configuration
# - Capture and analyze JA3 fingerprints
# - Verify padding boundaries
# - Generate comprehensive report
```

### 3. Review Report

```bash
# Report is saved as: verification_report_YYYYMMDD_HHMMSS.md
cat verification_report_*.md
```

## Manual Verification

### Test 1: JA3 Fingerprint Randomization

**Goal:** Verify that each connection generates a different JA3 hash.

**Steps:**

1. Start packet capture:
```bash
sudo ./tools/verify_ja3.sh any 30
```

2. In another terminal, run test client 5 times:
```bash
for i in {1..5}; do
    cargo run --example test_randomization --with-randomization
    sleep 2
done
```

3. Check results:
```bash
# Should show different cipher orders, extension orders, and lengths
cat ja3_captures_*.txt
```

**Expected Results:**

✅ **PASS:** Multiple unique cipher suite orders
✅ **PASS:** Multiple unique extension orders  
✅ **PASS:** Multiple unique ClientHello lengths

❌ **FAIL:** All connections have identical values

**Example Output:**

```
Unique cipher suite orders: 3
Unique extension orders: 4
Unique ClientHello lengths: 5
Total connections captured: 5

✅ PASS: Fingerprints are randomized

Diversity metrics:
- Cipher diversity: 60%
- Extension diversity: 80%
- Length diversity: 100%
```

### Test 2: ECH Verification

**Goal:** Verify that ECH is encrypting the SNI (if ECH is enabled).

**Steps:**

1. Run ECH verification:
```bash
./tools/verify_ech.sh
```

2. Check DNS for ECH config:
```bash
dig +short HTTPS crypto.cloudflare.com
```

3. Test with curl (if available):
```bash
curl -v https://crypto.cloudflare.com/cdn-cgi/trace 2>&1 | grep sni=
```

**Expected Results:**

✅ **PASS:** `sni=encrypted` in response
❌ **FAIL:** `sni=plaintext` in response

**Important Notes:**

- ECH requires TLS 1.3
- ECH config must be obtained from DNS HTTPS record
- Not all domains support ECH
- Test domains: crypto.cloudflare.com, defo.ie, tls-ech.dev

### Test 3: Padding Boundary Check

**Goal:** Verify that padding doesn't cause ClientHello to exceed MTU.

**Steps:**

1. Start packet capture:
```bash
sudo ./tools/verify_padding.sh any 30
```

2. In another terminal, run test client 10 times:
```bash
for i in {1..10}; do
    cargo run --example test_randomization --with-randomization
    sleep 1
done
```

3. Check results:
```bash
cat padding_analysis_*.txt
```

**Expected Results:**

✅ **PASS:** Max length < 1400 bytes (recommended)
⚠️ **WARNING:** Max length 1400-1500 bytes (usually OK)
❌ **CRITICAL:** Max length > 1500 bytes (will fragment)

**Example Output:**

```
ClientHello Length Statistics:
--------------------------------
Total connections: 10
Minimum length: 512 bytes
Maximum length: 789 bytes
Average length: 650 bytes

Boundary Analysis:
--------------------------------
Over 512 bytes (old FW threshold): 10 / 10 (100%)
Over 1400 bytes (recommended max): 0 / 10 (0%)
Over 1500 bytes (MTU threshold): 0 / 10 (0%)

✅ PASS: ClientHello within safe limits
```

## Troubleshooting

### Issue: No packets captured

**Symptoms:**
```
⚠️  No TLS ClientHello packets captured
```

**Solutions:**

1. Check network interface:
```bash
ip link show
# Use correct interface name
sudo ./tools/verify_ja3.sh eth0 30
```

2. Verify permissions:
```bash
# Must run as root
sudo ./tools/verify_ja3.sh
```

3. Ensure client is running during capture:
```bash
# Start capture first, then run client
```

### Issue: All fingerprints identical

**Symptoms:**
```
❌ FAIL: All fingerprints are identical
```

**Solutions:**

1. Verify randomization is enabled:
```rust
config.randomize_fingerprint = true;
```

2. Check you're testing correct binary:
```bash
cargo build --example test_randomization
./target/debug/examples/test_randomization --with-randomization
```

3. Verify code changes were compiled:
```bash
cargo clean
cargo build --example test_randomization
```

### Issue: ECH not working

**Symptoms:**
```
❌ ECH is NOT working (SNI in plaintext)
```

**Solutions:**

1. Check DNS for ECH config:
```bash
dig +short HTTPS crypto.cloudflare.com
# Should show: ... ech=<base64>
```

2. Verify TLS 1.3 is enabled:
```rust
// TLS 1.3 is required for ECH
config.supports_version(ProtocolVersion::TLSv1_3)
```

3. Check HPKE suite compatibility:
```rust
// Ensure your crypto provider supports required HPKE suites
```

4. Review client logs:
```bash
RUST_LOG=debug cargo run --example test_randomization
```

### Issue: ClientHello exceeds MTU

**Symptoms:**
```
❌ CRITICAL: ClientHello exceeds MTU (1523 > 1500)
```

**Solutions:**

1. Reduce padding maximum:
```rust
// In rustls/src/client/hs.rs
// Change from:
let padding_len = 80 + (random_bytes[1] as usize % 221); // 80-300

// To:
let padding_len = 80 + (random_bytes[1] as usize % 121); // 80-200
```

2. Rebuild and test:
```bash
cargo build --lib
cargo build --example test_randomization
sudo ./tools/verify_padding.sh any 30
```

## Advanced Verification

### Calculate Actual JA3 Hashes

If you have the `ja3` tool installed:

```bash
# Capture packets to pcap file
sudo tshark -i any -f "tcp port 443" -w capture.pcap

# Calculate JA3 hashes
ja3 -a capture.pcap

# Should show different hashes for each connection
```

### Analyze with Wireshark GUI

```bash
# Capture packets
sudo tshark -i any -f "tcp port 443" -w capture.pcap

# Open in Wireshark
wireshark capture.pcap

# Filter: tls.handshake.type == 1
# Inspect: TLS -> Handshake Protocol -> Client Hello
```

### Compare with Real Browser

```bash
# Capture your client
sudo tshark -i any -f "tcp port 443" -w rustls.pcap

# Capture Chrome
# (Open Chrome and visit same site)
sudo tshark -i any -f "tcp port 443" -w chrome.pcap

# Compare in Wireshark
wireshark rustls.pcap chrome.pcap
```

## Continuous Monitoring

### Production Monitoring

```bash
# Monitor connection success rate
watch -n 5 'grep "connection" /var/log/myapp.log | tail -20'

# Monitor for fragmentation
sudo tcpdump -i any 'tcp port 443 and (ip[6:2] & 0x3fff != 0)'

# Alert on high failure rate
# (Implement in your monitoring system)
```

### Regression Testing

```bash
# Add to CI/CD pipeline
#!/bin/bash
set -e

# Build
cargo build --example test_randomization

# Run verification
sudo ./tools/run_all_verifications.sh ./target/debug/examples/test_randomization

# Check report
if grep -q "All tests passed" verification_report_*.md; then
    echo "✅ Verification passed"
    exit 0
else
    echo "❌ Verification failed"
    exit 1
fi
```

## Verification Checklist

Before deploying to production:

- [ ] JA3 fingerprints are randomized (verified with packet capture)
- [ ] ECH is working (if enabled, verified with test endpoint)
- [ ] Padding is within safe boundaries (< 1400 bytes)
- [ ] Connection success rate is acceptable (> 95%)
- [ ] No fragmentation observed in production traffic
- [ ] Tested against target WAF/DPI
- [ ] Monitoring and alerting configured
- [ ] Rollback plan prepared

## Support

If verification fails:

1. Review this guide carefully
2. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
3. Review [FINGERPRINT_RANDOMIZATION.md](FINGERPRINT_RANDOMIZATION.md)
4. Open GitHub issue with:
   - Verification report
   - Packet captures (sanitized)
   - Client configuration
   - Error logs

## References

- [JA3 Fingerprinting](https://github.com/salesforce/ja3)
- [JA4 Fingerprinting](https://github.com/FoxIO-LLC/ja4)
- [Wireshark TLS Analysis](https://wiki.wireshark.org/TLS)
- [RFC 7685: Padding Extension](https://datatracker.ietf.org/doc/html/rfc7685)
- [ECH Draft](https://datatracker.ietf.org/doc/draft-ietf-tls-esni/)
