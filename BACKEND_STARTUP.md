# MindTwin Backend - Automatic Startup Guide

## How Backend Startup Works

The backend needs to run before testing the app because the Flutter app makes API calls to:
- `http://localhost:5000/health` - Health check
- `http://localhost:5000/api/*` - All endpoints

Without the backend running, the app cannot:
- Login (auth validation)
- Load patient/therapist data
- Submit wearable data
- Generate reports
- Trigger alerts

---

## Option 1: Automatic Startup (Recommended)

### When you open the VS Code project:

1. Open the project folder in VS Code
2. VS Code will automatically run the "Start MindTwin Backend" task
3. Backend will start on port 5000
4. Watch the Terminal panel for confirmation: `🚀 MindTwin Backend running on port 5000`

✅ **No manual steps needed!**

---

## Option 2: Manual Startup via VS Code Terminal

### Using the Tasks menu:

1. Press `Ctrl + Shift + B` (or go to Terminal → Run Task)
2. Select **"Start MindTwin Backend"**
3. Backend starts automatically

Or in the integrated terminal:
```powershell
cd C:\mindtwin\backend
node index.js
```

---

## Option 3: Quick Startup Scripts

### Windows Batch File (Double-click to run):
```bash
C:\mindtwin\start-backend.bat
```

### PowerShell Script:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
C:\mindtwin\start-backend.ps1
```

---

## Checking Backend Status

### In VS Code:
- Open Terminal → Problems panel
- Look for logs: `🚀 MindTwin Backend running on port 5000`

### In Browser:
```
http://localhost:5000/health
```
Should return:
```json
{
  "status": "ok",
  "timestamp": "2026-03-09T...",
  "environment": "development"
}
```

### In PowerShell:
```powershell
(Invoke-WebRequest -UseBasicParsing http://localhost:5000/health).Content
```

---

## Stopping Backend

### From VS Code:
1. Press `Ctrl + Shift + B` 
2. Select **"Stop Backend"**

### From Terminal:
```powershell
taskkill /IM node.exe /F
```

Or manually close the terminal window where backend is running.

---

## Troubleshooting

### Error: "Port 5000 already in use"
```
Kill existing process:
netstat -ano | findstr :5000    # Find PID
taskkill /PID <PID> /F          # Kill it
```

### Error: "Node.js not found"
Install Node.js: https://nodejs.org/

### Error: "Database initialization failed"
```powershell
# Delete old database and restart
Remove-Item C:\mindtwin\backend\mindtwin.db
node index.js
```

---

## Development Workflow

### When starting development:

1. **Open VS Code** → Backend starts automatically ✓
2. **Flutter runs automatically connect to backend** ✓
3. **Test the app:**
   - Web: `flutter run -d edge`
   - Mobile: Connect Android phone via USB
   - Windows: `flutter run -d windows`

### When testing on mobile:

1. Backend running locally ✓
2. Go to Therapist/Patient auth → Settings ⚙️
3. Click "Backend Configuration"
4. Enter your PC IP: `http://<YOUR_PC_IP>:5000`
5. Test connection → Save

(Find your PC IP: `ipconfig` → IPv4 Address)

---

## Environment Variables (Optional)

Create `.env` file in backend folder to override settings:

```
PORT=5000
NODE_ENV=development
DATABASE=./mindtwin.db
CORS_ORIGIN=http://localhost:3000,http://localhost:5000
```

---

**Questions?** Check the logs in VS Code Terminal or contact support.
