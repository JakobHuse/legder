# File device

`Legder.File_Device`: a legder block device over one desktop file.
Block *i* is bytes `i*512 .. i*512+511` of the file. Same three
procedures as the RAM device, so the store instantiates the same way:

```ada
package KV is new Legder.Store
  (Legder.File_Device.Block_Count, Legder.File_Device.Read,
   Legder.File_Device.Write, Legder.File_Device.Sync);

Legder.File_Device.Attach ("settings.db");   --  before KV.Open
```

## Layout

```
devices/file/
  src/legder-file_device.ads    contract (D1..D4), limits     the deliverable
  src/legder-file_device.adb    pread / pwrite / fsync        SPARK_Mode => Off
  smoke/src/smoke_scenario.*    portable scenario, generic over Read/Write/Sync
  smoke/src/file_smoke.adb      one scenario phase per process, on a file
  smoke/src/file_device_tests.adb  device contract + S3 capacity, 31 checks
  smoke/run_smoke.sh            the four phases as four processes
```

## Run

```
cd devices/file/smoke
alr build
./bin/file_device_tests
./run_smoke.sh                 # temporary file, removed afterwards
./run_smoke.sh /tmp/demo.db    # keeps the file so you can hexdump it
```

CI runs both after the showcase.

## Decisions

The log is only as safe as the device's promises. These are the
choices that make a file keep them; the spec comment has the full text.

| | Decision | Why |
|---|---|---|
| D1 | Never-written blocks read as all `FF`, including past EOF, gaps, and the missing tail of a partial last block | Recovery must stop cleanly at the end of the log; FF matches erased flash, so the board behaves the same |
| D1 | `Write` past EOF fills the gap with `FF` first | A plain `pwrite` past EOF leaves a hole that reads as zeros |
| D2 | `Sync` calls `fsync(2)` on the file | Flushing an Ada or libc buffer only reaches the page cache; a power cut loses it |
| D2 | `Attach` fsyncs the parent directory after creating the file | Otherwise a power cut can lose the file itself, synced records and all |
| D4 | Every I/O failure raises `Device_Error`; short writes and `EINTR` are retried first | The interface has no status out-parameter; returning normally would let `Append` acknowledge a record that is not on disk |
| | After `Device_Error`, discard the store: `Detach`, `Attach`, `Open` | A failed `fsync` leaves the kernel's view of the file unreliable |

Short read: the bytes that exist are returned and the rest is `FF`
(D1), not an error. A torn extension of the file therefore looks like
a torn block, which the CRC rejects.

## Evidence that Sync is a real fsync

A process-kill test cannot show this (the kernel still flushes the
page cache after the process dies), so check the syscalls:

```
$ strace -e trace=openat,pwrite64,fsync ./bin/file_smoke write /tmp/x.db
openat(AT_FDCWD, "/tmp/x.db", O_WRONLY|O_CREAT|O_EXCL, 0666) = 3
fsync(3)                                = 0      file created
openat(AT_FDCWD, "/tmp", O_RDONLY)      = 3
fsync(3)                                = 0      directory entry durable
openat(AT_FDCWD, "/tmp/x.db", O_RDWR)   = 3
pwrite64(3, "RGDLalpha"..., 512, 0)     = 512
fsync(3)                                = 0      commit 1
pwrite64(3, "RGDLbeta"..., 512, 512)    = 512
fsync(3)                                = 0      commit 2
...                                              one fsync per commit
```

## Limits

- POSIX only: Linux and macOS. Windows users build under WSL.
- macOS `fsync` does not flush the drive's own cache (that needs
  `fcntl(F_FULLFSYNC)`), so on macOS D2 holds against a process crash
  or kernel panic, not a power cut. Do power-cut experiments on Linux.
- One writer. Nothing locks the file; do not attach it from two
  processes.
- `Block_Count` is 4095 (a 2 MiB log at most). The file only grows to
  the blocks actually written.

## What this enables

- **S3 test.** With 4096 log blocks the 256-entry table fills before
  the log does, so `file_device_tests` checks that a new key on a full
  table is refused with zero device writes. The RAM device cannot.
- **Week 3 crash harness.** Data now outlives the process.
- **Board device.** `smoke_scenario` takes only Read/Write/Sync, so the
  board instantiates it unchanged; a reset replaces the process boundary.
