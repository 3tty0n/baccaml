let rec fib n =
  if n < 2 then 1
  else fib (n - 1) + fib (n - 2)
in
let rec loop_fib n =
  if n = 0 then ()
  else let _ = fib 40 in loop_fib (n - 1)
in
let start = get_micro_time () in
let _ = fib 40 in
let stop = get_micro_time () in
print_int (stop - start);
print_newline ()
