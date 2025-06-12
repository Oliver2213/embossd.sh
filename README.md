# EmbossD

A simple HTTP daemon for braille embossers, making it easier for blind users to print braille documents.

## Overview

EmbossD provides a web interface to send text and files directly to braille embossers via USB. It was created to make the Braille Blazer and similar embossers more accessible through a simple web form.

## Features

- Web interface on port 9999
- Text input for quick braille printing
- File upload support for .txt and .brf files
- Print queue management (prevents concurrent printing)
- Simple setup with minimal dependencies

## Usage

### Basic Usage

```bash
./embossd.sh
```

This starts the daemon on port 9999 using the default device `/dev/usb/lp0`.

### Command Line Options

```bash
# Custom device
./embossd.sh --device /dev/ttyUSB0

# Custom web port
./embossd.sh --web-port 8080

# Both custom device and port
./embossd.sh --device /dev/ttyUSB0 --web-port 8080

# Show version
./embossd.sh --version

# Show help
./embossd.sh --help
```

### Web Interface

Once running, open your browser to `http://localhost:9999` where you can:

1. **Print Text**: Type or paste text directly into the form and click Print
2. **Upload Files**: Choose a .txt or .brf file and click Upload & Print

### Command Line Usage with curl

You can also send text or files directly using curl:

```bash
# Send text directly
echo "Hello World" | curl -X POST --data-binary @- http://localhost:9999/

# Send a file
curl -X POST --data-binary @myfile.brf http://localhost:9999/

# Pipe text from another command
fortune | curl -X POST --data-binary @- http://localhost:9999/
```

**Status Codes:**
- `200 OK`: Text successfully queued for printing
- `503 Service Unavailable`: Printer is busy, try again later

## File Formats

**Best Results**: Upload pre-formatted BRF (Braille Ready Format) files for optimal braille output.

**ASCII Text**: The Braille Blazer and many similar embossers will automatically translate ASCII text into readable braille, so plain text files work well too.

## Requirements

- Bash shell
- `netcat` (nc command)
- USB braille embosser connected and recognized by the system
- Write permissions to the embosser device (usually `/dev/usb/lp0`)

## Device Setup

1. Connect your braille embosser via USB
2. Verify the device appears (usually as `/dev/usb/lp0`)
3. Ensure you have write permissions to the device
4. Test basic functionality: `echo "test" > /dev/usb/lp0`

## Troubleshooting

- **Permission denied**: Make sure your user has write access to the device file
- **Device not found**: Check USB connection and verify device path with `ls /dev/usb/`
- **Port in use**: Another service may be using port 9999

## Version

Current version: 0.1
