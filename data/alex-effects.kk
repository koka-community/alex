// -----------------------------------------------------------------------------
// ALEX TEMPLATE
// -----------------------------------------------------------------------------
// This code is in the PUBLIC DOMAIN; you may copy it freely and use
// it for any purpose whatsoever.

// -----------------------------------------------------------------------------
// Main lexing routines

effect alex
  ctl alex-error(): ()
  ctl skip-input(): ()
  fun recognize-token(): action-info
  fun push-state(i: int): ()
  fun pop-state(): int
  fun get-state(): int
  ctl next-char(): maybe<char>
  fun prev-char(): char
  fun accept-char(): ()
  fun current-alex-info(): action-info

pub value struct alex-pos
  offset: int
  column: int
  line: int

fun pos-move(Alex-pos(o, l, c), ch: char): alex-pos
  val o1 = if o < 0 then o else o+1
  match ch
    '\n' -> Alex-pos(o1, l + 1, 1)
    _    -> Alex-pos(o1, l, c + 1)

alias action = () -> <pure,alex%effects> ();

struct action-info
  token: sslice
  start: alex-pos
  end: alex-pos

fun get-slice()
  current-alex-info().token

fun get-string()
  get-slice().string

fun get-start()
  current-alex-info().start

fun get-end()
  current-alex-info().end

fun alex-scan(input: sslice, sc: int, restart:bool=False): <pure%effects> ()
  var states := [sc]
  var seek := input
  var current := input
  var acc := input.truncate
  var prev := ' '
  var curr := ' '
  var start := Alex-pos(0,1,1)
  var end := Alex-pos(0,1,1)
  var current-info := Action-info(acc, start, end)
  fun current-state()
    match states
      Cons(s) -> s
  with handler
    fun get-state()
      current-state()
    fun push-state(i)
      states := Cons(i, states)
    fun pop-state()
      match states
        Cons(s, ss) -> 
          states := ss
          s
        _ -> throw("No states to pop.")
    fun recognize-token()
      current-info := Action-info(acc, start, end)
      seek := current
      start := end
      acc := current.truncate()
      current-info
    ctl alex-error()
      match seek.next()
        Nothing -> ()  // EOF
        Just ->
          if restart then
            current := seek
            acc := current.truncate()
            resume(())
          else
            throw("Alex Error at: " ++ current.subslice(0, 50).string.show)
    ctl skip-input()
      current := seek
      acc := current.truncate()
      resume(())
    fun next-char()
      match seek.next()
        Just((c, slice')) -> 
          prev := curr
          curr := c
          seek := slice'
          Just(c)
        Nothing -> Nothing
    fun accept-char()
      acc := acc.extend(1)
      current := seek
      end := end.pos-move(curr)
    fun prev-char()
      prev
    fun current-alex-info()
      current-info
  alex-scan-tkns()

value type alexAcc
  AlexAccNone
  AlexAcc(i: int)
  AlexAccSkip

fun alex-scan-tkns(): <pure,alex%effects> ()
  match alex_scan_tkn(get-state(), AlexAccNone)
    AlexAccNone -> 
      alex-error()
    AlexAccSkip -> 
      skip-input()
      alex-scan-tkns()
    AlexAcc(a) -> 
      recognize-token()
      alex-actions.unsafe-idx(a.ssize_t)()
      alex-scan-tkns()

// Push the input through the DFA, remembering the most recent accepting
// state it encountered.
fun alex_scan_tkn(s: int, acc: alexAcc): <pure,alex> alexAcc
  val new-acc =
        match alex-accept.unsafe-idx(s.ssize_t)
          AlexAccNone -> acc
          AlexAcc(a) -> AlexAcc(a)
          AlexAccSkip -> AlexAccSkip
  val mc = next-char()
  match mc 
    Nothing -> new-acc
    Just(c) ->
      match c.int
        ord_c ->
          val base = alex-base.unsafe-idx(s.ssize_t)
          val offset = base + ord_c
          val check  = alex-check.unsafe-idx(offset.ssize_t)
          val new_s = if offset >= 0 && check == ord_c
                          then alex-table.unsafe-idx(offset.ssize_t)
                          else alex-deflt.unsafe-idx(s.ssize_t)
          match new_s
              -1 -> new-acc
                  // on an error, we want to keep the input *before* the
                  // character that failed, not after.
              _ ->
                accept-char() 
                alex_scan_tkn(new_s, new-acc)
