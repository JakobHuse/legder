with Ada.Directories;
with Interfaces.C;
with System;
with GNAT.OS_Lib;

package body Legder.File_Device is

   package OS renames GNAT.OS_Lib;
   use type OS.File_Descriptor;

   --  POSIX calls GNAT.OS_Lib does not offer with error reporting.
   --  ssize_t and off_t are C long on the LP64 targets we support
   --  (Linux and macOS, 64-bit).

   subtype C_Int  is Interfaces.C.int;
   subtype C_Long is Interfaces.C.long;
   use type C_Int, C_Long;

   function C_Pread
     (FD : C_Int; Buf : System.Address; Count : Interfaces.C.size_t; Offset : C_Long)
      return C_Long
     with Import, Convention => C, External_Name => "pread";

   function C_Pwrite
     (FD : C_Int; Buf : System.Address; Count : Interfaces.C.size_t; Offset : C_Long)
      return C_Long
     with Import, Convention => C, External_Name => "pwrite";

   function C_Fsync (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "fsync";

   EINTR : constant := 4;  --  Same value on Linux and macOS.

   FD       : OS.File_Descriptor := OS.Invalid_FD;
   N_Writes : Natural := 0;
   N_Syncs  : Natural := 0;

   Erased : constant Block := [others => 16#FF#];

   procedure Fail (What : String) with No_Return;
   procedure Fail (What : String) is
   begin
      raise Device_Error with What & ": " & OS.Errno_Message;
   end Fail;

   procedure Require_Attached (What : String);
   procedure Require_Attached (What : String) is
   begin
      if FD = OS.Invalid_FD then
         raise Device_Error with What & ": no file attached";
      end if;
   end Require_Attached;

   function Offset_Of (Index : Block_Index) return C_Long;
   function Offset_Of (Index : Block_Index) return C_Long is
     (C_Long (Index) * Block_Size);

   procedure Write_All (Data : Byte_Array; Offset : C_Long);
   --  Write all of Data at Offset, retrying short writes and EINTR.
   procedure Write_All (Data : Byte_Array; Offset : C_Long) is
      Done : Natural := 0;
      N    : C_Long;
   begin
      while Done < Data'Length loop
         N := C_Pwrite (C_Int (FD),
                        Data (Data'First + Done)'Address,
                        Interfaces.C.size_t (Data'Length - Done),
                        Offset + C_Long (Done));
         if N < 0 then
            if OS.Errno /= EINTR then
               Fail ("write at offset" & Offset'Image);
            end if;
         elsif N = 0 then
            raise Device_Error with "write at offset" & Offset'Image & ": no progress";
         else
            Done := Done + Natural (N);
         end if;
      end loop;
   end Write_All;

   procedure Fsync_Directory_Of (Path : String);
   procedure Fsync_Directory_Of (Path : String) is
      Dir : constant String :=
        Ada.Directories.Containing_Directory (Ada.Directories.Full_Name (Path));
      DFD : constant OS.File_Descriptor := OS.Open_Read (Dir, OS.Binary);
      Bad : Boolean;
   begin
      if DFD = OS.Invalid_FD then
         Fail ("open directory " & Dir);
      end if;
      Bad := C_Fsync (C_Int (DFD)) /= 0;
      OS.Close (DFD);
      if Bad then
         Fail ("fsync directory " & Dir);
      end if;
   end Fsync_Directory_Of;

   ------------
   -- Attach --
   ------------

   procedure Attach (Path : String) is
   begin
      if FD /= OS.Invalid_FD then
         raise Device_Error with "attach " & Path & ": a file is already attached";
      end if;

      if not OS.Is_Regular_File (Path) then
         --  O_EXCL create: fails rather than truncating if the file
         --  appeared in the meantime. Write-only, so reopen below.
         declare
            New_FD : constant OS.File_Descriptor := OS.Create_New_File (Path, OS.Binary);
         begin
            if New_FD = OS.Invalid_FD then
               Fail ("create " & Path);
            end if;
            if C_Fsync (C_Int (New_FD)) /= 0 then
               OS.Close (New_FD);
               Fail ("fsync " & Path);
            end if;
            OS.Close (New_FD);
         end;
         --  The new directory entry is not durable until the directory
         --  itself is synced. Without this a power cut can lose the
         --  whole file, synced records included.
         Fsync_Directory_Of (Path);
      end if;

      FD := OS.Open_Read_Write (Path, OS.Binary);
      if FD = OS.Invalid_FD then
         Fail ("open " & Path);
      end if;

      N_Writes := 0;
      N_Syncs  := 0;
   end Attach;

   ------------
   -- Detach --
   ------------

   procedure Detach is
   begin
      if FD /= OS.Invalid_FD then
         OS.Close (FD);
         FD := OS.Invalid_FD;
      end if;
   end Detach;

   function Is_Attached return Boolean is (FD /= OS.Invalid_FD);

   ----------
   -- Read --
   ----------

   procedure Read (Index : Block_Index; Data : out Block) is
      Offset : constant C_Long := Offset_Of (Index);
      Done   : Natural := 0;
      N      : C_Long;
   begin
      Require_Attached ("read");
      Data := Erased;  --  D1: whatever the file does not have reads as FF.
      while Done < Block_Size loop
         N := C_Pread (C_Int (FD),
                       Data (Data'First + Done)'Address,
                       Interfaces.C.size_t (Block_Size - Done),
                       Offset + C_Long (Done));
         if N < 0 then
            if OS.Errno /= EINTR then
               Fail ("read block" & Index'Image);
            end if;
         elsif N = 0 then
            exit;  --  End of file: the rest stays erased.
         else
            Done := Done + Natural (N);
         end if;
      end loop;
   end Read;

   -----------
   -- Write --
   -----------

   procedure Write (Index : Block_Index; Data : Block) is
      Offset : constant C_Long := Offset_Of (Index);
      Size   : C_Long;
   begin
      Require_Attached ("write");

      --  If the block lies beyond the end of the file, fill the gap
      --  with FF first. A plain pwrite past EOF would leave a hole that
      --  reads back as zeros, breaking D1 for the blocks in between.
      --  The log writes blocks in order, so this is normally a no-op.
      Size := C_Long (OS.File_Length64 (FD));
      if Size < 0 then
         Fail ("size of file");
      end if;
      while Size < Offset loop
         declare
            Chunk : constant C_Long := C_Long'Min (Block_Size, Offset - Size);
         begin
            Write_All (Erased (0 .. Natural (Chunk) - 1), Size);
            Size := Size + Chunk;
         end;
      end loop;

      Write_All (Data, Offset);
      N_Writes := N_Writes + 1;
   end Write;

   ----------
   -- Sync --
   ----------

   procedure Sync is
   begin
      Require_Attached ("sync");
      if C_Fsync (C_Int (FD)) /= 0 then
         Fail ("fsync");
      end if;
      N_Syncs := N_Syncs + 1;
   end Sync;

   function Writes return Natural is (N_Writes);
   function Syncs  return Natural is (N_Syncs);

end Legder.File_Device;
