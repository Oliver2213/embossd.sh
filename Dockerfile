FROM alpine:latest

# Install required packages
RUN apk add --no-cache bash netcat-openbsd

# Create app directory
WORKDIR /app

# Copy the script
COPY embossd.sh /app/embossd.sh
RUN chmod +x /app/embossd.sh

# Create data directory for user files
RUN mkdir -p /data

# Expose the default port
EXPOSE 9999

# Set default command
CMD ["/app/embossd.sh"]
