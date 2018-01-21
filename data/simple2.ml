let rec interp code pc a =
  let instr = code.(pc) in
  if instr = 0 then
    interp code (pc + 1) (a + 1)
  else if instr = 1 then
    interp code (pc + 1) (a - 1)
  else if instr = 10 then
    let t = code.(pc + 1) in
    interp code t a
  else if instr = 11 then
    if 0 < a then
      let t1 = code.(pc + 1) in
      interp code t1 a
    else
      let t2 = code.(pc + 2) in
      interp code t2 a
  else if instr = 20 then
    a
  else
    -1
in
let code = Array.make 10 0 in
code.(0) <- 0;
code.(1) <- 11; code.(2) <- 4; code.(3) <- 7;
(* then *)
code.(4) <- 0;
code.(5) <- 0;
code.(6) <- 20;
code.(7) <- 1;
code.(8) <- 1;
code.(9) <- 20;
print_int (interp code 0 0)