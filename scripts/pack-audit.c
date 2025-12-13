/* nix-on-droid rtld-audit module for library path redirection
   Based on GNU Guix pack-audit.c by Ludovic Courtès <ludo@gnu.org>

   This file implements part of the GNU ld.so audit interface. It is used
   to make the loader look for shared objects under the nix-on-droid prefix
   instead of /nix/store.

   On Android, /nix/store doesn't exist - Nix store is at:
   /data/data/com.termux.nix/files/usr/nix/store

   ELF binaries have hardcoded /nix/store paths in their RPATH/RUNPATH.
   This audit module intercepts library lookups and redirects them to
   the real location specified by FAKECHROOT_BASE.

   Additionally, this module redirects standard glibc libraries to the
   Android-patched glibc. This is essential because:
   1. Standard glibc uses syscalls (clone3, rseq) blocked by Android seccomp
   2. Our Android glibc has Termux patches to avoid these blocked syscalls
   3. Binary-cached packages reference standard glibc in RUNPATH
   4. We redirect those references to Android glibc at load time

   Environment variables:
   - FAKECHROOT_BASE: Prefix for /nix/store -> real path translation
   - STANDARD_GLIBC: Hash of standard nixpkgs glibc (e.g., "89n0gcl1yjp37ycca45rn50h7lms5p6f-glibc-2.40-66")
   - ANDROID_GLIBC: Hash of Android-patched glibc (e.g., "lb0hd462xiicipri33q3idk43nzz0983-glibc-android-2.40-66")
   - PACK_AUDIT_DEBUG: Set to "1" for debug output

   Usage:
   FAKECHROOT_BASE=/data/data/com.termux.nix/files/usr \
   STANDARD_GLIBC=89n0gcl1yjp37ycca45rn50h7lms5p6f-glibc-2.40-66 \
   ANDROID_GLIBC=lb0hd462xiicipri33q3idk43nzz0983-glibc-android-2.40-66 \
   ld.so --audit /path/to/pack-audit.so --preload libfakechroot.so /path/to/program
*/

#define _GNU_SOURCE 1

#include <link.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* The pseudo root directory and store that we are relocating to.  */
static const char *root_directory;
static char *store;
static size_t store_len;

/* The original store, "/nix/store" by default.  */
static const char original_store[] = "/nix/store";

/* Standard glibc path to replace (set via STANDARD_GLIBC env var) */
static const char *standard_glibc = NULL;
static size_t standard_glibc_len = 0;

/* Android glibc path to use instead (set via ANDROID_GLIBC env var) */
static const char *android_glibc = NULL;
static size_t android_glibc_len = 0;

/* Full paths for glibc redirection (after applying store prefix) */
static char *standard_glibc_path = NULL;
static char *android_glibc_path = NULL;

/* Enable debug output via PACK_AUDIT_DEBUG=1 */
static int debug_enabled = 0;

/* Like 'malloc', but abort if 'malloc' returns NULL.  */
static void *
xmalloc (size_t size)
{
  void *result = malloc (size);
  if (result == NULL)
    {
      fprintf (stderr, "pack-audit: out of memory\n");
      abort ();
    }
  return result;
}

unsigned int
la_version (unsigned int v)
{
  const char *debug_env = getenv ("PACK_AUDIT_DEBUG");
  debug_enabled = (debug_env != NULL && debug_env[0] == '1');

  if (debug_enabled)
    fprintf (stderr, "pack-audit: la_version called with v=%u (LAV_CURRENT=%u)\n",
             v, LAV_CURRENT);

  root_directory = getenv ("FAKECHROOT_BASE");
  if (root_directory == NULL)
    {
      fprintf (stderr, "pack-audit: error: FAKECHROOT_BASE is not set\n");
      /* Return version anyway to allow loading, but path translation won't work */
      return v;
    }

  store = xmalloc (strlen (root_directory) + sizeof original_store);
  strcpy (store, root_directory);
  strcat (store, original_store);
  store_len = strlen (store);

  if (debug_enabled)
    fprintf (stderr, "pack-audit: redirecting %s -> %s\n", original_store, store);

  /* Set up glibc redirection */
  standard_glibc = getenv ("STANDARD_GLIBC");
  android_glibc = getenv ("ANDROID_GLIBC");

  if (standard_glibc != NULL && android_glibc != NULL)
    {
      standard_glibc_len = strlen (standard_glibc);
      android_glibc_len = strlen (android_glibc);

      /* Build full paths: $store/$hash/lib */
      /* Standard glibc: /data/data/.../nix/store/xxx-glibc-2.40-66 */
      standard_glibc_path = xmalloc (store_len + 1 + standard_glibc_len + 1);
      sprintf (standard_glibc_path, "%s/%s", store, standard_glibc);

      /* Android glibc: /data/data/.../nix/store/yyy-glibc-android-2.40-66 */
      android_glibc_path = xmalloc (store_len + 1 + android_glibc_len + 1);
      sprintf (android_glibc_path, "%s/%s", store, android_glibc);

      if (debug_enabled)
        fprintf (stderr, "pack-audit: glibc redirect: %s -> %s\n",
                 standard_glibc_path, android_glibc_path);
    }
  else if (debug_enabled)
    {
      fprintf (stderr, "pack-audit: glibc redirection disabled (STANDARD_GLIBC or ANDROID_GLIBC not set)\n");
    }

  return v;
}

/* Return NAME, a shared object file name, relocated under STORE.  This
   function is called by the loader whenever it looks for a shared object.  */
char *
la_objsearch (const char *name, uintptr_t *cookie, unsigned int flag)
{
  char *result;
  char *temp;
  size_t std_path_len;

  /* Required by rtld-audit interface but unused */
  (void) cookie;
  (void) flag;

  /* If FAKECHROOT_BASE wasn't set, pass through unchanged */
  if (store == NULL)
    return strdup (name);

  if (strncmp (name, original_store, sizeof original_store - 1) == 0)
    {
      /* Redirect /nix/store/... to $FAKECHROOT_BASE/nix/store/... */
      size_t suffix_len = strlen (name) - (sizeof original_store - 1);
      result = xmalloc (store_len + suffix_len + 1);
      memcpy (result, store, store_len);
      memcpy (result + store_len, name + sizeof original_store - 1, suffix_len + 1);

      if (debug_enabled)
        fprintf (stderr, "pack-audit: store redirect: %s -> %s\n", name, result);
    }
  else
    {
      result = strdup (name);
      if (debug_enabled && result != NULL)
        fprintf (stderr, "pack-audit: pass-through: %s\n", name);
    }

  /* Now check if we need to redirect standard glibc to Android glibc */
  if (result != NULL && standard_glibc_path != NULL && android_glibc_path != NULL)
    {
      std_path_len = strlen (standard_glibc_path);
      if (strncmp (result, standard_glibc_path, std_path_len) == 0)
        {
          /* Path starts with standard glibc path, redirect to Android glibc */
          const char *suffix = result + std_path_len;  /* e.g., "/lib/libc.so.6" */
          size_t suffix_len = strlen (suffix);
          size_t android_path_len = strlen (android_glibc_path);

          temp = xmalloc (android_path_len + suffix_len + 1);
          memcpy (temp, android_glibc_path, android_path_len);
          memcpy (temp + android_path_len, suffix, suffix_len + 1);

          if (debug_enabled)
            fprintf (stderr, "pack-audit: glibc redirect: %s -> %s\n", result, temp);

          free (result);
          result = temp;
        }
    }

  return result;
}
