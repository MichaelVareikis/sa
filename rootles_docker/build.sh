#!/bin/bash
set -xe
[ -z $CI ] && [ `id -u` == 0 ] && { echo "Run as non root user"; exit 0; }
wget -O makeself.run 'https://github.com/megastep/makeself/releases/download/release-2.5.0/makeself-2.5.0.run'
bash makeself.run --target makeself
cd makeself

DEFAULT_CHANNEL_VALUE="stable"
if [ -z "$CHANNEL" ]; then
	CHANNEL=$DEFAULT_CHANNEL_VALUE
fi
STABLE_LATEST="24.0.4"
TEST_LATEST="24.0.4"
STATIC_RELEASE_URL=
STATIC_RELEASE_ROOTLESS_URL=
case "$CHANNEL" in
    "stable")
        echo "# Installing stable version ${STABLE_LATEST}"
        STATIC_RELEASE_URL="https://download.docker.com/linux/static/$CHANNEL/$(uname -m)/docker-${STABLE_LATEST}.tgz"
        STATIC_RELEASE_ROOTLESS_URL="https://download.docker.com/linux/static/$CHANNEL/$(uname -m)/docker-rootless-extras-${STABLE_LATEST}.tgz"
        ;;
    "test")
        echo "# Installing test version ${TEST_LATEST}"
        STATIC_RELEASE_URL="https://download.docker.com/linux/static/$CHANNEL/$(uname -m)/docker-${TEST_LATEST}.tgz"
        STATIC_RELEASE_ROOTLESS_URL="https://download.docker.com/linux/static/$CHANNEL/$(uname -m)/docker-rootless-extras-${TEST_LATEST}.tgz"
        ;;
    "nightly")
        echo "# Installing nightly"
        STATIC_RELEASE_URL="https://master.dockerproject.org/linux/$(uname -m)/docker.tgz"
        STATIC_RELEASE_ROOTLESS_URL="https://master.dockerproject.org/linux/$(uname -m)/docker-rootless-extras.tgz"
        ;;
    *)
        >&2 echo "Aborting because of unknown CHANNEL \"$CHANNEL\". Set \$CHANNEL to either \"stable\", \"test\", or \"nightly\"."; exit 1
        ;;
esac

mkdir -p docker_tmp

curl -L -o docker_tmp/docker.tgz "$STATIC_RELEASE_URL"
curl -L -o docker_tmp/rootless.tgz "$STATIC_RELEASE_ROOTLESS_URL"

