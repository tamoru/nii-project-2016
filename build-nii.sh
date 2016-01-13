#!/bin/bash

reportfailed()		      
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}

[ "$1" != "" ] && fullpath="$(readlink -f $1)"

export ORGCODEDIR="$(cd "$(dirname $(readlink -f "$0"))" && pwd -P)" || reportfailed

if [ "$DATADIR" = "" ]; then
    # Default to putting output in the code directory, which means
    # a separate clone of the repository for each build
    DATADIR="$ORGCODEDIR"
fi
source "$ORGCODEDIR/simple-defaults-for-bashsteps.source"

# avoids errors on first run, but maybe not good to change state
# outside of a step
touch "$DATADIR/datadir.conf"

source "$DATADIR/datadir.conf"
: ${imagesource:=$fullpath}

DATADIR="$DATADIR" "$ORGCODEDIR/ind-steps/build-1box/build-1box.sh"

(
    $starting_group "Set up install GO in VM"
    (
	$starting_group "Set up vmdir"
	(
	    $starting_step "Make vmdir"
	    [ -d "$DATADIR/vmdir" ]
	    $skip_step_if_already_done ; set -e
	    mkdir "$DATADIR/vmdir"
	) ; prev_cmd_failed
	
	DATADIR="$DATADIR/vmdir" \
	       "$ORGCODEDIR/ind-steps/kvmsteps/kvm-setup.sh" \
	       "$DATADIR/vmapp-vdc-1box/1box-openvz.netfilter.x86_64.raw.tar.gz"
    )

    (
	$starting_group "Install GO language in the OpenVZ 1box image"
	[ -f "$DATADIR/vmdir/1box-openvz-w-go.raw.tar.gz" ]
	$skip_group_if_unnecessary

	# TODO: this guard is awkward.
	[ -x "$DATADIR/vmdir/kvm-boot.sh" ] && \
	    "$DATADIR/vmdir/kvm-boot.sh"

	(
	    $starting_step "Do yum install golang"
	    [ -x "$DATADIR/vmdir/ssh-to-kvm.sh" ] && {
		[ -f "$DATADIR/vmdir/1box-openvz-w-go.raw.tar.gz" ] || \
		    [ "$("$DATADIR/vmdir/ssh-to-kvm.sh" which go )" = "/usr/bin/go" ]
		}
	    $skip_step_if_already_done ; set -e
	    # Following this simple blog post: http://itekblog.com/centos-golang/
	    # Note: the vmbuilder scripts already install EPEL repository
	    "$DATADIR/vmdir/ssh-to-kvm.sh" sudo yum -y install go
	) ; prev_cmd_failed
	
	# TODO: this guard is awkward.
	[ -x "$DATADIR/vmdir/kvm-shutdown-via-ssh.sh" ] && \
	    "$DATADIR/vmdir/kvm-shutdown-via-ssh.sh"
    )

    (
	$starting_step "Make snapshot of image with GO installed"
	[ -f "$DATADIR/vmdir/1box-openvz-w-go.raw.tar.gz" ]
	$skip_step_if_already_done ; set -e
	cd "$DATADIR/vmdir/"
	tar czSvf 1box-openvz-w-go.raw.tar.gz 1box-openvz.netfilter.x86_64.raw
    ) ; prev_cmd_failed
)

(
    $starting_step "Expand fresh image from snapshot of image with GO installed"
    [ -f "$DATADIR/vmdir/1box-openvz.netfilter.x86_64.raw" ]
    $skip_step_if_already_done ; set -e
    cd "$DATADIR/vmdir/"
    tar xzSvf 1box-openvz-w-go.raw.tar.gz
) ; prev_cmd_failed

# TODO: this guard is awkward.
[ -x "$DATADIR/vmdir/kvm-boot.sh" ] && \
    "$DATADIR/vmdir/kvm-boot.sh"

# /home/centos/go/src/github.com/axsh/wakame-vdc/client/terraform-provider-wakamevdc/wakamevdc

(
    $starting_step "Initial go dir with wakame-vdc cloned"
    [ -f "$DATADIR/vmdir/1box-openvz-w-go.raw.tar.gz" ] && \
	"$DATADIR/vmdir/ssh-to-kvm.sh" '[ -d /home/centos/go/src ]' 2>/dev/null
    false # temporary hack to make this always run while debugging it
    $skip_step_if_already_done ; set -e
    "$DATADIR/vmdir/ssh-to-kvm.sh" <<EOF
set -x
set -e
mkdir -p go
export GOPATH=/home/centos/go
go get -v github.com/axsh/wakame-vdc/ || :
cd /home/centos/go/src/github.com/axsh/wakame-vdc/
git checkout terraform-provider
cd /home/centos/go/src/github.com/axsh/wakame-vdc/client/terraform-provider-wakamevdc/
go get -v
cd /home/centos/go/src/github.com/axsh/wakame-vdc/client/terraform-provider-wakamevdc/wakamevdc
export TF_ACC=something
export WAKAMEVDC_API_ENDPOINT="http://127.0.0.1:9001/api/12.03/"
go test -v
EOF
) ; prev_cmd_failed