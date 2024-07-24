// -----------------------------------------------------------------------------
// ALEX TEMPLATE
// -----------------------------------------------------------------------------
// This code is in the PUBLIC DOMAIN; you may copy it freely and use
// it for any purpose whatsoever.

// -----------------------------------------------------------------------------
// Main lexing routines

// import std/core-extras
// import std/core/undiv

effect alex
  // Lexer state
  fun push-state(i: int): () // Push a new state onto the stack
  fun pop-state(): int // Pop the current state off the stack
  fun replace-state(i: int): () // Pop the current state off the stack, and add the new one
  fun get-state(): int // Gets the current state of the stack
  // Lexer input movement
  fun next-char(): maybe<char> // Gets the next character in the input
  fun prev-char(): char // Gets the previous character in the input
  fun consume-char(): () // Consumes the current character, adding it to the accepted input
  // Lexer accepting finished tokens and info
  fun set-accept(s: int): () // Sets the latest potential accepting state, while still seeking for states that accept more input
  fun recognize-token(): alexAccRes // Recognizes that the last accepting state is the longest accepting token, and prepares to start the next token
  fun action-info(): action-info // Get the info about the last token recognized (start, end, and slice) for the action
 
pub value struct alex-pos
  offset: int
  column: int
  line: int

// alias alex-eff = <pure, alex>
// alias handled-alex-eff = <pure>
// val alex-actions: vector<action> = [].vector
// val alex-accept: vector<alexAcc> = [].vector
// val alex-base : vector<int> = [].vector
// val alex-check : vector<int> = [].vector
// val alex-table : vector<int> = [].vector
// val alex-deflt : vector<int> = [].vector

alias alex-eff = <pure,alex%effects>
alias handled-alex-eff = <pure%effects>

fun pos-move(Alex-pos(o, l, c): alex-pos, char: char): alex-pos
  val o1 = if o < 0 then o else o+1
  match char
    '\n' -> Alex-pos(o1, l + 1, 1)
    _    -> Alex-pos(o1, l, c + 1)

alias action = () -> alex-eff ();

struct action-info
  token: sslice
  start: alex-pos
  end: alex-pos

fun get-slice()
  action-info().token

fun get-string()
  get-slice().string

fun get-start()
  action-info().start

fun get-end()
  action-info().end

value type alexAcc
  AlexAccNone
  AlexAcc(a: int)
  AlexAccSkip

type alexAccRes
  AlexAccResNone
  AlexAccRes(action: int, input: sslice, acc: sslice, end: alex-pos)
  AlexAccResSkip(input: sslice, acc: sslice)

struct alexScanState
  states: list<int> 
  seek: sslice // The seeked position in the input
  // on an error, we want to keep the input *before* the
  // character that failed, not after.
  current: sslice // Trails the seeked position by one
  acc: sslice // The slice representing the current 'accepted' portion of the input
  prev: char // Previous character
  curr: char // Current character
  start: alex-pos // File position of the start of the current token
  end: alex-pos // File position of the end of the current token
  last-accept: alexAccRes // The last accepting state encountered
  action-info: action-info // The action info

// Consumes the current character, adding it to the accepted input for this token
fun alex-consume-char(a: alexScanState)
  match a
    AlexScanState(states, seek, current, acc, prev, curr, start, end, last-accept, action-info) ->
      AlexScanState(states, seek, current, acc.extend(1), prev, curr, start, end.pos-move(curr), last-accept, action-info)

pub value struct alex-next
  s: alexScanState
  c: char

