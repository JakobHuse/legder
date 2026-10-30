--  The smoke test on a file: one phase per process.
--
--    file_smoke write          PATH   (PATH must not exist yet, or be empty)
--    file_smoke check          PATH
--    file_smoke extend         PATH
--    file_smoke check-extended PATH
--
--  run_smoke.sh runs the four phases as four separate processes on a
--  temporary file. Exit status is non-zero on any failure.

with Ada.Command_Line;  use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;       use Ada.Text_IO;
with Legder.File_Device;
with Smoke_Scenario;

procedure File_Smoke is

   package Dev renames Legder.File_Device;
   package Scenario is new Smoke_Scenario (Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);

   procedure Usage is
   begin
      Put_Line ("usage: file_smoke {write|check|extend|check-extended} PATH");
      Set_Exit_Status (Failure);
   end Usage;

   OK : Boolean;

begin
   if Argument_Count /= 2 then
      Usage;
      return;
   end if;

   declare
      Phase : constant String := Argument (1);
      Path  : constant String := Argument (2);
   begin
      Put_Line ("phase " & Phase & " on " & Path);
      Dev.Attach (Path);

      if Phase = "write" then
         OK := Scenario.Run_Write;
      elsif Phase = "check" then
         OK := Scenario.Run_Check;
      elsif Phase = "extend" then
         OK := Scenario.Run_Extend;
      elsif Phase = "check-extended" then
         OK := Scenario.Run_Check_Extended;
      else
         Dev.Detach;
         Usage;
         return;
      end if;

      Put_Line ("  device: writes" & Dev.Writes'Image & ", syncs" & Dev.Syncs'Image
                & " (one sync per commit)");
      Dev.Detach;
   end;

   if OK then
      Put_Line ("phase ok");
   else
      Put_Line ("PHASE FAILED");
      Set_Exit_Status (Failure);
   end if;

exception
   when E : Dev.Device_Error =>
      Put_Line ("DEVICE ERROR: " & Ada.Exceptions.Exception_Message (E));
      Set_Exit_Status (Failure);
end File_Smoke;
