set -euo pipefail

if [ -n "${CONSTANTS_LOADED:-}" ]; then
    return 0
fi
readonly CONSTANTS_LOADED=true

readonly CODE_SUCCESS=0
readonly CODE_EMPTY_STRING=1
readonly CODE_INVALID_BOOLEAN=2
readonly CODE_INVALID_INTEGER=3
readonly CODE_INVALID_FLOAT=4
readonly CODE_NEGATIVE_NOT_ALLOWED=5
readonly CODE_OUT_OF_RANGE=6
readonly CODE_INVALID_IDENTIFIER=7
readonly CODE_DIRECTORY_NOT_FOUND=10
readonly CODE_DIRECTORY_NOT_WRITABLE=11
readonly CODE_FILE_NOT_FOUND=12
readonly CODE_FILE_PERMISSION=13
readonly CODE_INVALID_SOCKET=20
readonly CODE_INVALID_ENV=21
readonly CODE_PROCESS_NOT_RUNNING=22

readonly MESSAGE_EMPTY_STRING="Error: Input string cannot be empty."
readonly MESSAGE_INVALID_BOOLEAN="Error: Invalid boolean value."
readonly MESSAGE_INVALID_INTEGER="Error: Invalid integer value."
readonly MESSAGE_INVALID_FLOAT="Error: Invalid float value."
readonly MESSAGE_NEGATIVE_NOT_ALLOWED="Error: Negative numbers are not allowed."
readonly MESSAGE_OUT_OF_RANGE="Error: Value out of range."
readonly MESSAGE_INVALID_IDENTIFIER="Error: Invalid identifier format."
readonly MESSAGE_DIRECTORY_NOT_FOUND="Error: Directory does not exist."
readonly MESSAGE_DIRECTORY_NOT_WRITABLE="Error: Directory is not writable."
readonly MESSAGE_FILE_NOT_FOUND="Error: File does not exist."
readonly MESSAGE_FILE_PERMISSION="Error: File does not have the required permission (read/write/execute)"
