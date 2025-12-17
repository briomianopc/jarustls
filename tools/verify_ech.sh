#!/bin/bash
# ECH (Encrypted Client Hello) Verification Tool
#
# This script verifies that ECH is working correctly by:
# 1. Testing against Cloudflare's ECH test endpoint
# 2. Checking SNI encryption status
# 3. Verifying ECH extension presence in ClientHello
#
# Usage:
#   ./verify_ech.sh [test_binary]
#
# Example:
#   ./verify_ech.sh ./target/debug/my_client

set -e

TEST_BINARY="${1:-}"
TEST_URL="https://crypto.cloudflare.com/cdn-cgi/trace"
ECH_TEST_DOMAIN="crypto.cloudflare.com"

echo "==================================="
echo "ECH Verification Tool"
echo "==================================="
echo ""

# Function to test ECH with curl (if available)
test_with_curl() {
    echo "📡 Testing ECH with curl..."
    echo ""
    
    if ! command -v curl &> /dev/null; then
        echo "⚠️  curl not found, skipping curl test"
        return 1
    fi
    
    # Check if curl supports ECH
    if ! curl --help all 2>&1 | grep -q "ech"; then
        echo "⚠️  curl doesn't support ECH (need curl 8.2+)"
        echo "   Install ECH-enabled curl:"
        echo "   https://github.com/curl/curl/blob/master/docs/ECH.md"
        return 1
    fi
    
    # Test with ECH
    echo "Testing: $TEST_URL"
    RESULT=$(curl -s "$TEST_URL" 2>&1)
    
    if echo "$RESULT" | grep -q "sni=encrypted"; then
        echo "✅ ECH is working (SNI encrypted)"
        echo ""
        echo "Response excerpt:"
        echo "$RESULT" | grep "sni="
        return 0
    elif echo "$RESULT" | grep -q "sni=plaintext"; then
        echo "❌ ECH is NOT working (SNI in plaintext)"
        echo ""
        echo "Response excerpt:"
        echo "$RESULT" | grep "sni="
        echo ""
        echo "Possible reasons:"
        echo "  1. ECH config not obtained from DNS"
        echo "  2. ECH negotiation failed"
        echo "  3. Server doesn't support ECH"
        return 1
    else
        echo "⚠️  Could not determine ECH status"
        echo ""
        echo "Response:"
        echo "$RESULT"
        return 1
    fi
}

# Function to check DNS for ECH config
check_ech_dns() {
    echo "🔍 Checking DNS for ECH config..."
    echo ""
    
    if ! command -v dig &> /dev/null; then
        echo "⚠️  dig not found, skipping DNS check"
        echo "   Install: sudo apt-get install dnsutils"
        return 1
    fi
    
    # Query HTTPS record for ECH config
    echo "Querying: $ECH_TEST_DOMAIN"
    DNS_RESULT=$(dig +short HTTPS "$ECH_TEST_DOMAIN" 2>&1)
    
    if [ -z "$DNS_RESULT" ]; then
        echo "❌ No HTTPS record found"
        echo "   ECH config not available via DNS"
        return 1
    fi
    
    if echo "$DNS_RESULT" | grep -q "ech="; then
        echo "✅ ECH config found in DNS"
        echo ""
        echo "HTTPS record:"
        echo "$DNS_RESULT" | head -3
        echo ""
        
        # Extract ECH config (base64 encoded)
        ECH_CONFIG=$(echo "$DNS_RESULT" | grep -o 'ech=[^ ]*' | cut -d= -f2)
        if [ -n "$ECH_CONFIG" ]; then
            echo "ECH config (base64): ${ECH_CONFIG:0:50}..."
            echo "Length: ${#ECH_CONFIG} characters"
        fi
        return 0
    else
        echo "⚠️  HTTPS record found but no ECH config"
        echo ""
        echo "DNS response:"
        echo "$DNS_RESULT"
        return 1
    fi
}

# Function to test with custom binary
test_with_binary() {
    if [ -z "$TEST_BINARY" ]; then
        echo "⚠️  No test binary specified"
        echo "   Usage: $0 <path_to_binary>"
        return 1
    fi
    
    if [ ! -f "$TEST_BINARY" ]; then
        echo "❌ Binary not found: $TEST_BINARY"
        return 1
    fi
    
    if [ ! -x "$TEST_BINARY" ]; then
        echo "❌ Binary not executable: $TEST_BINARY"
        echo "   Try: chmod +x $TEST_BINARY"
        return 1
    fi
    
    echo "🧪 Testing with custom binary: $TEST_BINARY"
    echo ""
    
    # Run the binary (assumes it connects to ECH test endpoint)
    if "$TEST_BINARY" 2>&1 | grep -q "sni=encrypted"; then
        echo "✅ ECH working with custom binary"
        return 0
    else
        echo "❌ ECH not working with custom binary"
        return 1
    fi
}

