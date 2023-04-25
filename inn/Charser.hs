module Charser where
import Base
data Charser a = Charser { getCharser :: String -> Either String (a, String) }
instance Functor Charser where fmap f (Charser x) = Charser $ fmap (first f) . x
instance Applicative Charser where
  pure a = Charser \s -> Right (a, s)
  f <*> x = Charser \s -> do
    (fun, t) <- getCharser f s
    (arg, u) <- getCharser x t
    pure (fun arg, u)
instance Monad Charser where
  Charser f >>= g = Charser $ (good =<<) . f
    where good (r, t) = getCharser (g r) t
  return = pure
instance Alternative Charser where
  empty = Charser \_ -> Left ""
  (<|>) x y = Charser \s -> either (const $ getCharser y s) Right $ getCharser x s

sat f = Charser \case
  h:t | f h -> Right (h, t)
  _ -> Left "unsat"

eof = Charser \case
  [] -> Right ((), "")
  _ -> Left "want EOF"

char :: Char -> Charser Char
char = sat . (==)

string :: String -> Charser String
string s = mapM (sat . (==)) s

oneOf :: [Char] -> Charser Char
oneOf s = sat (`elem` s)

noneOf :: [Char] -> Charser Char
noneOf s = sat $ not . (`elem` s)

digitChar :: Charser Char
digitChar = sat $ \c -> '0' <= c && c <= '9'

lowerChar :: Charser Char
lowerChar = sat $ \c -> 'a' <= c && c <= 'z'

upperChar :: Charser Char
upperChar = sat $ \c -> 'A' <= c && c <= 'Z'

letterChar :: Charser Char
letterChar = lowerChar <|> upperChar

newline :: Charser Char
newline = char '\n'

decimal :: Integral x => Charser x
decimal = foldl (\acc c -> 10*acc + fromIntegral (ord c - ord '0')) 0 <$> some digitChar

alphaNumChar :: Charser Char
alphaNumChar = letterChar <|> digitChar

space :: Charser ()
space = many (sat isSpace) *> pure ()

parse p _ = fmap fst . getCharser p
