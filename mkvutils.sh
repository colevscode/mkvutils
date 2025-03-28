#!/bin/bash

show_help() {
    echo "Usage:"
    echo "  $0 extract <video_file> [-o output_file]"
    echo "  $0 replace <video_file> [-a audio_file] [-o output_file]"
    echo "  $0 info <video_file>"
    echo "  $0 split <audio_file> [-o output_dir] [-l overlap_ms] <timestamp1> [timestamp2 ...]"
    echo "  $0 merge <input_directory> [-o output_file] [-l overlap_ms]"
    echo ""
    echo "Commands:"
    echo "  extract    Extract audio from video file to FLAC"
    echo "  replace    Replace audio in video file with FLAC"
    echo "  info       Display detailed media information"
    echo "  split      Split audio file into tracks using timestamps"
    echo "  merge      Merge multiple FLAC files into a single file"
    echo ""
    echo "Options:"
    echo "  -a        Audio file to use for replacement (default: <video_name>.flac)"
    echo "  -o        Output file/directory name:"
    echo "            - For extract: output FLAC file (default: <video_name>.flac)"
    echo "            - For replace: output video file (default: <video_name>_replaced.mkv)"
    echo "            - For split: output directory (default: <audio_name>_tracks)"
    echo "            - For merge: output FLAC file (default: <directory_name>_merged.flac)"
    echo "  -l        Overlap in milliseconds:"
    echo "            - For split: each track will overlap with the previous track (default: 0)"
    echo "            - For merge: tracks will be merged with crossfading (default: 0)"
    echo "            When specified for merge, each track after the first will be shifted back"
    echo "            by overlap_ms and crossfaded with the previous track using equal power"
    echo "            crossfading (squared values of gain functions sum to 1)"
    echo ""
    echo "Timestamps should be in HH:MM:SS.mmm format (millisecond precision)"
    echo "Example:"
    echo "  ./mkvutils.sh split audio.flac -o custom_tracks -l 200 00:03:45.123 00:08:30.456"
    echo "  # Creates tracks with 200ms overlap before each split point"
    exit 1
}

# Check if command is provided
if [ $# -lt 2 ]; then
    show_help
fi

command="$1"
input_path="$2"

# Check if input file exists for commands that require it
case "$command" in
    "extract"|"replace"|"info"|"split")
        if [ ! -f "$input_path" ]; then
            echo "Error: Input file not found: $input_path"
            exit 1
        fi
        ;;
esac

