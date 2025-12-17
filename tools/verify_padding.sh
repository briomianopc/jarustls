#!/bin/bash
# Padding Extension Boundary Verification Tool
#
# This script checks if the Padding extension causes ClientHello to exceed
# safe boundaries (MTU, fragmentation thresholds).
#
# Checks:
# 1. ClientHello total length distribution
# 2. MTU boundary violations (1500 bytes)
# 3. Fragmentation risk (512 bytes for old firewalls)
# 4. Padding length distribution
#
# Usage:
#   sudo ./verify_padding.sh [interface] [duration]
#
# Example:
#   sudo ./verify_padding.sh eth0 30

set -e

INTERFACE="${1:-any}"
DURATION="${2:-30}"
OUTPUT_FILE="padding_analysis_$(date +%Y%m%d_%H%M%S).txt"

# Thresholds
MTU_THRESHOLD=1500
OLD_FW_THRESHOLD=512
RECOMMENDED_MAX=1400

echo "==================================="
echo "Padding Boundary Verification Tool"
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

# Capture TLS ClientHello packets with detailed length info
tshark -i "$INTERFACE" -a duration:"$DURATION" -f "tcp port 443" \
    -T fields \
    -e frame.time \
    -e ip.src \
    -e tls.record.length \
    -e tls.handshake.length \
    -e tls.handshake.extensions_length \
    -e tls.handshake.extension.type \
    -e tls.handshake.extension.len \
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
    echo "Run your test client during capture period"
    exit 1
fi

echo "📊 Analysis:"
echo ""

# Extract ClientHello lengths
LENGTHS=$(cut -d'|' -f3 "$OUTPUT_FILE" | grep -v '^$')
TOTAL=$(echo "$LENGTHS" | wc -l)

if [ "$TOTAL" -eq 0 ]; then
    echo "❌ No valid length data captured"
    exit 1
fi

# Calculate statistics
MIN=$(echo "$LENGTHS" | sort -n | head -1)
MAX=$(echo "$LENGTHS" | sort -n | tail -1)
AVG=$(echo "$LENGTHS" | awk '{sum+=$1} END {print int(sum/NR)}')

echo "  ClientHello Length Statistics:"
echo "  --------------------------------"
echo "  Total connections: $TOTAL"
echo "  Minimum length: $MIN bytes"
echo "  Maximum length: $MAX bytes"
echo "  Average length: $AVG bytes"
echo ""

# Check for boundary violations
OVER_MTU=$(echo "$LENGTHS" | awk -v t="$MTU_THRESHOLD" '$1 > t' | wc -l)
OVER_OLD_FW=$(echo "$LENGTHS" | awk -v t="$OLD_FW_THRESHOLD" '$1 > t' | wc -l)
OVER_RECOMMENDED=$(echo "$LENGTHS" | awk -v t="$RECOMMENDED_MAX" '$1 > t' | wc -l)

echo "  Boundary Analysis:"
echo "  --------------------------------"
echo "  Over $OLD_FW_THRESHOLD bytes (old FW threshold): $OVER_OLD_FW / $TOTAL ($(echo "scale=1; $OVER_OLD_FW * 100 / $TOTAL" | bc)%)"
echo "  Over $RECOMMENDED_MAX bytes (recommended max): $OVER_RECOMMENDED / $TOTAL ($(echo "scale=1; $OVER_RECOMMENDED * 100 / $TOTAL" | bc)%)"
echo "  Over $MTU_THRESHOLD bytes (MTU threshold): $OVER_MTU / $TOTAL ($(echo "scale=1; $OVER_MTU * 100 / $TOTAL" | bc)%)"
echo ""

# Length distribution histogram
echo "  Length Distribution:"
echo "  --------------------------------"
echo "$LENGTHS" | awk '{
    bucket = int($1/100)*100
    count[bucket]++
}
END {
    for (b in count) {
        printf "  %4d-%4d bytes: ", b, b+99
        for (i=0; i<count[b]; i++) printf "█"
        printf " (%d)\n", count[b]
    }
}' | sort -n

echo ""

# Check for Padding extension
echo "  Padding Extension Analysis:"
echo "  --------------------------------"

