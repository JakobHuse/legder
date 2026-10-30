--  The portable smoke test: a fixed scenario of Put/Delete/Get on any
--  legder device, split into phases that are meant to run in separate
--  processes (or across a reset on a board). Nothing here touches a
--  device directly; the device comes in through the same three
--  formals the store takes, so the board device reuses this unchanged.
--
--  Phases, in order, on a device that starts empty:
--    Write           5 records: alpha=1, beta=2, alpha=11, delete beta,
--                    gamma=3. Fails if the device is not empty.
--    Check           a fresh Open replays 5; alpha=11, beta absent,
--                    gamma=3, 2 live keys.
--    Extend          a fresh Open replays 5, then 3 more records:
--                    delta=4, alpha=111, delete gamma.
--    Check_Extended  a fresh Open replays 8; alpha=111, beta and gamma
--                    absent, delta=4, 2 live keys.
--
--  Each phase prints one line per check and returns False if any
--  check failed. None of them injects a fault: this is the normal
--  write/reopen/read path. Crashes are the Week 3 harness.

with Legder; use Legder;

generic
   Block_Count : Block_Index;
   with procedure Read  (Index : Block_Index; Data : out Block);
   with procedure Write (Index : Block_Index; Data : Block);
   with procedure Sync;
package Smoke_Scenario is

   function Run_Write return Boolean;
   function Run_Check return Boolean;
   function Run_Extend return Boolean;
   function Run_Check_Extended return Boolean;

end Smoke_Scenario;
