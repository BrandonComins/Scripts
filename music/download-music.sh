#!/bin/bash

function usage {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <playlist_url1> [playlist_url2 ...]

Download audio tracks from one or more playlists as MP3s with a single thumbnail.jpg 
thumbnail.
Tracks are saved in a subfolder named after the playlist title (with "OST" stripped).
Automatically installs yt-dlp and ffmpeg if missing.

Options:
  -o <dir>      Base output directory for downloaded playlists 
                (default: \$HOME/Downloads/music)
  -h            Display this help message and exit

Arguments:
  playlist_url  One or more playlist URLs supported by yt-dlp

Example:
  $(basename "$0") -o ~/Music "https://www.youtube.com/playlist?list=..."
EOF
    exit "${1:-0}"
}

function check_installed {
    if [ -n "$(which "$1")" ] || [ -f "$1" ]; then
        return 0
    fi
    return 1
}

function download_ffmpeg {
    if [ "$OSTYPE" == "linux-gnu" ]; then
        if ! check_installed "ffmpeg"; then
            sudo apt install -y ffmpeg
        fi
    else
        if [ ! -f "$ffm" ]; then
            echo "[INFO] Downloading ffmpeg..."
            curl -L -o ffmpeg.zip https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip
            echo "[INFO] Extracting ffmpeg..."
            unzip -q -o "$PWD/ffmpeg.zip"
            
            extracted_ffmpeg=$(find "$PWD" -maxdepth 3 -iname "ffmpeg.exe" | head -n 1)
            if [ -n "$extracted_ffmpeg" ]; then
                mv "$extracted_ffmpeg" "$ffm"
                echo "[SUCCESS] ffmpeg placed at $ffm"
            else
                echo "[ERROR] Could not locate ffmpeg.exe in the extracted ZIP."
                exit 1
            fi
            
            rm -rf ./ffmpeg-*
            rm -f ./ffmpeg.zip
        fi
    fi
}

function download_dlp {
    if [ ! -f "$dlp" ]; then
        echo "[INFO] Downloading yt-dlp..."
        if [ "$OSTYPE" == "msys" ]; then
            curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -o "$dlp"
        else
            curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$dlp"
            chmod a+rx "$dlp"
        fi
    else
        echo "[INFO] Checking for yt-dlp updates..."
        "$dlp" -U || true
    fi
}

function check_args {
    error=false

    if (( "${#playlists[@]}" == 0 )); then
        error=true
        echo "[ERROR] playlist can not be empty"
        usage 1
    fi

    if $error; then
        exit 1
    fi
}

base_output_dir="$HOME/Downloads/music"

user_bin="$HOME/.local/bin"
mkdir -p "$user_bin"

dlp="$user_bin/yt-dlp.exe"
ffm="$user_bin/ffmpeg.exe"
extra_dlp_args=""

if [ "$OSTYPE" != "msys" ]; then
    dlp="$user_bin/yt-dlp"
    ffm="$user_bin/ffmpeg"
fi

declare -a playlists

while getopts "o:h" opt; do
    case ${opt} in
        o) base_output_dir="${OPTARG}";;
        h) usage 0;;
        ?) usage 1;;
    esac
done
shift $((OPTIND - 1))

for link in "$@"; do
    playlists+=("$link")
done

check_args

download_dlp
download_ffmpeg

if [ "$OSTYPE" == "msys" ]; then
    export PATH="$(echo "$PATH" | sed -e 's/:\/c\/Users\/[^\/]*\/AppData\/Local\/Microsoft\/WindowsApps//g')" 
    extra_dlp_args="--no-check-certificate"
fi

for playlist in "${playlists[@]}"; do
    playlist_name=$( "$dlp" "$playlist" -I 1:1 --skip-download --no-warning --restrict-filenames --no-mtime --print playlist_title ${extra_dlp_args:+"$extra_dlp_args"})

    if [ -z "$playlist_name" ]; then
        playlist_name="$(date +"%Y-%m-%d_%H-%M-%S")"
        echo -e "[WARNING] could not find playlist name re-naming to $playlist_name"
    fi
    playlist_name="${playlist_name//OST/}"
    
    target_dir="$base_output_dir/$playlist_name"
    
    echo "Saving to: $target_dir"
    mkdir -p "$target_dir"

    # Download thumbnail
    if [ ! -f "$target_dir/thumbnail.jpg" ]; then
        echo "[INFO] Fetching thumbnail.jpg thumbnail..."
        "$dlp" --ffmpeg-location "$ffm" \
            -P "$target_dir" \
            --playlist-items 1 \
            --skip-download \
            --write-thumbnail \
            --convert-thumbnails jpg \
            -o "thumbnail" \
            --extractor-args "youtube:player_client=default" \
            ${extra_dlp_args:+"$extra_dlp_args"} \
            "$playlist"
    fi

    # Download music
    "$dlp" --ffmpeg-location "$ffm" \
        -P "$target_dir" \
        -o "%(title)s.%(ext)s" \
        -f "ba/b" -x \
        --audio-format mp3 \
        --audio-quality 0 \
        --yes-playlist \
        --restrict-filenames \
        --no-mtime \
        --extractor-args "youtube:player_client=default" \
        ${extra_dlp_args:+"$extra_dlp_args"} \
        "$playlist"
done
