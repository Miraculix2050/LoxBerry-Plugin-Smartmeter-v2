#!/bin/sh

# Runs as root before LoxBerry processes dpkg/apt dependencies.
# Configure the external Volkszaehler repository so LoxBerry can install
# vzlogger through the normal plugin package mechanism.

PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

for required in LBPCONFIG; do
	eval "value=\${$required:-}"
	if [ -z "$value" ]; then
		echo "<ERROR> Required LoxBerry V4 environment variable $required is missing."
		exit 2
	fi
done
if [ -z "$PTEMPPATH" ]; then
	echo "<ERROR> LoxBerry did not provide the full installation temporary path in argument 6."
	exit 2
fi

KEYRING="/usr/share/keyrings/volkszaehler-volkszaehler-org-project-archive-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/volkszaehler-volkszaehler-org-project.list"
REPO_BASE="https://dl.cloudsmith.io/public/volkszaehler/volkszaehler-org-project"
KEY_URL="$REPO_BASE/gpg.21DBDAC56DF44DA1.key"
MARKER_DIR="$LBPCONFIG/$PDIR"
MARKER_FILE="$MARKER_DIR/vzlogger.installed-by-plugin"
SOURCE_MARKER="$MARKER_DIR/vzlogger.repository-installed-by-plugin"
KEYRING_MARKER="$MARKER_DIR/vzlogger.keyring-installed-by-plugin"
PREUPGRADE_ACTIVE_FILE="$MARKER_DIR/vzlogger.preupgrade-service-active"

if [ "$(id -u)" != "0" ]; then
	echo "<ERROR> preroot.sh must run as root."
	exit 2
fi

LOCK_HELPER="$PTEMPPATH/sbin/smartmeter_config_lock.sh"
if [ ! -r "$LOCK_HELPER" ]; then
	echo "<ERROR> SmartMeter configuration lock helper is missing."
	exit 2
fi
. "$LOCK_HELPER"
smartmeter_acquire_config_lock "/var/run/shm/$PDIR" || exit 4

mkdir -p "$MARKER_DIR"
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet vzlogger.service; then
	touch "$PREUPGRADE_ACTIVE_FILE"
	echo "<INFO> Remembered active vzLogger service before upgrade."
else
	rm -f "$PREUPGRADE_ACTIVE_FILE"
fi

if dpkg-query -W -f='${Status}' vzlogger 2>/dev/null | grep -q "install ok installed"; then
	echo "<INFO> vzLogger is already installed. Keeping existing package ownership."
else
	touch "$MARKER_FILE"
	echo "<INFO> Marked vzLogger for plugin-managed installation."
fi

if id loxberry >/dev/null 2>&1; then
	chown -R loxberry.loxberry "$MARKER_DIR"
	chmod u+rwX,go+rX "$MARKER_DIR"
fi

if [ -r /etc/os-release ]; then
	. /etc/os-release
else
	ID="debian"
	VERSION_CODENAME=""
fi

CODENAME="${VERSION_CODENAME:-}"
if [ -z "$CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
	CODENAME="$(lsb_release -sc)"
fi
if [ -z "$CODENAME" ]; then
	echo "<ERROR> Could not determine Debian/Raspberry Pi OS codename."
	exit 3
fi

REPO_OS="debian"
case "${ID:-debian}" in
	raspbian)
		REPO_OS="raspbian"
		;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
	echo "<INFO> Installing apt helper packages for Volkszaehler repository setup"
	apt-get update
	apt-get install -y ca-certificates curl gnupg
fi

tmpkey="$(mktemp)"
trap 'rm -f "$tmpkey"' EXIT

echo "<INFO> Installing Volkszaehler repository key"
if [ ! -e "$KEYRING" ]; then
	touch "$KEYRING_MARKER"
fi
curl -fsSL "$KEY_URL" -o "$tmpkey"
gpg --dearmor < "$tmpkey" > "$KEYRING"
chmod 0644 "$KEYRING"

echo "<INFO> Configuring Volkszaehler apt repository for $REPO_OS $CODENAME"
if [ ! -e "$SOURCE_LIST" ]; then
	touch "$SOURCE_MARKER"
fi
cat > "$SOURCE_LIST" <<EOF
deb [signed-by=$KEYRING] $REPO_BASE/deb/$REPO_OS $CODENAME main
deb-src [signed-by=$KEYRING] $REPO_BASE/deb/$REPO_OS $CODENAME main
EOF

exit 0
