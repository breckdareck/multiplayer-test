# API Endpoint Management Guide

## Overview

The game now provides easy switching between different backend servers from the LoginScreen, making it simple to switch between local development, cloud backends, and custom servers.

## Quick Switching

### From LoginScreen

1. **Click "Backend Settings"** to expand the settings panel
2. **Use Quick Select buttons:**
   - **Local**: Switches to `http://127.0.0.1:5000/api` (local Docker)
   - **Cloud**: Switches to your configured cloud server
3. **Or enter a custom URL:**
   - Type your server URL in the input field
   - Click **Apply**
4. Settings collapse automatically after applying

### Preset Buttons

The "Local" preset is always available. The "Cloud" preset is configured the first time you enter a custom URL.

## Workflow: Local → Cloud Testing

### Step 1: Set Cloud URL (First Time)
1. On LoginScreen, click **Backend Settings**
2. Enter your cloud server URL: `http://your-server-ip:5000/api`
3. Click **Apply**
4. Now "Cloud" preset is saved for future use

### Step 2: Quick Switch Between Backends
- **To Local:** Backend Settings → Cloud → **Local**
- **To Cloud:** Backend Settings → Local → **Cloud**

This persists to your config file, so the choice is remembered next session.

## Auto-Display: Backend in CharacterSelectScreen

When you advance to CharacterSelectScreen, you'll see a cyan label showing which backend you're using:

```
Backend: http://127.0.0.1:5000/api      (Local)
Backend: http://165.232.45.90:5000/api  (Cloud)
```

This helps verify you're connecting to the right server before starting a game.

## Configuration Scenarios

### Scenario 1: Solo Development
```
LoginScreen → Local (default)
             ↓
    Backend: http://127.0.0.1:5000/api
             ↓
CharacterSelectScreen → [Shows: Backend: http://127.0.0.1:5000/api]
             ↓
    All data stored locally on your PC
```

### Scenario 2: Local Multiplayer (Friends on Same WiFi)
```
All players → LoginScreen → Local
             ↓
    Backend: http://127.0.0.1:5000/api (shared database)
             ↓
CharacterSelectScreen → Host chooses "Host"
             ↓
    Friends see host IP and join
    (Only works if all on same WiFi connecting to same PC's Docker!)
```

### Scenario 3: Cloud Multiplayer (Friends Anywhere)
```
Step 1: Set Cloud URL
LoginScreen → Backend Settings → Enter: http://cloud-ip:5000/api → Apply

Step 2: All players use Cloud
Player 1 → LoginScreen → Cloud
Player 2 → LoginScreen → Cloud  
Player 3 → LoginScreen → Cloud
             ↓
    All connect to same cloud backend
             ↓
CharacterSelectScreen → Anyone can Host
             ↓
    Others connect via host's external IP
    (Game server runs on someone's PC, backend data shared in cloud)
```

## Files Modified

- `scripts/UI/LoginScreen.gd` - Added preset buttons and quick switching
- `scripts/UI/CharacterSelectScreen.gd` - Display current backend

## Backend Settings Details

| Feature | Purpose |
|---------|---------|
| **Quick Select: Local** | Fast switch to local Docker backend |
| **Quick Select: Cloud** | Fast switch to your saved cloud URL |
| **Custom URL Input** | Enter any backend server address |
| **Status Label** | Shows current API URL |
| **Apply Button** | Save custom URL and update connection |

## Environment Variable Override

For advanced usage, you can override via environment variable (takes precedence over UI):

```bash
BACKEND_API_URL=http://custom-server:5000/api godot
```

This is useful for CI/CD, testing, or deployment scripts.

## Common Questions

**Q: How do I switch back to Local?**
A: LoginScreen → Backend Settings → Click "Local" button

**Q: Does changing the backend affect character data?**
A: Yes! Different backends have separate databases. Changing backends shows different character lists.

**Q: Can I have characters on both Local and Cloud?**
A: Yes, they're separate. Use the Backend Settings to switch and create/manage characters on each.

**Q: What if the Cloud server is down?**
A: The game will show connection errors. Switch back to Local via Backend Settings.

**Q: Do my friends need to use the same backend?**
A: Yes, for account/character sharing. But the game server can run on any player's PC and others join via that player's IP.

## Troubleshooting

**Can't see Cloud preset button**
- You haven't configured a cloud URL yet
- Enter one in the Custom URL field and click Apply first

**Backend Settings panel won't expand**
- The button may not be visible on screen
- Try scrolling in the LoginScreen or resize the window

**Getting "Connection refused" errors**
- Check the backend URL in the status label
- Verify the server is running: `docker-compose ps`
- Try switching to Local to test local backend

**Character list is empty**
- Verify the correct backend is selected (check status label)
- You may not have created characters on this backend yet
- Try creating a new character

## Production Tips

### For Hosting a Game Server
1. Deploy backend to cloud (once per group, not per player)
2. All players configure: LoginScreen → Backend Settings → Cloud → [same URL]
3. Each player can then Host a game server on their PC
4. Other players join that specific player's PC, but share character data in cloud

### For Maximum Availability
1. Deploy backend to DigitalOcean/AWS
2. Set Cloud preset in LoginScreen
3. Share the Cloud URL in your group Discord
4. Anyone can host anytime, data is always synced

### Backup Strategy
- Regularly backup your cloud database
- See DEPLOYMENT.md for backup instructions
- Or enable automated backups on your cloud provider

---

For backend deployment instructions, see: **DEPLOYMENT.md**
For quick reference, see: **QUICK_START.md**