cat << "MOF" > docker_tmp/docker_install.sh
#!/bin/sh
[ `id -u` == 0 ] && { echo "Run as non root user"; exit 0; }
set -e
SCRIPT_COMMIT_SHA=acabc63
while (($#)); do
    case $1 in
        --docker-bin | -p)
        shift
        tmp=$1
        DOCKER_BIN=${tmp%/}
        if [[ $DOCKER_BIN != /* ]]; then 
            error "Make sure you provide absolute path with --docker-bin"
            exit 1
        fi
        ;;
    esac
shift
done
[ -z $DOCKER_BIN ] && { echo "Provide --docker-bin /somepath"; exit; }
init_vars() {
	BIN="${DOCKER_BIN:-$HOME/bin}"

	DAEMON=dockerd
	SYSTEMD=
	if systemctl --user daemon-reload >/dev/null 2>&1; then
		SYSTEMD=1
	fi
}

checks() {
	# OS verification: Linux only, point osx/win to helpful locations
	case "$(uname)" in
	Linux)
		;;
	*)
		>&2 echo "Rootless Docker cannot be installed on $(uname)"; exit 1
		;;
	esac

	# User verification: deny running as root (unless forced?)
	if [ "$(id -u)" = "0" ] && [ -z "$FORCE_ROOTLESS_INSTALL" ]; then
		>&2 echo "Refusing to install rootless Docker as the root user"; exit 1
	fi

	# HOME verification
	if [ ! -d "$HOME" ]; then
		>&2 echo "Aborting because HOME directory $HOME does not exist"; exit 1
	fi

	if [ -d "$BIN" ]; then
		if [ ! -w "$BIN" ]; then
			>&2 echo "Aborting because $BIN is not writable"; exit 1
		fi
	else
		if [ ! -w "$HOME" ]; then
			>&2 echo "Aborting because HOME (\"$HOME\") is not writable"; exit 1
		fi
	fi

	# Existing rootful docker verification
	if [ -w /var/run/docker.sock ] && [ -z "$FORCE_ROOTLESS_INSTALL" ]; then
		>&2 echo "Aborting because rootful Docker is running and accessible. Set FORCE_ROOTLESS_INSTALL=1 to ignore."; exit 1
	fi

	# Validate XDG_RUNTIME_DIR
	if [ ! -w "$XDG_RUNTIME_DIR" ]; then
		if [ -n "$SYSTEMD" ]; then
			>&2 echo "Aborting because systemd was detected but XDG_RUNTIME_DIR (\"$XDG_RUNTIME_DIR\") does not exist or is not writable"
			>&2 echo "Hint: this could happen if you changed users with 'su' or 'sudo'. To work around this:"
			>&2 echo "- try again by first running with root privileges 'loginctl enable-linger <user>' where <user> is the unprivileged user and export XDG_RUNTIME_DIR to the value of RuntimePath as shown by 'loginctl show-user <user>'"
			>&2 echo "- or simply log back in as the desired unprivileged user (ssh works for remote machines)"
			exit 1
		fi
	fi

	# Already installed verification (unless force?). Only having docker cli binary previously shouldn't fail the build.
	if [ -x "$BIN/$DAEMON" ]; then
		# If rootless installation is detected print out the modified PATH and DOCKER_HOST that needs to be set.
		echo "# Existing rootless Docker detected at $BIN/$DAEMON"
		echo
		echo "# To reinstall or upgrade rootless Docker, run the following commands and then rerun the installation script:"
		echo "systemctl --user stop docker"
		echo "rm -f $BIN/$DAEMON"
		echo
		echo "# Alternatively, install the docker-ce-rootless-extras RPM/deb package for ease of package management (requires root)."
		echo "# See https://docs.docker.com/go/rootless/ for details."
		exit 0
	fi

	INSTRUCTIONS=

	# uidmap dependency check
	if ! command -v newuidmap >/dev/null 2>&1; then
		if command -v apt-get >/dev/null 2>&1; then
			INSTRUCTIONS="apt-get install -y uidmap"
		elif command -v dnf >/dev/null 2>&1; then
			INSTRUCTIONS="dnf install -y shadow-utils"
		elif command -v yum >/dev/null 2>&1; then
			INSTRUCTIONS="curl -o /etc/yum.repos.d/vbatts-shadow-utils-newxidmap-epel-7.repo https://copr.fedorainfracloud.org/coprs/vbatts/shadow-utils-newxidmap/repo/epel-7/vbatts-shadow-utils-newxidmap-epel-7.repo
yum install -y shadow-utils46-newxidmap"
		else
			echo "newuidmap binary not found. Please install with a package manager."
			exit 1
		fi
	fi

	# iptables dependency check
	if [ -z "$SKIP_IPTABLES" ] && ! command -v iptables >/dev/null 2>&1 && [ ! -f /sbin/iptables ] && [ ! -f /usr/sbin/iptables ]; then
		if command -v apt-get >/dev/null 2>&1; then
			INSTRUCTIONS="${INSTRUCTIONS}
apt-get install -y iptables"
		elif command -v dnf >/dev/null 2>&1; then
			INSTRUCTIONS="${INSTRUCTIONS}
dnf install -y iptables"
		else
			echo "iptables binary not found. Please install with a package manager."
			exit 1
		fi
	fi

	# ip_tables module dependency check
	if [ -z "$SKIP_IPTABLES" ] && ! lsmod | grep ip_tables >/dev/null 2>&1 && ! grep -q ip_tables "/lib/modules/$(uname -r)/modules.builtin"; then
			INSTRUCTIONS="${INSTRUCTIONS}
modprobe ip_tables"
	fi

	# debian requires setting unprivileged_userns_clone
	if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
		if [ "1" != "$(cat /proc/sys/kernel/unprivileged_userns_clone)" ]; then
			INSTRUCTIONS="${INSTRUCTIONS}
cat <<EOT > /etc/sysctl.d/50-rootless.conf
kernel.unprivileged_userns_clone = 1
EOT
sysctl --system"
		fi
	fi

	# centos requires setting max_user_namespaces
	if [ -f /proc/sys/user/max_user_namespaces ]; then
		if [ "0" = "$(cat /proc/sys/user/max_user_namespaces)" ]; then
			INSTRUCTIONS="${INSTRUCTIONS}
cat <<EOT > /etc/sysctl.d/51-rootless.conf
user.max_user_namespaces = 28633
EOT
sysctl --system"
		fi
	fi

	if [ -n "$INSTRUCTIONS" ]; then
		echo "# Missing system requirements. Please run following commands to
# install the requirements and run this installer again.
# Alternatively iptables checks can be disabled with SKIP_IPTABLES=1"

		echo
		echo "cat <<EOF | sudo sh -x"
		echo "$INSTRUCTIONS"
		echo "EOF"
		echo
		exit 1
	fi

	# validate subuid/subgid files for current user
	if ! grep "^$(id -un):\|^$(id -u):" /etc/subuid >/dev/null 2>&1; then
		>&2 echo "Could not find records for the current user $(id -un) from /etc/subuid . Please make sure valid subuid range is set there.
For example:
echo \"$(id -un):100000:65536\" >> /etc/subuid"
		exit 1
	fi
	if ! grep "^$(id -un):\|^$(id -u):" /etc/subgid >/dev/null 2>&1; then
		>&2 echo "Could not find records for the current user $(id -un) from /etc/subgid . Please make sure valid subuid range is set there.
For example:
echo \"$(id -un):100000:65536\" >> /etc/subgid"
		exit 1
	fi
}

exec_setuptool() {
	if [ -n "$FORCE_ROOTLESS_INSTALL" ]; then
		set -- "$@" --force
	fi
	if [ -n "$SKIP_IPTABLES" ]; then
		set -- "$@" --skip-iptables
	fi
	(
		set -x
		PATH="$BIN:$PATH" "$BIN/dockerd-rootless-setuptool.sh" install "$@"
	)
}

do_install() {
	echo "# Executing docker rootless install script, commit: $SCRIPT_COMMIT_SHA"

	init_vars
	checks

	# Extract under $HOME/bin/
	(
		mkdir -p "$BIN"
		mv *tgz $BIN
		cd "$BIN"
		tar zxf "docker.tgz" --strip-components=1
		tar zxf "rootless.tgz" --strip-components=1
	)

	exec_setuptool "$@"
}

do_install "$@"
loginctl enable-linger $USER
cat << EOF | tee -a ~/.bashrc
export PATH=${DOCKER_BIN}:$PATH 
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
EOF
cat << EOF 
#####################
# This environment variables appended to your ~/.bashrc, relogin or execute source ~/.bashrc to interract with docker
####################
EOF
[ -e /var/lib/systemd/linger/$USER ] && echo "linger enabled for user $USER" || echo "WARNING: Linger wasn't enabled for user $USER"
MOF

bash makeself.sh --notemp docker_tmp/ docker_rootless_offline.sh "" bash ./docker_install.sh
cd -
mv makeself/docker_rootless_offline.sh .
rm -rf makeself*
