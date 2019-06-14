= Compiler Quest =

Bootstrapping a compiler is like a role-playing game. From humble beginnings,
we painstakingly cobble together a primtive, hard-to-use compiler whose only
redeeming quality is that it can build itself.

Because the language supported by our compiler is so horrible, we can only
bear to write a few incremental improvements. But once we persevere, we
compile the marginally better compiler to gain a level. We can now iterate: we
add more features to our new compiler, which is easier thanks to our most
recent changes, then compile again, and so on. Eventually we reach a compiler
that no longer causes embarrassment.

== Parenthetically ==

Our first compiler converts combinatory logic terms that humans would write to
ION assembly, for example:

------------------------------------------------------------------------------
parse "BS(BB);Y(B(CS)(B(B(C(BB:)))C));"
  ==  "``BS`BB;`Y``B`CS``B`B`C``BB:C;"
------------------------------------------------------------------------------

We assume the input is valid and contains no numbers in parentheses or
square brackets (so it only uses `@` to refer to previous terms and `#` for
integer constants).

In Haskell we could write:

------------------------------------------------------------------------------
term acc (h:t)
  | h == ')' || h == ';' -> (acc, t)
  | h == '('             -> uncurry (app acc) (term "" t)
  | otherwise            -> if h == '#' || h == '@'
    then app acc (h:head t:"") (tail t)
    else app acc (h:"") t
  where app acc s = term (if null acc then s else '`':acc ++ s)
  
parse "" = ""
parse s = let (p, t) = term "" s in p ++ ';':parse t
------------------------------------------------------------------------------

To translate to combinatory logic, we first break our code into more
digestible pieces:

------------------------------------------------------------------------------
pair x y f = f x y;
(||) f g x y = f x (g x y);
(++) xs ys = xs ys (\x xt -> x : (xt ++ ys));
ifNull xs a b = xs a (\_ _ -> b);
add r acc p = r (ifNull acc p ('`':(acc ++ p)));
isPre h = h('#'(==)) || h('@'(==));
suffix f h t = isPre h (t undefined (\a b -> pair (a:[]) b)) (pair [] t) (\x y -> f (h:x) y);
atom r h acc t = suffix (add r acc) h t;
sub r acc = uncurry (add r acc) . r "";
closes h = h(';'(==)) || h(')'(==));
if3 h x y z = closes h x (h('('(==)) y z);
switch r a h t = if3 h pair (sub r) (atom r h) a t;
term acc s = s undefined (\h t -> switch term acc h t);
parse s = term "" s (\p t -> ifNull p ";" (p ++ (';':parse t)));
------------------------------------------------------------------------------

where it's understood that:

------------------------------------------------------------------------------
uncurry x y = y x;
(.) x y z = x (y z);
------------------------------------------------------------------------------

In ION assembly, this is:

