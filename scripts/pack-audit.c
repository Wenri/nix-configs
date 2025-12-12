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

   Additionally, this module installs a SIGSYS handler to catch syscalls
   blocked by Android's seccomp filter. When a blocked syscall triggers
   SIGSYS, we return -ENOSYS so glibc can fall back to older alternatives.
   This handles: clone3 -> clone, rseq -> disabled, etc.

   Usage:
   FAKECHROOT_BASE=/data/data/com.termux.nix/files/usr \
   ld.so --audit /path/to/pack-audit.so --preload libfakechroot.so /path/to/program
*/

#define _GNU_SOURCE 1

#include <link.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <signal.h>
#include <errno.h>
#include <ucontext.h>

/* The pseudo root directory and store that we are relocating to.  */
static const char *root_directory;
static char *store;
static size_t store_len;

/* The original store, "/nix/store" by default.  */
static const char original_store[] = "/nix/store";

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

/*
 * SIGSYS handler for Android seccomp bypass
 *
 * When Android's seccomp filter blocks a syscall, it sends SIGSYS.
 * This handler intercepts SIGSYS and returns -ENOSYS to the caller,
 * allowing glibc to fall back to older syscall alternatives:
 *   - clone3 -> clone
 *   - rseq -> disabled (glibc skips rseq registration)
 *   - set_robust_list -> skipped
 *
 * The syscall number is available in siginfo->si_syscall.
 * We modify the return register (x0 on aarch64) to -ENOSYS.
 */
static void
sigsys_handler (int sig, siginfo_t *info, void *ucontext)
{
  ucontext_t *ctx = (ucontext_t *) ucontext;

  if (debug_enabled)
    {
      fprintf (stderr, "pack-audit: SIGSYS caught for syscall %d, returning ENOSYS\n",
               info->si_syscall);
    }

  /*
   * Set syscall return value to -ENOSYS.
   * On aarch64, x0 holds the return value.
   * mcontext.regs[0] is x0 in glibc's ucontext.
   */
#if defined(__aarch64__)
  ctx->uc_mcontext.regs[0] = -ENOSYS;
#elif defined(__x86_64__)
  ctx->uc_mcontext.gregs[REG_RAX] = -ENOSYS;
#elif defined(__i386__)
  ctx->uc_mcontext.gregs[REG_EAX] = -ENOSYS;
#elif defined(__arm__)
  ctx->uc_mcontext.arm_r0 = -ENOSYS;
#else
  #error "Unsupported architecture for SIGSYS handler"
#endif
}

/*
 * Install the SIGSYS handler as early as possible.
 * Use constructor with highest priority (101 is lowest user priority,
 * lower numbers run earlier).
 */
static void
install_sigsys_handler (void)
{
  struct sigaction sa;

  memset (&sa, 0, sizeof (sa));
  sa.sa_sigaction = sigsys_handler;
  sa.sa_flags = SA_SIGINFO;
  sigemptyset (&sa.sa_mask);

  if (sigaction (SIGSYS, &sa, NULL) < 0)
    {
      /* Can't use fprintf here - might not be initialized yet */
    }
}

/*
 * Constructor that runs VERY early - before la_version().
 * Priority 101 is the earliest user-accessible priority.
 */
__attribute__((constructor(101)))
static void
early_init (void)
{
  install_sigsys_handler ();
}

unsigned int
la_version (unsigned int v)
{
  const char *debug_env = getenv ("PACK_AUDIT_DEBUG");
  debug_enabled = (debug_env != NULL && debug_env[0] == '1');

  if (debug_enabled)
    fprintf (stderr, "pack-audit: la_version called with v=%u (LAV_CURRENT=%u)\n",
             v, LAV_CURRENT);

  /* Install SIGSYS handler FIRST, before any potentially blocked syscalls */
  install_sigsys_handler ();

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

  return v;
}

/* Return NAME, a shared object file name, relocated under STORE.  This
   function is called by the loader whenever it looks for a shared object.  */
char *
la_objsearch (const char *name, uintptr_t *cookie, unsigned int flag)
{
  char *result;

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
        fprintf (stderr, "pack-audit: %s -> %s\n", name, result);
    }
  else
    {
      result = strdup (name);
      if (debug_enabled && result != NULL)
        fprintf (stderr, "pack-audit: pass-through: %s\n", name);
    }

  return result;
}
