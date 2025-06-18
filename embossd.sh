#!/bin/bash

# EmbossD - An HTTP daemon for braille embossers, in shell!
# This runs a "so bare there aren't bones" http server to let users emboss text or brf files over the network.
# You can also post to it with curl and it will print that directly - no web form upload required.
# Optionally set or add to .env the following:
# CONTENT_FILE: an html snipet to place above the form and buttons. Disabled instructions by default if provided; SHOW_INSTRUCTIONS=1 to return them.
# EMBOSSER_MODEL, PAPER_SIZE: included in instructions so people know.

# Written in an afternoon with AI assistance

VERSION="0.1"
AUTHORS="Blake Oliver"
SOURCE_URL="https://github.com/Oliver2213/embossd.sh"

# Source .env file if it exists (before setting other variables)
# Check both current directory and /data directory
if [[ -f "/data/.env" ]]; then
    source /data/.env
elif [[ -f ".env" ]]; then
    source .env
fi

DEVICE="${DEVICE:-/dev/usb/lp0}"
PORT="${PORT:-9999}"
# If CONTENT_FILE is set but doesn't exist in current dir, check /data
if [[ -n "${CONTENT_FILE:-}" && ! -f "$CONTENT_FILE" && -f "/data/$CONTENT_FILE" ]]; then
    CONTENT_FILE="/data/$CONTENT_FILE"
else
    CONTENT_FILE="${CONTENT_FILE:-}"
fi
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
            <button type='submit' $disabled accesskey='m'>E<u>m</u>boss</button>
        </form>
        
        <h2>Upload File</h2>
        $(build_instructions "file")
        <form method='post' action='/upload' enctype='multipart/form-data'>
            <input type='file' name='file' accept='text/plain,application/brf,text/x-braille-document' required>
            <button type='submit' $disabled accesskey='u'><u>U</u>pload & Emboss</button>
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
    local content_type=""
    local boundary=""
    local is_curl=false
    local line
    
    # Read request line
    read -r line
    method=$(echo "$line" | cut -d' ' -f1)
    path=$(echo "$line" | cut -d' ' -f2)
    echo "Request: $method $path" >&2
    
    # Read headers
    while read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ -z "$line" ]] && break
        
        echo "Header: $line" >&2
        
        if [[ "$line" =~ ^Content-Length:\ ([0-9]+) ]]; then
            content_length=${BASH_REMATCH[1]}
            echo "Content-Length: $content_length" >&2
        elif [[ "$line" =~ ^User-Agent:\ (.+) ]]; then
            user_agent="${BASH_REMATCH[1]}"
            echo "User-Agent: $user_agent" >&2
            if [[ "$user_agent" =~ curl ]]; then
                is_curl=true
            fi
        elif [[ "$line" =~ ^Content-Type:\ (.+) ]]; then
            content_type="${BASH_REMATCH[1]}"
            echo "Content-Type: $content_type" >&2
            if [[ "$content_type" =~ boundary=([^;\ ]+) ]]; then
                boundary="${BASH_REMATCH[1]}"
                echo "Boundary: $boundary" >&2
            fi
        fi
    done
    
    # Handle POST data
    if [[ "$method" == "POST" && "$content_length" -gt 0 ]]; then
        echo "Processing POST request with $content_length bytes" >&2
        local post_data
        post_data=$(head -c "$content_length")
        echo "POST data received: ${#post_data} bytes" >&2
        
        # Handle curl requests (raw data)
        if [[ "$is_curl" == true ]]; then
            echo "Handling curl request" >&2
            # Check if currently printing
            if [[ -f "$LOCK_FILE" ]]; then
                echo "Printer busy, returning 503" >&2
                # Return 503 Service Unavailable if busy
                echo "HTTP/1.1 503 Service Unavailable"
                echo "Content-Type: text/plain"
                echo "Connection: close"
                echo ""
                echo "Printer busy, try again later"
                return
            fi
            
            # Print the raw POST data
            echo "Sending raw data to printer" >&2
            print_text "$post_data"
            
            # Return 200 OK for successful queue
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/plain"
            echo "Connection: close"
            echo ""
            echo "Text queued for embossing"
            return
        fi
        
        # Handle multipart form data (file uploads)
        if [[ -n "$boundary" && "$content_type" =~ multipart/form-data ]]; then
            echo "Handling multipart form data with boundary: $boundary" >&2
            
            # Extract file content from multipart data
            # This is a simplified parser - real multipart parsing is complex
            local file_content=""
            local in_file_data=false
            local filename=""
            
            # Split on boundary and process each part
            echo "$post_data" | while IFS= read -r line; do
                if [[ "$line" =~ --${boundary} ]]; then
                    in_file_data=false
                elif [[ "$line" =~ filename=\"([^\"]+)\" ]]; then
                    filename="${BASH_REMATCH[1]}"
                    echo "Found filename: $filename" >&2
                elif [[ -z "$line" && -n "$filename" ]]; then
                    # Empty line after headers means file content starts next
                    in_file_data=true
                elif [[ "$in_file_data" == true ]]; then
                    file_content+="$line"$'\n'
                fi
            done
            
            # Use a temporary file approach for multipart parsing
            local temp_file="/tmp/embossd_upload_$$"
            echo "$post_data" > "$temp_file"
            
            # Extract file content using sed (more reliable for binary data)
            # Find the boundary, skip headers, extract content until next boundary
            file_content=$(sed -n "/--${boundary}/,/--${boundary}/p" "$temp_file" | \
                          sed '1,/^$/d' | \
                          sed '$d' | \
                          head -n -1)
            
            rm -f "$temp_file"
            
            if [[ -n "$file_content" ]]; then
                echo "Extracted file content: ${#file_content} bytes" >&2
                print_text "$file_content"
                
                # Send response
                echo "HTTP/1.1 200 OK"
                echo "Content-Type: text/html"
                echo "Connection: close"
                echo ""
                echo "<html><body><h1>EmbossD v$VERSION</h1><p>File '$filename' queued for embossing!</p><a href='/'>Back</a></body></html>"
                return
            else
                echo "Failed to extract file content" >&2
            fi
        fi
        
        # Handle regular form data (text input)
        if [[ "$post_data" =~ text=([^&]*) ]]; then
            echo "Found form text field" >&2
            # URL decode the text
            local text="${BASH_REMATCH[1]}"
            text=$(echo "$text" | sed 's/+/ /g' | sed 's/%20/ /g' | sed 's/%0D%0A/\n/g')
            echo "Decoded text: '$text'" >&2
            print_text "$text"
            
            # Send response
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            echo "Connection: close"
            echo ""
            echo "<html><body><h1>EmbossD v$VERSION</h1><p>Text queued for embossing!</p><a href='/'>Back</a></body></html>"
            return
        else
            echo "POST data doesn't match expected form format" >&2
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
    
    echo "print_text called with: ${#text} bytes" >&2
    
    # Create lock file to prevent concurrent printing
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        echo "Another emboss job is in progress" >&2
        return 1
    fi
    
    echo "Lock acquired, starting emboss job" >&2
    
    # Print in background
    (
        echo "Writing to device $DEVICE: ${#text} bytes" >&2
        echo "$text" > "$DEVICE"
        if [[ $? -eq 0 ]]; then
            echo "Successfully wrote to device" >&2
        else
            echo "Error writing to device" >&2
        fi
        sleep 1  # Small delay to ensure write completes
        rmdir "$LOCK_FILE"
        echo "Emboss job completed, lock released" >&2
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
