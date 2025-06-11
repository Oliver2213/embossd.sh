#!/bin/bash

# EmbossD - A simple HTTP daemon for braille embossers

VERSION="0.1"
AUTHORS="Blake Oliver"
SOURCE_URL=""
DEVICE="/dev/usb/lp0"
PORT=9999
LOCK_FILE="/tmp/embossd.lock"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --device)
            DEVICE="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--device /dev/path]"
            exit 1
            ;;
    esac
done

# Check if device exists
if [[ ! -w "$DEVICE" ]]; then
    echo "Error: Cannot write to device $DEVICE"
    exit 1
fi

echo "Starting EmbossD v$VERSION by $AUTHORS on port $PORT, device: $DEVICE"

# Generate HTML page
generate_html() {
    local status_msg=""
    if [[ -f "$LOCK_FILE" ]]; then
        status_msg="<div style='color: red; font-weight: bold;'>Currently printing... Please wait.</div>"
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
    </style>
</head>
<body>
    <div class='container'>
        <h1>EmbossD v$VERSION</h1>
        <p><em>by $AUTHORS</em></p>
        $status_msg
        
        <h2>Print Text</h2>
        <p><strong>Instructions:</strong> Type or paste your text in the field below, then click Print to send it to your braille embosser.</p>
        <form method='post' action='/print'>
            <input type='text' name='text' placeholder='Enter text to print' required>
            <button type='submit' $disabled>Print</button>
        </form>
        
        <h2>Upload File</h2>
        <p><strong>Instructions:</strong> Choose a .txt or .brf file from your computer, then click Upload & Print to send its contents to your braille embosser.</p>
        <form method='post' action='/upload' enctype='multipart/form-data'>
            <input type='file' name='file' accept='.txt,.brf' required>
            <button type='submit' $disabled>Upload & Print</button>
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
            echo "Text queued for printing"
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
            echo "<html><body><h1>EmbossD v$VERSION</h1><p>Text queued for printing!</p><a href='/'>Back</a></body></html>"
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
        echo "Another print job is in progress"
        return 1
    fi
    
    # Print in background
    (
        echo "Printing: $text"
        echo "$text" > "$DEVICE"
        sleep 1  # Small delay to ensure write completes
        rmdir "$LOCK_FILE"
        echo "Print job completed"
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
    {
        echo "HTTP/1.1 200 OK"
        echo "Content-Type: text/html"
        echo "Connection: close"
        echo ""
        generate_html
    } | nc -l -p "$PORT" -q 1
done
