# MKV Utils

A simple bash script for working with media files, primarily designed for MKV containers but also supporting audio operations.

## Requirements

- `ffmpeg` - The script requires FFmpeg to be installed on your system
- Bash shell

## Installation

1. Clone this repository or download the `mkvutils.sh` script
2. Make the script executable:
   ```bash
   chmod +x mkvutils.sh
   ```

## Usage

The script provides seven main commands:

### 1. Pad Audio

Add silence to the start and/or end of an audio file.

```bash
./mkvutils.sh pad <audio_file> [-b start_ms] [-e end_ms] [-o output_file]
```

Options:
- `audio_file`: The input FLAC audio file (required)
- `-b start_ms`: Add silence at the start (in milliseconds)
- `-e end_ms`: Add silence at the end (in milliseconds)
- `-o output_file`: The output FLAC file (optional, defaults to `<audio_name>_padded.flac`)

Examples:
```bash
# Add 500ms silence to start and 1000ms to end
./mkvutils.sh pad input.flac -b 500 -e 1000

# Add only start padding
./mkvutils.sh pad input.flac -b 500

# Add only end padding
./mkvutils.sh pad input.flac -e 1000
```

### 2. Trim Audio

Remove audio from the start and/or end of an audio file.

```bash
./mkvutils.sh trim <audio_file> [-b start_ms] [-e end_ms] [-o output_file]
```

Options:
- `audio_file`: The input FLAC audio file (required)
- `-b start_ms`: Remove audio from the start (in milliseconds)
- `-e end_ms`: Remove audio from the end (in milliseconds)
- `-o output_file`: The output FLAC file (optional, defaults to `<audio_name>_trimmed.flac`)

Examples:
```bash
# Remove 500ms from start and 1000ms from end
./mkvutils.sh trim input.flac -b 500 -e 1000

# Remove only from start
./mkvutils.sh trim input.flac -b 500

# Remove only from end
./mkvutils.sh trim input.flac -e 1000
```

### 3. Extract Audio

Extracts audio from a video file and saves it as FLAC.

```bash
./mkvutils.sh extract <video_file> [-o output_file]
```

Options:
- `video_file`: The input video file (required)
- `-o output_file`: The output FLAC file (optional, defaults to `<video_name>.flac`)

Examples:
```bash
# Using default output file name
./mkvutils.sh extract video.mkv
# Creates video.flac

# Specifying custom output file
./mkvutils.sh extract video.mkv -o output.flac
```

### 4. Replace Audio

Replaces the audio track in a video file with a new audio file.

```bash
./mkvutils.sh replace <video_file> [-a audio_file] [-o output_file]
```

Options:
- `video_file`: The input video file (required)
- `-a audio_file`: The new audio file to use (optional, defaults to `<video_name>.flac`)
- `-o output_file`: The output video file (optional, defaults to `<video_name>_replaced.mkv`)

Examples:
```bash
# Using default audio file name
./mkvutils.sh replace video.mkv
# Creates video_replaced.mkv using video.flac

# Specifying custom audio file
./mkvutils.sh replace video.mkv -a new_audio.flac

# Specifying custom output file
./mkvutils.sh replace video.mkv -o output.mkv

# Using both custom audio and output files
./mkvutils.sh replace video.mkv -a new_audio.flac -o output.mkv
```

### 5. Media Information

Display detailed information about a media file, including duration, codecs, bitrate, and other properties. Works with both video and audio files.

```bash
./mkvutils.sh info <media_file>
```

- `media_file`: The input video or audio file (required)

Examples:
```bash
# Video file information
./mkvutils.sh info video.mkv
# Shows detailed media information including video and audio streams

# Audio file information
./mkvutils.sh info audio.flac
# Shows detailed audio information including duration, sample rate, and format
```

### 6. Split Audio

Split a FLAC audio file into separate tracks using timestamps with millisecond precision.

```bash
./mkvutils.sh split <audio_file> [-o output_dir] [-l overlap_ms] <timestamp1> [timestamp2 ...]
```

Options:
- `audio_file`: The input FLAC audio file (required)
- `-o output_dir`: The output directory for the split tracks (optional, defaults to `<audio_name>_tracks`)
- `-l overlap_ms`: Overlap duration in milliseconds between tracks (optional, defaults to 0)
  - When specified, each track will overlap with the previous track by overlap_ms
  - For example, with overlap_ms=200, each track will start 200ms before its timestamp
- `timestamp1`, `timestamp2`, etc.: Timestamps in HH:MM:SS.mmm format where to split the audio (required)

The script will:
1. Create a new directory (default: `<audio_name>_tracks` or specified with `-o`)
2. Split the audio file into separate FLAC files at the specified timestamps
3. If overlap is specified, each track will overlap with the previous track:
   - Track 1: Starts at 00:00:00.000, ends at first timestamp
   - Track 2..n-1: Starts overlap_ms before timestamp, ends at next timestamp
   - Track n: Starts overlap_ms before last timestamp, ends at file end
4. Name the output files `track_01.flac`, `track_02.flac`, etc.

Examples:
```bash
# Using default output directory
./mkvutils.sh split audio.flac 00:03:45.123 00:08:30.456
# Creates:
#   audio_tracks/track_01.flac (00:00:00.000 to 00:03:45.123)
#   audio_tracks/track_02.flac (00:03:45.123 to 00:08:30.456)
#   audio_tracks/track_03.flac (00:08:30.456 to end)

# Using overlap between tracks (200ms overlap before each split point)
./mkvutils.sh split audio.flac -l 200 00:03:45.123 00:08:30.456
# Creates:
#   audio_tracks/track_01.flac (00:00:00.000 to 00:03:45.123)
#   audio_tracks/track_02.flac (00:03:44.923 to 00:08:30.456)
#   audio_tracks/track_03.flac (00:08:30.256 to end)
# Each track (except the first) starts 200ms before its timestamp
# For example, track 2 starts 200ms before 00:03:45.123

# Specifying custom output directory (note: options must come before timestamps)
./mkvutils.sh split audio.flac -o custom_tracks -l 200 00:03:45.123 00:08:30.456
```

### 7. Merge Audio

Merge multiple FLAC files from a directory into a single FLAC file. Files are merged in alphabetical order, making it perfect for combining tracks created by the `split` command.

```bash
./mkvutils.sh merge <input_directory> [-o output_file]
```

Options:
- `input_directory`: Directory containing FLAC files to merge (required)
- `-o output_file`: The output FLAC file (optional, defaults to `<directory_name>_merged.flac`)

The script will:
1. Find all FLAC files in the input directory
2. Sort them alphabetically (so track_01.flac, track_02.flac, etc. are in order)
3. Merge them into a single output file while preserving audio quality

Examples:
```bash
# Using default output file name
./mkvutils.sh merge audio_tracks
# Creates audio_tracks_merged.flac from all FLAC files in audio_tracks/

# Specifying custom output file
./mkvutils.sh merge audio_tracks -o output.flac
# Creates output.flac from all FLAC files in audio_tracks/
```

## Notes

- The script is designed to work with MKV containers but may work with other video formats supported by FFmpeg
- The audio replacement preserves the original video stream without re-encoding
- The script will exit with an error if required input files or directories are not found
- Timestamps for splitting audio should be in HH:MM:SS.mmm format (millisecond precision)
- Audio operations (split, merge) preserve the original audio quality without re-encoding
