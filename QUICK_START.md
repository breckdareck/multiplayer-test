# Quick Reference: Multiplayer Configuration

## Problem Solved

Your friends can now create accounts and join your game even if they're not on your local network!

## What Changed

The game now supports configurable backend servers:
- **Development**: Local Docker (default)
- **Production**: Cloud server (DigitalOcean, AWS, etc.)

## How to Use

### For Single Player / Local Testing
Just play normally. Everything works the same.

### For Friends (Cloud Setup)

#### Step 1: Deploy Backend (5-10 minutes)
Follow [DEPLOYMENT.md](./DEPLOYMENT.md) to deploy to DigitalOcean or AWS.
Note your server IP address.

#### Step 2: Configure Game (All Players)
1. Start game and reach LoginScreen
2. Click "**Backend Settings**" button
3. Enter: `http://CLOUD_SERVER_IP:5000/api`
4. Click "**Apply**"
5. Restart game (optional, but recommended)

#### Step 3: Create Accounts (All Players)
1. Register new account at LoginScreen
2. Create a character
3. Now everyone's data is synced on the cloud server!

#### Step 4: Play Together
1. One player clicks "**Host**" to start the game server
2. Their IP address displays on screen
3. Other players enter that IP on CharacterSelectScreen to join
4. Play together! 🎮

---

## Architecture

```
Your PC (Game Client)
	↓
	└─→ [Game Server running on your PC] ← Friends connect here
	└─→ [Cloud Backend API] ← All players share accounts/characters
		 └─→ [Cloud PostgreSQL Database]
```

---

## Backend Settings Explained

| Setting | What It Does | Example |
|---------|-------------|---------|
| Backend API URL | Where accounts/characters are stored | `http://localhost:5000/api` (local) |
| | | `http://165.232.45.90:5000/api` (cloud) |
| Game Server Port | Port your game server listens on | `8080` (default) |

---

## File Locations

| File | Purpose |
|------|---------|
| `user://user_config.cfg` | Stores your backend API URL |
| `res://saves/player_*.json` | Local character saves (fallback) |
| `DEPLOYMENT.md` | How to deploy backend to cloud |
| `IMPLEMENTATION_SUMMARY.md` | Technical details |

---

## Environment Variables (Advanced)

You can set these to override config files:

```bash
# Override backend API URL for development
BACKEND_API_URL=http://api.yourgame.com:5000/api

# Example: Run game with env var
BACKEND_API_URL=http://cloud.example.com:5000/api godot
```

---

## Common Scenarios

### Scenario 1: Playing Alone
- No changes needed, use default settings
- Data stored locally on your PC

### Scenario 2: Playing with Friends on Same WiFi
1. Start game, Host starts server
2. Friends see your LAN IP on screen
3. Friends enter your LAN IP to join
4. Uses local backend (no internet needed)

### Scenario 3: Playing with Friends Remotely
1. Deploy backend to cloud (DigitalOcean, AWS)
2. All players configure: Backend Settings → Cloud Server URL
3. Anyone can host server on their PC
4. Friends enter host's external IP to join
5. Character data synced in cloud backend

### Scenario 4: Dedicated Server
1. Deploy both backend AND game server to cloud
2. Both share same server
3. Anyone can log in and play anytime
4. (More complex setup, not covered here)

---

## Troubleshooting

**Friends can't create accounts**
- Check Backend Settings API URL is correct
- Verify cloud server is running: `docker-compose ps`
- Check network connection

**Can't see friend's server IP**
- Friend must click "Host" first
- IP shows on their CharacterSelectScreen
- They need to share it with you

**Game freezes on login**
- Backend API might be slow, wait 10 seconds
- Check if API URL is correct
- Look at game logs for error messages

**Character data not saving**
- Check API connection (Backend Settings)
- Verify backend server is running
- Check local save file: `res://saves/player_USERNAME.json`

---

## Cost

| Scenario | Cost |
|----------|------|
| Local only (free) | $0/month |
| DigitalOcean cloud | $5/month |
| AWS EC2 | $0-15/month (free tier + small instance) |
| Self-hosted + internet | Electricity + ISP |

---

## Security Notes

- Passwords are hashed ✓
- Local saves are unencrypted ✓
- API URLs should use HTTPS in production (not implemented)
- Don't share database passwords

---

## For Developers

See [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md) for technical details on:
- Code changes made
- Configuration system
- How to extend it further

---

## Support

1. Check DEPLOYMENT.md for cloud setup issues
2. Check game logs for API errors
3. Test API manually: `curl http://BACKEND_IP:5000/api`
4. Access database UI: `http://BACKEND_IP:8080`
