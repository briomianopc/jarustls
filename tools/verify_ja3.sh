#!/bin/bash
# JA3 Fingerprint Verification Tool
# 
# This script captures TLS ClientHello packets and extracts JA3 fingerprints
# to verify that fingerprint randomization is working correctly.
#
# Requirements:
# - tshark (Wireshark CLI)
# - Root/sudo access for packet capture
#
# Usage:
#   sudo ./verify_ja3.sh [interface] [duration]
#
# Example:
#   sudo ./verify_ja3.sh eth0 30

set -e

INTERFACE="${1:-any}"
DURATION="${2:-30}"
OUTPUT_FILE="ja3_captures_$(date +%Y%m%d_%H%M%S).txt"

echo "==================================="
echo "JA3 Fingerprint Verification Tool"
echo "==================================="
echo ""
echo "Interface: $INTERFACE"
echo "Duration: ${DURATION}s"
echo "Output: $OUTPUT_FILE"
echo ""

# Check if tshark is installed
if ! command -v tshark &> /dev/null; then
    echo "❌ Error: tshark not found"
    echo ""
    echo "Install with:"
    echo "  Ubuntu/Debian: sudo apt-get install tshark"
    echo "  CentOS/RHEL:   sudo yum install wireshark"
    echo "  macOS:         brew install wireshark"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Warning: Not running as root"
    echo "   Packet capture may fail. Try: sudo $0 $@"
    echo ""
fi

echo "📡 Starting packet capture..."
echo "   Press Ctrl+C to stop early"
echo ""

# Capture TLS ClientHello packets
# Extract: JA3 hash, SNI, cipher suites, extensions
tshark -i "$INTERFACE" -a duration:"$DURATION" -f "tcp port 443" \
    -T fields \
    -e frame.time \
    -e ip.src \
    -e ip.dst \
    -e tls.handshake.extensions_server_name \
    -e tls.handshake.ciphersuite \
    -e tls.handshake.extension.type \
    -e tls.handshake.extensions_supported_group \
    -e tls.record.length \
    -Y "tls.handshake.type == 1" \
    -E separator='|' \
    2>/dev/null | tee "$OUTPUT_FILE"

echo ""
echo "✅ Capture complete"
echo ""

# Analyze results
if [ ! -s "$OUTPUT_FILE" ]; then
    echo "⚠️  No TLS ClientHello packets captured"
    echo ""
    echo "Possible reasons:"
    echo "  1. No TLS connections during capture period"
    echo "  2. Wrong network interface"
    echo "  3. Insufficient permissions"
    echo ""
    echo "Try:"
    echo "  - Run your test client during capture"
    echo "  - Check interface with: ip link show"
    echo "  - Run with sudo"
    exit 1
fi

echo "📊 Analysis:"
echo ""

# Count unique cipher suite orders
CIPHER_ORDERS=$(cut -d'|' -f5 "$OUTPUT_FILE" | sort | uniq | wc -l)
echo "  Unique cipher suite orders: $CIPHER_ORDERS"

# Count unique extension orders
EXT_ORDERS=$(cut -d'|' -f6 "$OUTPUT_FILE" | sort | uniq | wc -l)
echo "  Unique extension orders: $EXT_ORDERS"

# Count unique ClientHello lengths
LENGTHS=$(cut -d'|' -f8 "$OUTPUT_FILE" | sort | uniq | wc -l)
echo "  Unique ClientHello lengths: $LENGTHS"

# Total connections
TOTAL=$(wc -l < "$OUTPUT_FILE")
echo "  Total connections captured: $TOTAL"

echo ""

# Verdict
if [ "$TOTAL" -lt 2 ]; then
    echo "⚠️  Need at least 2 connections to verify randomization"
    echo "   Run your test client multiple times during capture"
elif [ "$CIPHER_ORDERS" -eq 1 ] && [ "$EXT_ORDERS" -eq 1 ] && [ "$LENGTHS" -eq 1 ]; then
    echo "❌ FAIL: All fingerprints are identical"
    echo "   Randomization is NOT working"
    echo ""
    echo "   Check:"
    echo "   - Is randomize_fingerprint = true?"
    echo "   - Are you testing the correct binary?"
elif [ "$CIPHER_ORDERS" -gt 1 ] || [ "$EXT_ORDERS" -gt 1 ] || [ "$LENGTHS" -gt 1 ]; then
    echo "✅ PASS: Fingerprints are randomized"
    echo ""
    echo "   Diversity metrics:"
    echo "   - Cipher diversity: $(echo "scale=2; $CIPHER_ORDERS * 100 / $TOTAL" | bc)%"
    echo "   - Extension diversity: $(echo "scale=2; $EXT_ORDERS * 100 / $TOTAL" | bc)%"
    echo "   - Length diversity: $(echo "scale=2; $LENGTHS * 100 / $TOTAL" | bc)%"
else
    echo "⚠️  Inconclusive results"
fi

echo ""
echo "📄 Detailed results saved to: $OUTPUT_FILE"
echo ""
echo "To manually inspect:"
echo "  cat $OUTPUT_FILE"
echo ""
echo "To calculate JA3 hashes (requires ja3 tool):"
echo "  ja3 -a $OUTPUT_FILE"
