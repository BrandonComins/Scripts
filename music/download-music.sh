#!/bin/bash

function check_installed {
    if [ -n "$(which "$1")" ]; then
        return 0
    fi

    return 1
}

function download {
    if ! check_installed "$1"; then
        sudo apt install "$1"
    fi
}

function download_ffmpeg {
    if [ "$OSTYPE" == "linux-gnu" ]; then
        download "$ffm"
    else
        if ! check_installed "$ffm"; then
            curl -L -o ffmpeg.zip https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip
            unzip "$PWD/ffmpeg.zip"
            sudo mv "$(find "$PWD" -iname "ffmpeg.exe")" "/usr/bin"
            rm -rf ./ffmpeg-*-essentials_build*
            rm -f ./ffmpeg.zip
        fi
    fi
}

function download_dlp {
    if ! check_installed "$dlp"; then
        sudo curl -L "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$dlp"
        sudo chmod a+rx "$dlp"

        if [ "$OSTPYE"  == "msys" ]; then
            mv "$PWD/yt-dlp.ext" /usr/bin
        fi
    fi
}

function check_args {
    error=false

    if (( "${#playlists[@]}" == 0 )); then
        error=true
        echo "[ERROR] playlist can not be empty"
    fi

    if $error; then
        exit 1
    fi 
}

output_dir="$HOME/Downloads/music"
dlp="/usr/local/bin/yt-dlp"
ffm="/usr/local/bin/ffmpeg"
extra_dlp_args=""

if [ "$OSTYPE" == "msys" ]; then
    dlp="/usr/bin/yt-dlp.exe"
    ffm="/usr/bin/ffmpeg.exe"
fi

declare -a playlists

while getopts "o:h" opt; do
    case ${opt} in
        o) output_dir="${OPTARG}";;
        h) usage;;
        ?) usage;;
    esac
done
shift $((OPTIND - 1))

for link in "$@"; do
    playlists+=("$link")
done

check_args

download_dlp
download_ffmpeg
download curl

if [ "$OSTYPE" == "msys" ]; then
    # Remove the Microsoft Store paths (Python not found error)
    export PATH="$BIN_DIR:$(echo "$PATH" | sed -e 's/:\/c\/Users\/[^\/]*\/AppData\/Local\/Microsoft\/WindowsApps//g')" 
    extra_dlp_args="--no-check-certificate"
fi

for playlist in "${playlists[@]}"; do
    playlist_name=$( "$dlp" "$playlist" -I 1:1 --skip-download --no-warning --restrict-filenames --no-mtime --print playlist_title ${extra_dlp_args:+"$extra_dlp_args"})

    if [ -z "$playlist_name" ]; then
        playlist_name="$(date +"%Y-%m-%d_%H-%M-%S")"
        echo -e "[WARNING] could not find playlist name re-naming to $playlist_name"
    fi
    playlist_name="${playlist_name//OST/}"
    output_dir="$output_dir/$playlist_name"
    
    echo "$output_dir"

    rm -rf "$output_dir"

    "$dlp" --ffmpeg-location "$ffm" \
        -P "$output_dir" \
        -o "%(title)s.%(ext)s" \
        -f "ba/b" -x \
        --audio-format mp3 \
        --audio-quality 0 \
        --yes-playlist \
        --restrict-filenames \
        --no-mtime \
        --write-thumbnail \
        ${extra_dlp_args:+"$extra_dlp_args"} \
        "$playlist"
done