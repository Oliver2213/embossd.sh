# EmbossD

An emboss-over-network webserver, written in shell.

## Overview

EmbossD provides a web interface to send text and files directly to braille embossers via USB. It was vibe-coded in an afternoon to make the Braille Blazer and similar embossers more accessible through a simple web form, rather than through the cli, which doesn't work for everyone or well on mobile.  
Set this up, bookmark the address or send it to others on the network and emboss anything you need.

## Features

- Web interface on port 9999 by default
- Text input for quick braille printing
- File upload support for .txt and .brf files
- (dumb) print queue management (prevents concurrent printing)
- Simple setup with minimal dependencies
- Dockerfile, locally buildable image; run and label it for your favorite dashboard or homepage

## Usage

### Basic Usage

```bash
./embossd.sh
```

This starts the daemon on port 9999 using the default device `/dev/usb/lp0`.

### Configuration with .env file

You can create a `.env` file in the same directory to set default values:

```bash
# Example .env file
DEVICE=/dev/ttyUSB0
PORT=8080
EMBOSSER_MODEL=Braille Blazer
PAPER_SIZE=8.5x11
SHOW_INSTRUCTIONS=0
CONTENT_FILE=welcome.html
```

Then simply run:
```bash
./embossd.sh
```

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

1. **Emboss Text**: Type or paste text directly into the form and click Emboss
2. **Upload Files**: Choose a .txt or .brf file and click Upload & Emboss

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
- `200 OK`: Text successfully queued for embossing
- `503 Service Unavailable`: Embosser is busy, try again later

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

## Systemd Service Installation

To run EmbossD as a system service:

### 1. Install EmbossD

```bash
# Create system user
sudo useradd -r -s /bin/false embossd

# Create installation directory
sudo mkdir -p /opt/embossd

# Copy files
sudo cp embossd.sh /opt/embossd/
sudo cp embossd.service /etc/systemd/system/

# Set permissions
sudo chown -R embossd:embossd /opt/embossd
sudo chmod +x /opt/embossd/embossd.sh

# Add embossd user to dialout group for device access
sudo usermod -a -G dialout embossd
```

### 2. Configure the Service

Edit the service file to customize your device and settings:

```bash
sudo systemctl edit embossd
```

Add your configuration:

```ini
[Service]
Environment=DEVICE=/dev/ttyUSB0
Environment=EMBOSSER_MODEL=Braille Blazer
Environment=PAPER_SIZE=8.5x11
Environment=SHOW_INSTRUCTIONS=0
```

### 3. Start the Service

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable and start the service
sudo systemctl enable embossd
sudo systemctl start embossd

# Check status
sudo systemctl status embossd

# View logs
sudo journalctl -u embossd -f
```

### 4. Service Management

```bash
# Stop the service
sudo systemctl stop embossd

# Restart the service
sudo systemctl restart embossd

# Disable the service
sudo systemctl disable embossd
```

## Troubleshooting

- **Permission denied**: Make sure your user has write access to the device file
- **Device not found**: Check USB connection and verify device path with `ls /dev/usb/`
- **Port in use**: Another service may be using port 9999
- **Service fails to start**: Check logs with `sudo journalctl -u embossd -n 50`
- **Device access denied**: Ensure the embossd user is in the dialout group and has device permissions

## Docker Usage

### Quick Start with Docker

```bash
# Build the image
docker build -t embossd .

# Run with default settings
docker run -p 9999:9999 --device=/dev/usb/lp0 embossd

# Run with custom configuration
docker run -p 8080:8080 --device=/dev/ttyUSB0 \
  -e PORT=8080 \
  -e DEVICE=/dev/ttyUSB0 \
  -e EMBOSSER_MODEL="Braille Blazer" \
  -e PAPER_SIZE="8.5x11" \
  embossd
```

### Docker Compose

Create a `data/` directory for your configuration:

```bash
mkdir data
```

Put your `.env` file and any HTML content files in the `data/` directory:

```bash
# data/.env
DEVICE=/dev/usb/lp0
PORT=9999
EMBOSSER_MODEL=Braille Blazer
PAPER_SIZE=8.5x11
SHOW_INSTRUCTIONS=0
CONTENT_FILE=welcome.html
```

```bash
# data/welcome.html
<h2>Welcome to Our Braille Service</h2>
<p>This embosser is available for community use.</p>
```

Then run with docker-compose:

```bash
docker-compose up -d
```

The container will automatically use configuration from `data/.env` and serve content files from the `data/` directory.

### Docker Environment Variables

All configuration variables can be set via Docker environment variables:

- `DEVICE` - Embosser device path (default: `/dev/usb/lp0`)
- `PORT` - Web server port (default: `9999`)
- `EMBOSSER_MODEL` - Display embosser model in instructions
- `PAPER_SIZE` - Display paper size in instructions  
- `SHOW_INSTRUCTIONS` - Show/hide instructions (default: `1`)
- `CONTENT_FILE` - HTML file to display above forms

## Changelog
### Version 0.1
**Current release**
