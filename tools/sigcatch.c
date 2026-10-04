/*
 * sigcatch — a low-overhead PTRACE_SEIZE signal catcher.
 *
 * Why this exists: on a build whose debuggerd/crash_dump is broken, a fatal signal
 * leaves no tombstone and no abort message. strace is unusable here (tracing 200+
 * threads perturbs timing and can freeze the process). PTRACE_SEIZE does NOT stop
 * the target — it only traps on signal delivery. This program seizes every thread
 * of a target pid (auto-following new threads), reinjects every signal EXCEPT the
 * one of interest, and on SIGABRT records the exact siginfo (si_code / si_pid /
 * si_uid), the faulting thread's registers, /proc/<pid>/maps and a stack slice,
 * then cleanly detaches so the process dies normally.
 *
 * Build (static, runs on Android via `su`/`adb root`):
 *   aarch64-linux-gnu-gcc -static -O2 -o sigcatch tools/sigcatch.c
 * Run:
 *   ./sigcatch <pid> <outfile>          # then collect /proc dumps it writes
 *
 * Unwind the captured fp-chain against the captured maps on the host to symbolize.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <linux/ptrace.h>
#include <elf.h>

#ifndef SI_KERNEL
#define SI_KERNEL 0x80
#endif
#ifndef PTRACE_SEIZE
#define PTRACE_SEIZE 0x4206
#endif
#ifndef PTRACE_GETSIGINFO
#define PTRACE_GETSIGINFO 0x4202
#endif

static FILE *out;
static unsigned long long g_sp, g_pc, g_fp;

static void logln(const char *fmt, ...) {
    char ts[32]; time_t t = time(0); struct tm tm; localtime_r(&t, &tm);
    strftime(ts, sizeof ts, "%H:%M:%S", &tm);
    va_list ap; va_start(ap, fmt);
    fprintf(out, "%s ", ts); vfprintf(out, fmt, ap); fprintf(out, "\n");
    fflush(out); fsync(fileno(out)); va_end(ap);
}

static int seize_all(pid_t pid) {
    char path[64]; snprintf(path, sizeof path, "/proc/%d/task", pid);
    DIR *d = opendir(path); if (!d) { logln("ERR opendir: %s", strerror(errno)); return -1; }
    struct dirent *e; int n = 0;
    long opts = PTRACE_O_TRACECLONE | PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK;
    while ((e = readdir(d)))
        if (e->d_name[0] >= '0' && e->d_name[0] <= '9')
            if (ptrace(PTRACE_SEIZE, atoi(e->d_name), 0, (void*)opts) == 0) n++;
    closedir(d);
    return n;
}

static void dump_regs(pid_t tid) {
    struct { unsigned long long regs[31], sp, pc, pstate; } rg;
    struct iovec iov = { &rg, sizeof rg };
    if (ptrace(PTRACE_GETREGSET, tid, (void*)NT_PRSTATUS, &iov) == 0) {
        logln("faulting tid=%d pc=0x%llx lr=0x%llx sp=0x%llx x29=0x%llx",
              tid, rg.pc, rg.regs[30], rg.sp, rg.regs[29]);
        logln("x0=0x%llx x1=0x%llx x2=0x%llx x8(syscall)=0x%llx",
              rg.regs[0], rg.regs[1], rg.regs[2], rg.regs[8]);
        g_sp = rg.sp; g_pc = rg.pc; g_fp = rg.regs[29];
    } else logln("GETREGSET failed: %s", strerror(errno));
}

static void dump_abort_message(pid_t target) {
    char mp[64]; snprintf(mp, sizeof mp, "/proc/%d/maps", target);
    FILE *m = fopen(mp, "r"); if (!m) return;
    char memp[64]; snprintf(memp, sizeof memp, "/proc/%d/mem", target);
    int fd = open(memp, O_RDONLY), found = 0; char line[512];
    while (fgets(line, sizeof line, m)) {
        if (strstr(line, "[anon:abort message]")) {
            unsigned long lo = 0, hi = 0; sscanf(line, "%lx-%lx", &lo, &hi);
            found = 1; char buf[2048]; memset(buf, 0, sizeof buf);
            if (fd >= 0 && pread(fd, buf, sizeof buf - 1, (off_t)lo) > 0)
                logln("ABORT_MESSAGE >>> %s", buf + 8);   /* {size_t size; char msg[];} */
        }
    }
    if (!found) logln("no [anon:abort message] mapping (bare abort / raw sigqueue)");
    if (fd >= 0) close(fd);
    fclose(m);
}

