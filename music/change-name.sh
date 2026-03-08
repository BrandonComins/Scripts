#!/bin/bash

function check_args {

    if [ ! -d "$input_directory" ]; then
        echo "Error $input_directory is not a directory"
    fi

}

function extract_words {
    local str="${1//_/ }"

    IFS=' ' read -r -a array <<< "$str"

    for item in "${array[@]}"; do
        if [[ -v word_map[$item] ]]; then
            ((word_map["$item"]+=1))
        else
            word_map["$item"]=1
        fi
    done
}

input_directory=""
preview_mode=false
declare -a strings_to_remove
declare -A word_map
num_songs=0

while getopts "r:i:hp" opt; do
    case ${opt} in
        i) input_directory="${OPTARG}";;
        r) strings_to_remove+=("${OPTARG}");;
        p) preview_mode=true;;
        h) usage;;
        ?) usage;;
    esac
done

shift $((OPTIND - 1))

check_args

for file in "$input_directory"/*; do
    if [[ "$file" =~ .mp3 ]]; then

        basename="$(basename "$file")"
        ((num_songs+=1))

        extract_words "$basename"
    fi
done

for key in "${!word_map[@]}"; do
    if (("${word_map[$key]}"  >= num_songs/2)); then
        strings_to_remove+=("$key")
    fi
done

for file in "$input_directory"/*; do
    if [[ "$file" =~ .mp3 ]]; then
        basename="$(basename "$file")"
        dirname="$(dirname "$file")"
        new_file="$basename"

        if ((${#strings_to_remove[@]} != 0)); then
            for string_to_remove in "${strings_to_remove[@]}"; do
                new_file="${new_file//$string_to_remove}"
            done
        fi

        new_file=${new_file//_/}

        echo "$new_file"
        if ! $preview_mode; then
            mv "$file" "$dirname/$new_file"
        fi
    fi
done