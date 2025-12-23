/* nix-on-droid rtld-audit module for library path redirection
   Based on GNU Guix pack-audit.c by Ludovic Courtès <ludo@gnu.org>

   This file implements part of the GNU ld.so audit interface. It is used
   to make the loader look for shared objects under the nix-on-droid prefix
   instead of /nix/store.

   On Android, /nix/store doesn't exist - Nix store is at:
   /data/data/com.termux.nix/files/usr/nix/store

   ELF binaries have hardcoded /nix/store paths in their RPATH/RUNPATH.
   This audit module intercepts library lookups and redirects them to
   the real Android location.

   Additionally, this module redirects standard glibc libraries to the
   Android-patched glibc. This is essential because:
   1. Standard glibc uses syscalls (clone3, rseq) blocked by Android seccomp
   2. Our Android glibc has Termux patches to avoid these blocked syscalls
   3. Binary-cached packages reference standard glibc in RUNPATH
   4. We redirect those references to Android glibc at load time

   Compile-time configuration (passed via -D flags):
   - FAKECHROOT_BASE: Prefix for /nix/store -> real path translation
   - STANDARD_GLIBC_HASH: Hash of standard nixpkgs glibc
   - ANDROID_GLIBC_HASH: Hash of Android-patched glibc

   Runtime configuration (optional):
   - PACK_AUDIT_DEBUG: Set to "1" for debug output

   Build example:
   gcc -shared -fPIC -O2 \
     -DFAKECHROOT_BASE='"/data/data/com.termux.nix/files/usr"' \
     -DSTANDARD_GLIBC_HASH='"89n0gcl1yjp37ycca45rn50h7lms5p6f-glibc-2.40-66"' \
     -DANDROID_GLIBC_HASH='"xxx-glibc-android-2.40-66"' \
     -o pack-audit.so pack-audit.c -ldl
*/

#define _GNU_SOURCE 1

#include <link.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Compile-time configuration - these MUST be defined via -D flags */
#ifndef FAKECHROOT_BASE
#error "FAKECHROOT_BASE must be defined at compile time"
#endif

#ifndef STANDARD_GLIBC_HASH
#error "STANDARD_GLIBC_HASH must be defined at compile time"
#endif

#ifndef ANDROID_GLIBC_HASH
#error "ANDROID_GLIBC_HASH must be defined at compile time"
#endif

/* The original store path */
static const char original_store[] = "/nix/store";

/* Hardcoded configuration from compile-time defines */
static const char root_directory[] = FAKECHROOT_BASE;
static const char store[] = FAKECHROOT_BASE "/nix/store";
static const size_t store_len = sizeof(FAKECHROOT_BASE "/nix/store") - 1;

/* Full paths for glibc redirection */
static const char standard_glibc_path[] = FAKECHROOT_BASE "/nix/store/" STANDARD_GLIBC_HASH;
static const char android_glibc_path[] = FAKECHROOT_BASE "/nix/store/" ANDROID_GLIBC_HASH;

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
    {
      fprintf (stderr, "pack-audit: la_version called with v=%u (LAV_CURRENT=%u)\n",
               v, LAV_CURRENT);
      fprintf (stderr, "pack-audit: compiled with hardcoded paths:\n");
      fprintf (stderr, "pack-audit:   FAKECHROOT_BASE=%s\n", root_directory);
      fprintf (stderr, "pack-audit:   store=%s\n", store);
      fprintf (stderr, "pack-audit:   standard_glibc=%s\n", standard_glibc_path);
      fprintf (stderr, "pack-audit:   android_glibc=%s\n", android_glibc_path);
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
  static const size_t std_path_len = sizeof(standard_glibc_path) - 1;
  static const size_t android_path_len = sizeof(android_glibc_path) - 1;

  /* Required by rtld-audit interface but unused */
  (void) cookie;
  (void) flag;

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
  if (result != NULL && strncmp (result, standard_glibc_path, std_path_len) == 0)
    {
      /* Path starts with standard glibc path, redirect to Android glibc */
      const char *suffix = result + std_path_len;  /* e.g., "/lib/libc.so.6" */
      size_t suffix_len = strlen (suffix);

      temp = xmalloc (android_path_len + suffix_len + 1);
      memcpy (temp, android_glibc_path, android_path_len);
      memcpy (temp + android_path_len, suffix, suffix_len + 1);

      if (debug_enabled)
        fprintf (stderr, "pack-audit: glibc redirect: %s -> %s\n", result, temp);

      free (result);
      result = temp;
    }

  return result;
}

/* Stub implementations for other audit interface functions.
   These are optional but some ld.so versions complain if they're missing.
   We implement them as no-ops to avoid error messages. */

void
la_activity (uintptr_t *cookie, unsigned int flag)
{
  (void) cookie;
  (void) flag;
}

unsigned int
la_objopen (struct link_map *map, Lmid_t lmid, uintptr_t *cookie)
{
  (void) map;
  (void) lmid;
  (void) cookie;
  return 0;  /* Return 0 = don't audit PLT for this object */
}

void
la_preinit (uintptr_t *cookie)
{
  (void) cookie;
}

unsigned int
la_objclose (uintptr_t *cookie)
{
  (void) cookie;
  return 0;
}
