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

# Example: Enable pack-audit debug output
# export PACK_AUDIT_DEBUG=1

# Example: Print debug info
# echo "DEBUG: login-debug.sh loaded" >&2
