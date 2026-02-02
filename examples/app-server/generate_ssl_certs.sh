
# Setup a domain + server first.
# Then run this script.
sudo apt update && sudo apt install -y certbot

sudo certbot certonly --standalone -d api.l2restaking.info --agree-tos --non-interactive

# Successfully received certificate.
# Certificate is saved at: /etc/letsencrypt/live/api.l2restaking.info/fullchain.pem
# Key is saved at:         /etc/letsencrypt/live/api.l2restaking.info/privkey.pem