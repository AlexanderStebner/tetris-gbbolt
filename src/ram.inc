; Named RAM / IO addresses.
; Format: DEF name EQU $addr ;@ type description
;   type: u8 | u16 (little endian) | u8[N] | code[N] | const
; Lines without ";@" are plain constants.

DEF hJoyHeld EQU $FF80 ;@ u8 Buttons held: bit 7 Down, 6 Up, 5 Left, 4 Right, 3 Start, 2 Select, 1 B, 0 A
DEF hJoyPressed EQU $FF81 ;@ u8 Buttons newly pressed this frame (same bit layout as hJoyHeld)
DEF hVBlankDone EQU $FF85 ;@ u8 Set to 1 by the VBlank handler; the main loop waits for it
DEF hTimer1 EQU $FFA6 ;@ u8 General purpose countdown, decremented once per frame while non-zero
DEF hTimer2 EQU $FFA7 ;@ u8 Second countdown, decremented once per frame while non-zero
DEF hCoordY EQU $FFB2 ;@ u8 Y coordinate in OAM space (screen y + 16)
DEF hCoordX EQU $FFB3 ;@ u8 X coordinate in OAM space (screen x + 8)
DEF hBGMapAddr EQU $FFB4 ;@ u16 BG map address computed by CoordsToBGMapAddr
DEF hOAMDMA EQU $FFB6 ;@ code[10] OAM DMA routine, copied here from ROM at boot (must run from HRAM)
DEF hGameType EQU $FFC0 ;@ u8 GAME_TYPE_A ($37) or GAME_TYPE_B ($77)
DEF hMusicType EQU $FFC1 ;@ u8 Selected music: $1C-$1E = A/B/C, $1F = off
DEF hSerialRole EQU $FFCB ;@ u8 Link cable role: $29 = master, $55 = slave
DEF hSerialDone EQU $FFCC ;@ u8 Set to 1 when a serial transfer has completed
DEF hSerialState EQU $FFCD ;@ u8 Index into SerialStateTable
DEF hSerialSendPending EQU $FFCE ;@ u8 Non-zero: VBlank should start sending hSerialTx
DEF hSerialTx EQU $FFCF ;@ u8 Next byte to send over the link cable
DEF hSerialRx EQU $FFD0 ;@ u8 Last byte received over the link cable
DEF hDrawBCDFlag EQU $FFE0 ;@ u8 Set when a BCD number must be redrawn; reused by DrawBCD as 'a digit was printed'
DEF hGameState EQU $FFE1 ;@ u8 Index into GameStateTable
DEF hFrameCounter EQU $FFE2 ;@ u8 Incremented every VBlank
DEF wScore EQU $C0A0 ;@ u8[3] Score, 6 BCD digits, least significant byte first
DEF vBGMap0 EQU $9800 ;@ const BG tile map 0 (32x32 tiles)
DEF vBGMap1 EQU $9C00 ;@ const BG tile map 1 (32x32 tiles)
DEF vTiles0 EQU $8000 ;@ const Tile data block 0

