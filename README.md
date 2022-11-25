# wordpress-environment-cloner
Script allowing to clone WordPress files and database from one environment to another.

Usage: `./cloner-novars.sh <source_environment> <destination_environment>`
Example: `./cloner-novars.sh prod dev1`

Pre-requisites:
- WordPress installation in source and destination environment.
- WP-CLI properly configured.
- SSH agent with SSH key loaded.