// Moves the current to the seeked position, and moves the seeked position to the next character
fun alex-next(a: alexScanState): (maybe<alex-next>)
  match a
    AlexScanState(states, seek, _, acc, _, curr, start, end, last-accept, action-info) ->
      match seek.next()
        Just((c, slice')) ->
          Just(Alex-next(AlexScanState(states, slice', seek, acc, curr, c, start, end, last-accept, action-info), c))
        Nothing ->  Nothing

fun do-alex-accept(a: alexScanState, s: int) // Sets the accepting state
  match a
    AlexScanState(states, seek, current, acc, prev, curr, start, end, last-accept, action-info) ->
      match alex-accept.unsafe-idx(s.ssize_t)
        AlexAccNone -> 
          AlexScanState(states, seek, current, acc, prev, curr, start, end, last-accept, action-info) // Just use the previous accepting state
        AlexAcc(act) -> 
          // New accepting state with this accumlated input and end, and the action associated with it
          AlexScanState(states, seek, current, acc, prev, curr, start, end, AlexAccRes(act, seek, acc, end), action-info)
        AlexAccSkip -> 
          // An accepting state that skips over this input
          AlexScanState(states, seek, current, acc, prev, curr, start, end, AlexAccResSkip(seek, acc), action-info)

// Recognizes the last accepting state as the longest accepting token
fun recognize(a: alexScanState, restart: bool)
  match a
    AlexScanState(states, seek, current, acc, prev, curr, start, end, last-accept, action-info) ->
      match last-accept
        AlexAccResNone ->  
          match seek.next() // Check if we are at the end of the input
            Nothing -> 
              // EOF
              AlexScanState(states, seek, current, acc, prev, curr, start, end, last-accept, action-info)
            Just ->
              if restart then // Try skipping the first character, and start again
                AlexScanState(states, seek, seek, seek.truncate(), ' ', ' ', end, end, AlexAccResNone, action-info)
              else // Skip?
                AlexScanState(states, seek, seek, seek.truncate(), ' ', ' ', end, end, AlexAccResNone, action-info)
                // throw("Alex Error at: " ++ seek.subslice(0, 50).string.show)
        AlexAccRes(_, resnext, resacc, resend) ->
          // trace("Recognized " ++ resacc.show)
          AlexScanState(states, resnext, resnext, resnext.truncate(), ' ', ' ', resend, resend, AlexAccResNone, Action-info(resacc, start, resend))
        AlexAccResSkip(resnext) ->
          AlexScanState(states, resnext, resnext, resnext.truncate(), ' ', ' ', end, end, AlexAccResNone, action-info)

fun alex-scan(input: sslice, sc: int, restart:bool=False): handled-alex-eff ()
  var state := AlexScanState([sc], input, input, input.truncate, ' ', ' ' , Alex-pos(0,1,1), Alex-pos(0,1,1), AlexAccResNone, Action-info(input.truncate, Alex-pos(0,1,1), Alex-pos(0,1,1)))
  with handler
    fun get-state()
      match state.states // Get the current lexer state (i.e. the state to start the next token in)
        Cons(s) -> s
    fun push-state(i)
      state := state(states=Cons(i, state.states)) // Push a new state onto the stack
    fun replace-state(i)
      match state.states
        Cons(_, states) -> 
          state := state(states=Cons(i, states)) // Push a new state onto the stack
    fun pop-state() // Pop the current state off the stack
      match state.states
        Cons(s, ss) -> 
          state := state(states=ss)
          s
        _ -> throw("No states to pop.")
    fun next-char() 
      val mc = state.alex-next()
      match mc
        Nothing -> Nothing
        Just(Alex-next(s, c)) -> 
          state := s
          Just(c)
    fun consume-char() 
      state := state.alex-consume-char()
    fun prev-char() // Gets the previous character
      state.prev
    fun action-info() // Gets the info for the action
      state.action-info
    fun set-accept(s) // Sets the accepting state
      state := state.do-alex-accept(s)
    fun recognize-token() 
      val la = state.last-accept
      state := state.recognize(restart) 
      la
  alex-scan-tokens(sc)

inline fun do-recognize-token(): alex-eff ()
  val la = recognize-token() // Changes last accept, so we get it prior
  match la
    AlexAccRes(a) ->
      alex-actions.unsafe-idx(a.ssize_t)()
    _ -> ()

// Push the input through the DFA, remembering the most recent accepting
// state it encountered.
fun alex-scan-tokens(s: int): alex-eff ()
  set-accept(s)
  val mc = next-char()
  match mc
    Nothing -> 
      do-recognize-token()
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
              -1 -> 
                do-recognize-token()
                alex-scan-tokens(get-state())
              _ ->
                consume-char()
                alex-scan-tokens(new_s)