------------------------------------------------------------------------------
``BCT;
``BS`BB;
`Y``B`CS``B`B`C``BB:C;
``B`R``BKK`BB;
``C``BBB``S``BS@#``B`B`:#`@";
``S``B@!`T`##=`T`#@=;
``B`S``BC``C``BS``C``BB@%``C`T?``B@ ``C:K`@ K``C``BBB:;
``BC``B`B@&@$;
``S``BC``B`BB``B`BT@$`TK;
``S``B@!`T`#;=`T`#)=;
``S``BC``B`BB``B`BB@)`T`#(=;
``BC``S``BS``B`C``C@*@ @(@';
`Y``B`B`C`T?@+;
`Y``B`S`TK``B`BK``B`BK``B`C`@,K``B`C``BB@"`B`:#;;
------------------------------------------------------------------------------

== Exponentially ==

Our next compiler rewrites lambda expressions as combinators using the
straightforward bracket abstraction algorithm we described earlier.

We start with some defintiions that make our code more readable, but
which are equivalent to the combinators I, K, T, C, Y, and K, respectively:

------------------------------------------------------------------------------
id x = x;
const x _ = x;
(&) x f = f x;
flip f x y = f y x;
fix x = x (fix x);
Nothing x _ = x;
------------------------------------------------------------------------------

Our program starts with a few classic definitions. `P` stands for "pair".

------------------------------------------------------------------------------
Just x f g = g x;
P x y f = f x y;
(||) f g x y = f x (g x y);
(++) xs ys = xs ys (\x xt -> x : (xt ++ ys));
------------------------------------------------------------------------------

As combinators:

------------------------------------------------------------------------------
BKT;
BCT;
BS(BB);
Y(B(CS)(B(B(C(BB:)))C));
------------------------------------------------------------------------------

=== Parser combinators ===

Parsing is based on functions of type:

------------------------------------------------------------------------------
type Parser x = [Char] -> Maybe (x, [Char])
------------------------------------------------------------------------------

A `Parser x` tries to parse the beginning of a given string for a value of
type `x`. If successful, it returns the value along with the unparsed
remainder of the input string. Otherwise t returns `Nothing`.

Values of type `Parser x` compose in natural ways. See
http://www.cs.uu.nl/research/techreps/repo/CS-2008/2008-044.pdf['Combinator Parsing: A Short Tutorial` by Swierstra] for details.

------------------------------------------------------------------------------
pure x inp = Just (P x inp);
bind f m = m Nothing (\x -> x f);
(<*>) x y = \inp -> bind (\a t -> bind (\b u -> pure (a b) u) (y t)) (x inp);
(<$>) f x = pure f <*> x;
(*>) p q = (\_ x -> x) <$> p <*> q;
(<*) p q = (\x _ -> x) <$> p <*> q;
(<|>) x y = \inp -> (x inp) (y inp) Just;
------------------------------------------------------------------------------

These turn into:

------------------------------------------------------------------------------
B(B@ )@!;
B(C(TK))T;
C(BB(B@%(C(BB(B@%(B@$))))));
B@&@$;
B@&(@'(KI));
B@&(@'K);
B(B(R@ ))S;
------------------------------------------------------------------------------

=== Abstract syntax tree ===

Our syntax tree goes into the following data type:

------------------------------------------------------------------------------
data Ast = R [Char] | V Char | A Ast Ast | L Char Ast
------------------------------------------------------------------------------

The `R` stands for "raw", and its field passes through unchanged during
bracket abstraction. Otherwise we have a lambda calculus that supports
one-character variable names. Scott-encoding yields:

------------------------------------------------------------------------------
R s   = \a b c d -> a s;
V v   = \a b c d -> b v;
A x y = \a b c d -> c x y;
L x y = \a b c d -> d x y;
------------------------------------------------------------------------------

which translates to:

------------------------------------------------------------------------------
B(BK)(B(BK)(B(BK)T));
BK(B(BK)(B(BK)T));
B(BK)(B(BK)(B(B(BK))(BCT)));
B(BK)(B(BK)(B(BK)(BCT)));
------------------------------------------------------------------------------

=== Grammar ===

The `sat` parser combinator parses a single character that satisfies a given
predicate. The `char` specializes this to parse a given character, and
`var` accepts any character except the semicolon and closing parenthesis.
We use `sat (const const)` to accept any character, and with that, we can
parse a lambda calculus expression such as `\x.(\y.Bx)`:

------------------------------------------------------------------------------
sat f inp = inp Nothing (\h t -> f h (pure h t) Nothing);
char c = sat (\x -> x(c(==)));
var = sat (\c -> flip (c(';'(==)) || c(')'(==))));
pre = (:) <$> (char '#' <|> char '@') <*> (flip (:) const <$> sat (const const));
atom r = (char '(' *> (r <* char ')')) <|> (char '\\' *> (L <$> var) <*> (char '.' *> r)) <|> (R <$> pre) <|> (V <$> var);
apps r = (((&) <$> atom r) <*> ((\vs v x -> vs (A x v)) <$> apps r)) <|> pure id;
expr = ((&) <$> atom expr) <*> apps expr;
------------------------------------------------------------------------------

As combinators, we have:

------------------------------------------------------------------------------
B(C(TK))(B(B(RK))(C(BS(BB))@$));
B@/(BT(T=));
@/(BC(S(B@"(T(#;=)))(T(#)=))));
@&(@':(@*(@0##)(@0#@)))(@'(C:K)(@/(KK)));
C(B@*(C(B@*(S(B@*(B(@((@0#())(C@)(@0#)))))(B(@&(@((@0#\)(@'@.@1)))(@((@0#.)))))(@'@+@2)))(@'@,@1);
Y(B(R(@$I))(B(B@*)(B(S(B@&(B(@'T)@3)))(B(@'(C(BBB)(C@-)))))));
Y(S(B@&(B(@'T)@3))@4);
------------------------------------------------------------------------------

=== Bracket abstraction ===

The `babs` and `unlam` functions perform simple bracket abstraction, and
`show` writes the resulting lambda-free `Ast` in ION assembly.

Putting it all together, `main` parses as many semicolon-terminated
expressions as it can and converts them to ION assembly.

------------------------------------------------------------------------------
show t = t id (\v -> v:[])(\x y -> '`':(show x ++ show y)) undefined;
unlam v = fix (\r t -> t (\x -> A (V 'K') (R x)) (\x -> x(v(==)) (V 'I') (A (V 'K') (V x))) (\x y -> A (A (V 'S') (r x)) (r y)) undefined);
babs t = t R V (\x y -> A (babs x) (babs y)) (\x y -> unlam x (babs y));
main s = (expr <* char ';') s "" (\p -> p (\x t -> show (babs x) ++ ";" ++ main t)));
------------------------------------------------------------------------------

As combinators:

------------------------------------------------------------------------------
Y(B(R?)(B(C(C(TI)(C:K)))(B(B(B(:#`)))(S(BC(B(BB)(B@#)))I))));
BY(B(B(R?))(C(BB(BC(B(C(T(B(@-(@,#K))@+)))(C(BS(B(R(@,#I))(BT(T=))))(B(@-(@,#K))@,)))))(S(BC(B(BB)(B(B@-)(B(@-(@,#S))))))I)));
Y(S(BC(B(C(C(T@+)@,))(S(BC(B(BB)(B@-)))I)))(C(BB@7)));
Y(B(C(C(@)@5(@0#;))K))(BT(C(BB(B@#(C(B@#(B@6@8))(:#;K)))))));
------------------------------------------------------------------------------

We feed the combinators into our first compiler to produce an ION assembly
program that compiles lambda calculus to ION assembly. We're back to where we
were before, except instead of Haskell, we can use any language where it's
easy to simulate an ION machine.

Apart from the primitive grammar, our task might seem complete.
However, there is a problem with classic bracket abstraction.
For each variable we abstract over, the algorithm adds an application of the S
combinator to every application. Hence for N variables, this multiplies the
number of applications by 2^N, making this algorithm impractical.

We therefore use this algorithm sparingly; just enough to reach a better
algorithm.

== Practically ==

Our next compiler uses the most straightforward optimization to improve on
classic bracket abstraction.

We stop recursively adding S combinators as soon as we realize they are
unnecessary by modifying `unlam` and adding a helper function `occurs`:

------------------------------------------------------------------------------
occurs v t = t (\x -> (\_ y -> y)) (\x -> x(v(==))) (\x y -> occurs v x || occurs v y) undefined;
unlam v t = occurs v t (t undefined (const (V 'I')) (\x y -> A (A (V 'S') (unlam v x)) (unlam v y)) undefined) (A (V 'K') t);
------------------------------------------------------------------------------

We rewrite these as lambda abstractions with one-character variable names
and replace the line defining `unlam` with them:

------------------------------------------------------------------------------
Y\a.\b.\c.c(\d.\e.\f.f)(\d.d(b=))(\d.\e.@((abd)(abe))?;
Y\a.\b.\c.@=bc(c?(@!(@2#I))(\d.\e.@3(@3(@2#S)(abd))(abe))?)(@3(@2#K)c);
------------------------------------------------------------------------------

Our previous compiler can compile this to a new compiler with better bracket
abstraction. The optimization works well enough that in our next iteration,
we're comfortable writing lambda abstractions whenever we wish.

== Sacrificial lambdas ==

Adding term-rewriting rules further reduce the size of the output combinatory
logic term after bracket abstraction.

https://tromp.github.io/cl/LC.pdf[John Tromp's paper contains a useful list
of rewrite rules.]

Chapter 16 of
https://www.microsoft.com/en-us/research/publication/the-implementation-of-functional-programming-languages/['The
Implementation of Functional Programming Languages' by Simon Peyton Jones]
gives a comprehensive overview of this strategy.

http://www.cantab.net/users/antoni.diller/brackets/intro.html[Antoni Diller has interactive demos and more references].
