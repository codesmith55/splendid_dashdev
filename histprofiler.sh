#!/bin/bash
# Rigorous error checking
set -euo pipefail

# --- Configuration ---
# Directory to store profiles. Using a custom name to avoid conflicts.
PROFILES_DIR="$HOME/.bash_history_profiles"
mkdir -p "$PROFILES_DIR" # Ensure the base directory for profiles exists

# Default number of history lines to show
DEFAULT_HISTORY_LINES=50
show_n_history_lines="$DEFAULT_HISTORY_LINES"

# --- Function to display help ---
show_help() {
    echo "Usage: $(basename "$0") [ACTION] [OPTIONS]"
    echo "Manages profiles for storing selected bash history commands."
    echo
    echo "Initial Choice (if no action is provided as an argument):"
    echo "  - (A)dd to/Create Profile: Select or create a profile and add history commands to it."
    echo "  - (V)iew Profile: Select an existing profile to view its stored commands."
    echo "  - (E)dit Profile: Select an existing profile to remove commands from it."
    echo "  - (R)emove Profile: Select an existing profile to delete it."
    echo
    echo "OPTIONS:"
    echo "  -h, --help             Show this help message."
    echo "  -n LINES, --num-lines LINES"
    echo "                         Specify the number of recent history lines to display when adding commands."
    echo "                         (Default: $DEFAULT_HISTORY_LINES)"
    echo
    echo "Workflow for Adding/Creating (A):"
    echo "1. You will be prompted to select an existing profile or enter a name for a new one."
    echo "2. The script will then display the last specified number (default $DEFAULT_HISTORY_LINES) of your command history."
    echo "3. Enter selection criteria to specify which history lines to save."
    echo
    echo "Workflow for Editing (E):"
    echo "1. Select an existing profile."
    echo "2. The script will display the commands currently in the profile, numbered."
    echo "3. Enter selection criteria to specify which commands to remove."
    echo
    echo "Input format for selecting/deselecting lines (comma-separated):"
    echo "  - Single line number: e.g., '5' (selects/deselects the 5th displayed command/history line)"
    echo "  - Range of lines: e.g., '10-15' (selects/deselects lines 10 through 15)"
    echo "  - Keyword search: e.g., 'mykeyword' (selects/deselects lines containing 'mykeyword')"
    echo "  - Keyword search with context (Only for Adding): e.g., 'another_keyword+2' (selects lines containing 'another_keyword' plus 2 lines before and 2 after)"
    echo "  - Combinations: e.g., '5, 10-15, mykeyword'"
    echo
    echo "Commands are saved to a '.sh' file within the profile's directory (e.g., $PROFILES_DIR/my_profile/commands.sh)."
    echo "The script attempts to avoid adding duplicate commands or the command that invoked the script itself."
}

# --- Argument Parsing ---
main_action=""
# Process options first
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--num-lines)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                show_n_history_lines="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --num-lines requires a numeric argument." >&2
                exit 1
            fi
            ;;
        -*)
            # Check if it's a known action that might look like an option if shortened (e.g., -A)
            # This simple check assumes actions are single uppercase/lowercase letters
            if [[ "$1" =~ ^-[aAvVeErR]$ ]]; then
                 # Let it fall through to action processing later
                 break
            fi
            echo "Error: Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
        *)
            # Not an option, assume it could be an action
            break
            ;;
    esac
done

# Process action if provided as the current argument
if [[ $# -gt 0 && -z "$main_action" ]]; then
    # Convert to uppercase for consistent matching
    ACTION_ARG=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    case "$ACTION_ARG" in
        A|ADD)
            main_action="A"
            shift
            ;;
        V|VIEW)
            main_action="V"
            shift
            ;;
        E|EDIT)
            main_action="E"
            shift
            ;;
        R|REMOVE)
            main_action="R"
            shift
            ;;
        *)
            # If it's not a recognized action, it could be an error
            # or the user didn't provide an action and we should prompt.
            # If an unknown arg remains, it's an error.
            if [[ -n "$1" ]]; then
                echo "Error: Invalid action or unexpected argument '$1'. Use -h or --help for options." >&2
                exit 1
            fi
            ;;
    esac
fi


