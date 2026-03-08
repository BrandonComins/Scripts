#!/bin/bash

function check_args {
    error=0

    if [ ! -d "$1" ]; then
        ((error+=1))
        echo "[Error] $1 is not a directory skipping..."
    fi

    return $error
}

function check_digits {
    shopt -s extglob
    local input="$1"
    local leading_digits="${input%%[!0-9]*}"
    local count=${#leading_digits}

    if (( count > largest_number )); then
        largest_number=$count
    fi
}

function pad_digits {
    shopt -s extglob
    local input="$1"
    local target_length="$2" 
    local digits="${input%%[!0-9]*}"
    local suffix="${input#"$digits"}"

    if [[ -n "$digits" ]]; then
        printf -v padded "%0*d" "$target_length" "$digits"
        echo "${padded}${suffix}"
    else
        echo "$input"
    fi
}

function remove_leading_digits {
    shopt -s extglob
    echo "${1##+([0-9])}"
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

preview_mode=false
declare -a input_directories
declare -a initial_strings_to_remove
remove_digits_mode=false

while getopts "r:dhp" opt; do
    case ${opt} in
        r) initial_strings_to_remove+=("${OPTARG}");;
        p) preview_mode=true;;
        d) remove_digits_mode=true;;
        h) usage;;
        ?) usage;;
    esac
done
shift $((OPTIND - 1))

for dir in "$@"; do
    input_directories+=("$dir")
done

for input_directory in "${input_directories[@]}"; do
    num_songs=0
    largest_number=0
    
    if ! check_args "$input_directory"; then
        continue
    fi
    
    declare -a strings_to_remove
    declare -A word_map
    # shellcheck disable=SC2206
    strings_to_remove=(${initial_strings_to_remove[@]})

    for file in "$input_directory"/*; do
        if [[ "$file" =~ .mp3 ]]; then

            basename="$(basename "$file")"
            ((num_songs+=1))

            extract_words "$basename"
        fi

        check_digits "$basename"
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

            new_file=${new_file//_/ }
            new_file="${new_file#"${new_file%%[![:space:]]*}"}"
            new_file="${new_file%"${new_file##*[![:space:]]}"}"
            new_file=$(echo "$new_file" | sed -E 's/ [Ff]eat(\.|uring).*\.([^.]+)$/.\2/')

            if $remove_digits_mode; then
                new_file=$(remove_leading_digits "$new_file")
            else
                new_file=$(pad_digits "$new_file" "$largest_number")
            fi

            echo "$new_file"
            if ! $preview_mode; then
                mv "$file" "$dirname/$new_file"
            fi
        fi
    done
done