#!/bin/sh

# Runs as loxberry before the plugin files are copied. LoxBerry V4 exports the
# system directory variables through /etc/environment. This plugin has no
# pre-copy work, but keeping the hook makes the lifecycle explicit.

PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

echo "<INFO> Preparing SmartMeter v2 $PVERSION for folder $PDIR."
exit 0
