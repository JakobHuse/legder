--  Unit tests for Legder.File_Device: the device contract (D1..D4 in
--  the spec) and the table-capacity rule S3, which the 256-block RAM
--  device cannot exercise because its log fills first.
--
--  Works in a scratch directory under the current directory, removed
--  at the end. Non-zero exit on failure.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;          use Ada.Text_IO;
with Legder;               use Legder;
with Legder.File_Device;
with Legder.Store;

procedure File_Device_Tests is

   package Dev renames Legder.File_Device;
   package KV is new Legder.Store (Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);

   Scratch : constant String := "file_device_tests.tmp";

   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "PASS  " else "FAIL  ") & Name);
      if not Cond then
         Failures := Failures + 1;
      end if;
   end Check;

   function Path (Name : String) return String is (Scratch & "/" & Name);

   function All_Are (B : Block; X : Byte) return Boolean is
     (for all I in B'Range => B (I) = X);

   function Pattern (Seed : Byte) return Block is
     [for I in Block_Offset => Byte ((I + Natural (Seed)) mod 256)];

   function Key_Of (N : Natural) return Key is
      Img : constant String := N'Image;
      R   : Key;
   begin
      R.Length := Img'Length;
      for I in Img'Range loop
         R.Bytes (I - Img'First + 1) := Byte (Character'Pos (Img (I)));
      end loop;
      return R;
   end Key_Of;

   function File_Size (Name : String) return Natural is
     (Natural (Ada.Directories.Size (Path (Name))));

   ---------------------------------------------------------------------

   procedure Test_Fresh_File is
      B : Block;
   begin
      Dev.Attach (Path ("fresh.bin"));
      Check ("attach creates the file", Ada.Directories.Exists (Path ("fresh.bin")));
      Check ("new file is empty", File_Size ("fresh.bin") = 0);
      Dev.Read (0, B);
      Check ("unwritten block 0 reads all FF", All_Are (B, 16#FF#));
      Dev.Read (Dev.Block_Count, B);
      Check ("unwritten last block reads all FF", All_Are (B, 16#FF#));
      Dev.Detach;
   end Test_Fresh_File;

   procedure Test_Write_Read_Persist is
      B : Block;
   begin
      Dev.Attach (Path ("persist.bin"));
      Dev.Write (0, Pattern (1));
      Dev.Read (0, B);
      Check ("read sees own unsynced write", B = Pattern (1));
      Dev.Sync;
      Check ("counters: 1 write, 1 sync", Dev.Writes = 1 and then Dev.Syncs = 1);

      Dev.Write (3, Pattern (3));
      Dev.Sync;
      Check ("write past EOF extends the file to 4 blocks", File_Size ("persist.bin") = 4 * 512);
      Dev.Read (1, B);
      Check ("gap block 1 reads all FF, not zeros", All_Are (B, 16#FF#));
      Dev.Read (2, B);
      Check ("gap block 2 reads all FF, not zeros", All_Are (B, 16#FF#));

      Dev.Write (0, Pattern (7));
      Dev.Sync;
      Dev.Detach;
      Check ("detach", not Dev.Is_Attached);

      Dev.Attach (Path ("persist.bin"));
      Check ("reattach resets counters", Dev.Writes = 0 and then Dev.Syncs = 0);
      Dev.Read (0, B);
      Check ("overwritten block 0 persists across reattach", B = Pattern (7));
      Dev.Read (3, B);
      Check ("block 3 persists across reattach", B = Pattern (3));
      Dev.Read (4, B);
      Check ("block past EOF still reads all FF", All_Are (B, 16#FF#));
      Dev.Detach;
   end Test_Write_Read_Persist;

   procedure Test_Partial_Last_Block is
      use Ada.Streams;
      package SIO renames Ada.Streams.Stream_IO;
      F    : SIO.File_Type;
      Tail : constant Stream_Element_Array (1 .. 100) := [others => 16#AA#];
      B    : Block;
   begin
      --  A file whose last block was only partly extended, as a crash
      --  during a write past EOF can leave it.
      Dev.Attach (Path ("partial.bin"));
      Dev.Write (0, Pattern (0));
      Dev.Sync;
      Dev.Detach;
      SIO.Open (F, SIO.Append_File, Path ("partial.bin"));
      SIO.Write (F, Tail);
      SIO.Close (F);

      Dev.Attach (Path ("partial.bin"));
      Dev.Read (1, B);
      Check ("partial block: bytes present are returned",
             (for all I in 0 .. 99 => B (I) = 16#AA#));
      Check ("partial block: missing tail reads FF",
             (for all I in 100 .. Block_Size - 1 => B (I) = 16#FF#));
      Dev.Write (1, Pattern (9));
      Dev.Sync;
      Dev.Read (1, B);
      Check ("partial block can be overwritten whole", B = Pattern (9));
      Dev.Detach;
   end Test_Partial_Last_Block;

   procedure Test_Errors is
      B      : Block;
      Raised : Boolean;
   begin
      Raised := False;
      begin
         Dev.Read (0, B);
      exception
         when Dev.Device_Error => Raised := True;
      end;
      Check ("read with no file attached raises Device_Error", Raised);

      Raised := False;
      begin
         Dev.Sync;
      exception
         when Dev.Device_Error => Raised := True;
      end;
      Check ("sync with no file attached raises Device_Error", Raised);

      Raised := False;
      begin
         Dev.Attach (Path ("no_such_dir/x.bin"));
      exception
         when Dev.Device_Error => Raised := True;
      end;
      Check ("attach in a missing directory raises Device_Error", Raised);
      Check ("failed attach leaves nothing attached", not Dev.Is_Attached);

      Dev.Attach (Path ("twice.bin"));
      Raised := False;
      begin
         Dev.Attach (Path ("twice.bin"));
      exception
         when Dev.Device_Error => Raised := True;
      end;
      Check ("second attach raises Device_Error", Raised);
      Dev.Detach;
   end Test_Errors;

   procedure Test_Table_Capacity is
      --  S3 with the log large enough not to fill first: 4096 blocks
      --  against 256 table entries.
      S      : KV.Store;
      N      : Natural;
      OK     : Boolean;
      All_OK : Boolean := True;
      Before : Natural;
      Got    : Value;
      Found  : Boolean;
      One    : Value;
   begin
      One.Length := 1;
      One.Bytes (1) := 16#31#;

      Dev.Attach (Path ("capacity.bin"));
      KV.Open (S, N);
      for I in 1 .. KV.Max_Entries loop
         KV.Put (S, Key_Of (I), One, OK);
         All_OK := All_OK and OK;
      end loop;
      Check ("256 distinct keys fit", All_OK and then KV.Count (S) = KV.Max_Entries);

      Before := Dev.Writes;
      KV.Put (S, Key_Of (KV.Max_Entries + 1), One, OK);
      Check ("S3: new key on a full table is refused", not OK);
      Check ("S3: refused put writes nothing to the log", Dev.Writes = Before);

      KV.Put (S, Key_Of (1), One, OK);
      Check ("existing key on a full table still updates", OK);

      KV.Delete (S, Key_Of (2), OK);
      KV.Put (S, Key_Of (KV.Max_Entries + 1), One, OK);
      Check ("after a delete the new key fits", OK and then KV.Count (S) = KV.Max_Entries);
      Dev.Detach;

      Dev.Attach (Path ("capacity.bin"));
      KV.Open (S, N);
      Check ("reopen replays all 259 records", N = KV.Max_Entries + 3);
      Check ("reopen: table full again", KV.Count (S) = KV.Max_Entries);
      KV.Get (S, Key_Of (2), Got, Found);
      Check ("reopen: deleted key absent", not Found);
      KV.Get (S, Key_Of (KV.Max_Entries + 1), Got, Found);
      Check ("reopen: late key present", Found);
      Dev.Detach;
   end Test_Table_Capacity;

begin
   if Ada.Directories.Exists (Scratch) then
      Ada.Directories.Delete_Tree (Scratch);
   end if;
   Ada.Directories.Create_Directory (Scratch);

   Test_Fresh_File;
   Test_Write_Read_Persist;
   Test_Partial_Last_Block;
   Test_Errors;
   Test_Table_Capacity;

   Ada.Directories.Delete_Tree (Scratch);
   New_Line;
   if Failures = 0 then
      Put_Line ("all file device tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end File_Device_Tests;
