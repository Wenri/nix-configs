#!/system/bin/sh
# Debug script for /bin/login - sourced at the very beginning
# Modify this file to debug login issues without rebuilding
#
# Available variables at this point:
#   USER, HOME - user configuration
#
# You can:
#   - Override environment variables
#   - Add debug output (echo to stderr)
#   - Exit early with 'exit 0' to abort login
#   - Set PACK_AUDIT_DEBUG=1 for verbose audit lib output

# Enable shell debugging
#set -eux

# Enable pack-audit debug output
#export PACK_AUDIT_DEBUG=1

# Enable fakechroot debug output
#export FAKECHROOT_DEBUG=true

# Enable ld.so debug output (libs, files, bindings, symbols, reloc, all)
#export LD_DEBUG=libs

# Print debug info
#echo "DEBUG: login-debug.sh loaded" >&2
