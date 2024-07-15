#!/bin/sh


# Function to handle SIGTERM
handle_sigterm() {
    echo "handle_sigterm:init: Logging all processes running in the container..."
    ps aux
    echo "SIGTERM received, sending SIGTERM to Node.js process..."
    export SIGTERM_RECEIVED=true # Set environment variable
    echo "Waiting for 15 seconds before completing shutdown..."
    sleep 15 # Delay in seconds
    
    echo "Killing Node.js process..."
    kill -15 "$PID" # Send SIGTERM to the Node.js process
    
    
    echo "handle_sigterm:exit: Logging all processes running in the container..."
    ps aux
}

# Run cleanup script before running migrations
# Check if DATABASE_URL is not set
if [ -z "$DATABASE_URL" ]; then
    # Check if all required variables are provided
    if [ -n "$DATABASE_HOST" ] && [ -n "$DATABASE_USERNAME" ] && [ -n "$DATABASE_PASSWORD" ]  && [ -n "$DATABASE_NAME" ]; then
        # Construct DATABASE_URL from the provided variables
        DATABASE_URL="postgresql://${DATABASE_USERNAME}:${DATABASE_PASSWORD}@${DATABASE_HOST}/${DATABASE_NAME}"
        export DATABASE_URL
    else
        echo "Error: Required database environment variables are not set. Provide a postgres url for DATABASE_URL."
        exit 1
    fi
fi

# Set DIRECT_URL to the value of DATABASE_URL if it is not set, required for migrations
if [ -z "$DIRECT_URL" ]; then
    export DIRECT_URL=$DATABASE_URL
fi

# Always execute the scripts, except when disabled.
if [ "$LANGFUSE_AUTO_POSTGRES_MIGRATION_DISABLED" != "true" ]; then
    prisma db execute --url "$DIRECT_URL" --file "./packages/shared/scripts/cleanup.sql"

    # Apply migrations
    prisma migrate deploy --schema=./packages/shared/prisma/schema.prisma
fi
status=$?

# If migration fails (returns non-zero exit status), exit script with that status
if [ $status -ne 0 ]; then
    echo "Applying database migrations failed. This is mostly caused by the database being unavailable."
    echo "Exiting..."
    exit $status
fi

# Start the Node.js application
node web/server.js &

# Save the PID of the Node.js process
PID=$!

# Trap SIGTERM signals
trap 'handle_sigterm' SIGTERM

# Wait for the Node.js process to exit
wait $PID