# reload cache then have to fix permissions again

# to reload cache:
bin/console kimai:reload --env=prod

# to fix permissions execute the below inside /opt/kimai directory
chown -R :www-data .
chmod -R g+r .
chmod -R g+rw var/
