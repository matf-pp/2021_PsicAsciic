module Game (runGame) where

import qualified Data.Map as Map
import Data.String
import Control.Monad ( when )
import Control.Monad.IO.Class ( liftIO )
import System.Random
import Input
import Linear
import Asciic
import Food
import UI.NCurses

type IndexedGlyph = (V2 Integer, Glyph)
type IndexedGlyphs = [IndexedGlyph]

type Inventory = Map.Map Food Int

findKey :: (Eq k) => k -> [(k,v)] -> Maybe v  
findKey key [] = Nothing  
findKey key ((k,v):xs) = if key == k  
                            then Just v  
                            else findKey key xs  

data Game = Game 
    { running   :: Bool 
    , stdGen    :: StdGen
    , psic      :: Psic
    , inventory :: Inventory
    } deriving Show

initialInventory :: Inventory
initialInventory = Map.fromList [(Water, 10), (Bone, 5), (Meat, 3)]

initialGame :: StdGen -> Game
initialGame gen = Game True gen defaultPsic initialInventory 

update :: EventGame -> Game -> Game
update Quit game = game { running = False }

update (Feed food) game@(Game _ oldGen psic inventory) = 
    let newMood         = mood psic + (moodValue food)
        newHunger       = hunger psic + (hungerValue food)
        newDirtiness    = dirtiness psic + (dirtinessValue food)
        foodInMap       = inventoryLookup food inventory
        psicNew      
            | foodInMap /= 0 = updatePsicMood newMood
                                $ updatePsicHunger newHunger
                                $ updatePsicDirtiness newDirtiness
                                $ psic
            | otherwise = psic {psicSays = "There is no any " ++ (show food) ++ " in my bowl :("}
        inventoryNew
                    | foodInMap > 0 = Map.adjust pred food $ inventory
                    | otherwise  = Map.adjust (*0) food $ inventory
    in game { psic = psicNew
            , inventory = inventoryNew
            }

