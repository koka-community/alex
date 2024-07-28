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
  fun get-state(): int // Gets the current state of the stack
  // Lexer input movement
  fun next-char(): maybe<char> // Gets the next character in the input
  fun prev-char(): char // Gets the previous character in the input
  fun consume-char(): () // Consumes the current character, adding it to the accepted input
  // Lexer accepting finished tokens and info
  fun set-accept(s: int): () // Sets the latest potential accepting state, while still seeking for states that accept more input
  fun get-last-accept(): alexAccRes // Get's the last discovered accepting state
  fun recognize-token(): () // Recognizes that the last accepting state is the longest accepting token, and prepares to start the next token
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

reference type alexAccRes
  AlexAccResNone
  AlexAccRes(action: int, input: sslice, acc: sslice, end: alex-pos)
  AlexAccResSkip(input: sslice, acc: sslice)

fun alex-scan(input: sslice, sc: int, restart:bool=False): handled-alex-eff ()
  var states := [sc]
  var seek := input // The seeked position in the input
  // on an error, we want to keep the input *before* the
  // character that failed, not after.
  var current := input // Trails the seeked position by one
  var acc := input.truncate // The slice representing the current 'accepted' portion of the input
  var prev := ' ' // Previous character
  var curr := ' ' // Current character
  var start := Alex-pos(0,1,1) // File position of the start of the current token
  var end := Alex-pos(0,1,1) // File position of the end of the current token
  var last-accept := AlexAccResNone // The last accepting state encountered
  var action-info := Action-info(acc, start, end) // The action info
  with handler
    fun get-state()
      match states // Get the current lexer state (i.e. the state to start the next token in)
        Cons(s) -> s
    fun push-state(i)
      states := Cons(i, states) // Push a new state onto the stack
    fun pop-state() // Pop the current state off the stack
      match states
        Cons(s, ss) -> 
          states := ss
          s
        _ -> throw("No states to pop.")
    fun next-char() // Moves the current to the seeked position, and moves the seeked position to the next character
      current := seek
      match seek.next()
        Just((c, slice')) -> 
          prev := curr
          curr := c
          seek := slice'
          Just(c)
        Nothing -> Nothing
    fun consume-char() // Consumes the current character, adding it to the accepted input for this token
      acc := acc.extend(1)
      end := end.pos-move(curr)
    fun prev-char() // Gets the previous character
      prev
    fun action-info() // Gets the info for the action
      action-info
    fun get-last-accept() // Get the last accepting state
      last-accept
    fun set-accept(s) // Sets the accepting state
      match alex-accept.unsafe-idx(s.ssize_t)
        AlexAccNone -> 
          () // Just use the previous accepting state
        AlexAcc(act) -> 
          // New accepting state with this accumlated input and end, and the action associated with it
          last-accept := AlexAccRes(act, current, acc, end) 
        AlexAccSkip -> 
          last-accept := AlexAccResSkip(current, acc) // An accepting state that skips over this input
    fun recognize-token() // Recognizes the last accepting state as the longest accepting token
      match last-accept
        AlexAccResNone ->  
          match seek.next() // Check if we are at the end of the input
            Nothing -> ()  // EOF
            Just ->
              if restart then // Try skipping the first character, and start again
                current := seek
                start := end
                acc := seek.truncate() // TODO: End / start positions
                last-accept := AlexAccResNone
              else
                throw("Alex Error at: " ++ seek.subslice(0, 50).string.show)
        AlexAccRes(_, rescurr, resacc, resend) ->
          action-info := Action-info(resacc, start, resend)
          start := end
          seek := rescurr
          acc := seek.truncate()
          last-accept := AlexAccResNone
        AlexAccResSkip(rescurr) ->      
          start := end
          seek := rescurr
          acc := seek.truncate()
          last-accept := AlexAccResNone
  alex-scan-tokens(sc)

inline fun do-recognize-token(): alex-eff ()
  val la = get-last-accept()
  recognize-token() // Changes last accept, so we get it prior
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