# --- Function to list profiles and get selection ---
# Returns the selected profile name in the global variable `selected_profile_name`
# or an empty string if no selection/creation.
# Takes one argument: "select_only" or "select_or_create"
select_profile_flow() {
    local mode="$1" # "select_only" or "select_or_create"
    selected_profile_name="" # Reset global variable

    echo "Available profiles:"
    profiles=() # Array to hold names of existing profiles
    i=1         # Counter for listing profiles

    if [ -d "$PROFILES_DIR" ] && [ "$(ls -A "$PROFILES_DIR")" ]; then
        for profile_path in "$PROFILES_DIR"/*/; do
            if [ -d "$profile_path" ]; then # Check if it's a directory
                profile_name=$(basename "$profile_path")
                echo "  $i) $profile_name"
                profiles+=("$profile_name")
                i=$((i + 1))
            fi
        done
    fi

    if [ ${#profiles[@]} -eq 0 ]; then
        echo "  No profiles found."
        if [ "$mode" == "select_only" ]; then
            return 1 # Indicate no profiles to select
        fi
    fi

    local prompt_msg="Choose a profile number"
    if [ "$mode" == "select_or_create" ]; then
        prompt_msg+=", or type a new profile name"
    fi
    prompt_msg+=": "

    read -r -p "$prompt_msg" profile_choice

    if [[ "$profile_choice" =~ ^[0-9]+$ ]] && [ "$profile_choice" -ge 1 ] && [ "$profile_choice" -le "${#profiles[@]}" ]; then
        selected_profile_name="${profiles[$((profile_choice - 1))]}"
        echo "Selected profile: $selected_profile_name"
        return 0
    elif [[ "$mode" == "select_or_create" ]]; then
        # Assume any other non-empty input is a new profile name
        if [ -z "$profile_choice" ]; then
            echo "Error: Profile name cannot be empty. Exiting."
            return 1
        fi
        if [[ "$profile_choice" =~ [/] ]]; then
            echo "Error: Profile name cannot contain slashes. Exiting."
            return 1
        fi
        selected_profile_name="$profile_choice"
        echo "Selected new profile name: $selected_profile_name"
        return 0 # Indicates a new profile name was chosen or an existing one typed
    else
        echo "Error: Invalid choice."
        return 1 # Indicate invalid choice or no selection
    fi
}

# --- Main Action Selection (if not set by argument) ---
if [ -z "${main_action-}" ]; then
    echo "What would you like to do?"
    echo "  A) Add to/Create a profile"
    echo "  V) View an existing profile"
    echo "  E) Edit an existing profile (remove commands)"
    echo "  R) Remove an existing profile"
    read -r -p "Choose an action (A/V/E/R): " main_action_choice
    main_action=$(echo "$main_action_choice" | tr '[:lower:]' '[:upper:]') # Convert to uppercase
fi


if [[ "$main_action" == "V" ]]; then
    # --- View Profile ---
    echo -e "\n--- View Profile ---"
    if ! select_profile_flow "select_only"; then
        exit 1
    fi

    if [ -z "$selected_profile_name" ]; then
         echo "No profile selected for viewing. Exiting."
         exit 1
    fi

    PROFILE_CMDS_FILE="$PROFILES_DIR/$selected_profile_name/commands.sh"
    echo "Viewing commands for profile: $selected_profile_name"
    echo "File: $PROFILE_CMDS_FILE"
    echo "------------------------------------"
    if [ -f "$PROFILE_CMDS_FILE" ]; then
        if [ -s "$PROFILE_CMDS_FILE" ]; then
            cat "$PROFILE_CMDS_FILE"
        else
            echo "(Profile is empty)"
        fi
    else
        echo "(Profile commands file does not exist - profile might be empty or new)"
    fi
    echo "------------------------------------"
    echo "Done viewing."
    exit 0

elif [[ "$main_action" == "A" ]]; then
    # --- Add to/Create Profile ---
    echo -e "\n--- Add to/Create Profile ---"
    if ! select_profile_flow "select_or_create"; then
        echo "No profile selected or created. Exiting."
        exit 1
    fi

    if [ -z "$selected_profile_name" ]; then
         echo "Error: Profile selection failed unexpectedly. Exiting."
         exit 1
    fi

    mkdir -p "$PROFILES_DIR/$selected_profile_name"
    echo "Using profile: $selected_profile_name (directory ensured at $PROFILES_DIR/$selected_profile_name)"
    PROFILE_CMDS_FILE="$PROFILES_DIR/$selected_profile_name/commands.sh"
    touch "$PROFILE_CMDS_FILE"

    echo -e "\n--- Last $show_n_history_lines History Lines (or fewer if total history is less) ---" # MODIFIED
    _SCRIPT_HISTFILE="${HISTFILE:-$HOME/.bash_history}"
    set -o history # Enable history tracking in the script
    history -c # Clear script's internal history
    if [ -f "$_SCRIPT_HISTFILE" ]; then
        # Consider `history -a` here if essential to force write from parent before read,
        # but be mindful of potential HISTFILE contention or duplicate entries if parent also writes.
        # Forcing a `history -a` in the calling shell *before* running the script is safer.
        history -r "$_SCRIPT_HISTFILE" # Read history from file
    else
        echo "Warning: History file '$_SCRIPT_HISTFILE' not found."
    fi

    original_histtimeformat="${HISTTIMEFORMAT-}" # Save current HISTTIMEFORMAT
    unset HISTTIMEFORMAT # Unset to get plain history output

    mapfile -t full_history_lines < <(history) # Capture history lines

    if [ -n "$original_histtimeformat" ]; then # Restore original HISTTIMEFORMAT
        export HISTTIMEFORMAT="$original_histtimeformat"
    fi

    total_history_lines=${#full_history_lines[@]}
    echo "Total history lines available to script: $total_history_lines (from in-memory history, loaded from $_SCRIPT_HISTFILE)"

    # MODIFIED: Use show_n_history_lines
    display_start_index=$((total_history_lines > show_n_history_lines ? total_history_lines - show_n_history_lines : 0))
    if [ "$total_history_lines" -gt 0 ]; then
        for ((idx = display_start_index; idx < total_history_lines; idx++)); do
            # Ensure the line is not empty or just whitespace before printing
            if [[ -n "${full_history_lines[$idx]// }" ]]; then
                 printf "%s\n" "${full_history_lines[$idx]}"
            fi
        done
    else
        echo "No history lines to display."
    fi
    echo "--------------------------"

    echo -e "\nEnter history line numbers, ranges, keywords (e.g., 123, 450-455, git commit, sudo+1)."
    echo "Line numbers correspond to those shown above. Separate criteria with commas."
    read -r -p "Selection: " user_selection_str
    if [ -z "$user_selection_str" ]; then
        echo "No selection made. Exiting."
        exit 0
    fi

    declare -A history_line_numbers_to_add_map
    declare -A history_map_num_to_cmd

    for hist_line_full_str in "${full_history_lines[@]}"; do
        if [[ "$hist_line_full_str" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.*)$ ]]; then
            num="${BASH_REMATCH[1]}"
            cmd="${BASH_REMATCH[2]}"
            # Only map commands that were actually displayed or could be selected
            # This means commands from display_start_index onwards
            # However, the user input refers to the *history number*, not the displayed sequence number
            history_map_num_to_cmd["$num"]="$cmd"
        fi
    done

    IFS=',' read -r -a selection_criteria <<< "$user_selection_str"
    for selection_item in "${selection_criteria[@]}"; do
        selection_item_trimmed=$(echo "$selection_item" | xargs) # Trim whitespace

        if [[ "$selection_item_trimmed" =~ ^[0-9]+$ ]]; then # Single number (history number)
            if [[ -v history_map_num_to_cmd["$selection_item_trimmed"] ]]; then
                 history_line_numbers_to_add_map["$selection_item_trimmed"]=1
            else
                echo "Warning: History line number '$selection_item_trimmed' not found in the displayed/processed history. Skipping."
            fi
        elif [[ "$selection_item_trimmed" =~ ^([0-9]+)-([0-9]+)$ ]]; then # Range (history numbers)
            range_start="${BASH_REMATCH[1]}"
            range_end="${BASH_REMATCH[2]}"
            if [ "$range_start" -le "$range_end" ]; then
                for ((j = range_start; j <= range_end; j++)); do
                     if [[ -v history_map_num_to_cmd["$j"] ]]; then
                        history_line_numbers_to_add_map["$j"]=1
                     else
                        # Optional: echo "Warning: History line '$j' in range not found. Skipping."
                        : # Do nothing, just skip
                     fi
                done
            else
                echo "Warning: Invalid range '$selection_item_trimmed'. Skipping."
            fi
        elif [[ "$selection_item_trimmed" =~ ^([^[:space:]+]+)\+([0-9]+)$ ]]; then # keyword+N
            keyword="${BASH_REMATCH[1]}"
            extender="${BASH_REMATCH[2]}"
            # Search within the full_history_lines (which contains history numbers)
            for hist_num_key in "${!history_map_num_to_cmd[@]}"; do
                current_cmd="${history_map_num_to_cmd[$hist_num_key]}"
                if [[ "$current_cmd" == *"$keyword"* ]]; then
                    current_hist_num_int=$((hist_num_key)) # Convert to integer for arithmetic
                    for ((k = current_hist_num_int - extender; k <= current_hist_num_int + extender; k++)); do
                        if [[ -v history_map_num_to_cmd["$k"] ]]; then # Check if index k exists
                            history_line_numbers_to_add_map["$k"]=1
                        fi
                    done
                fi
            done
        elif [[ -n "$selection_item_trimmed" ]]; then # Non-empty, assume keyword
            keyword="$selection_item_trimmed"
            # Search within the full_history_lines
             for hist_num_key in "${!history_map_num_to_cmd[@]}"; do
                current_cmd="${history_map_num_to_cmd[$hist_num_key]}"
                if [[ "$current_cmd" == *"$keyword"* ]]; then
                     if [[ -v history_map_num_to_cmd["$hist_num_key"] ]]; then
                        history_line_numbers_to_add_map["$hist_num_key"]=1
                    fi
                fi
            done
        else
            echo "Warning: Unrecognized selection format '$selection_item_trimmed'. Skipping."
        fi
    done

    commands_to_save_to_profile=()
    sorted_line_numbers=($(printf "%s\n" "${!history_line_numbers_to_add_map[@]}" | sort -n))
    current_script_name=$(basename "$0")
    # Robust way to get script's own invocation patterns
    current_script_invocation_regex_patterns=(
        "bash[[:space:]]+.*${current_script_name}" # bash script.sh, bash /path/to/script.sh
        "\./${current_script_name}"               # ./script.sh
        "source[[:space:]]+.*${current_script_name}" # source script.sh
        "\.[[:space:]]+.*${current_script_name}"      # . script.sh
    )
    # Get absolute path of the script
    absolute_script_path=""
    if command -v realpath &> /dev/null; then
        absolute_script_path=$(realpath "$0" 2>/dev/null || echo "$0")
    else # Fallback for systems without realpath (less robust for symlinks)
        if [[ "$0" == /* ]]; then absolute_script_path="$0"; else absolute_script_path="$PWD/$0"; fi
    fi

    # Add patterns for invoking with full path or just name if in PATH
    current_script_invocation_regex_patterns+=("${current_script_name}")
    if [[ -n "$absolute_script_path" && "$absolute_script_path" != "$0" && "$absolute_script_path" != "$PWD/${current_script_name}" ]]; then
        current_script_invocation_regex_patterns+=("$(realpath "$0" 2>/dev/null || echo "$0")") # Covers invoking by full path
    fi


    for line_num in "${sorted_line_numbers[@]}"; do
        if [[ -v history_map_num_to_cmd["$line_num"] ]]; then
            cmd_to_add="${history_map_num_to_cmd["$line_num"]}"
            is_self_invocation=0
            # Skip simple 'history' command
            if [[ "$cmd_to_add" =~ ^history($|[[:space:]]) ]]; then
                # echo "Skipping 'history' command: $line_num: $cmd_to_add"
                continue
            fi
            # Skip commands that invoked this script
            for pattern in "${current_script_invocation_regex_patterns[@]}"; do
                # Add word boundaries for the script name itself to avoid partial matches in other commands
                # e.g., if script is 'hist' and command is 'history', don't match.
                # This is tricky because pattern can be a path.
                # A simple check:
                if [[ "$cmd_to_add" == *"$current_script_name"* ]]; then
                    # More specific check if it's actually an invocation
                    # This is a heuristic. A perfect check is very complex.
                    if echo "$cmd_to_add" | grep -E "^\s*(\.?/|bash\s+|source\s+|sh\s+)*.*${current_script_name}(\s|$)"; then
                         is_self_invocation=1; break
                    fi
                    # Check absolute path invocation
                     if [[ "$cmd_to_add" == *"$absolute_script_path"* ]]; then
                        is_self_invocation=1; break
                     fi
                fi
            done


            if [ $is_self_invocation -eq 1 ]; then
                # echo "Skipping self-referential command: $line_num: $cmd_to_add"
                continue
            fi
            commands_to_save_to_profile+=("$cmd_to_add")
        fi
    done

    if [ ${#commands_to_save_to_profile[@]} -eq 0 ]; then
        echo "No valid (new, non-self-referential) commands selected to add."
    else
        echo -e "\n--- Commands to be added to profile '$selected_profile_name' ---"
        printf "%s\n" "${commands_to_save_to_profile[@]}"
        echo "------------------------------------"

        existing_commands_in_profile_str=""
        if [ -f "$PROFILE_CMDS_FILE" ] && [ -s "$PROFILE_CMDS_FILE" ]; then
            existing_commands_in_profile_str=$(<"$PROFILE_CMDS_FILE")
        fi

        final_commands_to_append_to_file=()
        for cmd in "${commands_to_save_to_profile[@]}"; do
            # Exact match check, line by line
            if echo "$existing_commands_in_profile_str" | grep -Fxq -- "$cmd"; then
                echo "Skipping duplicate: $cmd"
            else
                final_commands_to_append_to_file+=("$cmd")
            fi
        done

        if [ ${#final_commands_to_append_to_file[@]} -gt 0 ]; then
            printf "%s\n" "${final_commands_to_append_to_file[@]}" >> "$PROFILE_CMDS_FILE"
            # Add a blank line for separation if desired, only if adding new commands
            if [[ $(tail -c1 "$PROFILE_CMDS_FILE" | wc -l) -eq 0 ]]; then # if no trailing newline
                 echo "" >> "$PROFILE_CMDS_FILE" # Add one
            fi
            echo "" >> "$PROFILE_CMDS_FILE" # Add an extra blank line for visual separation of future appends
            echo "${#final_commands_to_append_to_file[@]} new command(s) added to $PROFILE_CMDS_FILE"
        else
            echo "No new (non-duplicate) commands to add to the profile."
        fi
    fi
    echo -e "\nProfile '$selected_profile_name' is located at: $PROFILE_CMDS_FILE"
    echo "Done."

elif [[ "$main_action" == "E" ]]; then
    # --- Edit Profile (Remove Commands) ---
    echo -e "\n--- Edit Profile: Remove Commands ---"
    if ! select_profile_flow "select_only"; then
        exit 1
    fi
    if [ -z "$selected_profile_name" ]; then
         echo "No profile selected for editing. Exiting."
         exit 1
    fi

    PROFILE_CMDS_FILE="$PROFILES_DIR/$selected_profile_name/commands.sh"
    if [ ! -f "$PROFILE_CMDS_FILE" ] || [ ! -s "$PROFILE_CMDS_FILE" ]; then
        echo "Profile '$selected_profile_name' is empty or does not exist. Nothing to edit."
        exit 0
    fi

    echo "Commands in profile '$selected_profile_name':"
    echo "------------------------------------"
    mapfile -t profile_cmds_array < "$PROFILE_CMDS_FILE"
    # Filter out empty lines that might have been added for spacing
    temp_cmds_array=()
    for cmd_line in "${profile_cmds_array[@]}"; do
        if [[ -n "$(echo "$cmd_line" | xargs)" ]]; then # Only add non-empty lines (after trimming)
            temp_cmds_array+=("$cmd_line")
        fi
    done
    profile_cmds_array=("${temp_cmds_array[@]}")


    if [ ${#profile_cmds_array[@]} -eq 0 ]; then
        echo "(Profile is effectively empty after filtering blank lines)"
        echo "------------------------------------"
        exit 0
    fi

    cmd_idx=1
    for cmd in "${profile_cmds_array[@]}"; do
        echo "$cmd_idx: $cmd"
        cmd_idx=$((cmd_idx + 1))
    done
    echo "------------------------------------"

    echo -e "\nEnter line numbers, ranges, or keywords of commands to REMOVE."
    echo "Example: '1, 3-5, specific_command_keyword'"
    read -r -p "Lines/keywords to remove: " removal_selection_str

    if [ -z "$removal_selection_str" ]; then
        echo "No selection made for removal. Exiting."
        exit 0
    fi

    declare -A lines_to_remove_map # Using 1-based indexing for user input matching

    IFS=',' read -r -a removal_criteria <<< "$removal_selection_str"
    for criterion in "${removal_criteria[@]}"; do
        criterion_trimmed=$(echo "$criterion" | xargs)

        if [[ "$criterion_trimmed" =~ ^[0-9]+$ ]]; then # Single line number
            if (( criterion_trimmed >= 1 && criterion_trimmed <= ${#profile_cmds_array[@]} )); then
                lines_to_remove_map["$criterion_trimmed"]=1
            else
                echo "Warning: Line number '$criterion_trimmed' is out of range (1-${#profile_cmds_array[@]}). Skipping."
            fi
        elif [[ "$criterion_trimmed" =~ ^([0-9]+)-([0-9]+)$ ]]; then # Range
            range_start="${BASH_REMATCH[1]}"
            range_end="${BASH_REMATCH[2]}"
            if (( range_start <= range_end )); then
                for ((j = range_start; j <= range_end; j++)); do
                    if (( j >= 1 && j <= ${#profile_cmds_array[@]} )); then
                        lines_to_remove_map["$j"]=1
                    else
                         # Optional: echo "Warning: Line number '$j' in range is out of range. Skipping."
                        :
                    fi
                done
            else
                echo "Warning: Invalid range '$criterion_trimmed' (start > end). Skipping."
            fi
        elif [[ -n "$criterion_trimmed" ]]; then # Keyword
            keyword="$criterion_trimmed"
            for ((k = 0; k < ${#profile_cmds_array[@]}; k++)); do
                if [[ "${profile_cmds_array[$k]}" == *"$keyword"* ]]; then
                    lines_to_remove_map["$((k + 1))"]=1 # Store 1-based index
                fi
            done
        else
             echo "Warning: Unrecognized removal format '$criterion_trimmed'. Skipping."
        fi
    done

    if [ ${#lines_to_remove_map[@]} -eq 0 ]; then
        echo "No valid lines selected for removal. Profile remains unchanged."
        exit 0
    fi

    echo -e "\n--- Commands marked for REMOVAL ---"
    temp_commands_kept=()
    removed_count=0
    for ((l_idx = 0; l_idx < ${#profile_cmds_array[@]}; l_idx++)); do
        current_line_num=$((l_idx + 1))
        if [[ -v lines_to_remove_map["$current_line_num"] ]]; then
            echo "Removing line $current_line_num: ${profile_cmds_array[$l_idx]}"
            removed_count=$((removed_count + 1))
        else
            temp_commands_kept+=("${profile_cmds_array[$l_idx]}")
        fi
    done
    echo "------------------------------------"


    if [ "$removed_count" -eq 0 ]; then
        echo "No commands were actually marked for removal after processing. Profile unchanged."
        exit 0
    fi

    # Overwrite the profile file with the remaining commands
    # Ensure there's a newline after each command, but not multiple blank lines unless intended.
    # And a final newline if the file is not empty.
    > "$PROFILE_CMDS_FILE" # Truncate the file
    if [ ${#temp_commands_kept[@]} -gt 0 ]; then
        printf "%s\n" "${temp_commands_kept[@]}" >> "$PROFILE_CMDS_FILE"
        # Ensure a single trailing newline if content exists
        # The printf above adds one, so this might not be strictly necessary
        # unless the original commands didn't have newlines (which they should from mapfile).
        # To be safe, ensure the file doesn't end mid-line if all kept commands were one line.
    fi


    echo "$removed_count command(s) removed. Profile '$selected_profile_name' updated."
    echo "File: $PROFILE_CMDS_FILE"
    echo "Done."


elif [[ "$main_action" == "R" ]]; then
    # --- Remove Profile ---
    echo -e "\n--- Remove Profile ---"
    if ! select_profile_flow "select_only"; then
        # select_profile_flow prints "No profiles found" or error
        exit 1
    fi

    if [ -z "$selected_profile_name" ]; then
         echo "No profile selected for removal. Exiting."
         exit 1
    fi

    PROFILE_TO_REMOVE_DIR="$PROFILES_DIR/$selected_profile_name"

    read -r -p "Are you sure you want to REMOVE the profile '$selected_profile_name' and all its commands? (yes/N): " confirmation
    if [[ "$confirmation" == "yes" || "$confirmation" == "YES" ]]; then
        if [ -d "$PROFILE_TO_REMOVE_DIR" ]; then
            rm -rf "$PROFILE_TO_REMOVE_DIR"
            if [ $? -eq 0 ]; then
                echo "Profile '$selected_profile_name' removed successfully from $PROFILES_DIR."
            else
                echo "Error: Failed to remove profile directory '$PROFILE_TO_REMOVE_DIR'."
                exit 1 # Exit with error if removal fails
            fi
        else
            echo "Error: Profile directory '$PROFILE_TO_REMOVE_DIR' not found. Cannot remove."
            # This should ideally not happen if select_profile_flow worked correctly
            # and the profile wasn't deleted externally between selection and this point.
            # Consider exiting if this state is critical.
        fi
    else
        echo "Profile removal cancelled."
    fi
    echo "Done."

else
    echo "Error: Invalid action choice '$main_action'. Exiting."
    echo "Use -h or --help for options."
    exit 1
fi