/* copies /proc/<pid>/maps and a 32 KiB stack slice to fixed files for host-side unwind */
static void dump_maps_and_stack(pid_t target, unsigned long sp) {
    char mp[64]; snprintf(mp, sizeof mp, "/proc/%d/maps", target);
    FILE *in = fopen(mp, "r"), *o = fopen("/data/local/tmp/sigcatch_maps.txt", "w");
    if (in && o) { char l[512]; while (fgets(l, sizeof l, in)) fputs(l, o); }
    if (in) fclose(in); if (o) fclose(o);
    char memp[64]; snprintf(memp, sizeof memp, "/proc/%d/mem", target);
    int fd = open(memp, O_RDONLY);
    if (fd >= 0) {
        char buf[32768]; ssize_t r = pread(fd, buf, sizeof buf, (off_t)sp);
        if (r > 0) { FILE *so = fopen("/data/local/tmp/sigcatch_stack.bin", "wb");
                     if (so) { fwrite(buf, 1, r, so); fclose(so); } }
        close(fd);
    }
    logln("maps -> sigcatch_maps.txt, stack(from sp=0x%lx) -> sigcatch_stack.bin", sp);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: sigcatch <pid> <outfile>\n"); return 2; }
    pid_t target = atoi(argv[1]);
    out = fopen(argv[2], "w"); if (!out) { perror("fopen"); return 2; }
    setvbuf(out, NULL, _IONBF, 0);

    int n = seize_all(target);
    logln("STARTED target=%d seized=%d threads", target, n);
    if (n <= 0) { logln("ERR nothing seized (need root? wrong pid?)"); return 1; }

    for (;;) {
        int status; pid_t tid = waitpid(-1, &status, __WALL);
        if (tid == -1) { if (errno == EINTR) continue;
            logln(errno == ECHILD ? "ALL GONE" : "waitpid: %s", strerror(errno)); break; }
        if (WIFEXITED(status) || WIFSIGNALED(status)) { if (tid == target) break; continue; }
        if (!WIFSTOPPED(status)) continue;
        int sig = WSTOPSIG(status);
        if ((status >> 16) != 0) { ptrace(PTRACE_CONT, tid, 0, 0); continue; }  /* event stop */
        siginfo_t si; memset(&si, 0, sizeof si);
        if (ptrace(PTRACE_GETSIGINFO, tid, 0, &si) == -1) { ptrace(PTRACE_CONT, tid, 0, 0); continue; }

        if (sig == SIGABRT) {
            const char *cs = "?";
            switch (si.si_code) {
                case SI_USER: cs = "SI_USER";   break; case SI_QUEUE:  cs = "SI_QUEUE";  break;
                case SI_TKILL:cs = "SI_TKILL";  break; case SI_KERNEL: cs = "SI_KERNEL"; break;
            }
            logln("=== CAUGHT SIGABRT tid=%d si_code=%d (%s) si_pid=%d si_uid=%d ===",
                  tid, si.si_code, cs, (int)si.si_pid, (int)si.si_uid);
            logln("verdict: si_pid %s target (0=kernel, ==target=self)",
                  (int)si.si_pid == target ? "==" : "!=");
            dump_regs(tid);
            dump_abort_message(target);
            dump_maps_and_stack(target, (unsigned long)g_sp);
            /* detach all, delivering SIGABRT to the stopped tid so the process dies normally */
            char path[64]; snprintf(path, sizeof path, "/proc/%d/task", target);
            DIR *d = opendir(path);
            if (d) { struct dirent *e;
                while ((e = readdir(d))) { if (e->d_name[0] < '0' || e->d_name[0] > '9') continue;
                    pid_t t2 = atoi(e->d_name);
                    ptrace(PTRACE_DETACH, t2, 0, (void*)(long)(t2 == tid ? SIGABRT : 0)); }
                closedir(d);
            } else ptrace(PTRACE_DETACH, tid, 0, (void*)(long)SIGABRT);
            logln("DETACHED; process will die normally. DONE.");
            break;
        }
        ptrace(PTRACE_CONT, tid, 0, (void*)(long)sig);   /* reinject other signals */
    }
    fclose(out);
    return 0;
}