update Idle game@(Game _ oldGen psic inventory) = 
    let (randMood, newGen)          = randomR (-3, 3) oldGen
        (randHunger, newGen')       = randomR ( 0, 3) newGen
        (randDirtiness, newGen'')   = randomR ( 0, 1) newGen'
        (randWater, newGen''')      = randomR ( 0, 2) newGen''
        (randBone, newGen'''')      = randomR ( 0, 1) newGen'''
        (randMeat, newGen''''')     = randomR ( 0, 1) newGen''''
        newMood                     = mood psic - randMood
        newHunger                   = hunger psic + randHunger
        newDirtiness                = dirtiness psic + randDirtiness
    in game { stdGen    = newGen'''''
            , psic      = updatePsicMood newMood
                        $ updatePsicHunger newHunger
                        $ updatePsicDirtiness newDirtiness
                        $ psic
            , inventory = Map.adjust (+randWater) Water 
                        $ Map.adjust (+randBone) Bone 
                        $ Map.adjust (+randMeat) Meat
                        $ inventory
            }
update Play game@(Game _ oldGen psic _) =
    let (randMood, newGen)          = randomR (0, 10) oldGen 
        (randHunger, newGen')       = randomR (0,  5) newGen
        (randDirtiness, newGen'')   = randomR (0,  5) newGen'
        newMood                     = mood psic + randMood
        newHunger                   = hunger psic - randHunger
        newDirtiness                = dirtiness psic + randDirtiness
    in game { stdGen    = newGen''
            , psic      = updatePsicMood newMood
                        $ updatePsicHunger newHunger
                        $ updatePsicDirtiness newDirtiness
                        $ psic { psicSays = "I love playing with you, " 
                                         ++ owner psic 
                                         ++ "!" 
                               }
            }
update Clean game@(Game _ oldGen psic _) =
    let (randMood, newGen)          = randomR (0,  10) oldGen 
        (randDirtiness, newGen')   = randomR (20, 80) newGen
        newMood                     = mood psic + randMood
        newDirtiness                = dirtiness psic - randDirtiness
    in game { stdGen    = newGen'
            , psic      = updatePsicMood newMood
                        $ updatePsicDirtiness newDirtiness
                        $ psic { psicSays = "Wash washy wash washy wash wash!" }
            }

update Poop game@(Game _ oldGen psic _) =
    let (randMood, newGen)          = randomR (0, 10) oldGen 
        (randHunger, newGen')       = randomR (0, 5) newGen
        (randDirtiness, newGen'')   = randomR (10, 30) newGen'
        newMood                     = mood psic - randMood
        newHunger                   = hunger psic + randHunger
        newDirtiness                = dirtiness psic + randDirtiness
    in game { stdGen    = newGen''
            , psic      = updatePsicMood newMood
                        $ updatePsicHunger newHunger
                        $ updatePsicDirtiness newDirtiness
                        $ psic { psicSays = "Aghe, sometnihg stinks! "
                                         ++ "Can you, please, clean me?" 
                               }
            }
update Hunger game@(Game _ oldGen psic _) =
    let (randMood, newGen)          = randomR (0, 10) oldGen 
        (randHunger, newGen')       = randomR (10, 30) newGen
        (randDirtiness, newGen'')   = randomR (0,  5) newGen'
        newMood                     = mood psic - randMood
        newHunger                   = hunger psic + randHunger
        newDirtiness                = dirtiness psic + randDirtiness
    in game { stdGen    = newGen''
            , psic      = updatePsicMood newMood
                        $ updatePsicHunger newHunger
                        $ updatePsicDirtiness newDirtiness
                        $ psic { psicSays = "Aghe, I'm hungry! "
                                         ++ "Can you, please, feed me?" 
                               }
            }
update Sleep game@(Game _ oldGen psic _) =
    let (randMood, newGen)          = randomR (5, 10) oldGen 
        (randHunger, newGen')       = randomR (0, 5) newGen
        (randDirtiness, newGen'')   = randomR (0, 5) newGen'
        newMood                     = mood psic + randMood
        newHunger                   = hunger psic - randHunger
        newDirtiness                = dirtiness psic + randDirtiness
    in game { stdGen    = newGen''
            , psic      = updatePsicMood newMood
                        $ updatePsicHunger newHunger
                        $ updatePsicDirtiness newDirtiness
                        $ psic { psicSays = "Good night! Zzzz..." }
            }
update _    game = game -- Implement other actions

inventoryLookup :: Food -> Inventory -> Integer
inventoryLookup food inventory =
    let maybeCount = Map.lookup food inventory
    in case maybeCount of
        Nothing      -> 0
        (Just count) -> toInteger count

asciic2IndexedGlyphs :: String -> IndexedGlyphs
asciic2IndexedGlyphs str = 
    let indexedRows = zip [0..] (lines str)
        indexedCols = foldr (\(row, line) acc -> (row, zip [0..] line):acc) 
                            [] indexedRows
        indexedRowsCols = concat 
                        $ map (\(row, lst) -> map (\(col, chr) 
                                           -> (row, col, chr)) lst) indexedCols
    in map (\(row, col, chr) -> (V2 row col, Glyph chr [])) indexedRowsCols

drawAsciic :: String -> Integer -> Integer -> Update ()
drawAsciic asciic xOffset yOffset =
    mapM_ (\(V2 row col, glyph) -> do
                moveCursor (xOffset + row) (yOffset + col) 
                drawGlyph glyph) $ indexedAsciic
    where indexedAsciic = asciic2IndexedGlyphs asciic

header :: Update ()
header = do
    let name = "Psic Asciic"
        len  = fromIntegral $ length name
    moveCursor 1 (25 - (floor $ len / 2))
    drawString name
    moveCursor 2 0

body :: Psic -> Inventory -> Update ()
body psicState inventoryState = do
    moveCursor 3 2
    drawString "Mood:"
    drawLineH (Just glyphBlock) (moodLevel psicState)
    moveCursor 3 15
    drawString "Hunger:"
    drawLineH (Just glyphBlock) (hungerLevel psicState)
    moveCursor 3 30
    drawString "Dirtiness:"
    drawLineH (Just glyphBlock) (dirtinessLevel psicState)
    drawAsciic (psicLook psicState) 5 22
    drawSaying $ psicSays psicState
    moveCursor 13 3
    drawString "Water:"
    drawString $ "x" ++ (show $ inventoryLookup Water inventoryState)
    moveCursor 13 20
    drawString "Bone:"
    drawString $ "x" ++ (show $ inventoryLookup Bone inventoryState)
    moveCursor 13 35
    drawString "Meat:"
    drawString $ "x" ++ (show $ inventoryLookup Meat inventoryState)
    where drawSaying saying = do
            let len = fromIntegral $ length saying
            moveCursor 11 (25 - (floor $ len / 2))
            drawString saying
 
footer :: Update ()
footer = do
    moveCursor 15 30
    drawString "(Press q to quit)"

drawGame :: Game -> Update ()
drawGame (Game _ _ psicState inventoryState) = do
    moveCursor 0 0
    hBar
    header
    hBar
    moveCursor 3 0
    body psicState inventoryState
    moveCursor 14 0
    hBar
    footer
    where hBar = drawLineH Nothing 50

renderGame :: Game -> Curses ()
renderGame game = do
    w <- defaultWindow
    updateWindow w $ do
        clear
        drawGame game
    render

loop :: Game -> Curses ()
loop oldGame = if ((state (psic oldGame)) /= Dead) then (do 
    renderGame oldGame
    gen       <- liftIO $ newStdGen
    event     <- nextEvent
    randEvent <- randomEvent gen
    let newGame = update randEvent 
                $ update event oldGame 
                    { stdGen = gen }
    when (running newGame) $ do
        loop newGame
    )   

    else (do
        renderGame oldGame
        gen       <- liftIO $ newStdGen
        event     <- nextEvent
        let noviPsic = (psic oldGame) { hunger    = 0
                                      , mood      = 0
                                      , dirtiness = 0
                                      , state = Dead
                                      , psicSays  = "I died from starvation. You are terrible owner :("
                                      }
            newGame 
                | event == Quit = update event oldGame 
                    { stdGen = gen 
                    , psic = noviPsic
                    }
                | otherwise = oldGame
             
                                
        when (running newGame) $ do
            loop newGame
    )   
    

runGame :: IO ()
runGame = runCurses $ do
    setEcho False
    setCursorMode CursorInvisible
    gen <- liftIO $ getStdGen
    loop $ initialGame gen
