#!/bin/bash

# EmbossD - A simple HTTP daemon for braille embossers

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

echo "Starting EmbossD on port $PORT, device: $DEVICE"

# Simple HTTP server using netcat
serve_http() {
    local request_line
    local content_length=0
    local boundary=""
    local is_post=false
    
    # Read HTTP request
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        
        if [[ -z "$line" ]]; then
            break
        fi
        
        if [[ "$line" =~ ^POST ]]; then
            is_post=true
        elif [[ "$line" =~ ^Content-Length:\ ([0-9]+) ]]; then
            content_length=${BASH_REMATCH[1]}
        elif [[ "$line" =~ ^Content-Type:.*boundary=([^;]+) ]]; then
            boundary=${BASH_REMATCH[1]}
        fi
    done
    
    # Generate HTML response
    local status_msg=""
    if [[ -f "$LOCK_FILE" ]]; then
        status_msg="<div style='color: red; font-weight: bold;'>Currently printing... Please wait.</div>"
    fi
    
    local disabled=""
    if [[ -f "$LOCK_FILE" ]]; then
        disabled="disabled"
    fi
    
    local html="<!DOCTYPE html>
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
        <h1>EmbossD</h1>
        $status_msg
        
        <h2>Print Text</h2>
        <form method='post' action='/print'>
            <input type='text' name='text' placeholder='Enter text to print' required>
            <button type='submit' $disabled>Print</button>
        </form>
        
        <h2>Upload File</h2>
        <form method='post' action='/upload' enctype='multipart/form-data'>
            <input type='file' name='file' accept='.txt,.brf' required>
            <button type='submit' $disabled>Upload & Print</button>
        </form>
    </div>
</body>
</html>"
    
    # Handle POST requests
    if [[ "$is_post" == true && "$content_length" -gt 0 ]]; then
        local post_data
        post_data=$(head -c "$content_length")
        
        if [[ "$post_data" =~ text=([^&]*) ]]; then
            # URL decode the text
            local text="${BASH_REMATCH[1]}"
            text=$(echo "$text" | sed 's/+/ /g' | sed 's/%20/ /g')
            print_text "$text"
            html="<html><body><h1>EmbossD</h1><p>Text queued for printing!</p><a href='/'>Back</a></body></html>"
        elif [[ "$post_data" =~ filename=\"([^\"]+)\" ]]; then
            # Extract file content (simplified - real multipart parsing is complex)
            local filename="${BASH_REMATCH[1]}"
            # This is a simplified approach - in practice, multipart parsing is more complex
            local file_content=$(echo "$post_data" | sed -n '/^$/,$p' | tail -n +2)
            print_text "$file_content"
            html="<html><body><h1>EmbossD</h1><p>File '$filename' queued for printing!</p><a href='/'>Back</a></body></html>"
        fi
    fi
    
    # Send HTTP response
    echo "HTTP/1.1 200 OK"
    echo "Content-Type: text/html"
    echo "Content-Length: ${#html}"
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
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start the server
while true; do
    serve_http | nc -l -p "$PORT" -q 1
done
