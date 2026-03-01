# Latest Updates: Enhanced Backend Selection

## What's New

The LoginScreen now has **easy preset switching** for backend servers, making it trivial to switch between local development, cloud production, and custom servers.

## New Features

### 1. Quick Preset Buttons
Click **Backend Settings** on the LoginScreen to reveal:
- **Local** - One-click switch to local Docker (127.0.0.1:5000)
- **Cloud** - One-click switch to your saved cloud server

### 2. Save Cloud Preset
When you enter a custom Cloud URL:
1. Type the URL in the input field
2. Click **Apply**
3. The URL is saved and becomes your "Cloud" preset button

Next time, just click **Cloud** to switch back!

### 3. Backend Display in CharacterSelectScreen
When you proceed from LoginScreen, you'll see:
```
Backend: http://127.0.0.1:5000/api
```
or
```
Backend: http://165.232.45.90:5000/api
```

This confirms you're using the correct backend before starting a game.

## How to Use

### For Development (Local Play)
1. LoginScreen → **Backend Settings**
2. Click **Local** (already configured)
3. Play normally!

### For Cloud Play (Friends)
1. LoginScreen → **Backend Settings**
2. Enter your cloud server: `http://your-ip:5000/api`
3. Click **Apply** (saves as Cloud preset)
4. Next time, just click **Cloud**!

### Switch Between Multiple Servers
1. **Backend Settings**
2. Choose: **Local** | **Cloud** | Enter new URL + **Apply**
3. Changes saved automatically to config

## Technical Changes

### LoginScreen Enhancements
- Added preset button dictionary system
- Cloud preset saved to `api_presets` on first custom URL
- Buttons organized in HBoxContainer for clean UI
- Status label confirms which preset was selected

### CharacterSelectScreen Improvements
- Displays current backend URL at top
- Helps verify you're on the correct server
- Useful for debugging connection issues

## File Updates
- `scripts/UI/LoginScreen.gd` - Preset system implementation
- `scripts/UI/CharacterSelectScreen.gd` - Backend display

## Configuration Persistence

All backend settings are saved to:
```
user://user_config.cfg
```

This means:
- Your preset choices are remembered
- Cloud URL is saved for next session
- Settings survive game restarts

## Example Workflows

### Workflow 1: Daily Local Testing
```
Day 1: LoginScreen → Local → Create/test character
Day 2: LoginScreen → Local → Continue playing
Day 3: LoginScreen → Local → Works!
```

### Workflow 2: Deploy to Cloud + Share with Friends
```
Step 1: Deploy backend to DigitalOcean ($5/month)
Step 2: Get the server IP (e.g., 165.232.45.90)
Step 3: LoginScreen → Backend Settings → Custom URL
        Enter: http://165.232.45.90:5000/api
Step 4: Click Apply (saves as Cloud preset)
Step 5: Share URL with friends via Discord
Step 6: Friends: LoginScreen → Backend Settings → Enter same URL
Step 7: Everyone plays together!
```

### Workflow 3: Testing Before Release
```
Local Testing:
  LoginScreen → Local → Test everything

Pre-Release:
  LoginScreen → Cloud → Test on production server

Post-Release:
  Players: LoginScreen → Cloud → Play together
```

## Benefits

✅ **No Code Changes** - Just click buttons to switch servers
✅ **Persistent Config** - Your choice is saved across sessions
✅ **Fast Switching** - One click to go Local ↔ Cloud
✅ **Clear Feedback** - CharacterSelectScreen shows which backend
✅ **Production Ready** - Easy for players to use, no technical knowledge needed

## For Cloud Deployment

See **DEPLOYMENT.md** for step-by-step cloud setup:
- DigitalOcean (recommended, $5/month)
- AWS EC2
- Self-hosted options

---

**Coming Soon:** Support for multiple saved cloud URLs (e.g., "Dev Server", "Test Server", "Live Server")
