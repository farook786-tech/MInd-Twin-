#!/bin/bash
# MindTwin Backend Quick Start Script for Linux/macOS

echo "🚀 MindTwin Backend Quick Start"
echo "================================"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js 14+ first."
    exit 1
fi

echo "✅ Node.js version: $(node --version)"

# Navigate to backend directory
if [ ! -d "mindtwin-backend" ]; then
    echo "❌ mindtwin-backend directory not found!"
    exit 1
fi

cd mindtwin-backend

# Install dependencies
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install dependencies"
        exit 1
    fi
fi

# Create .env if it doesn't exist
if [ ! -f ".env" ]; then
    echo "⚙️  Creating .env file..."
    cp .env.example .env
    echo "⚠️  Please edit .env with your configuration"
fi

# Run migrations
echo "🔧 Running database migrations..."
npm run migrate
if [ $? -ne 0 ]; then
    echo "❌ Migration failed"
    exit 1
fi

# Start server
echo ""
echo "✅ Setup complete! Starting backend server..."
echo "📍 Server: http://localhost:5000"
echo "🏥 Health check: curl http://localhost:5000/health"
echo ""

npm run dev
