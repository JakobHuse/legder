--  A block device over a single desktop file, for Legder.Log and
--  Legder.Store.
--
--  Block I of the device is bytes I * Block_Size .. (I + 1) * Block_Size - 1
--  of the file. The file grows as blocks are written; it is never
--  truncated by this package.
--
--  Instantiate the store with it exactly as with the RAM device:
--
--     package KV is new Legder.Store
--       (Legder.File_Device.Block_Count, Legder.File_Device.Read,
--        Legder.File_Device.Write, Legder.File_Device.Sync);
--
--  and call Attach (Path) before KV.Open.
--
--  DEVICE CONTRACT (what the log relies on, see ARCHITECTURE.md)
--    D1  Read of a block that was never written returns all 16#FF#,
--        like erased flash. That covers every byte past the end of the
--        file, including the missing tail of a partially extended
--        last block: the bytes that exist are returned, the rest is FF.
--    D2  Write followed by a Sync that returns normally is durable:
--        Sync calls fsync (2) on the file, and Attach fsyncs the parent
--        directory when it creates the file, so the file itself
--        survives a power cut too.
--    D3  Writes after the last Sync may be lost or partly lost on a
--        power cut. The log's per-block CRC and sequence check handle
--        that; this package does not try to.
--    D4  Write and Sync never return normally after failing. Any I/O
--        error (open, short write, read error, failed fsync) raises
--        Device_Error with the OS error message. The generic interface
--        has no status parameter, so returning normally would let
--        Append report Success for a record that is not on the medium.
--
--  AFTER Device_Error
--    The exception propagates out of Append, before Head and the table
--    are updated, so the store never acknowledges the failed record.
--    But a failed fsync leaves the kernel's view of the file
--    unreliable (pending writes may have been dropped), so treat the
--    store instance as dead: Detach, then Attach and Open again to
--    recover from what is actually on the medium.
--
--  LIMITS
--    * POSIX only (Linux, macOS; Windows through WSL). Uses pread,
--      pwrite and fsync directly.
--    * On macOS fsync (2) hands data to the drive but does not force
--      the drive's own cache to the platter; D2 there holds against a
--      process crash or kernel panic, not against a power cut. Use
--      Linux for power-cut experiments, or a translation layer with
--      fcntl (F_FULLFSYNC).
--    * One writer. Nothing stops two processes from attaching the same
--      file; do not do it.
--    * A process kill (the Week 3 harness) does not test D2: the
--      kernel still writes the page cache back after the process
--      dies. Only a power cut or a VM reset tests fsync.
--
--  Not SPARK: this is the boundary to the OS (CONTRIBUTING.md allows
--  SPARK_Mode => Off under devices/).

package Legder.File_Device with SPARK_Mode => Off is

   Block_Count : constant Block_Index := Block_Index'Last;
   --  Highest usable block index: 4096 blocks, a 2 MiB log at most.
   --  The file only takes the space of blocks actually written.
   --  Larger than the store's 256-entry table, so the table can fill
   --  before the log does (the S3 test the RAM device cannot do).

   Device_Error : exception;

   procedure Attach (Path : String);
   --  Opens Path for reading and writing, creating it (empty, so every
   --  block reads as erased) if it does not exist. Raises Device_Error
   --  if a file is already attached or the file cannot be opened.

   procedure Detach;
   --  Closes the file. Does not Sync: unsynced writes may or may not
   --  reach the medium, exactly as on a crash. No-op if not attached.

   function Is_Attached return Boolean;

   procedure Read  (Index : Block_Index; Data : out Block);
   procedure Write (Index : Block_Index; Data : Block);
   procedure Sync;
   --  The three generic formals. All raise Device_Error when no file
   --  is attached or the OS reports a failure (D4).

   function Writes return Natural;
   function Syncs  return Natural;
   --  Calls since Attach, for the same "one sync per commit" check the
   --  showcase makes on the RAM device.

end Legder.File_Device;
