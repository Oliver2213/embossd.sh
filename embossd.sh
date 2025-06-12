#!/bin/bash

# EmbossD - A simple HTTP daemon for braille embossers

VERSION="0.1"
AUTHORS="Blake Oliver"
SOURCE_URL=""

# Source .env file if it exists (before setting other variables)
if [[ -f ".env" ]]; then
    source .env
fi

DEVICE="${DEVICE:-/dev/usb/lp0}"
PORT="${PORT:-9999}"
CONTENT_FILE="${CONTENT_FILE:-}"
# Check if SHOW_INSTRUCTIONS was explicitly set in environment
if [[ -n "${SHOW_INSTRUCTIONS:-}" ]]; then
    SHOW_INSTRUCTIONS_SET=1
else
    SHOW_INSTRUCTIONS=1
fi
EMBOSSER_MODEL="${EMBOSSER_MODEL:-}"
PAPER_SIZE="${PAPER_SIZE:-}"
LOCK_FILE="/tmp/embossd.lock"

# Usage function
usage() {
    echo "EmbossD v$VERSION - A simple HTTP daemon for braille embossers"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --device PATH     Braille embosser device path (default: $DEVICE)"
    echo "  --web-port PORT   Web server port (default: $PORT)"
    echo "  --version         Show version information"
    echo "  --help            Show this help message"
    echo ""
    echo "Author: $AUTHORS"
    echo ""
}

# Version function
show_version() {
    echo "EmbossD v$VERSION"
    echo "by $AUTHORS"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --device)
            DEVICE="$2"
            shift 2
            ;;
        --web-port)
            PORT="$2"
            shift 2
            ;;
        --version)
            show_version
            exit 0
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            echo ""
            usage
            exit 1
            ;;
    esac
done

# Check if device exists
if [[ ! -w "$DEVICE" ]]; then
    echo "Error: Cannot write to device $DEVICE"
    exit 1
fi

# Set SHOW_INSTRUCTIONS to 0 if content file exists and variable wasn't explicitly set
if [[ -n "$CONTENT_FILE" && -f "$CONTENT_FILE" ]]; then
    # Only auto-hide instructions if SHOW_INSTRUCTIONS wasn't explicitly set in environment
    if [[ "${SHOW_INSTRUCTIONS}" == "1" && -z "${SHOW_INSTRUCTIONS_SET:-}" ]]; then
        SHOW_INSTRUCTIONS=0
    fi
fi

echo "Starting EmbossD v$VERSION by $AUTHORS on port $PORT, device: $DEVICE"

# Build instructions text
build_instructions() {
    local section="$1"  # "text" or "file"
    
    if [[ "$SHOW_INSTRUCTIONS" != "1" ]]; then
        return
    fi
    
    local base_text=""
    if [[ "$section" == "text" ]]; then
        base_text="Type or paste your text in the field below, then click Emboss to send it to your braille embosser."
    else
        base_text="Choose a .txt or .brf file from your computer, then click Upload & Emboss to send its contents to your braille embosser."
    fi
    
    local extra_info=""
    if [[ -n "$EMBOSSER_MODEL" || -n "$PAPER_SIZE" ]]; then
        extra_info=" ("
        if [[ -n "$EMBOSSER_MODEL" ]]; then
            extra_info="${extra_info}Embosser model: $EMBOSSER_MODEL"
        fi
        if [[ -n "$EMBOSSER_MODEL" && -n "$PAPER_SIZE" ]]; then
            extra_info="${extra_info}, "
        fi
        if [[ -n "$PAPER_SIZE" ]]; then
            extra_info="${extra_info}Paper size: $PAPER_SIZE"
        fi
        extra_info="${extra_info})"
    fi
    
    echo "<p><strong>Instructions:</strong> ${base_text}${extra_info}</p>"
}

