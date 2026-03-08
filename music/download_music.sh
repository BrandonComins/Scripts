#!/bin/bash

function check_installed {
    if [ "$OSTYPE" == "linux-gnu" ]; then
        if [ -n "$(which "$1")" ]; then
            return 0
        fi
    fi

    return 1
}

function download {
    if ! check_installed "$1"; then
        sudo apt install "$1"
    fi
}

function download_dlp {
    if ! check_installed "$dlp"; then
        sudo curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$dlp"
        sudo chmod a+rx "$dlp"
    fi
}

function check_args {
    if [ -z "$playlist" ]; then
        echo "[ERROR] playlist can not be empty"
    fi 
}

output_dir="$HOME/Downloads/music"
dlp="/usr/local/bin/yt-dlp"
ffm="/usr/bin/ffmpeg"
if [ "$OSTYPE" == "msys" ]; then
    dlp="yt-dlp.exe"
    ffm="ffmpeg.exe"
fi

playlist=""

while getopts "o:p:h" opt; do
    case ${opt} in
        o) output_dir="${OPTARG}";;
        p) playlist="${OPTARG}";;
        h) usage;;
        ?) usage;;
    esac
done
shift $((OPTIND - 1))

check_args

download_dlp
download "ffmpeg"
download curl

rm -rf "$output_dir"
mkdir "$output_dir"

"$dlp" --ffmpeg-location "$ffm" \
    -P "$output_dir" \
    -o "%(title)s.%(ext)s" \
    -f "ba/b" -x --audio-format mp3 --audio-quality 0 \
    --yes-playlist --restrict-filenames --no-mtime \
    "$playlist"