# Extract extension types and lengths
PADDING_COUNT=$(grep -o '21' "$OUTPUT_FILE" | wc -l)
if [ "$PADDING_COUNT" -gt 0 ]; then
    echo "  Padding extension found: $PADDING_COUNT times"
    echo "  Padding probability: $(echo "scale=1; $PADDING_COUNT * 100 / $TOTAL" | bc)%"
    
    # Try to extract padding lengths (extension type 21 = 0x0015)
    # This is approximate as tshark output format varies
    echo ""
    echo "  Note: Padding length extraction requires manual inspection"
    echo "  Check $OUTPUT_FILE for detailed extension data"
else
    echo "  ⚠️  No Padding extension detected"
    echo ""
    echo "  Possible reasons:"
    echo "  1. randomize_fingerprint not enabled"
    echo "  2. Padding probability (70%) didn't trigger"
    echo "  3. Capture filter issue"
fi

echo ""

# Verdict
echo "==================================="
echo "Verdict"
echo "==================================="
echo ""

if [ "$MAX" -gt "$MTU_THRESHOLD" ]; then
    echo "❌ CRITICAL: ClientHello exceeds MTU ($MAX > $MTU_THRESHOLD)"
    echo ""
    echo "   This will cause IP fragmentation!"
    echo ""
    echo "   Recommendation:"
    echo "   - Reduce padding max from 300 to 200 bytes"
    echo "   - Or reduce padding max to 150 bytes"
    echo ""
    echo "   In rustls/src/client/hs.rs, change:"
    echo "   let padding_len = 80 + (random_bytes[1] as usize % 221);"
    echo "   to:"
    echo "   let padding_len = 80 + (random_bytes[1] as usize % 121); // 80-200"
    echo ""
elif [ "$MAX" -gt "$RECOMMENDED_MAX" ]; then
    echo "⚠️  WARNING: ClientHello exceeds recommended max ($MAX > $RECOMMENDED_MAX)"
    echo ""
    echo "   This is usually OK but may cause issues with:"
    echo "   - Very old firewalls (F5, CheckPoint)"
    echo "   - Misconfigured middleboxes"
    echo "   - High-latency networks"
    echo ""
    echo "   If you experience connection issues:"
    echo "   - Reduce padding max to 200 bytes"
    echo "   - Monitor connection success rate"
    echo ""
elif [ "$MAX" -gt "$OLD_FW_THRESHOLD" ]; then
    echo "✅ PASS: ClientHello within safe limits"
    echo ""
    echo "   Max length: $MAX bytes"
    echo "   Well below MTU threshold ($MTU_THRESHOLD bytes)"
    echo ""
    echo "   This configuration should work with:"
    echo "   ✅ Modern networks"
    echo "   ✅ Most firewalls"
    echo "   ✅ CDNs (Cloudflare, Akamai, etc.)"
    echo ""
    if [ "$PADDING_COUNT" -gt 0 ]; then
        echo "   Padding is active and working correctly!"
    fi
else
    echo "⚠️  ClientHello very small ($MAX < $OLD_FW_THRESHOLD)"
    echo ""
    echo "   This might indicate:"
    echo "   - Padding not enabled"
    echo "   - Very minimal TLS configuration"
    echo "   - Capture issue"
fi

echo ""

# Length variance check
VARIANCE=$(echo "$LENGTHS" | awk '{sum+=$1; sumsq+=$1*$1} END {print int(sqrt(sumsq/NR - (sum/NR)^2))}')
echo "  Length variance: $VARIANCE bytes"

if [ "$VARIANCE" -lt 10 ]; then
    echo "  ⚠️  Very low variance - randomization may not be working"
elif [ "$VARIANCE" -gt 50 ]; then
    echo "  ✅ Good variance - randomization is working"
else
    echo "  ✅ Moderate variance - randomization is active"
fi

echo ""
echo "📄 Detailed results saved to: $OUTPUT_FILE"
echo ""
echo "To manually inspect:"
echo "  cat $OUTPUT_FILE"
echo ""
echo "To see length distribution:"
echo "  cut -d'|' -f3 $OUTPUT_FILE | sort -n | uniq -c"