DEF TILE_BLANK EQU $2F ;@ const Empty/space tile in the font
DEF GAME_TYPE_A EQU $37 ;@ const
DEF GAME_TYPE_B EQU $77 ;@ const
DEF SERIAL_MASTER EQU $29 ;@ const
DEF SERIAL_SLAVE EQU $55 ;@ const
DEF wScoreDirty EQU $C0CE ;@ u8 Score changed (type A soft drop points): VBlank redraws the score on both BG maps during the line clear animation and clears it
DEF hPiecePhase EQU $FF98 ;@ u8 0 = piece falling, 1 = landed (LockPiece), 2 = locked (CheckLines), 3 = line clear animation (AnimateLineClear)
DEF hTwoPlayer EQU $FFC5 ;@ u8 Non-zero during a 2-player (link cable) game
DEF hSavedIE EQU $FFA1 ;@ u8 rIE saved by DisableLCD
DEF wShadowOAM EQU $C000 ;@ u8[160] Sprite attributes, copied to OAM every VBlank by hOAMDMA
DEF hBoardCopyStage EQU $FFE3 ;@ u8 0 = idle; 2..$13 = copying wBGMap0Copy to VRAM one board row per VBlank, bottom row first
DEF hLevel EQU $FFA9 ;@ u8 Current level (binary, 0-20)
DEF hLines EQU $FF9E ;@ u16 Lines, 4 BCD digits: cleared so far (type A) or still to clear (type B)
DEF hFallDelay EQU $FF99 ;@ u8 Frames between two steps down of the falling piece (current)
DEF hFallDelayBase EQU $FF9A ;@ u8 hFallDelay for the current level (hFallDelay is restored from it)
DEF hHardMode EQU $FFF4 ;@ u8 Non-zero: the fall speed is taken from level + 10
DEF wBoardCopyDone EQU $C0C7 ;@ u8 Set when VBlank has copied the last board row
DEF wSFXRequest EQU $DFE0 ;@ u8 Sound effect to start (sound engine request, 0 = none)
DEF wMusicRequest EQU $DFE8 ;@ u8 Song to start (sound engine request, 0 = none)
DEF wWaveSFXRequest EQU $DFF0 ;@ u8 Wave channel sound effect to start (sound engine request)
DEF wNoiseSFXRequest EQU $DFF8 ;@ u8 Noise channel sound effect to start (sound engine request)
DEF wBGMap0Copy EQU $C800 ;@ u8[$400] Copy of BG map 0 the game draws into; VBlank copies the board rows to VRAM
DEF hGarbageAdded EQU $FFD4 ;@ u8 2-player: set when garbage was just added (the refresh then plays its sound)
DEF hVersusGoalReached EQU $FFD5 ;@ u8 2-player: set when this player cleared all 30 lines
DEF hTypeBLevel EQU $FFC3 ;@ u8 Type B: chosen level (0-9). Winning at level 9 leads to state $22
DEF hObjState EQU $FF86 ;@ u8 Object being drawn: state byte (0 = visible, $80 = hidden, other = skip)
DEF hObjY EQU $FF87 ;@ u8 Object being drawn: Y (OAM space)
DEF hObjX EQU $FF88 ;@ u8 Object being drawn: X (OAM space)
DEF hObjSprite EQU $FF89 ;@ u8 Object being drawn: sprite id (index into SpriteTable); reused for the tile number
DEF hObjAttrBits EQU $FF8A ;@ u8 Object being drawn: extra OAM attribute bits ORed into every tile
DEF hObjFlip EQU $FF8B ;@ u8 Object being drawn: bit 6 = flip vertically, bit 5 = flip horizontally (also ORed into the attributes)
DEF hObjAttr EQU $FF8C ;@ u8 Object being drawn: base OAM attributes
DEF hOAMPtrHi EQU $FF8D ;@ u8 High byte of the next free shadow OAM entry (DrawObjects)
DEF hOAMPtrLo EQU $FF8E ;@ u8 Low byte of the next free shadow OAM entry (DrawObjects)
DEF hObjCount EQU $FF8F ;@ u8 Number of objects DrawObjects still has to draw
DEF hSpriteYOff EQU $FF90 ;@ u8 Sprite being drawn: Y offset from its header
DEF hSpriteXOff EQU $FF91 ;@ u8 Sprite being drawn: X offset from its header
DEF hTileX EQU $FF92 ;@ u8 Tile being drawn: screen X
DEF hTileY EQU $FF93 ;@ u8 Tile being drawn: screen Y
DEF hTileAttr EQU $FF94 ;@ u8 Tile being drawn: OAM attributes
DEF hObjHidden EQU $FF95 ;@ u8 Non-zero while drawing a hidden object (its tiles get Y = $FF)
DEF hObjPtrHi EQU $FF96 ;@ u8 High byte of the object being drawn
DEF hObjPtrLo EQU $FF97 ;@ u8 Low byte of the object being drawn
DEF wObjects EQU $C200 ;@ u8[$100] Objects: 16 bytes each (state, y, x, sprite, attribute bits, flip, attributes, ...)
DEF wClearedRows EQU $C0A3 ;@ u8[9] Full rows found by CheckLines: wBGMap0Copy address (high, low) per row, 0-terminated
DEF hTypeALevel EQU $FFC2 ;@ u8 Type A: chosen start level (0-9)
DEF hTypeBHigh EQU $FFC4 ;@ u8 Type B: chosen height of garbage (0-5)
DEF hDemo EQU $FFE4 ;@ u8 Non-zero while a demo plays: 2 = type A demo, 1 = type B demo (they alternate)
DEF hDemoCountdown EQU $FFC6 ;@ u8 Title screen: periods of 125 frames left before the demo starts
DEF hPieceListPos EQU $FFB0 ;@ u8 Position in wPieceList (demo and 2-player games use a fixed piece sequence)
DEF hDemoInputHi EQU $FFEB ;@ u8 Demo: high byte of the recorded-input pointer
DEF hDemoInputLo EQU $FFEC ;@ u8 Demo: low byte of the recorded-input pointer
DEF hDemoRecord EQU $FFE9 ;@ u8 $FF: record the player's input into the demo buffer instead of playing it back (leftover development feature)
DEF hClearAnimPhase EQU $FF9C ;@ u8 Step 0-6 of the line clear flashing
DEF hCollision EQU $FF9B ;@ u8 Result of the last PieceCollides (1 = the piece overlaps the board)
DEF hSpawnBlocked EQU $FFFB ;@ u8 Counts pieces that could not fall from the spawn position; the second one ends the game
DEF hNameEntryPending EQU $FFC7 ;@ u8 Set when a new high score needs a name: the level select then goes to name entry (state $15)
DEF hDemoButtons EQU $FFED ;@ u8 Demo: buttons of the current recorded input
DEF hDemoInputTimer EQU $FFEA ;@ u8 Demo: frames the current recorded input lasts
DEF wPieceList EQU $C300 ;@ u8[$100] Fixed piece sequence for demo and 2-player games
DEF wScoreTally EQU $C0AC ;@ u8[27] Line clear counters, 5 bytes apart: singles, doubles, triples, tetrises; then soft drop points (u16, $C0C0). Type A scores and clears them right away, type B keeps them for the end screen
DEF DemoPieceList EQU $6450 ;@ const 256 ROM bytes that State24_CopyrightScreen copies to wPieceList: the end of CutsceneTiles plus the start of the sound engine code - effectively arbitrary bytes used as a piece sequence
DEF BTN_A EQU $01 ;@ const hJoyHeld / hJoyPressed bit
DEF BTN_B EQU $02 ;@ const
DEF BTN_SELECT EQU $04 ;@ const
DEF BTN_START EQU $08 ;@ const
DEF BTN_RIGHT EQU $10 ;@ const
DEF BTN_LEFT EQU $20 ;@ const
DEF BTN_UP EQU $40 ;@ const
DEF BTN_DOWN EQU $80 ;@ const
DEF TILE_WALL EQU $8E ;@ const Brick tile of the board's walls
DEF wTypeBHighScores EQU $D000 ;@ u8[$654] Type B top 3 per level and height: 10 x 6 entries of 27 bytes (3 x score + name)
DEF wTypeAHighScores EQU $D654 ;@ u8[$10E] Type A top 3 per level: 10 entries of 27 bytes (3 x score + name)
DEF hHighScoresDirty EQU $FFE8 ;@ u8 Non-zero: VBlank copies the high score area to VRAM
DEF hPrevPieceRoll EQU $FFFC ;@ u8 The piece roll before hNextPieceRoll (RollPiece avoids repeating it); also borrowed as scratch by the high score entry
DEF hSoftDropRows EQU $FFE5 ;@ u8 Rows the piece has been soft-dropped (worth points when it lands)
DEF hNextPieceRoll EQU $FFAE ;@ u8 Piece rolled for the turn after next (the randomizer runs one piece ahead)
DEF hGarbagePending EQU $FFD3 ;@ u8 2-player: garbage waiting to be added; bit 7 (set at the next spawn) = add it now
DEF hTemp EQU $FFA0 ;@ u8 Scratch byte used by many routines
DEF hPaused EQU $FFAB ;@ u8 Non-zero while the game is paused
DEF hAutoShiftTimer EQU $FFAA ;@ u8 Frames until a held Left/Right moves the piece again (23 first, then 9)
DEF hLineClearKind EQU $FFDC ;@ u8 Last line clear: 0 single, 1 double, 2 triple, 4 tetris
DEF hLevelDigitPos EQU $FFE6 ;@ u8 Low byte of the BG map address where the level number is drawn
DEF hPausedSerialTx EQU $FFF1 ;@ u8 hSerialTx saved while a 2-player game is paused
DEF hPausedSerialRx EQU $FFF2 ;@ u8 hSerialRx saved while a 2-player game is paused
DEF hRealJoyHeld EQU $FFEE ;@ u8 Demo: the player's real hJoyHeld, restored after the frame
DEF wPreviewHidden EQU $C0DE ;@ u8 Non-zero: the next piece preview is hidden (toggled with Select)
DEF wSoundPause EQU $DF7F ;@ u8 Sound engine request: 1 = pause, 2 = resume
DEF wTallyRow EQU $C0C5 ;@ u8 Type B tally: row being counted (0-3 line clears, 4 soft drop points)
DEF wTallyStep EQU $C0C6 ;@ u8 Type B tally: 1 = count one more (VBlank), 2 = then redraw the total
DEF wCurrentSong EQU $DFE9 ;@ u8 Song the sound engine is playing (0 = none)
DEF hRocketSprite EQU $FFF3 ;@ u8 Sprite id of the rocket for the score ending ($58-$5A: bigger for higher scores)
DEF hMessagePosHi EQU $FFC9 ;@ u8 Shuttle ending: high byte of where the next message letter goes
DEF hMessagePosLo EQU $FFCA ;@ u8 Shuttle ending: low byte of where the next message letter goes
DEF hNameRank EQU $FFC8 ;@ u8 Name entry: place of the new score, 3 = first, 2 = second, 1 = third
DEF hMusicChanged EQU $FFF0 ;@ u8 2-player menu, slave: the master chose another song
DEF hMasterHeight EQU $FFAC ;@ u8 2-player: the master's handicap height (0-5)
DEF hSlaveHeight EQU $FFAD ;@ u8 2-player: the slave's handicap height (0-5)
DEF hVersusNextRound EQU $FFD6 ;@ u8 2-player: set after a round that did not end the match, so the next round skips the height select
DEF hRoundResult EQU $FFD1 ;@ u8 2-player round result from this side: $AA = won, $77 = lost
DEF hGarbageIncoming EQU $FFD2 ;@ u8 2-player: rows of garbage the opponent just sent (1, 2 or 4)
DEF hVersusWins EQU $FFD7 ;@ u8 2-player: rounds this player has won; at 4 it becomes 5 = match won
DEF hVersusLosses EQU $FFD8 ;@ u8 2-player: rounds this player has lost
DEF hAdvantageMe EQU $FFD9 ;@ u8 2-player: never set in practice (see hDeuce)
DEF hAdvantageOpponent EQU $FFDA ;@ u8 2-player: never set in practice (see hDeuce)
DEF hDeuce EQU $FFDB ;@ u8 2-player: never set (only cleared) - the deuce/advantage handling in UpdateDeuce is unreachable leftover code
DEF hPieceListPosHi EQU $FFAF ;@ u8 2-player: high byte of the position in wPieceList
DEF wGarbageRow EQU $C400 ;@ u8[10] 2-player: the garbage row added to the board when the opponent clears lines (one hole)
DEF hVersusTx EQU $FFB1 ;@ u8 2-player: byte for the opponent - stack height, $80 + lines kind, or $AA/$77
DEF hRoundTie EQU $FFEF ;@ u8 2-player: both players finished at the same time
DEF wSndChannel EQU $DF70 ;@ u8 Sound engine: channel being updated (1-4)
DEF wSndTemp EQU $DF71 ;@ u8 Sound engine: scratch (id of the sound being started, vibrato type)
DEF wPanFrame EQU $DF75 ;@ u8 Sound engine: frames since the last panning swap
DEF wPanPeriod EQU $DF76 ;@ u8 Sound engine: frames between panning swaps
DEF wPanToggle EQU $DF77 ;@ u8 Sound engine: bit 0 picks wPanA or wPanB
DEF wPanMode EQU $DF78 ;@ u8 Sound engine: 1 = fixed panning (wPanA), 3 = all channels on both sides, else alternating
DEF wPanA EQU $DF79 ;@ u8 Sound engine: NR51 value A of the song
DEF wPanB EQU $DF7A ;@ u8 Sound engine: NR51 value B of the song
DEF wPauseTimer EQU $DF7E ;@ u8 Sound engine: counts down the pause jingle
DEF wSongFlags EQU $DF80 ;@ u8 Sound engine: first byte of the song header (not used further)
DEF wNoteLengths EQU $DF81 ;@ u16 Sound engine: pointer to the song's note length table
DEF wChannel1 EQU $DF90 ;@ u8[16] Music channel 1 (square 1): pattern list, timers, pattern pointer, instrument, frequency, flags
DEF wChannel2 EQU $DFA0 ;@ u8[16] Music channel 2 (square 2)
DEF wChannel3 EQU $DFB0 ;@ u8[16] Music channel 3 (wave)
DEF wChannel4 EQU $DFC0 ;@ u8[16] Music channel 4 (noise)
DEF wSFXPlaying EQU $DFE1 ;@ u8 Square channel sound effect playing (0 = none); followed by its frame counter, period and step
DEF wWaveSFXPlaying EQU $DFF1 ;@ u8 Wave channel sound effect playing (0 = none)
DEF wNoiseSFXPlaying EQU $DFF9 ;@ u8 Noise channel sound effect playing (0 = none)
DEF wSFXSlot EQU $DFE0 ;@ u8[8] Square effect slot: request, playing, frame counter, period, step, spare
DEF wMusicSlot EQU $DFE8 ;@ u8[8] Music slot: request, playing song
DEF wWaveSFXSlot EQU $DFF0 ;@ u8[8] Wave effect slot: request, playing, frame counter, period, step, ...
DEF wNoiseSFXSlot EQU $DFF8 ;@ u8[8] Noise effect slot: request, playing, frame counter, period, step, spare
DEF hUnused EQU $FFA4 ;@ u8 Cleared by SoftReset, never used otherwise
DEF WORK_RAM0 EQU $C000 ;@ const Work RAM, first 4 KB ($C000-$CFFF)
DEF WORK_RAM1 EQU $D000 ;@ const Work RAM, second 4 KB ($D000-$DFFF)
DEF OAM_START EQU $FE00 ;@ const Object attribute memory (40 sprites x 4 bytes)
DEF HRAM_START EQU $FF80 ;@ const High RAM ($FF80-$FFFE)
DEF WAVE_RAM EQU $FF30 ;@ const Wave pattern RAM of sound channel 3 (32 4-bit samples)
