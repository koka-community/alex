{
import compiler/common/name
import compiler/common/range
import compiler/syntax/lexeme
}

%encoding "latin1"

-----------------------------------------------------------
-- Character sets
-----------------------------------------------------------
$digit        = [0-9]
$hexdigit     = [0-9a-fA-F]
$lower        = [a-z]
$upper        = [A-Z]
$letter       = [$lower$upper]
$space        = [\ ]
$tab          = [\t]
$return       = \r
$linefeed     = \n
$graphic      = [\x21-\x7E]
$cont         = [\x80-\xBF]
$symbol       = [\$\%\&\*\+\~\!\\\^\#\=\.\:\-\?\|\<\>]
$special      = [\(\)\[\]\{\}\;\,]
$anglebar     = [\<\>\|]
$angle        = [\<\>]
$finalid      = [\']
$charesc      = [nrt\\\'\"]    -- "

-----------------------------------------------------------
-- Regular expressions
-----------------------------------------------------------
@newline      = $return?$linefeed

@utf8valid    = [\xC2-\xDF] $cont
              | \xE0 [\xA0-\xBF] $cont
              | [\xE1-\xEC] $cont $cont
              | \xED [\x80-\x9F] $cont
              | [\xEE-\xEF] $cont $cont
              | \xF0 [\x90-\xBF] $cont $cont
              | [\xF1-\xF3] $cont $cont $cont
              | \xF4 [\x80-\x8F] $cont $cont

@utf8unsafe   = \xE2 \x80 [\x8E-\x8F\xAA-\xAE]
              | \xE2 \x81 [\xA6-\xA9]

@utf8         = @utf8valid          

@linechar     = [$graphic$space$tab]|@utf8
@commentchar  = ([$graphic$space$tab] # [\/\*])|@newline|@utf8

@hexdigit2    = $hexdigit $hexdigit
@hexdigit4    = @hexdigit2 @hexdigit2
@hexesc       = x@hexdigit2|u@hexdigit4|U@hexdigit4@hexdigit2
@escape       = \\($charesc|@hexesc)
@stringchar   = ([$graphic$space] # [\\\"])|@utf8             -- " fix highlight
@charchar     = ([$graphic$space] # [\\\'])|@utf8
@stringraw    = ([$graphic$space$tab] # [\"])|@newline|@utf8  -- "

@idchar       = $letter | $digit | _ | \-
@lowerid      = $lower @idchar* $finalid*
@upperid      = $upper @idchar* $finalid*
@conid        = @upperid
@modulepath   = (@lowerid\/)+
@qvarid       = @modulepath @lowerid
@qconid       = @modulepath @conid
@symbols      = $symbol+ | \/
@qidop        = @modulepath \(@symbols\)
@idop         = \(@symbols\)

@sign         = [\-]?
@digitsep     = _ $digit+
@hexdigitsep  = _ $hexdigit+
@digits       = $digit+ @digitsep*
@hexdigits    = $hexdigit+ @hexdigitsep*
@decimal      = 0 | [1-9] (_? @digits)?
@hexadecimal  = 0[xX] @hexdigits
@integer      = @sign (@decimal | @hexadecimal)

@exp          = (\-|\+)? $digit+
@exp10        = [eE] @exp
@exp2         = [pP] @exp
@decfloat     = @sign @decimal (\. @digits @exp10? | @exp10)
@hexfloat     = @sign @hexadecimal (\. @hexdigits @exp2? | @exp2)

-----------------------------------------------------------
-- Main tokenizer
-----------------------------------------------------------
program :-
-- white space
<0> $space+               { fn(s) token(LexWhite(s)) }
<0> @newline              { fn(_) token(LexWhite("\n")) }
<0> "/*" $symbol*         { fn(_) next(comment, more(id)) }
<0> "//" $symbol*         { fn(_) next(linecom, more(id)) }
<0> @newline\# $symbol*   { fn(_) next(linedir, more(id)) }


-- qualified identifiers
<0> @qconid               { fn(s) token(LexCons(s.newQName)) }
<0> @qvarid               { fn(s) token(LexId(s.newQName)) }
<0> @qidop                { fn(s) token(LexIdOp(s.stripParens.newQName)) }

-- identifiers
<0> @lowerid              { fn(s') {val s = s'.string; if s.isReserved
                                               then token(LexKeyword(s, ""))
                                           elif s.isMalformed
                                               then token(LexError(messageMalformed))
                                               else token(LexId(s.newName)) } }
<0> @conid                { fn(s) token(LexCons(s.newName)) }
<0> _@idchar*             { fn(s) token(LexWildCard(s.newName)) }

-- specials
<0> $special              { fn(s) token(LexSpecial(s)) }

-- literals
<0> @decfloat             { fn(s') {val s = s'.string; token(LexFloat(s.parseFloat)) } }
<0> @hexfloat             { fn(s') {val s = s'.string; token(LexFloat(s.parseFloat)) } }
<0> @integer              { fn(s') {val s = s'.string; token(LexInt(s.parseInt)) } }


-- type operators
<0> "||"                  { fn(s) token(LexOp(s.newName)) }
<0> $anglebar $anglebar+  { less(1, fn(s') {val s = s'.string; if (s=="|") then token(LexKeyword(s, "")) else token(LexOp(s.newName)) } ) }

-- operators
<0> @idop                 { fn(s) token(LexIdOp(s.stripParens.newName)) }
<0> @symbols              { fn(s') {val s = s'.string; if s.isReserved
                                             then token(LexKeyword(s,""))
                                           elif s.isPrefixOp
                                             then token(LexPrefix(s.newName))
                                             else token(LexOp(s.newName)) } }


-- characters
<0> \"                    { next(stringlit, more(fn(_) "")) }  -- "
<0> r\#*\"                { next(stringraw, rawdelim(more, fn(_) "")) }  -- "

<0> \'\\$charesc\'        { fn(s) token(LexChar(s.drop(2).head.fromCharEsc)) }
<0> \'\\@hexesc\'         { fn(s) token(LexChar(s.drop(3).init.fromHexEsc)) }
<0> \'@charchar\'         { fn(s) token(LexChar(s.tail.head)) }
<0> \'.\'                 { fn(s) token(LexError("illegal character literal: " ++ s.tail.head.show)) }

-- catch errors
<0> $tab+                 { fn(s) token(LexError("tab characters: configure your editor to use spaces instead (soft tab)")) }
<0> .                     { fn(s) token(LexError("illegal character: " ++ s.show ++ (if (s=="\t") then " (replace tabs with spaces)" else ""))) }

--------------------------
-- string literals

<stringlit> @utf8unsafe   { fn(s) unsafeChar("string", s) }
<stringlit> @stringchar   { more(id) }
<stringlit> \\$charesc    { more(fromCharEscB) }
<stringlit> \\@hexesc     { more(fromHexEscB) }
<stringlit> \"            { pop(fn(_) withmore(fn(s) token(LexString(s.init)))) } -- "
<stringlit> @newline      { pop(fn(_) fn(_) token(LexError("string literal ended by a new line"))) }
<stringlit> .             { fn(s) token(LexError("illegal character in string: " ++ s.show)) }

<stringraw> @utf8unsafe   { fn(s) token(unsafeChar("raw string", s)) }
<stringraw> @stringraw    { more(id) }
<stringraw> \"\#*         { withRawDelim(fn(s, delim) {
                              if (s == delim) then  //  done
                                pop(fn(_) less(delim.length, withmore(fn(s) token(LexString(s.string.reverse.drop(delim.length).reverse)))))                              
                              elif (s.length > delim.length) then  // too many terminating hashse
                                fn(s) token(LexError("raw string: too many '#' terminators in raw string (expecting " ++ show(delim.length - 1) ++ ")"))
                              else // continue
                                 more(id)
                              }
                            ) 
                          }
<stringraw> .             { fn(s) token(LexError("illegal character in raw string: " ++ s.show)) }


--------------------------
-- block comments

<comment> "*/"            { pop(fn(state) { if state==comment then more(id)
                                             else withmore(fn(s) token(LexComment(s.string.filter(fn(c) c != '\r')))) } ) }
<comment> "/*"            { push(more(id)) }
<comment> @utf8unsafe     { fn(s) token(unsafeChar("comment", s)) }
<comment> @commentchar    { more(id) }
<comment> [\/\*]          { more(id) }
<comment> .               { fn(s) token(LexError("illegal character in comment: " ++ s.show)) }

--------------------------
-- line comments

<linecom> @utf8unsafe     { fn(s) token(unsafeChar("line comment", s)) }
<linecom> @linechar       { more(id) }
<linecom> @newline        { pop(fn(_) withmore(fn(s) token(LexComment(s.string.filter(fn(c) c !='\r'))))) }
<linecom> .               { fn(s) token(LexError("illegal character in line comment: " ++ s.show)) }

--------------------------
-- line directives (ignored for now)

<linedir> @utf8unsafe     { fn(s) token(unsafeChar("line directive", s)) }
<linedir> @linechar       { more(id) }
<linedir> @newline        { pop(fn(_) withmore(fn(s) token(LexComment(s.string.filter(fn(c) c !='\r'))))) }
<linedir> .               { fn(s) token(LexError("illegal character in line directive: " ++ s.show)) }

-- TODO: Add helper functions

{
struct state
     pos: pos
     startPos: pos
     states: list<int>
     retained: list<sslice>
     previous: char
     current: sslice
     previousLex: lex
     rawEnd: string;

alias action = sslice -> (state -> (state -> (maybe<lex>, state)));

fun token(lex)
  fn(bs) fn(st0) fn(st1) (Just(lex(bs)), st1)

fun next(state, action)
  fn(bs) fn(st0) fn(st1)
     val (x, State(p, sp, sts, ret, prev, cur, pL, rE)) = action(bs)(st0)(st1)
     (x, State(p, sp, Cons(state, sts), ret, prev, cur, pL, rE))

fun push(action)
  fn(bs) fn(st0) fn(st1)
     next(st1.head)(action)(bs)(st0)(st1)

fun pop(action)
  fn(bs) fn(st0) fn(st1)
    val sts = st1.states.tail
    val sts' = if sts.is-nil then [0] else sts
    val (x, State(p, sp, _, ret, prev, cur, pL, rE)) = action(sts'.head)(bs)(st0)(st1)
    (x, State(p, sp, sts', ret, prev, cur, pL, rE))

fun more(f)
  fn(bs) fn(st0) fn(State(p, sp, sts, ret, prev, cur, pL, rE)) (Nothing, State(p, sp, sts, f(bs) ++ ret, prev, cur, pL, rE))

fun less(n, action)
  fn(bs) fn(st0) fn(State(_, sp, sts, ret, prev, _, pL, rE))
    val bs2 = st0.current.take(n)
    val pos2 = bs2.posMoves8(st0.pos)
    val st2 = State(pos2, sp, sts, ret, prev, st0.current.drop(n), pL, rE)
    action(bs2)(st0)(st2)

fun withmore(action)
  fn(bs: sslice) fn(st0) fn(State(p, sp, sts, ret, prev, cur, pL, rE))
    action((bs.string ++ ret.string).reverse.concat.slice)(st0)(State(p, sp, sts, [], prev, cur, pL, rE))

fun withRawDelim(f)
  fn(bs) fn(st0) fn(st1)
    f(bs.string, st1.rawEnd)(bs)(st0)(st1)

alias alexInput = state

fun unsafeChar(kind: string, s: string)
  LexError("unsafe character in " ++ kind ++ ": " ++ s.head) // TODO: Fix this
}