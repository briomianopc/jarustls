#!/bin/bash
# Automated Verification Suite
#
# Runs all verification tests in sequence and generates a comprehensive report.
#
# Usage:
#   sudo ./run_all_verifications.sh [test_binary]
#
# Example:
#   sudo ./run_all_verifications.sh ./target/debug/my_client

set -e

TEST_BINARY="${1:-}"
REPORT_FILE="verification_report_$(date +%Y%m%d_%H%M%S).md"
TOOLS_DIR="$(dirname "$0")"

echo "==================================="
echo "Automated Verification Suite"
echo "==================================="
echo ""
echo "Report will be saved to: $REPORT_FILE"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Warning: Not running as root"
    echo "   Some tests require root privileges"
    echo "   Run with: sudo $0 $@"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Initialize report
cat > "$REPORT_FILE" << 'EOF'
# TLS Fingerprint Randomization - Verification Report

**Generated:** $(date)
**Test Binary:** ${TEST_BINARY:-"Not specified"}

---

## Executive Summary

EOF

# Function to add section to report
add_section() {
    echo "" >> "$REPORT_FILE"
    echo "## $1" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Function to run test and capture output
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    add_section "$test_name"
    echo '```' >> "$REPORT_FILE"
    
    # Run test and capture output
    if eval "$test_cmd" 2>&1 | tee -a "$REPORT_FILE"; then
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "✅ **Status:** PASS" >> "$REPORT_FILE"
        return 0
    else
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "❌ **Status:** FAIL" >> "$REPORT_FILE"
        return 1
    fi
}

# Test 1: ECH Verification
echo ""
echo "═══════════════════════════════════"
echo "Test 1: ECH Verification"
echo "═══════════════════════════════════"
echo ""

if [ -f "$TOOLS_DIR/verify_ech.sh" ]; then
    if run_test "ECH Verification" "$TOOLS_DIR/verify_ech.sh $TEST_BINARY"; then
        ECH_PASS=1
    else
        ECH_PASS=0
    fi
else
    echo "⚠️  verify_ech.sh not found"
    ECH_PASS=-1
fi

echo ""
echo "Press Enter to continue to next test..."
read

# Test 2: JA3 Verification (requires active connections)
echo ""
echo "═══════════════════════════════════"
echo "Test 2: JA3 Fingerprint Verification"
echo "═══════════════════════════════════"
echo ""

if [ -f "$TOOLS_DIR/verify_ja3.sh" ]; then
    echo "This test requires you to run your client multiple times"
    echo "during the 30-second capture window."
    echo ""
    
    if [ -n "$TEST_BINARY" ]; then
        echo "Suggested command (run in another terminal):"
        echo "  for i in {1..5}; do $TEST_BINARY; sleep 2; done"
    else
        echo "Run your test client 5 times during capture"
    fi
    echo ""
    read -p "Ready? Press Enter to start capture..."
    
    if run_test "JA3 Fingerprint Verification" "$TOOLS_DIR/verify_ja3.sh any 30"; then
        JA3_PASS=1
    else
        JA3_PASS=0
    fi
else
    echo "⚠️  verify_ja3.sh not found"
    JA3_PASS=-1
fi

echo ""
echo "Press Enter to continue to next test..."
read

# Test 3: Padding Boundary Check
echo ""
echo "═══════════════════════════════════"
echo "Test 3: Padding Boundary Verification"
echo "═══════════════════════════════════"
echo ""

if [ -f "$TOOLS_DIR/verify_padding.sh" ]; then
    echo "This test requires you to run your client multiple times"
    echo "during the 30-second capture window."
    echo ""
    
    if [ -n "$TEST_BINARY" ]; then
        echo "Suggested command (run in another terminal):"
        echo "  for i in {1..10}; do $TEST_BINARY; sleep 1; done"
    else
        echo "Run your test client 10 times during capture"
    fi
    echo ""
    read -p "Ready? Press Enter to start capture..."
    
    if run_test "Padding Boundary Verification" "$TOOLS_DIR/verify_padding.sh any 30"; then
        PADDING_PASS=1
    else
        PADDING_PASS=0
    fi
else
    echo "⚠️  verify_padding.sh not found"
    PADDING_PASS=-1
fi

# Generate summary
echo ""
echo "═══════════════════════════════════"
echo "Generating Report"
echo "═══════════════════════════════════"
echo ""