# Function to capture and analyze ClientHello
analyze_clienthello() {
    echo "📊 Analyzing ClientHello for ECH extension..."
    echo ""
    
    if ! command -v tshark &> /dev/null; then
        echo "⚠️  tshark not found, skipping packet analysis"
        echo "   Install: sudo apt-get install tshark"
        return 1
    fi
    
    if [ "$EUID" -ne 0 ]; then
        echo "⚠️  Need root for packet capture"
        echo "   Run with: sudo $0"
        return 1
    fi
    
    echo "Starting packet capture (10 seconds)..."
    echo "Run your test client now!"
    echo ""
    
    # Capture ClientHello and check for ECH extension (type 0xfe0d)
    CAPTURE=$(timeout 10 tshark -i any -f "tcp port 443" \
        -T fields \
        -e tls.handshake.extension.type \
        -Y "tls.handshake.type == 1" \
        2>/dev/null || true)
    
    if [ -z "$CAPTURE" ]; then
        echo "⚠️  No ClientHello captured"
        return 1
    fi
    
    # Check for ECH extension (0xfe0d = 65037)
    if echo "$CAPTURE" | grep -q "65037\|0xfe0d"; then
        echo "✅ ECH extension found in ClientHello"
        echo ""
        echo "Extensions present:"
        echo "$CAPTURE" | tr ',' '\n' | sort -u | head -10
        return 0
    else
        echo "❌ ECH extension NOT found in ClientHello"
        echo ""
        echo "Extensions present:"
        echo "$CAPTURE" | tr ',' '\n' | sort -u | head -10
        return 1
    fi
}

# Main execution
echo "Test 1: DNS ECH Config"
echo "----------------------"
check_ech_dns
DNS_RESULT=$?
echo ""

echo "Test 2: ECH with curl"
echo "---------------------"
test_with_curl
CURL_RESULT=$?
echo ""

if [ -n "$TEST_BINARY" ]; then
    echo "Test 3: Custom Binary"
    echo "---------------------"
    test_with_binary
    BINARY_RESULT=$?
    echo ""
fi

# Summary
echo "==================================="
echo "Summary"
echo "==================================="
echo ""

if [ $DNS_RESULT -eq 0 ]; then
    echo "✅ DNS: ECH config available"
else
    echo "❌ DNS: ECH config not found"
fi

if [ $CURL_RESULT -eq 0 ]; then
    echo "✅ curl: ECH working"
elif [ $CURL_RESULT -eq 1 ]; then
    echo "❌ curl: ECH not working"
else
    echo "⚠️  curl: Test skipped"
fi

if [ -n "$TEST_BINARY" ]; then
    if [ ${BINARY_RESULT:-1} -eq 0 ]; then
        echo "✅ Binary: ECH working"
    else
        echo "❌ Binary: ECH not working"
    fi
fi

echo ""

# Overall verdict
if [ $DNS_RESULT -eq 0 ] && [ $CURL_RESULT -eq 0 ]; then
    echo "🎉 ECH is properly configured and working!"
    echo ""
    echo "Next steps:"
    echo "  1. Enable fingerprint randomization"
    echo "  2. Test with: config.randomize_fingerprint = true"
    echo "  3. Verify with: ./verify_ja3.sh"
elif [ $DNS_RESULT -eq 0 ]; then
    echo "⚠️  ECH config available but not working"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if your client supports ECH"
    echo "  2. Verify HPKE suite compatibility"
    echo "  3. Check for TLS 1.3 support"
    echo "  4. Review client logs for ECH errors"
else
    echo "❌ ECH not available"
    echo ""
    echo "To use ECH:"
    echo "  1. Choose a domain that supports ECH"
    echo "  2. Query DNS for HTTPS record with ECH config"
    echo "  3. Pass ECH config to rustls ClientConfig"
    echo ""
    echo "Example domains with ECH:"
    echo "  - crypto.cloudflare.com"
    echo "  - defo.ie"
    echo "  - tls-ech.dev"
fi

echo ""
