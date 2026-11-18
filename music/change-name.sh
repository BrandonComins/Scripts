#!/bin/bash

function usage {
    cat << EOF
Usage: $(basename "$0") [-p] [-d] [-i] [-b] <directory1> [directory2 ...]

Options:
  -p            Preview mode (prints clean alignment without renaming)
  -d            Remove / omit order numbers entirely (keep name only)
  -i            Remove instrumental tracks
  -b            Remove bonus / extra tracks
  -h            Display this help message and exit
EOF
    exit 1
}

function check_args {
    local error=0
    if [ ! -d "$1" ]; then
        ((error+=1))
        echo "[Error] $1 is not a directory skipping..."
    fi
    return $error
}

function remove_leading_digits {
    shopt -s extglob
    echo "${1##+([0-9])}"
}

preview_mode=false
remove_digits_mode=false
remove_instrumentals=false
remove_bonus=false
declare -a input_directories

while getopts "dhpib" opt; do
    case ${opt} in
        p) preview_mode=true;;
        d) remove_digits_mode=true;;
        i) remove_instrumentals=true;;
        b) remove_bonus=true;;
        h) usage;;
        ?) usage;;
    esac
done
shift $((OPTIND - 1))

for dir in "$@"; do
    input_directories+=("$dir")
done

if (( ${#input_directories[@]} == 0 )); then
    echo "[Error] No directories specified."
    usage
fi

for input_directory in "${input_directories[@]}"; do
    if ! check_args "$input_directory"; then
        continue
    fi

    # Load and naturally sort all files (e.g. Track 2 comes before Track 10)
    mapfile -t all_files < <(find "$input_directory" -maxdepth 1 -type f ! -name "thumbnail.jpg" | sort -V)

    total_kept_songs=0
    max_len=0
    declare -a raw_filenames

    # First pass: Filter out deleted tracks (instrumentals / bonus) and count survivors
    for file in "${all_files[@]}"; do
        basename="$(basename "$file")"

        is_instrumental=false
        is_bonus=false

        if [[ "$basename" =~ [Ii]nstrumental ]]; then
            is_instrumental=true
        fi
        if [[ "$basename" =~ ([Bb]onus|[Ee]xtra) ]]; then
            is_bonus=true
        fi

        if $remove_instrumentals && $is_instrumental; then
            continue
        fi
        if $remove_bonus && $is_bonus; then
            continue
        fi

        ((total_kept_songs+=1))
        raw_filenames+=("$basename")

        if (( ${#basename} > max_len )); then
            max_len=${#basename}
        fi
    done

    # Determine zero-padding length based strictly on total kept songs
    pad_len=${#total_kept_songs}
    if (( pad_len < 2 && total_kept_songs >= 10 )); then
        pad_len=2
    fi

    # Dynamic Boilerplate Phrase Detection
    threshold=$(( (${#raw_filenames[@]} ) / 2 ))
    if (( threshold < 2 )); then threshold=2; fi

    common_phrases=$(printf '%s\n' "${raw_filenames[@]}" | \
        sed -E 's/\.[^.]+$//' | \
        sed -E 's/[_-：]+/ /g' | \
        awk -v thresh="$threshold" '
        {
            line = tolower($0)
            n = split(line, words, " ")
            for (i=1; i<=n; i++) {
                phrase = words[i]
                for (j=i+1; j<=n && j<=i+8; j++) {
                    phrase = phrase " " words[j]
                    if (phrase !~ /^[0-9 ]+$/) {
                        count[phrase]++
                        file_seen[phrase, NR] = 1
                    }
                }
            }
        }
        END {
            for (p in count) {
                files_with_phrase = 0
                for (f=1; f<=NR; f++) {
                    if (file_seen[p, f]) files_with_phrase++
                }
                if (files_with_phrase >= thresh && length(p) > 8) {
                    print length(p), p
                }
            }
        }' | sort -nr | head -n 3 | cut -d' ' -f2-)

    echo "========================================================================"
    echo "Directory: $input_directory ($total_kept_songs valid tracks kept)"
    if $preview_mode; then
        echo "[PREVIEW MODE ACTIVE]"
    else
        echo "[LIVE RENAMING ACTIVE]"
    fi
    echo "========================================================================"

    # Second pass: Process transformations in strict natural sorted order
    seq_counter=1
    for file in "${all_files[@]}"; do
        basename="$(basename "$file")"
        dirname="$(dirname "$file")"

        is_instrumental=false
        is_bonus=false

        if [[ "$basename" =~ [Ii]nstrumental ]]; then
            is_instrumental=true
        fi
        if [[ "$basename" =~ ([Bb]onus|[Ee]xtra) ]]; then
            is_bonus=true
        fi

        if $remove_instrumentals && $is_instrumental; then
            printf "%-${max_len}s  -->  [DELETED / INSTRUMENTAL]\n" "$basename"
            if ! $preview_mode; then
                rm "$file"
            fi
            continue
        fi

        if $remove_bonus && $is_bonus; then
            if $preview_mode; then
                printf "%-${max_len}s  -->  [DELETED / BONUS]\n" "$basename"
            else
                echo "Removing bonus track: '$basename'"
                rm "$file"
            fi
            continue
        fi

        # Isolate extension and base name
        if [[ "$basename" == *.* ]]; then
            ext="${basename##*.}"
            name_no_ext="${basename%.*}"
        else
            ext="mp3"
            name_no_ext="$basename"
        fi

        # Remove feat parentheses/brackets
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/\([^)]*[Ff]eat[^)]*\)//g')
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/\[[^]]*[Ff]eat[^]]*\]//g')

        # Universal Structural Block Stripping:
        # This generically catches leading track numbers/dashes and strips out the middle 
        # album title block up to the final separator marker (like " - . " or "： ... - . ")
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/^[0-9]+[[:space:]]*[-–：][[:space:]]*(.-.[[:space:]]*)?//')
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/^[^–-]+[-–：]+[[:space:]]*.*[-–：]+[[:space:]]*\.[[:space:]]*/ /')
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/^[0-9]+[[:space:]]+[^–-]+[-–：]+[[:space:]]*//')
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/[_-]*[Tt]rack[[:space:]]+[0-9]+[_-]*/ /g')
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/[_-：]+[[:space:]]*\.[[:space:]]*/ /g')

        # Strip dynamically common phrases like if the entire album contains the game name
        while IFS= read -r phrase; do
            if [ -n "$phrase" ]; then
                name_no_ext=$(echo "$name_no_ext" | sed -E "s/([_-：]*)${phrase}([_-：]*)/\1\2/gi")
            fi
        done <<< "$common_phrases"

        # Strip generic trailing metadata tags if present (e.g., OST, Soundtrack, Platform names)
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/[_-]+(OST|Soundtrack|Switch|PlayStation|Xbox|PC).*$//i')

        # Clean up any remaining isolated track indicator words
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/[Tt]rack[[:space:]]+[0-9]+//gi')

        # Fix apostrophes
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/([a-zA-Z])[_-]+s([_-]+)/\1\x27s\2/g')

        # Convert remaining underscores, hyphens, and full-width colons into spaces
        name_no_ext="${name_no_ext//_/ }"
        name_no_ext="${name_no_ext//-/ }"
        name_no_ext="${name_no_ext//：/ }"

        # Trim leading/trailing spaces and collapse multiple spaces
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/[[:space:]]+/ /g')
        name_no_ext=$(echo "$name_no_ext" | sed -E 's/^[[:space:]-]+|[[:space:]-]+$//g')

        # Apply numbering logic (either strip all numbers via -d or prepend zero-padded sequential number)
        if $remove_digits_mode; then
            name_no_ext=$(remove_leading_digits "$name_no_ext")
            name_no_ext=$(echo "$name_no_ext" | sed -E 's/^[[:space:]-]+//')
        else
            # Strip any stray leading numbers left behind
            name_no_ext=$(remove_leading_digits "$name_no_ext")
            name_no_ext=$(echo "$name_no_ext" | sed -E 's/^[[:space:]-]+//')

            # Format with sequential zero-padded number
            printf -v padded_num "%0*d" "$pad_len" "$seq_counter"
            name_no_ext="${padded_num} - ${name_no_ext}"
            ((seq_counter+=1))
        fi

        # Reattach extension
        new_file="${name_no_ext}.${ext}"

        # Consistently use aligned formatting for output
        printf "%-${max_len}s  -->  %s\n" "$basename" "$new_file"
        if ! $preview_mode; then
            mv "$file" "$dirname/$new_file"
        fi
    done
    echo ""
done
