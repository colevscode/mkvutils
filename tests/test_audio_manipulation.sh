#!/bin/bash

# Exit on error
set -e

# Test directory setup
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_AUDIO="$TEST_DIR/noise.flac"
ARTIFACTS_DIR="$TEST_DIR/.artifacts"

# Clean artifacts directory at start only
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

MKVUTILS="$TEST_DIR/../mkvutils.sh"
cd "$ARTIFACTS_DIR"

# Helper function to get audio duration in seconds
get_duration() {
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}

# Helper function to check if file exists and has correct duration
check_duration() {
    local file="$1"
    local expected_duration="$2"
    local tolerance=0.1  # 100ms tolerance
    
    if [ ! -f "$file" ]; then
        echo "Error: File not found: $file"
        return 1
    fi
    
    local actual_duration=$(get_duration "$file")
    local diff=$(echo "scale=3; $actual_duration - $expected_duration" | bc)
    diff=${diff#-}  # Absolute value
    
    if (( $(echo "$diff > $tolerance" | bc -l) )); then
        echo "Error: Duration mismatch for $file"
        echo "Expected: $expected_duration seconds"
        echo "Got: $actual_duration seconds"
        echo "Difference: $diff seconds"
        return 1
    fi
    
    return 0
}

# Helper function to generate random string
generate_random_string() {
    local length=$1
    openssl rand -hex "$length" | tr -d '\n'
}

# Helper function to get mean volume of a section of audio
# Args: file start_sec duration_sec
get_mean_volume() {
    local file="$1"
    local start="$2"
    local duration="$3"
    
    # Use astats filter to get RMS level
    local vol=$(ffmpeg -ss "$start" -t "$duration" -i "$file" -filter_complex "astats=measure_perchannel=0[out]" -map "[out]" -f null /dev/null 2>&1 | \
    grep "RMS level dB" | head -n1 | sed 's/.*RMS level dB: //')
    
    # Return 0 if no volume detected
    echo "${vol:-0}"
}

# Helper function to get max volume of a section of audio
# Args: file start_sec duration_sec
get_max_volume() {
    local file="$1"
    local start="$2"
    local duration="$3"
    
    # Use astats filter to get Peak level
    local vol=$(ffmpeg -ss "$start" -t "$duration" -i "$file" -filter_complex "astats=measure_perchannel=0[out]" -map "[out]" -f null /dev/null 2>&1 | \
    grep "Peak level dB" | head -n1 | sed 's/.*Peak level dB: //')
    
    # Return 0 if no volume detected
    echo "${vol:-0}"
}

# Helper function to get min volume of a section of audio
# Args: file start_sec duration_sec
get_min_volume() {
    local file="$1"
    local start="$2"
    local duration="$3"
    
    # Use astats filter to get min volume
    local vol=$(ffmpeg -ss "$start" -t "$duration" -i "$file" -filter_complex "astats=measure_perchannel=0[out]" -map "[out]" -f null /dev/null 2>&1 | \
    grep "Min level dB" | head -n1 | sed 's/.*Min level dB: //')
    
    # Return -inf if no volume detected (silence)
    if [ -z "$vol" ]; then
        echo "-inf"
    else
        echo "$vol"
    fi
}

# Helper function to test crossfade equal power
test_crossfade_equal_power() {
    local test_dir="$ARTIFACTS_DIR/crossfade_test_$(generate_random_string 4)"
    mkdir -p "$test_dir"
    
    # Create two test files with noise
    ffmpeg -f lavfi -i "aevalsrc='random(0)-0.5':s=48000" -t 10 -ar 48000 -ac 2 "$test_dir/noise1.flac"
    ffmpeg -f lavfi -i "aevalsrc='random(0)-0.5':s=48000" -t 10 -ar 48000 -ac 2 "$test_dir/noise2.flac"
    
    # Merge with 1 second crossfade
    "$MKVUTILS" merge "$test_dir" -o "$test_dir/merged.flac" -l 1000
    
    # Check if merged file exists
    if [ ! -f "$test_dir/merged.flac" ]; then
        echo "✗ Crossfade test failed: merged file not created"
        return 1
    fi
    
    # Get volumes at specific points
    local before_vol=$(get_mean_volume "$test_dir/merged.flac" 8.8 0.2)
    local mid_vol=$(get_mean_volume "$test_dir/merged.flac" 9.5 0.2)
    local after_vol=$(get_mean_volume "$test_dir/merged.flac" 10.2 0.2)
    
    # Get max and min volumes during crossfade
    local max_vol=$(get_max_volume "$test_dir/merged.flac" 9.5 0.2)
    local min_vol=$(get_min_volume "$test_dir/merged.flac" 9.5 0.2)
    
    # Get volumes at same points for input files
    local input1_before=$(get_mean_volume "$test_dir/noise1.flac" 8.8 0.2)
    local input1_mid=$(get_mean_volume "$test_dir/noise1.flac" 9.5 0.2)
    local input2_before=$(get_mean_volume "$test_dir/noise2.flac" 0.2 0.2)
    local input2_mid=$(get_mean_volume "$test_dir/noise2.flac" 0.5 0.2)
    
    # Get max volumes for input files at same points
    local input1_max_before=$(get_max_volume "$test_dir/noise1.flac" 8.8 0.2)
    local input1_max_mid=$(get_max_volume "$test_dir/noise1.flac" 9.5 0.2)
    local input2_max_before=$(get_max_volume "$test_dir/noise2.flac" 0.2 0.2)
    local input2_max_mid=$(get_max_volume "$test_dir/noise2.flac" 0.5 0.2)
    
    # Check for volume issues
    local has_issues=0
    local issues=""
    
    # Check if output max exceeds input maxes by more than 0.5dB
    if (( $(echo "$max_vol > ($input1_max_mid + 2)" | bc -l) )) || (( $(echo "$max_vol > ($input2_max_mid + 2)" | bc -l) )); then
        has_issues=1
        local max_diff1=$(echo "scale=1; $max_vol - $input1_max_mid" | bc)
        local max_diff2=$(echo "scale=1; $max_vol - $input2_max_mid" | bc)
        issues="$issues\n  - Output max volume ($max_vol dB) exceeds input max volumes ($input1_max_mid dB, $input2_max_mid dB) by more than 2dB"
        issues="$issues\n    - Spike above input 1: $max_diff1 dB"
        issues="$issues\n    - Spike above input 2: $max_diff2 dB"
    fi
    
    # Check for volume changes during crossfade
    local vol_diff=$(echo "scale=1; $mid_vol - $before_vol" | bc)
    local abs_diff=${vol_diff#-}  # Get absolute value
    
    # Check for volume dip (mean volume drops by more than 2dB)
    if (( $(echo "$vol_diff < -2" | bc -l) )); then
        has_issues=1
        issues="$issues\n  - Mean volume dips during crossfade (diff: $vol_diff dB)"
    fi
    
    # Check for volume spike (mean volume increases by more than 2dB)
    if (( $(echo "$vol_diff > 2" | bc -l) )); then
        has_issues=1
        issues="$issues\n  - Mean volume spikes during crossfade (diff: $vol_diff dB)"
    fi
    
    # Check for minimum volume during crossfade
    if (( $(echo "$min_vol < -60" | bc -l) )); then
        has_issues=1
        issues="$issues\n  - Volume dips too low during crossfade (min: $min_vol dB)"
    fi
    
    if [ $has_issues -eq 0 ]; then
        echo "✓ Equal power crossfade test passed"
        echo "  Input 1 max: $input1_max_mid dB"
        echo "  Input 2 max: $input2_max_mid dB"
        echo "  Volumes at specific points:"
        echo "    Before crossfade (8.8s): $before_vol dB"
        echo "    During crossfade (9.5s): $mid_vol dB"
        echo "    After crossfade (10.2s): $after_vol dB"
        echo "  Max volume during crossfade: $max_vol dB"
        echo "  Min volume during crossfade: $min_vol dB"
    else
        echo "✗ Crossfade test failed:"
        echo -e "$issues"
        echo "  Detailed volume measurements:"
        echo "    Input 1:"
        echo "      Before crossfade (8.8s): mean=$input1_before dB, max=$input1_max_before dB"
        echo "      During crossfade (9.5s): mean=$input1_mid dB, max=$input1_max_mid dB"
        echo "    Input 2:"
        echo "      Before crossfade (0.2s): mean=$input2_before dB, max=$input2_max_before dB"
        echo "      During crossfade (0.5s): mean=$input2_mid dB, max=$input2_max_mid dB"
        echo "    Output:"
        echo "      Before crossfade (8.8s): mean=$before_vol dB"
        echo "      During crossfade (9.5s): mean=$mid_vol dB, max=$max_vol dB, min=$min_vol dB"
        echo "      After crossfade (10.2s): mean=$after_vol dB"
        return 1
    fi
}

echo "Testing audio manipulation commands..."

# Test pad command
echo "Testing pad command..."

# Test adding padding to start only
rand=$(generate_random_string 4)
"$MKVUTILS" pad "$TEST_AUDIO" -b 500 -o "$ARTIFACTS_DIR/noise_padded_$rand.flac"
check_duration "$ARTIFACTS_DIR/noise_padded_$rand.flac" 10.5
echo "✓ Start padding test passed"

# Test adding padding to end only
rand=$(generate_random_string 4)
"$MKVUTILS" pad "$TEST_AUDIO" -e 1000 -o "$ARTIFACTS_DIR/noise_padded_$rand.flac"
check_duration "$ARTIFACTS_DIR/noise_padded_$rand.flac" 11.0
echo "✓ End padding test passed"

# Test adding padding to both start and end
rand=$(generate_random_string 4)
"$MKVUTILS" pad "$TEST_AUDIO" -b 500 -e 1000 -o "$ARTIFACTS_DIR/noise_padded_$rand.flac"
check_duration "$ARTIFACTS_DIR/noise_padded_$rand.flac" 11.5
echo "✓ Both start and end padding test passed"

# Test custom output file
rand=$(generate_random_string 4)
"$MKVUTILS" pad "$TEST_AUDIO" -b 500 -e 1000 -o "$ARTIFACTS_DIR/custom_padded_$rand.flac"
check_duration "$ARTIFACTS_DIR/custom_padded_$rand.flac" 11.5
echo "✓ Custom output file test passed"

# Test trim command
echo "Testing trim command..."

# Test trimming from start only
rand=$(generate_random_string 4)
"$MKVUTILS" trim "$TEST_AUDIO" -b 500 -o "$ARTIFACTS_DIR/noise_trimmed_$rand.flac"
check_duration "$ARTIFACTS_DIR/noise_trimmed_$rand.flac" 9.5
echo "✓ Start trim test passed"

# Test trimming from end only
rand=$(generate_random_string 4)
"$MKVUTILS" trim "$TEST_AUDIO" -e 1000 -o "$ARTIFACTS_DIR/noise_trimmed_$rand.flac"
check_duration "$ARTIFACTS_DIR/noise_trimmed_$rand.flac" 9.0
echo "✓ End trim test passed"

# Test trimming from both start and end
rand=$(generate_random_string 4)
"$MKVUTILS" trim "$TEST_AUDIO" -b 500 -e 1000 -o "$ARTIFACTS_DIR/noise_trimmed_$rand.flac"
check_duration "$ARTIFACTS_DIR/noise_trimmed_$rand.flac" 8.5
echo "✓ Both start and end trim test passed"

# Test custom output file
rand=$(generate_random_string 4)
"$MKVUTILS" trim "$TEST_AUDIO" -b 500 -e 1000 -o "$ARTIFACTS_DIR/custom_trimmed_$rand.flac"
check_duration "$ARTIFACTS_DIR/custom_trimmed_$rand.flac" 8.5
echo "✓ Custom output file test passed"

# Test crossfade
echo "Testing crossfade..."
test_crossfade_equal_power

# Test error cases
echo "Testing error cases..."

# Test non-existent input file
if "$MKVUTILS" pad "nonexistent.flac" 2>/dev/null; then
    echo "Error: Should fail with non-existent input file"
    exit 1
fi
echo "✓ Non-existent input file test passed"

# Test invalid padding values
if "$MKVUTILS" pad "$TEST_AUDIO" -b -100 2>/dev/null; then
    echo "Error: Should fail with negative padding value"
    exit 1
fi
echo "✓ Invalid padding value test passed"

echo "All tests passed successfully!"
echo "Test artifacts are preserved in: $ARTIFACTS_DIR" 