# Update executive summary
{
    echo ""
    echo "### Test Results"
    echo ""
    echo "| Test | Status |"
    echo "|------|--------|"
    
    if [ $ECH_PASS -eq 1 ]; then
        echo "| ECH Verification | ✅ PASS |"
    elif [ $ECH_PASS -eq 0 ]; then
        echo "| ECH Verification | ❌ FAIL |"
    else
        echo "| ECH Verification | ⚠️ SKIPPED |"
    fi
    
    if [ $JA3_PASS -eq 1 ]; then
        echo "| JA3 Fingerprint | ✅ PASS |"
    elif [ $JA3_PASS -eq 0 ]; then
        echo "| JA3 Fingerprint | ❌ FAIL |"
    else
        echo "| JA3 Fingerprint | ⚠️ SKIPPED |"
    fi
    
    if [ $PADDING_PASS -eq 1 ]; then
        echo "| Padding Boundary | ✅ PASS |"
    elif [ $PADDING_PASS -eq 0 ]; then
        echo "| Padding Boundary | ❌ FAIL |"
    else
        echo "| Padding Boundary | ⚠️ SKIPPED |"
    fi
    
    echo ""
    echo "### Overall Assessment"
    echo ""
    
    TOTAL_TESTS=3
    PASSED_TESTS=$((ECH_PASS > 0 ? 1 : 0))
    PASSED_TESTS=$((PASSED_TESTS + (JA3_PASS > 0 ? 1 : 0)))
    PASSED_TESTS=$((PASSED_TESTS + (PADDING_PASS > 0 ? 1 : 0)))
    
    if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
        echo "🎉 **All tests passed!**"
        echo ""
        echo "Your TLS fingerprint randomization implementation is working correctly:"
        echo "- ✅ ECH is properly configured"
        echo "- ✅ JA3 fingerprints are randomized"
        echo "- ✅ Padding is within safe boundaries"
        echo ""
        echo "**Recommendation:** Ready for production use"
    elif [ $PASSED_TESTS -ge 2 ]; then
        echo "⚠️ **Most tests passed** ($PASSED_TESTS/$TOTAL_TESTS)"
        echo ""
        echo "Your implementation is mostly working, but some issues were detected."
        echo "Review the failed tests above for details."
        echo ""
        echo "**Recommendation:** Fix issues before production use"
    else
        echo "❌ **Multiple tests failed** ($PASSED_TESTS/$TOTAL_TESTS)"
        echo ""
        echo "Your implementation has significant issues that need to be addressed."
        echo "Review all test results above for details."
        echo ""
        echo "**Recommendation:** Do not use in production"
    fi
    
    echo ""
    echo "---"
    echo ""
    echo "## Recommendations"
    echo ""
    
    if [ $ECH_PASS -eq 0 ]; then
        echo "### ECH Issues"
        echo ""
        echo "- Verify ECH config is obtained from DNS"
        echo "- Check HPKE suite compatibility"
        echo "- Ensure TLS 1.3 is enabled"
        echo "- Review client logs for ECH errors"
        echo ""
    fi
    
    if [ $JA3_PASS -eq 0 ]; then
        echo "### JA3 Randomization Issues"
        echo ""
        echo "- Verify \`randomize_fingerprint = true\` is set"
        echo "- Check that you're testing the correct binary"
        echo "- Ensure multiple connections were made during capture"
        echo "- Review cipher suite and extension randomization logic"
        echo ""
    fi
    
    if [ $PADDING_PASS -eq 0 ]; then
        echo "### Padding Boundary Issues"
        echo ""
        echo "- If ClientHello exceeds MTU (1500 bytes):"
        echo "  - Reduce padding max from 300 to 200 bytes"
        echo "  - Or reduce to 150 bytes for very conservative approach"
        echo "- If padding not detected:"
        echo "  - Verify randomization is enabled"
        echo "  - Check padding probability (70% default)"
        echo ""
    fi
    
    echo "## Next Steps"
    echo ""
    echo "1. Review this report carefully"
    echo "2. Address any failed tests"
    echo "3. Re-run verification suite"
    echo "4. Test against your target WAF/DPI"
    echo "5. Monitor connection success rate in production"
    echo ""
    echo "---"
    echo ""
    echo "*Report generated by rustls fingerprint randomization verification suite*"
    
} >> "$REPORT_FILE"

# Display summary
echo ""
echo "═══════════════════════════════════"
echo "Verification Complete"
echo "═══════════════════════════════════"
echo ""
echo "Results:"
echo "--------"
[ $ECH_PASS -eq 1 ] && echo "✅ ECH Verification: PASS" || echo "❌ ECH Verification: FAIL"
[ $JA3_PASS -eq 1 ] && echo "✅ JA3 Fingerprint: PASS" || echo "❌ JA3 Fingerprint: FAIL"
[ $PADDING_PASS -eq 1 ] && echo "✅ Padding Boundary: PASS" || echo "❌ Padding Boundary: FAIL"
echo ""
echo "📄 Full report saved to: $REPORT_FILE"
echo ""
echo "To view report:"
echo "  cat $REPORT_FILE"
echo "  # or"
echo "  less $REPORT_FILE"
echo ""