case "$command" in
    "extract")
        shift 2  # Remove command and video_file from args
        output_file="${input_path%.*}.flac"
        
        # Parse optional arguments
        while getopts "o:" opt; do
            case $opt in
                o) output_file="$OPTARG";;
                \?) show_help;;
            esac
        done
        
        ffmpeg -i "$input_path" -vn -acodec flac "$output_file"
        echo "Extracted audio to: $output_file"
        ;;
        
    "replace")
        shift 2  # Remove command and video_file from args
        audio_file=""
        output_file="${input_path%.*}_replaced.mkv"
        
        # Parse optional arguments
        while getopts "a:o:" opt; do
            case $opt in
                a) audio_file="$OPTARG";;
                o) output_file="$OPTARG";;
                \?) show_help;;
            esac
        done
        
        # If no audio file specified, use default
        if [ -z "$audio_file" ]; then
            audio_file="${input_path%.*}.flac"
        fi
        
        # Check if audio file exists
        if [ ! -f "$audio_file" ]; then
            echo "Error: Audio file not found: $audio_file"
            exit 1
        fi
        
        # Replace audio
        ffmpeg -i "$input_path" -i "$audio_file" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 "$output_file"
        echo "Created new video with replaced audio: $output_file"
        ;;
        
    "info")
        echo "Media Information for: $input_path"
        echo "----------------------------------------"
        ffmpeg -i "$input_path" 2>&1 | grep -E "Duration|Stream|bitrate|fps|Hz|channels|codec|resolution|size" | sed 's/^/  /'
        echo "----------------------------------------"
        ;;
        
    "split")
        # Check if at least one timestamp is provided
        if [ $# -lt 3 ]; then
            echo "Error: At least one timestamp must be provided"
            show_help
            exit 1
        fi
        
        audio_file="$2"
        shift 2  # Remove command and audio_file from args
        
        # Check if audio file exists
        if [ ! -f "$audio_file" ]; then
            echo "Error: Audio file not found: $audio_file"
            exit 1
        fi
        
        # Set default output directory and overlap
        output_dir="${audio_file%.*}_tracks"
        overlap_ms=0
        
        # Parse optional arguments
        while getopts "o:l:" opt; do
            case $opt in
                o) output_dir="$OPTARG";;
                l) overlap_ms="$OPTARG";;
                \?) show_help;;
            esac
        done
        
        # Remove the processed options from the arguments
        shift $((OPTIND-1))
        
        # Create the output directory only if it doesn't exist
        if [ ! -d "$output_dir" ]; then
            mkdir -p "$output_dir"
        fi
        
        # Process timestamps
        prev_seconds=0
        track_num=1
        
        for timestamp in "$@"; do
            # Convert timestamps to seconds with millisecond precision using bc
            curr_seconds=$(echo "$timestamp" | awk -F: '{ printf "%.3f", ($1 * 3600) + ($2 * 60) + $3 }')
            
            # Calculate start time with overlap
            if [ $track_num -gt 1 ]; then
                start_seconds=$(echo "scale=3; $prev_seconds - ($overlap_ms/1000)" | bc)
            else
                start_seconds=0
            fi
            
            echo -e "\nDEBUG: Processing track $track_num" >&2
            echo -e "DEBUG: prev_seconds=$prev_seconds" >&2
            echo -e "DEBUG: curr_seconds=$curr_seconds" >&2
            echo -e "DEBUG: overlap_ms=$overlap_ms" >&2
            echo -e "DEBUG: start_seconds=$start_seconds" >&2
            
            # Calculate duration including overlap
            if [ $track_num -eq 1 ]; then
                duration_seconds=$curr_seconds
                echo -e "DEBUG: First track duration calculation" >&2
            else
                duration_seconds=$(echo "scale=3; $curr_seconds - $start_seconds" | bc)
                echo -e "DEBUG: Middle track duration calculation" >&2
            fi
            
            echo -e "DEBUG: duration_seconds=$duration_seconds" >&2
            
            # Extract the track with overlap
            output_file="$output_dir/track_$(printf "%02d" $track_num).flac"
            echo -e "DEBUG: Running ffmpeg with -ss $start_seconds -t $duration_seconds" >&2
            ffmpeg -i "$audio_file" -ss "$start_seconds" -t "$duration_seconds" -acodec flac "$output_file"
            echo "Created track $track_num: $output_file"
            
            # Update previous time to current timestamp (no need to subtract overlap)
            prev_seconds=$curr_seconds
            track_num=$((track_num + 1))
        done
        
        # Extract the final track
        output_file="$output_dir/track_$(printf "%02d" $track_num).flac"
        ffmpeg -i "$audio_file" -ss "$prev_seconds" -acodec flac "$output_file"
        echo "Created track $track_num: $output_file"
        
        echo "All tracks have been created in: $output_dir"
        ;;
        
    "merge")
        # Check if input directory is provided
        if [ $# -lt 2 ]; then
            echo "Error: Input directory must be provided"
            show_help
            exit 1
        fi
        
        input_dir="$2"
        shift 2  # Remove command and input_dir from args
        
        # Check if input directory exists
        if [ ! -d "$input_dir" ]; then
            echo "Error: Input directory not found: $input_dir"
            exit 1
        fi
        
        # Parse optional arguments
        output_file=""
        while getopts "o:" opt; do
            case $opt in
                o) output_file="$OPTARG";;
                \?) show_help;;
            esac
        done
        
        # Set default output file name if not specified
        if [ -z "$output_file" ]; then
            output_file="${input_dir}_merged.flac"
        fi
        
        # Get sorted list of FLAC files
        flac_files=($(find "$input_dir" -name "*.flac" -type f | sort))
        num_files=${#flac_files[@]}
        
        # Check if any FLAC files were found
        if [ $num_files -eq 0 ]; then
            echo "Error: No FLAC files found in directory: $input_dir"
            exit 1
        fi
        
        if [ $num_files -eq 1 ]; then
            # If only one file, just copy it
            cp "${flac_files[0]}" "$output_file"
        else
            # Build the FFmpeg command with filter_complex
            ffmpeg_cmd="ffmpeg"
            filter_complex=""
            
            # Add inputs and build filter_complex
            for ((i=0; i<num_files; i++)); do
                # Add input to command
                ffmpeg_cmd="$ffmpeg_cmd -i \"${flac_files[$i]}\""
                
                # Add input label to filter_complex
                filter_complex="$filter_complex[$i:a]"
            done
            
            # Add concat filter
            filter_complex="$filter_complex concat=n=$num_files:v=0:a=1[out]"
            
            # Add filter_complex and output to command
            ffmpeg_cmd="$ffmpeg_cmd -filter_complex \"$filter_complex\" -map \"[out]\" \"$output_file\""
            
            # Execute the command
            eval "$ffmpeg_cmd"
        fi
        
        echo "Merged audio files into: $output_file"
        ;;
        
    *)
        show_help
        ;;
esac 