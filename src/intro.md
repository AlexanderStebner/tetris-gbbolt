# From power-on to level 1

What the code does between switching the Game Boy on and an A-TYPE game ticking over from
level 0 to level 1, in the order it happens.

## Power on

The CPU starts at `Boot`, which jumps on to `Start`. It clears the upper half of work RAM
and falls into `SoftReset`, which wipes nearly everything else:

- the LCD goes off once the screen has reached line `$94`, safely inside VBlank, and the
  palettes and the sound hardware are set;
- the rest of work RAM, all of VRAM, OAM and HRAM are cleared, each with a loop counting
  downwards;
- the sprite DMA routine is copied into HRAM (`hOAMDMA`): during a DMA the CPU can only run
  code from there.

Holding A+B+SELECT+START at any time jumps back to `SoftReset`.

## One state per frame

After that the whole game runs in `MainLoop`, once per frame:

- `ReadJoypad`;
- `RunGameState`: an `rst $28` (`JumpTable`) into `GameStateTable`, indexed by `hGameState`;
- one tick of the sound engine (`UpdateSound`);
- the two countdown timers `hTimer1` and `hTimer2`;
- then a wait until the `VBlankHandler` sets `hVBlankDone`.

Each screen and each phase of the game is a state handler, from `State00_Playing` up to
`$35`. A handler does one frame's worth of work, sets `hGameState` if it wants to move on,
and returns.

The `VBlankHandler` does the VRAM work: the line clear flashing, the board copy, the type B
tally, the sprite DMA, the high score table and the score digits.

## Copyright and title

The first state is `State24_CopyrightScreen`. It loads the tiles (`LoadTitleTiles`), draws
the screen (`LoadScreen`) and copies 256 bytes from ROM into `wPieceList`: the piece
sequence for demos and 2-player games. Those bytes are just the end of a tile set and the
start of the sound code, read as pieces.

The copyright screen stays for 250 frames that can't be skipped (`State25_CopyrightWait`),
then another 250 where any button skips it (`State35_CopyrightWaitSkippable`).

`State06_TitleScreenInit` builds the title screen and quietly prepares the empty board,
walls and floor, in `wBGMap0Copy`. `State07_TitleScreen` moves the cursor between 1 PLAYER and
2 PLAYER and listens on the link cable for a second Game Boy. Hold Down while pressing
START and you get hard mode (`hHardMode`).

Leave it alone and `StartDemo` plays a recorded game (`DemoPlayback`: pairs of buttons and
how long they're held). See [the type A demo](demo-type-a). There's even the recorder,
`DemoRecord`, a development leftover whose writes go into ROM and are lost.

## Menus

`State0E_GameTypeMenu` picks A-TYPE or B-TYPE, `State0F_MusicMenu` plays each song as the
cursor moves over it, and `State11_TypeALevelSelect` picks the start level, with the top-3
scores for that level next to it (`ShowTypeAHighScores`). START leads to
`State0A_StartGame`.

## Setting up the game

`State0A_StartGame` builds everything with the LCD off:

- the empty board (`FillBoardAndRefresh`) and the game screen, drawn twice: on BG map 0, and
  on BG map 1 with the PAUSE text, so pausing just switches maps (`HandlePause`);
- `hLevel` and the fall speed: `SetFallSpeed` reads `FallDelayTable`, 52 frames per row
  at level 0 (hard mode adds 10 levels);
- three calls to `SpawnNextPiece`, to fill the randomizer's look-ahead.

Then it switches to `State00_Playing`.

## A piece's life

The falling piece is not in the background: it is a sprite object in `wObjects`, drawn
by `DrawObjects` like every other sprite in the game. Each frame `State00_Playing` runs:

- `HandlePieceInput`: B and A rotate, Left and Right move, with autoshift (23 frames, then
  every 9). `PieceCollides` checks the four tiles against `wBGMap0Copy`, and a move that
  collides is taken back.
- `UpdateFall`: gravity, or a soft drop of one row every 3 frames, worth one point per row
  after the first. When the piece can't move down, it has landed.
- `LockPiece` writes the piece's four tiles into the background, both on screen and in
  `wBGMap0Copy`, and hides the sprite.

The next piece comes from `SpawnNextPiece`, as soon as the board has settled: right after
the lock, or after a line clear. It rolls the following one from `rDIV` and rerolls up to
twice to avoid repeats, with an OR test that also rerolls some other pieces. The odds are
worked out in [the piece odds table](table-piece-odds).

## Lines

- `CheckLines` scans the 16 rows that can fill up in `wBGMap0Copy` for rows without a blank
  tile, notes them in `wClearedRows` and adds them to `hLines`.
- `AnimateLineClear` runs from VBlank every 10 frames and flashes the full rows: 7 steps.
- `CollapseClearedRows` moves everything above each cleared row down by one row, in the
  copy only.
- Then the board copy starts: the VBlank handler copies one board row per frame to VRAM,
  bottom row first (`RefreshBoardRow17` ... `RefreshBoardRow0`). The game never redraws the
  whole board at once. When the copy is done, `RefreshBoardRow0` spawns the next piece.
- On the way up, at stage 5, `AwardLineClearPoints` pays 40, 100, 300 or 1200 points
  times (level + 1). See [the points chart](chart-line-points).

## Level 1

At row 3 of the same copy, `CheckLevelUp` compares the tens of `hLines` with the level.
With 10 lines cleared, level 0 becomes level 1: the digit is drawn on both BG maps, a
sound plays, and `SetFallSpeed` drops the delay from 52 to 48 frames per row. It keeps
doing that every 10 lines, up to level 20. See [the fall speed chart](chart-fall-speed).

And if the game ends with 100000 points or more, `State0D_GameOverScreen` launches a rocket
instead of showing GAME OVER: [the big one](rocket-big).
