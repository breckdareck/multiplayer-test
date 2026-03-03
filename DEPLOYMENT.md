# Backend Deployment Guide

This guide explains how to deploy the Flask backend to a cloud provider so that external players can create accounts and access game services.

## Overview

The game currently has two deployment modes:

### Development (Local)
- Run on your PC with Docker
- Only accessible locally (127.0.0.1:5000)
- Perfect for testing and development
- **Default configuration**

### Production (Cloud)
- Deploy to a cloud provider
- Accessible from anywhere on the internet
- Players can create accounts and persist character data
- Recommended for multiplayer play with friends

---

## Option 1: DigitalOcean (Recommended for Beginners)

DigitalOcean is affordable ($4-5/month for a small app) and straightforward to set up.

### Prerequisites
- DigitalOcean account (sign up at https://www.digitalocean.com)
- Docker installed on your local machine
- Git installed

### Step 1: Create a Droplet

1. Log in to DigitalOcean and click **Create** → **Droplets**
2. Choose:
   - **Region**: Closest to your location
   - **OS**: Ubuntu 22.04 LTS
   - **Size**: Basic ($5/month is sufficient)
   - **Authentication**: SSH Key (recommended) or Password
3. Click **Create Droplet**
4. Wait for it to spin up (2-3 minutes), then note the IP address

### Step 2: Set Up Docker on the Droplet

SSH into your droplet:
```bash
ssh root@YOUR_DROPLET_IP
```

Install Docker and Docker Compose:
```bash
apt-get update
apt-get install -y docker.io docker-compose git

# Start Docker
systemctl start docker
systemctl enable docker
```

### Step 3: Deploy the Backend

Clone your project:
```bash
cd /opt
git clone https://github.com/YOUR_USERNAME/multiplayer-test.git
cd multiplayer-test
```

Start the containers:
```bash
docker-compose up -d
```

Verify it's running:
```bash
docker-compose ps
```

You should see all three containers (db, api, adminer) running.

### Step 4: Update Your Game Client

In the Godot game:

1. Open **LoginScreen**
2. Click **Backend Settings**
3. Enter the API URL: `http://YOUR_DROPLET_IP:5000/api`
4. Click **Apply**

Now all players can connect to your backend!

### Step 5: Database Backups (Important!)

Create a backup script on your droplet:

```bash
# Create /opt/backup_db.sh
cat > /opt/backup_db.sh << 'EOF'
#!/bin/bash
docker exec multiplayer-test-db-1 pg_dump -U postgres gamedb | gzip > /opt/backups/gamedb_$(date +%Y%m%d_%H%M%S).sql.gz
echo "Database backed up"
EOF

chmod +x /opt/backup_db.sh
```

Set up automated backups (cron):
```bash
crontab -e
```

Add this line (backup daily at 2 AM):
```
0 2 * * * /opt/backup_db.sh
```

### Stop/Restart Services

```bash
# Stop all containers
docker-compose down

# Restart all containers
docker-compose up -d

# View logs
docker-compose logs api

# Stop and keep data
docker-compose stop

# Remove containers but keep volumes (data)
docker-compose down
```

---

## Option 2: Heroku (Easiest for Node.js, Not Recommended for Python)

Heroku is shutting down free tiers. Not recommended for this project.

---

## Option 3: AWS EC2

AWS is powerful but more complex. Only recommended if you're familiar with AWS.

### Quick Setup:
1. Launch an EC2 instance (Ubuntu 22.04 LTS, t3.micro or t3.small)
2. Open port 5000 in security group
3. SSH in and follow the Docker setup steps from DigitalOcean above
4. Use your Elastic IP or custom domain

---

## Option 4: Self-Hosted on Your PC (NAT Forwarding)

If you want to keep hosting on your PC but make it accessible to friends over the internet:

### Prerequisites
- Static public IP or dynamic DNS service
- Port forwarding enabled on your router
- Your PC running 24/7

### Step 1: Configure Port Forwarding

1. Log into your router (usually 192.168.1.1)
2. Find **Port Forwarding** settings
3. Forward external port 5000 → internal port 5000 (your PC's local IP)
4. Save and apply

### Step 2: Get Your Public IP

```bash
curl https://api.ipify.org
```

Or use a dynamic DNS service if your IP changes frequently.

### Step 3: Update Game Client

Enter your public IP: `http://YOUR_PUBLIC_IP:5000/api`

### Risks:
- Your PC must stay on 24/7
- Your public IP may change (use dynamic DNS)
- Limited by your home internet speed
- Not recommended for production

---

## Managing the Backend on Cloud

### Access the Database UI (Adminer)

Navigate to: `http://YOUR_SERVER_IP:8080`

Login with:
- **System**: PostgreSQL
- **Server**: db
- **Username**: postgres
- **Password**: password
- **Database**: gamedb

### View API Logs

```bash
docker-compose logs -f api
```

### Restart Services

```bash
docker-compose restart api
```

### Update Backend Code

If you modify `backend/app.py`:

```bash
# Stop the old container
docker-compose down

# Rebuild with new code
docker-compose up -d --build

# Verify it's running
docker-compose ps
```

---

## Troubleshooting

### "Connection refused" from game
- Check if the server is running: `docker-compose ps`
- Check if the API URL is correct in your game
- Verify port 5000 is open: `netstat -tlnp | grep 5000`

### Database connection errors
- Check if PostgreSQL container is running: `docker-compose logs db`
- Verify DATABASE_URL in docker-compose.yml

### "Failed to parse server response"
- Check API logs: `docker-compose logs api`
- Verify account creation worked with Adminer

### SSL/HTTPS Issues
- For production, use a reverse proxy like Nginx with Let's Encrypt
- For testing, stick with HTTP

---

## Updating Default API URL in Game

After deploying to cloud, you can set the default API URL in code:

**Option A: Update config file (temporary)**
1. On first login, click **Backend Settings**
2. Enter cloud server URL
3. Click Apply

**Option B: Update code (permanent for all users)**

Edit `scripts/Managers/user_config.gd`:
```gdscript
const DEFAULT_API_URL = "http://YOUR_CLOUD_SERVER_IP:5000/api"
```

Or set environment variable on game startup:
```bash
BACKEND_API_URL=http://YOUR_CLOUD_SERVER_IP:5000/api godot
```

---

## Security Considerations

### Passwords
- Already hashed with werkzeug (good!)
- Consider adding password requirements

### API Keys
- Currently no authentication on API endpoints
- For production, add token-based authentication (JWT)
- Implement rate limiting

### Database
- Change default PostgreSQL password from "password"
- Use environment variables for credentials (already supported)

### Network
- Consider using HTTPS (requires SSL certificate)
- Restrict database access to only necessary ports
- Keep system updated

---

## Cost Estimates

| Provider | Size | Monthly Cost | Notes |
|----------|------|--------------|-------|
| DigitalOcean | $5 Droplet | $5 | Recommended for small groups |
| DigitalOcean | $12 Droplet | $12 | Better for high player counts |
| AWS EC2 | t3.micro | Free (12 months) | Limited resources |
| AWS EC2 | t3.small | $8-15 | Production-grade |
| Linode | $5 Nanode | $5 | Alternative to DigitalOcean |

---

## Next Steps

1. Choose a provider and deploy
2. Test account creation from multiple locations
3. Verify character data persists
4. Share the API URL with your friends
5. Set up automated backups
6. Monitor performance and costs

For questions or issues, check the API logs and Adminer database UI!
