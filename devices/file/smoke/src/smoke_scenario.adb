with Ada.Text_IO; use Ada.Text_IO;
with Legder.Store;

package body Smoke_Scenario is

   package KV is new Legder.Store (Block_Count, Read, Write, Sync);

   function K (S : String) return Key is
      R : Key;
   begin
      R.Length := S'Length;
      for I in S'Range loop
         R.Bytes (I - S'First + 1) := Byte (Character'Pos (S (I)));
      end loop;
      return R;
   end K;

   function V (S : String) return Value is
      R : Value;
   begin
      R.Length := S'Length;
      for I in S'Range loop
         R.Bytes (I - S'First + 1) := Byte (Character'Pos (S (I)));
      end loop;
      return R;
   end V;

   function Img (X : Value) return String is
      S : String (1 .. X.Length);
   begin
      for I in S'Range loop
         S (I) := Character'Val (X.Bytes (I));
      end loop;
      return S;
   end Img;

   Ok_So_Far : Boolean := True;

   procedure Check (What : String; Cond : Boolean; Detail : String := "") is
   begin
      if Cond then
         Put_Line ("  ok   " & What);
      else
         Put_Line ("  FAIL " & What & (if Detail = "" then "" else " (" & Detail & ")"));
         Ok_So_Far := False;
      end if;
   end Check;

   procedure Expect (S : KV.Store; Name : String; Want : String) is
      Got   : Value;
      Found : Boolean;
   begin
      KV.Get (S, K (Name), Got, Found);
      Check (Name & " = '" & Want & "'",
             Found and then Img (Got) = Want,
             (if Found then "got '" & Img (Got) & "'" else "absent"));
   end Expect;

   procedure Expect_Absent (S : KV.Store; Name : String) is
      Got   : Value;
      Found : Boolean;
   begin
      KV.Get (S, K (Name), Got, Found);
      Check (Name & " absent", not Found,
             (if Found then "got '" & Img (Got) & "'" else ""));
   end Expect_Absent;

   procedure Do_Put (S : in out KV.Store; Name, Val : String) is
      OK : Boolean;
   begin
      KV.Put (S, K (Name), V (Val), OK);
      Check ("put " & Name & " = '" & Val & "'", OK);
   end Do_Put;

   procedure Do_Delete (S : in out KV.Store; Name : String) is
      OK : Boolean;
   begin
      KV.Delete (S, K (Name), OK);
      Check ("delete " & Name, OK);
   end Do_Delete;

   procedure Open_Expecting (S : out KV.Store; Records : Natural) is
      N : Natural;
   begin
      KV.Open (S, N);
      Check ("open replays" & Records'Image & " records", N = Records, "replayed" & N'Image);
   end Open_Expecting;

   ---------------------------------------------------------------------

   function Run_Write return Boolean is
      S : KV.Store;
   begin
      Ok_So_Far := True;
      Open_Expecting (S, 0);
      if not Ok_So_Far then
         Put_Line ("  device is not empty; start from a fresh file");
         return False;
      end if;
      Do_Put (S, "alpha", "1");
      Do_Put (S, "beta", "2");
      Do_Put (S, "alpha", "11");
      Do_Delete (S, "beta");
      Do_Put (S, "gamma", "3");
      Check ("2 live keys", KV.Count (S) = 2, "count" & KV.Count (S)'Image);
      return Ok_So_Far;
   end Run_Write;

   function Run_Check return Boolean is
      S : KV.Store;
   begin
      Ok_So_Far := True;
      Open_Expecting (S, 5);
      Expect (S, "alpha", "11");
      Expect_Absent (S, "beta");
      Expect (S, "gamma", "3");
      Check ("2 live keys", KV.Count (S) = 2, "count" & KV.Count (S)'Image);
      return Ok_So_Far;
   end Run_Check;

   function Run_Extend return Boolean is
      S : KV.Store;
   begin
      Ok_So_Far := True;
      Open_Expecting (S, 5);
      Do_Put (S, "delta", "4");
      Do_Put (S, "alpha", "111");
      Do_Delete (S, "gamma");
      return Ok_So_Far;
   end Run_Extend;

   function Run_Check_Extended return Boolean is
      S : KV.Store;
   begin
      Ok_So_Far := True;
      Open_Expecting (S, 8);
      Expect (S, "alpha", "111");
      Expect_Absent (S, "beta");
      Expect_Absent (S, "gamma");
      Expect (S, "delta", "4");
      Check ("2 live keys", KV.Count (S) = 2, "count" & KV.Count (S)'Image);
      return Ok_So_Far;
   end Run_Check_Extended;

end Smoke_Scenario;