# Generate HTML page
generate_html() {
    local status_msg=""
    if [[ -f "$LOCK_FILE" ]]; then
        status_msg="<div style='color: red; font-weight: bold;'>Currently embossing... Please wait.</div>"
    fi
    
    local disabled=""
    if [[ -f "$LOCK_FILE" ]]; then
        disabled="disabled"
    fi
    
    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <title>EmbossD</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; }
        input[type=text] { width: 300px; padding: 5px; }
        input[type=file] { margin: 10px 0; }
        button { padding: 10px 20px; margin: 5px; }
        button:disabled { opacity: 0.5; }
        .content-section { margin: 20px 0; padding: 15px; background-color: #f9f9f9; border-left: 4px solid #007cba; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>EmbossD v$VERSION</h1>
        $status_msg
        
$(if [[ -n "$CONTENT_FILE" && -f "$CONTENT_FILE" ]]; then
    echo "        <div class='content-section'>"
    cat "$CONTENT_FILE"
    echo "        </div>"
    echo ""
fi)        <h2>Emboss Text</h2>
        $(build_instructions "text")
        <form method='post' action='/print'>
            <input type='text' name='text' placeholder='Enter text to emboss' required>
            <button type='submit' $disabled>Emboss</button>
        </form>
        
        <h2>Upload File</h2>
        $(build_instructions "file")
        <form method='post' action='/upload' enctype='multipart/form-data'>
            <input type='file' name='file' accept='.txt,.brf' required>
            <button type='submit' $disabled>Upload & Emboss</button>
        </form>
        
        <footer style='margin-top: 40px; padding-top: 20px; border-top: 1px solid #ccc; font-size: 0.9em; color: #666;'>
            EmbossD v$VERSION by $AUTHORS$(if [[ -n "$SOURCE_URL" ]]; then echo " | <a href='$SOURCE_URL'>Source Code</a>"; fi)
        </footer>
    </div>
</body>
</html>
EOF
}

# Handle HTTP request
handle_request() {
    local method=""
    local path=""
    local content_length=0
    local user_agent=""
    local is_curl=false
    local line
    
    # Read request line
    read -r line
    method=$(echo "$line" | cut -d' ' -f1)
    path=$(echo "$line" | cut -d' ' -f2)
    
    # Read headers
    while read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ -z "$line" ]] && break
        
        if [[ "$line" =~ ^Content-Length:\ ([0-9]+) ]]; then
            content_length=${BASH_REMATCH[1]}
        elif [[ "$line" =~ ^User-Agent:\ (.+) ]]; then
            user_agent="${BASH_REMATCH[1]}"
            if [[ "$user_agent" =~ curl ]]; then
                is_curl=true
            fi
        fi
    done
    
    # Handle POST data
    if [[ "$method" == "POST" && "$content_length" -gt 0 ]]; then
        local post_data
        post_data=$(head -c "$content_length")
        
        # Handle curl requests (raw data)
        if [[ "$is_curl" == true ]]; then
            # Check if currently printing
            if [[ -f "$LOCK_FILE" ]]; then
                # Return 503 Service Unavailable if busy
                echo "HTTP/1.1 503 Service Unavailable"
                echo "Content-Type: text/plain"
                echo "Connection: close"
                echo ""
                echo "Printer busy, try again later"
                return
            fi
            
            # Print the raw POST data
            print_text "$post_data"
            
            # Return 200 OK for successful queue
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/plain"
            echo "Connection: close"
            echo ""
            echo "Text queued for embossing"
            return
        fi
        
        # Handle web form data
        if [[ "$post_data" =~ text=([^&]*) ]]; then
            # URL decode the text
            local text="${BASH_REMATCH[1]}"
            text=$(echo "$text" | sed 's/+/ /g' | sed 's/%20/ /g' | sed 's/%0D%0A/\n/g')
            print_text "$text"
            
            # Send response
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            echo "Connection: close"
            echo ""
            echo "<html><body><h1>EmbossD v$VERSION</h1><p>Text queued for embossing!</p><a href='/'>Back</a></body></html>"
            return
        fi
    fi
    
    # Send main page
    local html
    html=$(generate_html)
    echo "HTTP/1.1 200 OK"
    echo "Content-Type: text/html"
    echo "Content-Length: ${#html}"
    echo "Connection: close"
    echo ""
    echo "$html"
}

# Function to print text to device
print_text() {
    local text="$1"
    
    # Create lock file to prevent concurrent printing
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        echo "Another emboss job is in progress"
        return 1
    fi
    
    # Print in background
    (
        echo "Printing: $text"
        echo "$text" > "$DEVICE"
        sleep 1  # Small delay to ensure write completes
        rmdir "$LOCK_FILE"
        echo "Emboss job completed"
    ) &
}

# Cleanup function
cleanup() {
    echo "Shutting down EmbossD..."
    rmdir "$LOCK_FILE" 2>/dev/null
    rm -f "/tmp/embossd_pipe" 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start the server
while true; do    
    # Create a named pipe for this connection (unique per process ID)
    PIPE="/tmp/embossd_pipe_$$"
    mkfifo "$PIPE"
    
    # Handle the connection using bidirectional communication:
    # - nc listens on PORT and reads responses from the pipe (< "$PIPE")
    # - HTTP requests from nc are piped to handle_request (|)
    # - handle_request processes the request and writes response to pipe (> "$PIPE")
    # - This creates a loop: nc <- pipe <- handle_request <- nc
    nc -l -p "$PORT" < "$PIPE" | handle_request > "$PIPE" &
    
    # Wait for the connection to finish
    wait
    
    # Clean up the temporary pipe
    rm -f "$PIPE"
done
