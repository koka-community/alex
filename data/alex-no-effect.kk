// -----------------------------------------------------------------------------
// ALEX TEMPLATE
// -----------------------------------------------------------------------------
// This code is in the PUBLIC DOMAIN; you may copy it freely and use
// it for any purpose whatsoever.

// -----------------------------------------------------------------------------
// Main lexing routines

type alex-return
  AlexEOF
  AlexError(i: alex-input)
  AlexSkip(i: alex-input, n: int)
  AlexToken(i: alex-input, n: int, a: action) // a is the action type


// alexScan :: AlexInput -> StartCode -> AlexReturn a
fun alexScan(input: alex-input, sc: int): <%effectspure|e> alex-return
  alexScanUser(Nothing, input, sc)

fun alexScanUser(user: maybe<alex-user>, input: alex-input, sc: int): <%effectspure|e> alex-return
  match alex_scan_tkn(user, input, 0, input, sc, AlexNone)
    (AlexNone, input__') ->
      match alexGetByte(input)
        Nothing ->
          AlexEOF
        Just ->
          AlexError(input__')
    (AlexLastSkip(input__'', len), _) ->
      AlexSkip(input__'', len)
    (AlexLastAcc(k, input__''', len), _) ->
      AlexToken(input__''', len, alex-actions.unsafe-idx(k.ssize_t))

// Push the input through the DFA, remembering the most recent accepting
// state it encountered.
fun alex_scan_tkn(user__:maybe<alex-user>, orig_input:alex-input, len:int, input__:alex-input, s: int, last_acc: alex-last-acc): <%effectspure|e> (alex-last-acc, alex-input)
  fun check_accs(acc: alex-acc<<%effects|e>>): <%effects|e> alex-last-acc
    match acc
      AlexAccNone -> last_acc
      AlexAcc(a) -> AlexLastAcc(a, input__, len)
      AlexAccSkip -> AlexLastSkip(input__, len)
      AlexAccPred(a, predx, rest)
        -> if predx(user__, orig_input, len, input__) then AlexLastAcc(a, input__, len)
           else check_accs(rest)
      AlexAccSkipPred(predx, rest)
        -> if predx(user__, orig_input, len, input__) then AlexLastSkip(input__, len)
           else check_accs(rest)
  val new_acc = check_accs(alex-accept.unsafe-idx(s.ssize_t))
  match alexGetByte(input__)
     Nothing -> (new_acc, input__)
     Just((c, new_input)) ->
       match c.int
        ord_c ->
          val base = alex-base.unsafe-idx(s.ssize_t)
          val offset = base + ord_c
          val check  = alex-check.unsafe-idx(offset.ssize_t)
          val new_s = if offset >= 0 && check == ord_c
                          then alex-table.unsafe-idx(offset.ssize_t)
                          else alex-deflt.unsafe-idx(s.ssize_t)
        
          match new_s
              -1 -> (new_acc, input__)
                  // on an error, we want to keep the input *before* the
                  // character that failed, not after.
              _ -> alex_scan_tkn(user__, orig_input, len + 1, new_input, new_s, new_acc)
 

type alex-last-acc
  AlexNone
  AlexLastAcc(i: int, a: alex-input, n: int)
  AlexLastSkip(a: alex-input, n: int)

type alex-acc<e>
  AlexAccNone
  AlexAcc(i: int)
  AlexAccSkip
  AlexAccPred(i: int, pred: alex-acc-pred<e>, acc: alex-acc<e>)
  AlexAccSkipPred(pred: alex-acc-pred<e>, acc: alex-acc<e>)

alias alex-acc-pred<e> = (maybe<alex-user>, alex-input, int, alex-input) -> e bool;

// -----------------------------------------------------------------------------
// Predicates on a rule

inline fun alexAndPred(p1: alex-acc-pred<e>, p2: alex-acc-pred<e>, user__: maybe<alex-user>, in1: alex-input, len: int, in2: alex-input): e bool
  p1(user__, in1, len, in2) && p2(user__, in1, len, in2)

// alexPrevCharIsPred :: Char -> AlexAccPred _
inline fun alexPrevCharIs(c: char, _, input__: alex-input, _, _): <%effectspure> bool
  c == alexInputPrevChar(input__)

inline fun alexPrevCharMatches(f: (char) -> pure bool, _, input__: alex-input, _, _): <%effectspure> bool
  f(alexInputPrevChar(input__))

// alexPrevCharIsOneOfPred :: Array Char Bool -> AlexAccPred _
inline fun alexPrevCharIsOneOf(arr: list<char>, _, input__: alex-input, _, _): <%effectspure> bool
  val prev = alexInputPrevChar(input__)
  arr.any(fn(c) c == prev)

// alexRightContext :: Int -> AlexAccPred _
inline fun alexRightContext(sc:int, user__: maybe<alex-user>, _, _, input__: alex-input): <%effectspure|e> bool
  match alex_scan_tkn(user__, input__, 0, input__, sc, AlexNone)
    (AlexNone, _) -> False
    _ -> True
        // TODO: there's no need to find the longest
        // match when checking the right context, just
        // the first match will do.