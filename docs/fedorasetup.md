# fedorasetup.sh

[Back to script index](../README.md) · [Script source](../fedorasetup.sh)

Provisions a Fedora machine: installs Docker CE, schedules a weekly Docker image prune, installs XCP-ng guest utilities, neofetch, nano, and mailx, configures ssmtp as a mail relay, and spins up Portainer and Watchtower.

```bash
wget -O - https://raw.githubusercontent.com/ajpri/linux-scripts/main/fedorasetup.sh | bash
```
