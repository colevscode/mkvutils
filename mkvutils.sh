#!/bin/bash

# Helper function to get audio duration in seconds
get_duration() {
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}

# Helper function to get audio sample rate
get_sample_rate() {
    ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$1"
}

show_help() {
    echo "Usage:"
    echo "  $0 extract <video_file> [-o output_file]"
    echo "  $0 replace <video_file> [-a audio_file] [-o output_file]"
    echo "  $0 info <video_file>"
    echo "  $0 split <audio_file> [-o output_dir] [-l overlap_ms] <timestamp1> [timestamp2 ...]"
    echo "  $0 merge <input_directory> [-o output_file] [-l overlap_ms]"
    echo "  $0 pad <audio_file> [-o output_file] [-b start_pad_ms] [-e end_pad_ms]"
    echo "  $0 trim <audio_file> [-o output_file] [-b start_trim_ms] [-e end_trim_ms]"
    echo ""
    echo "Commands:"
    echo "  extract    Extract audio from video file to FLAC"
    echo "  replace    Replace audio in video file with FLAC"
    echo "  info       Display detailed media information"
    echo "  split      Split audio file into tracks using timestamps"
    echo "  merge      Merge multiple FLAC files into a single file"
    echo "  pad        Add silence padding to the beginning or end of an audio file"
    echo "  trim       Remove audio from the beginning or end of a file"
    echo ""
    echo "Options:"
    echo "  -a        Audio file to use for replacement (default: <video_name>.flac)"
    echo "  -o        Output file/directory name:"
    echo "            - For extract: output FLAC file (default: <video_name>.flac)"
    echo "            - For replace: output video file (default: <video_name>_replaced.mkv)"
    echo "            - For split: output directory (default: <audio_name>_tracks)"
    echo "            - For merge: output FLAC file (default: <directory_name>_merged.flac)"
    echo "            - For pad: output FLAC file (default: <audio_name>_padded.flac)"
    echo "            - For trim: output FLAC file (default: <audio_name>_trimmed.flac)"
    echo "  -l        Overlap in milliseconds:"
    echo "            - For split: each track will overlap with the previous track (default: 0)"
    echo "            - For merge: tracks will be merged with crossfading (default: 0)"
    echo "            When specified for merge, each track after the first will be shifted back"
    echo "            by overlap_ms and crossfaded with the previous track using equal power"
    echo "            crossfading (squared values of gain functions sum to 1)"
    echo "  -b        For pad: Start padding duration in milliseconds (default: 0)"
    echo "            For trim: Amount to trim from start in milliseconds (default: 0)"
    echo "  -e        For pad: End padding duration in milliseconds (default: 0)"
    echo "            For trim: Amount to trim from end in milliseconds (default: 0)"
    echo ""
    echo "Timestamps should be in HH:MM:SS.mmm format (millisecond precision)"
    echo ""
    echo "Examples:"
    echo "  # Extract audio from video"
    echo "  ./mkvutils.sh extract video.mkv"
    echo "  ./mkvutils.sh extract video.mkv -o custom_audio.flac"
    echo ""
    echo "  # Replace audio in video"
    echo "  ./mkvutils.sh replace video.mkv -a new_audio.flac"
    echo "  ./mkvutils.sh replace video.mkv -a new_audio.flac -o output.mkv"
    echo ""
    echo "  # Display media information"
    echo "  ./mkvutils.sh info video.mkv"
    echo ""
    echo "  # Split audio into tracks with overlap"
    echo "  ./mkvutils.sh split audio.flac -o custom_tracks -l 200 00:03:45.123 00:08:30.456"
    echo "  # Creates tracks with 200ms overlap before each split point"
    echo ""
    echo "  # Merge audio files with crossfading"
    echo "  ./mkvutils.sh merge tracks_dir -o merged.flac -l 200"
    echo ""
    echo "  # Add silence padding to audio"
    echo "  ./mkvutils.sh pad audio.flac -b 500 -e 1000"
    echo ""
    echo "  # Trim audio from start and end"
    echo "  ./mkvutils.sh trim audio.flac -b 100 -e 200"
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
        # Calculate start time with overlap for final track
        start_seconds=$(echo "scale=3; $prev_seconds - ($overlap_ms/1000)" | bc)
        ffmpeg -i "$audio_file" -ss "$start_seconds" -acodec flac "$output_file"
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
        overlap_ms=0
        while getopts "o:l:" opt; do
            case $opt in
                o) output_file="$OPTARG";;
                l) overlap_ms="$OPTARG";;
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
            total_duration=0
            
            # Add inputs and build filter_complex
            for ((i=0; i<num_files; i++)); do
                # Add input to command
                ffmpeg_cmd="$ffmpeg_cmd -i \"${flac_files[$i]}\""
                
                # Get duration of current file
                duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${flac_files[$i]}")
                duration_ms=$(echo "scale=3; $duration * 1000" | bc)
                
                if [ $i -eq 0 ]; then
                    # First file - no delay, but fade out at the end
                    filter_complex="$filter_complex[0:a]afade=t=out:st=$(echo "scale=3; ($duration_ms-$overlap_ms)/1000" | bc):d=$(echo "scale=3; $overlap_ms/1000" | bc):curve=qsin[0a];"
                    # Update total duration for next iteration
                    total_duration=$(echo "scale=3; $total_duration + $duration_ms" | bc)
                else
                    # Calculate delay for this file
                    delay_ms=$(echo "scale=3; $total_duration - $overlap_ms" | bc)
                    # Apply both fade in and fade out first with same duration
                    filter_complex="$filter_complex[$i:a]afade=t=in:st=0:d=$(echo "scale=3; $overlap_ms/1000" | bc):curve=hsin[faded$i];"
                    if [ $i -lt $((num_files-1)) ]; then
                        filter_complex="$filter_complex[faded$i]afade=t=out:st=$(echo "scale=3; ($duration_ms-$overlap_ms)/1000" | bc):d=$(echo "scale=3; $overlap_ms/1000" | bc):curve=qsin[faded$i];"
                    fi
                    # Then apply delay to the already faded audio
                    filter_complex="$filter_complex[faded$i]adelay=${delay_ms}|${delay_ms}[delayed${i}a];"
                    # Update total duration for next iteration, accounting for overlap
                    total_duration=$(echo "scale=3; $total_duration + $duration_ms - $overlap_ms" | bc)
                fi
            done
            
            # Add mix filter to combine all streams
            if [ $num_files -gt 1 ]; then
                # Add first stream
                mix_inputs="[0a]"
                # Add delayed and faded streams
                for ((i=1; i<num_files; i++)); do
                    mix_inputs="$mix_inputs[delayed${i}a]"
                done
                # Use amix without duration parameter to let FFmpeg determine it automatically
                filter_complex="$filter_complex ${mix_inputs}amix=inputs=$num_files:dropout_transition=0:normalize=0[out]"
            fi
            
            # Add filter_complex and output to command
            ffmpeg_cmd="$ffmpeg_cmd -filter_complex \"$filter_complex\" -map \"[out]\" \"$output_file\""
            
            # Echo the command for inspection
            echo "Generated FFmpeg command:"
            echo "$ffmpeg_cmd"
            
            # Execute the command
            eval "$ffmpeg_cmd"
        fi
        
        echo "Merged audio files into: $output_file"
        ;;
        
    "pad")
        # Check if input file is provided
        if [ $# -lt 2 ]; then
            echo "Error: Input audio file must be provided"
            show_help
            exit 1
        fi
        
        audio_file="$2"
        shift 2  # Remove command and audio_file from args
        
        # Check if input file exists
        if [ ! -f "$audio_file" ]; then
            echo "Error: Input file not found: $audio_file"
            exit 1
        fi
        
        output_file=""
        start_pad_ms=0
        end_pad_ms=0
        
        # Parse optional arguments
        while getopts "o:b:e:" opt; do
            case $opt in
                o) output_file="$OPTARG";;
                b) start_pad_ms="$OPTARG"
                   if [ $start_pad_ms -lt 0 ]; then
                       echo "Error: Start padding value must be non-negative"
                       exit 1
                   fi;;
                e) end_pad_ms="$OPTARG"
                   if [ $end_pad_ms -lt 0 ]; then
                       echo "Error: End padding value must be non-negative"
                       exit 1
                   fi;;
                \?) show_help;;
            esac
        done
        
        # Set default output file name if not specified
        if [ -z "$output_file" ]; then
            output_file="${audio_file%.*}_padded.flac"
        fi
        
        # Build FFmpeg command with filters
        ffmpeg_cmd="ffmpeg -i \"$audio_file\""
        
        if [ $start_pad_ms -gt 0 ] || [ $end_pad_ms -gt 0 ]; then
            filter_complex="[0:a]"
            
            # Add start padding if needed
            if [ $start_pad_ms -gt 0 ]; then
                filter_complex="$filter_complex adelay=${start_pad_ms}|${start_pad_ms}"
            fi
            
            # Add end padding if needed
            if [ $end_pad_ms -gt 0 ]; then
                if [ $start_pad_ms -gt 0 ]; then
                    filter_complex="$filter_complex,"
                fi
                filter_complex="$filter_complex apad=pad_dur=$(echo "scale=3; $end_pad_ms / 1000" | bc)"
            fi
            
            filter_complex="$filter_complex[out]"
            ffmpeg_cmd="$ffmpeg_cmd -filter_complex \"$filter_complex\" -map \"[out]\""
        fi
        
        ffmpeg_cmd="$ffmpeg_cmd \"$output_file\""
        
        # Execute the command
        eval "$ffmpeg_cmd"
        echo "Created padded audio file: $output_file"
        ;;
        
    "trim")
        # Check if input file is provided
        if [ $# -lt 2 ]; then
            echo "Error: Input audio file must be provided"
            show_help
            exit 1
        fi
        
        audio_file="$2"
        shift 2  # Remove command and audio_file from args
        
        # Check if input file exists
        if [ ! -f "$audio_file" ]; then
            echo "Error: Input file not found: $audio_file"
            exit 1
        fi
        
        # Set default values
        output_file="${audio_file%.*}_trimmed.flac"
        start_trim_ms=0
        end_trim_ms=0
        
        # Parse optional arguments
        while getopts "o:b:e:" opt; do
            case $opt in
                o) output_file="$OPTARG";;
                b) start_trim_ms="$OPTARG";;
                e) end_trim_ms="$OPTARG";;
                \?) show_help;;
            esac
        done
        
        # Convert milliseconds to seconds for FFmpeg
        start_trim_sec=$(echo "scale=3; $start_trim_ms / 1000" | bc | sed 's/^\./0./')
        end_trim_sec=$(echo "scale=3; $end_trim_ms / 1000" | bc | sed 's/^\./0./')
        
        # Get total duration
        total_duration=$(get_duration "$audio_file")
        
        # Build FFmpeg command with atrim filter
        ffmpeg_cmd="ffmpeg -i \"$audio_file\""
        
        if [ $start_trim_ms -gt 0 ] || [ $end_trim_ms -gt 0 ]; then
            # Calculate end time by subtracting end_trim_sec from total duration
            end_time=$(echo "scale=3; $total_duration - $end_trim_sec" | bc | sed 's/^\./0./')
            filter_complex="[0:a]atrim=start=$start_trim_sec:end=$end_time[out]"
            ffmpeg_cmd="$ffmpeg_cmd -filter_complex \"$filter_complex\" -map \"[out]\""
        fi
        
        ffmpeg_cmd="$ffmpeg_cmd \"$output_file\""
        
        # Execute the command
        eval "$ffmpeg_cmd"
        echo "Created trimmed audio file: $output_file"
        ;;
        
    *)
        show_help
        ;;
esac 