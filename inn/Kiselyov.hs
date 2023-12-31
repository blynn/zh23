-- Add `Show` instance.
module Kiselyov where
import Base
import Ast

-- Conversion to De Bruijn indices.
data LC = Ze | Su LC | Pass IntTree | La LC | App LC LC

debruijn n e = case e of
  E x -> Pass $ Lf x
  V v -> maybe (Pass $ LfVar v) id $
    foldr (\h found -> if h == v then Just Ze else Su <$> found) Nothing n
  A x y -> App (debruijn n x) (debruijn n y)
  L s t -> La (debruijn (s:n) t)

-- Kiselyov bracket abstraction.
data IntTree = Lf Extra | LfVar String | Nd IntTree IntTree
data Sem = Defer | Closed IntTree | Need Sem | Weak Sem

instance Show IntTree where
  showsPrec prec = \case
    LfVar s -> showVar s
    Lf extra -> shows extra
    Nd x y -> showParen (1 <= prec) $ showsPrec 0 x . (' ':) . showsPrec 1 y

lf = Lf . Basic

x ## y = case x of
  Defer -> case y of
    Defer -> Need $ Closed (Nd (Nd (lf "S") (lf "I")) (lf "I"))
    Closed d -> Need $ Closed (Nd (lf "T") d)
    Need e -> Need $ Closed (Nd (lf "S") (lf "I")) ## e
    Weak e -> Need $ Closed (lf "T") ## e
  Closed d -> case y of
    Defer -> Need $ Closed d
    Closed dd -> Closed $ Nd d dd
    Need e -> Need $ Closed (Nd (lf "B") d) ## e
    Weak e -> Weak $ Closed d ## e
  Need e -> case y of
    Defer -> Need $ Closed (lf "S") ## e ## Closed (lf "I")
    Closed d -> Need $ Closed (Nd (lf "R") d) ## e
    Need ee -> Need $ Closed (lf "S") ## e ## ee
    Weak ee -> Need $ Closed (lf "C") ## e ## ee
  Weak e -> case y of
    Defer -> Need e
    Closed d -> Weak $ e ## Closed d
    Need ee -> Need $ Closed (lf "B") ## e ## ee
    Weak ee -> Weak $ e ## ee

babs t = case t of
  Ze -> Defer
  Su x -> Weak $ babs x
  Pass x -> Closed x
  La t -> case babs t of
    Defer -> Closed $ lf "I"
    Closed d -> Closed $ Nd (lf "K") d
    Need e -> e
    Weak e -> Closed (lf "K") ## e
  App x y -> babs x ## babs y

nolam x = (\(Closed d) -> d) $ babs $ debruijn [] x

-- Optimizations.
optim t = case t of
  Nd x y -> go (optim x) (optim y)
  _ -> t
  where
  go (Lf (Basic "I")) q = q
  go p q@(Lf (Basic c)) = case c of
    "K" -> case p of
      Lf (Basic "B") -> lf "BK"
      _ -> Nd p q
    "I" -> case p of
      Lf (Basic r) -> case r of
        "C" -> lf "T"
        "B" -> lf "I"
        "K" -> lf "KI"
        _ -> Nd p q
      Nd p1 p2 -> case p1 of
        Lf (Basic "B") -> p2
        Lf (Basic "R") -> Nd (lf "T") p2
        _ -> Nd (Nd p1 p2) q
      _ -> Nd p q
    "T" -> case p of
      Nd (Lf (Basic "B")) (Lf (Basic r)) -> case r of
        "C" -> lf "V"
        "BK" -> lf "LEFT"
        _ -> Nd p q
      _ -> Nd p q
    "V" -> case p of
      Nd (Lf (Basic "B")) (Lf (Basic "BK")) -> lf "CONS"
      _ -> Nd p q
    _ -> Nd p q
  go p q = Nd p q
